#!/bin/bash
# WORKTREE.
#
# WHAT THIS SUITE OWNS. One payload library:
#
#   payload/scripts/lib/worktree.sh   the lease: the tree's checks, legacy links, overruns
#
# WHY A LIBRARY AND NOT THE SCRIPT. The landing line (lib/line.sh: `ready`, the hand
# landing) and the Patrol tick's lease-overrun line need the same answers: whether a
# tree may land, and whether a run holds the checkout. A copy in each is two
# definitions of "a suite is running", the divergence class this repo keeps paying
# for. The verbs in spawn-worktree.sh are call sites; the behaviour is here.
#
# HERMETIC. No network, no `claude` CLI, no contact with the bionic checkout
# this suite runs inside beyond sourcing the library under test. Every git
# command is `-C <fixture>` or inside a subshell that has cd'd into one; global
# and system git config are pointed at /dev/null. The session files some arms plant
# (to show that a session plays no part in what holds a landing) go to a fixture claude-home reached
# through BIONIC_CLAUDE_HOME — the knob payload/scripts/lib/patrol.sh already uses
# for exactly this directory, so there is one override chain and not two.
#
# THE SUITE-RUNNING ARMS START THEIR OWN PROCESSES. When this suite runs under tests/run.sh,
# that runner sits in the bionic checkout, outside every fixture, so it never answers for
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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME="Bionic Test" GIT_AUTHOR_EMAIL="test@example.invalid"
export GIT_COMMITTER_NAME="Bionic Test" GIT_COMMITTER_EMAIL="test@example.invalid"
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

# An EMPTY fixture claude-home by default; the arms that plant a session file there show
# that a session changes nothing. No stand-in runner works inside any fixture outside
# §HOLDS and Group 7, so every other landing sees "no suite running".
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
# (a page at 15, its run's log at step 4) under the docs root, so the same file doubles as the
# root's newest open run for the unbound `fallback` arm.
bind_plan() {  # <repo> <sid> <working-branch or empty> -> echoes the plan path
  local r="$1" sid="$2" wb="$3" p
  p="$r/.bionic/docs/plans/epic-x/wave-x.plan.md"
  mkdir -p "${p%/*}" "$r/.bionic/tmp" "$r/.bionic/docs/record/wave-x"
  printf -- '---\ncanonical_sdlc_version: 15\n%s---\n# fixture plan\n' "${wb:+working-branch: $wb$'\n'}" > "$p"
  printf 'run/v1|ev=step|n=4|at=2026-09-23T00:00:00Z\n' >> "$r/.bionic/docs/record/wave-x/run.log"
  printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$p" > "$r/.bionic/tmp/engaged-${sid}.state"
  printf '%s' "$p"
}

# Every ref and its object, one line each: a refused land changes NONE of them, which is
# "no merge commit anywhere" read off git rather than off the refusal line.
refs_of() { git -C "$1" for-each-ref --format='%(refname) %(objectname)'; }

# shellcheck source=/dev/null
. "$LIB" 2>/dev/null || { echo "FAIL: the library does not source ($LIB)"; exit 1; }
# The landing line (wave-28 T3): `land --by-hand` and §LAND-BIONIC's drive. Sourced when present, so
# a tree without it reads every row that needs it red rather than stopping here.
LINE_LIB="${REPO}/payload/scripts/lib/line.sh"
# shellcheck source=/dev/null
[ -r "$LINE_LIB" ] && . "$LINE_LIB" 2>/dev/null
export BIONIC_GATE_DIR="$TMP/gate"

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

section "§HOLDS: what holds a publish in the checkout that holds the branch, as the line reads it"
#
# The line's predicate (lib/line.sh `_line_live_run`, over lib/worktree.sh `_wt_busy_suite`): an
# admitted, unended request of the gate whose tree is the checkout and whose holder lives, or a process
# that RUNS a `tests/run.sh` with its script or its working directory there. Each arm starts its own
# STAND-IN RUNNER, a script at `<dir>/tests/run.sh` that only sleeps; the real runner is never started.
# A row tree's run holds nothing (landing-line-1 §BUSY b3).
S="$(new_repo "$TMP/land-busy")"
held() { _line_live_run "$1" "$1"; }   # <checkout> -> what holds a publish there; rc 1 when nothing
RUNNER_PID=""
start_runner_argv() {  # <cwd> <glob> <argv>... -> RUNNER_PID, once ps shows a command matching <glob>
  local d="$1" g="$2"; shift 2
  ( cd "$d" && exec "$@" ) >/dev/null 2>&1 &
  RUNNER_PID=$!
  runner_matches() { [[ "$(ps -o command= -p "$RUNNER_PID" 2>/dev/null)" == $g ]]; }
  wait_ticks 100 0.05 runner_matches
}
start_runner() { start_runner_argv "$1" "*tests/run.sh*" bash "$2"; }   # <cwd> <script as invoked>
stop_runner() { [ -n "$RUNNER_PID" ] || return 0; kill "$RUNNER_PID" 2>/dev/null; wait "$RUNNER_PID" 2>/dev/null; RUNNER_PID=""; }
make_runner() {  # <dir> -> <dir>/tests/run.sh
  mkdir -p "$1/tests"
  # the stand-in runner idles until the arm kills it (`sleep 1` is its heartbeat); no wait can observe a process that is meant to stay alive
  printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$1/tests/run.sh"; chmod +x "$1/tests/run.sh"
}
MENTION_PID=""
start_mention() {  # <cwd> <-c text> -> MENTION_PID, once ps shows the text
  ( cd "$1" && exec bash -c "$2" ) >/dev/null 2>&1 &
  MENTION_PID=$!
  mention_shows_run_sh() { case "$(ps -o command= -p "$MENTION_PID" 2>/dev/null)" in *tests/run.sh*) return 0 ;; esac; return 1; }
  wait_ticks 100 0.05 mention_shows_run_sh
}
stop_mention() { [ -n "$MENTION_PID" ] || return 0; kill "$MENTION_PID" 2>/dev/null; wait "$MENTION_PID" 2>/dev/null; MENTION_PID=""; }
GB_HOLD=""
gb_clear() { rm -rf "$BIONIC_GATE_DIR"; [ -z "$GB_HOLD" ] || kill "$GB_HOLD" 2>/dev/null; GB_HOLD=""; }
trap 'gb_clear; stop_runner; stop_mention; rm -rf "$TMP"' EXIT
ELSE="$TMP/elsewhere"; make_runner "$ELSE"
OTHER="$(new_repo "$TMP/other-repo")"; make_runner "$OTHER"
make_runner "$S"

expect_true "a stand-in runner started (script in the checkout, cwd elsewhere)" start_runner "$ELSE" "$S/tests/run.sh"
OUTB="$(held "$S")"; RCB=$?
expect_match "a runner whose script is in the checkout holds it, naming the process and the script" "pid=${RUNNER_PID} *script=${S}/tests/run.sh" "$OUTB"
expect_eq "…rc 0" "0" "$RCB"
stop_runner
expect_false "once the runner is gone nothing holds it (the arm discriminates)" held "$S"
expect_true "a stand-in runner started (relative, cwd the checkout)" start_runner "$S" "tests/run.sh"
expect_match "a relative runner whose working directory is the checkout holds it" "pid=${RUNNER_PID} cwd=${S} *" "$(held "$S")"
stop_runner
expect_true "a stand-in runner started (relative, in another repository)" start_runner "$OTHER" "tests/run.sh"
expect_false "a runner in another repository holds nothing" held "$S"
stop_runner
expect_true "a stand-in runner started (absolute, another repository's script, cwd elsewhere)" start_runner "$ELSE" "$OTHER/tests/run.sh"
expect_false "…nor one invoked by its absolute path" held "$S"
stop_runner

# A COMMAND THAT ONLY MENTIONS THE RUNNER IS NOT THE RUNNER. The harness runs every Bash call as
# `zsh -c '… <the whole command text>'`, so a wait loop naming `tests/run.sh` is a process in the
# project whose command line holds that text. Only a process that RUNS the script counts.
# the `sleep 1` in each mention body below keeps the shell alive until stop_mention kills it; no wait can observe that
expect_true "a shell started in the checkout whose -c text names the runner bare" start_mention "$S" 'while :; do sleep 1; done # bash tests/run.sh'
expect_false "a shell whose -c text names tests/run.sh holds nothing" held "$S"
stop_mention
expect_true "a shell whose -c text quotes the runner, as the harness's wait loops do" \
  start_mention "$S" "while :; do sleep 1; done; until ! pgrep -f 'tests/run.sh'; do sleep 30; done"
expect_false "a quoted mention holds nothing either" held "$S"
expect_true "a stand-in runner started beside the mention (relative, cwd the checkout)" start_runner "$S" "tests/run.sh"
expect_eq "the real runner beside it holds, naming the runner, not the mention" "pid=${RUNNER_PID} cwd=${S} script=${S}/tests/run.sh" "$(held "$S")"
stop_runner; stop_mention
mkdir -p "$S/sub/tests"; printf 'not a runner\n' > "$S/sub/tests/run.sh"
expect_true "a shell whose -c string opens with a tests/run.sh that resolves in the checkout" \
  start_mention "$S/sub" 'tests/run.sh 2>/dev/null; while :; do sleep 1; done'
expect_false "a -c string is never a script, whatever its first word" held "$S"
stop_mention; rm -rf "$S/sub"
# the `sleep 30` below is a process named as the runner that stays alive until stop_runner; no wait can observe it
expect_true "a process started with the checkout's tests/run.sh as its argv[0]" \
  start_runner_argv "$ELSE" "$S/tests/run.sh 30" bash -c "exec -a '$S/tests/run.sh' sleep 30"
expect_match "a process whose argv[0] is the runner's script holds it" "pid=${RUNNER_PID} *script=${S}/tests/run.sh" "$(held "$S")"
stop_runner
mkdir -p "$S/empty/tests"
expect_true "a process started with a missing tests/run.sh in the checkout as its argv[0]" \
  start_runner_argv "$ELSE" "$S/empty/tests/run.sh 30" bash -c "exec -a '$S/empty/tests/run.sh' sleep 30"
expect_false "a runner path that resolves to no file holds nothing" held "$S"
stop_runner; rmdir "$S/empty/tests" "$S/empty"
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
# A RUN THE GATE ADMITTED IS A RUN. Every suite asks the gate, and its request records the tree it runs
# in (`tree=`). An admitted, unended request whose holder lives holds the checkout it names; a waiting
# request has run nothing, an ended or killed one runs nothing. The store is this suite's own.
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
holder_gone() { ! kill -0 "${1:-}" 2>/dev/null; }
GB="$(new_repo "$TMP/busy-gate")"; GBO="$(new_repo "$TMP/busy-gate-other")"
gb_holder; gb_plant 7 "$GB" "$GB_HOLD"
expect_match "an admitted run in the checkout holds it, naming the request, its key and its tree" "request*7 key=x.test.sh tree=${GB}*" "$(held "$GB")"
gb_plant 7 "$GB" "$GB_HOLD" waiting
expect_false "a request that is only waiting has run nothing: nothing holds it" held "$GB"
gb_plant 7 "$GB" "$GB_HOLD" ended
expect_false "an ended request holds nothing" held "$GB"
gb_plant 7 "$GBO" "$GB_HOLD"
expect_false "a run in another repository holds nothing" held "$GB"
gb_plant 7 "$GB" "$GB_HOLD"; kill "$GB_HOLD" 2>/dev/null; wait_ticks 100 0.05 holder_gone "$GB_HOLD"; GB_HOLD=""
expect_false "an admitted request whose holder is dead (killed) holds nothing" held "$GB"
gb_clear

# THE REAL SHIM, NOT A PLANTED FILE. The rows above write their request files by hand, which is how no
# suite saw the shim name its own cwd as the tree: `cd <row tree> || exit 1; bash tests/x.test.sh`, wrapped
# from the main checkout with `--stamp-dir <row tree>`, wrote `tree=<main checkout>` and held every
# landing. These rows drive payload/scripts/booked.sh itself, from the main checkout, holding mid-run.
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
gb_shim_end() { touch "$1"; wait "$GB_SHIM_PID" 2>/dev/null; GB_SHIM_PID=""; gb_clear; }   # <go file>
GBW7="$(new_tree "$GB" gate-shim-own)"
gb_shim_bg "" "while [ ! -f '$TMP/gb7a.go' ]; do sleep 0.05; done"
expect_true "the real shim, run in the main checkout, is admitted" wait_ticks 200 0.05 gb_has_admitted
expect_match "…and its run holds the main checkout (the positive for the row below)" "request*tree=${GB}*" "$(held "$GB")"
gb_shim_end "$TMP/gb7a.go"
gb_shim_bg "$GBW7" "cd '$GBW7' || exit 1; while [ ! -f '$TMP/gb7b.go' ]; do sleep 0.05; done"
expect_true "a writer's suite run from the main checkout (cd <tree>, --stamp-dir <tree>) is admitted" wait_ticks 200 0.05 gb_has_admitted
expect_eq "…its request names the writer's tree, the stamp's tree" "$(cd "$GBW7" && pwd -P)" \
  "$(sed -n 's/^tree=//p' "$BIONIC_GATE_DIR"/requests/* 2>/dev/null | tail -n 1)"
expect_false "…and it does not hold the main checkout" held "$GB"
gb_shim_end "$TMP/gb7b.go"

section "Group 7: the land VERB — spawn-worktree.sh land <path> --by-hand --reason <why>"
#
# The verb is a call site, not a second implementation: what is asserted here
# is the wiring and the exit codes a caller reads. Since wave-28 T3 (D9) a person lands a row with
# `--by-hand --reason`, through the line's one publish; a bare `land` refuses (§BY-HAND).

# THE VERB NAMES NO TARGET: the session's bound plan does. So the verb runs with a
# session id, and that session is bound to a plan whose working branch the fixture holds.
V="$(new_repo "$TMP/verb")"
VSID="verb-session-0001"
bind_plan "$V" "$VSID" wave/fixture >/dev/null
vland() { ( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$1" --by-hand --reason r 2>/dev/null ); }
VT="$(new_tree "$V" verb-arm)"
ln -s "${V}/.bionic" "${VT}/.bionic"
OUTV="$(vland "$VT")"
expect_match "the verb lands onto the bound plan's working branch, its .bionic link the tree's only untracked entry" \
  "spawn-worktree: LANDED branch=verb-arm onto=wave/fixture checkout=${V} *" "$OUTV"
expect_false "the tree is gone" test -d "$VT"
expect_eq "…its branch stays, the state its link pointed at stands, and git's entries name the landing tree, not it" "yes yes 1 0" \
  "$(git -C "$V" show-ref -q --verify refs/heads/verb-arm && echo yes) $([ -f "$V/.bionic/docs/note.md" ] && echo yes) $(cat "$V"/.git/worktrees/*/gitdir 2>/dev/null | grep -c /landing/) $(cat "$V"/.git/worktrees/*/gitdir 2>/dev/null | grep -c /verb-arm/)"

# THE TREE'S OWN CHECKS, each refused before anything is touched, the tree and every ref kept. The
# tree landed must sit under `<root>/.worktrees/`, tested on the path SEGMENT, not the prefix string.
VD="$(new_tree "$V" verb-dirty)"; echo x >> "${VD}/file.txt"
VU="$(new_tree "$V" verb-untracked)"; echo scratch > "${VU}/notes.txt"
VN="$(new_tree "$V" verb-nothing)"; git -C "$V" merge --quiet --no-ff -m "already merged" verb-nothing
VX="$TMP/verb-outside/stranger"; git -C "$V" worktree add --quiet -b stranger "$VX" HEAD >/dev/null 2>&1
VX="$(cd "$VX" && pwd -P)"; echo w > "$VX/w.txt"; git -C "$VX" add -A; git -C "$VX" commit -qm w; ln -s "${V}/.bionic" "$VX/.bionic"
VY="${V}/.worktrees-decoy/decoy"; git -C "$V" worktree add --quiet -b decoy "$VY" HEAD >/dev/null 2>&1
echo d > "$VY/d.txt"; git -C "$VY" add -A; git -C "$VY" commit -qm d
VREFS1="$(refs_of "$V")"
for c in "$VD dirty-tree" "$VU dirty-tree" "$VN nothing-to-land" "$V not-a-linked-worktree" \
         "$V/.worktrees/never-existed no-such-worktree" "$VX outside-worktrees" "$VY outside-worktrees"; do
  set -- $c; OUTC="$(vland "$1")"; RCC=$?
  expect_eq "a hand landing of ${1##*/} is refused ${2} (exit 2)" "spawn-worktree: REFUSED reason=${2} rc=2" "$(printf %s "$OUTC" | cut -d" " -f1-3) rc=$RCC"
done
expect_eq "no ref moved, and the refused tree outside the farm keeps its .bionic link" "$VREFS1 yes" \
  "$(refs_of "$V") $([ -L "$VX/.bionic" ] && echo yes)"

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
# A stale entry, its directory gone, planted after the landing tree exists: the removal prunes it.
git -C "$V" worktree add -q -b verb-stale "$V/.worktrees/verb-stale" HEAD; rm -rf "$V/.worktrees/verb-stale"
expect_match "the same tree lands from the bound session (the arm discriminates)" \
  "spawn-worktree: LANDED branch=verb-dirty onto=wave/fixture *" \
  "$( cd "$V" && CLAUDE_CODE_SESSION_ID="$VSID" bash "$SPAWN" land "$VD" --by-hand --reason r 2>/dev/null )"
expect_eq "…and git keeps no entry for the stale tree (pruned), but one for the landing tree" "0 1" \
  "$(cat "$V"/.git/worktrees/*/gitdir 2>/dev/null | grep -c /verb-stale/) $(cat "$V"/.git/worktrees/*/gitdir 2>/dev/null | grep -c /landing/)"

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
# A plan whose working branch is protected lands nothing there: hooks/protect-main.sh reads `git push`
# argv and never sees a landing, so this check is the one wall in the path.
bind_plan "$V" "$VSID" main >/dev/null; VP="$(new_tree "$V" verb-onto-main)"; VREFS2="$(refs_of "$V")"
expect_match "a landing onto main is refused, naming the branch" "spawn-worktree: REFUSED reason=protected-branch branch=main *" "$(vland "$VP")"
expect_eq "…and no ref moved" "$VREFS2" "$(refs_of "$V")"

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
{ printf -- '---\nworking-branch: wave/fixture\ncanonical_sdlc_version: 15\n---\n# fixture plan (§BY-HAND)\n\n## Tasks\n\n'
  printf '| id | step | kind | task | deps | size | serves | Files | artifact |\n|---|---|---|---|---|---|---|---|---|\n'; } > "$BHP"
BHLOG="$BH/.bionic/docs/record/wave-x/run.log"; mkdir -p "${BHLOG%/*}"
bh_row() {  # <n> -> row T<n> on the plan, dispatched to bh-T<n> on its tree in the run's log
  printf '| T%s | 4 | build | row %s | — | 10 | REQ-1 | bh-T%s.txt | — |\n' "$1" "$1" "$1" >> "$BHP"
  printf 'run/v1|ev=%s|at=2026-10-04T00:0%s:0%sZ\n' "dispatch|row=T$1|name=bh-T$1" "$1" 1 "tree|row=T$1|path=.worktrees/bh-T$1" "$1" 2 >> "$BHLOG"
}
printf 'run/v1|ev=%s|at=2026-10-04T00:00:0%sZ\n' 'step|n=4' 1 'approval|key=step3|by=fixture|said=approved' 2 > "$BHLOG"; bh_row 1
printf 'plan=%s\nengaged_at=2026-09-23T00:00:00Z\n' "$BHP" > "$BH/.bionic/tmp/engaged-${BHSID}.state"
bh_all() { cat "$BHLOG" 2>/dev/null; }
BH_SUM="$(cksum < "$BHP")|$(cksum < "$BHLOG")"
BH_REFS0="$(refs_of "$BH")"
bh_land() { ( cd "$BH" && CLAUDE_CODE_SESSION_ID="$BHSID" bash "$SPAWN" land "$@" 2>&1 ); }
OUTBH0="$(bh_land "$BHT" --by-hand)"; RCBH0=$?
expect_eq    "(h1) a hand landing with no --reason is refused (exit 2)" "2" "$RCBH0"
expect_match "(h1) …naming why" "spawn-worktree: REFUSED reason=no-reason *" "$OUTBH0"
expect_eq    "(h1) …and nothing is recorded: the plan and its log are as they were" "$BH_SUM" "$(cksum < "$BHP")|$(cksum < "$BHLOG")"
OUTBHB="$(bh_land "$BHT")"; RCBHB=$?
expect_ne    "(h2) a bare land exits non-zero" "0" "$RCBHB"
expect_eq    "(h2) …and no ref moved" "$BH_REFS0" "$(refs_of "$BH")"
OUTBH="$(bh_land "$BHT" --by-hand --reason "the person's why")"; RCBH=$?
expect_eq    "(h3) a hand landing with a reason exits 0" "0" "$RCBH"
expect_match "(h3) …on land's own LANDED line" "*spawn-worktree: LANDED branch=wt/bh-T1 onto=wave/fixture checkout=${BH} merge=* removed=${BHT} proofs=${BHLOG}*" "$OUTBH"
BH_PUB="$(grep '^run/v1|ev=published|' "$BHLOG" 2>/dev/null)"
expect_regex "(h4) the log's published line carries the user, the time and the reason" \
  "^run/v1\\|ev=published\\|row=T1\\|commit=$(git -C "$BH" rev-parse wave/fixture)\\|kind=hand\\|by=Hand Lander\\|why=the person's why\\|branch=wt/bh-T1\\|head=[0-9a-f]{40}\\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" "$BH_PUB"
BH_AT="${BH_PUB##*|at=}"
expect_eq    "(h5) the plan is the landing's to leave: its bytes stand as they were, the who, when and why on the event" \
  "${BH_SUM%|*}|Hand Lander|the person's why" "$(cksum < "$BHP")|$(printf '%s' "$BH_PUB" | tr '|' '\n' | sed -n 's/^by=//p')|$(printf '%s' "$BH_PUB" | tr '|' '\n' | sed -n 's/^why=//p')"

section "§HAND: a hand landing lands a row whose suite is red, writes the person's words on its line, and runs nothing"
#
# A second row of the same plan commits a suite that fails and logs each run of it, and its launch line names that suite
# as the one it lands on. The hand landing merges it all the same: running a suite is no part of it, and none is wanted.
# What the person says of the writer's run (its suites, the commit they were green at, its log) is recorded as verdicts.
bh_row 2
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
expect_contains "(hd2) …and its landing carries the person's words" '|why=landed on the report|' \
  "$(grep '^run/v1|ev=published|row=T2|' "$BHLOG" 2>/dev/null)"
expect_eq    "(hd3) …no suite ran, and the record holds the person's verdict, keyed by the commit it was green at" \
  "0|run/v1|ev=verdict|row=T2|commit=${BHC2}|suite=r.test.sh|result=green|log=/logs/T2-green.log|admitted=-|width=-|promised=-|actual=-" \
  "$(awk 'END { print NR }' "$TMP/hand-runs")|$(bh_all | grep '|ev=verdict|' | sed 's/|at=[^|]*$//')"

# A hand landing that names its suites leaves a ready line that names them too, so the judge and the door read one
# row's suites; with none named, the ready line says none.
bh_row 3
BHT3="$(new_tree "$BH" wt/bh-T3)"; printf 'three\n' > "$BHT3/three.txt"; git -C "$BHT3" add three.txt && git -C "$BHT3" commit -qm "T3: a row"
printf '%s|row=T3|lands_on=a.test.sh,b.test.sh\n' "$(roster_row_fixture status=intended session="$BHSID" name=bh-T3 agent_id=b00T3 plan="$BHP")" \
  >> "$BH/.bionic/tmp/roster-${BHSID}.state"
BHC3="$(git -C "$BHT3" rev-parse HEAD)"
bh_land "$BHT3" --by-hand --reason "landed on the report" --suites a.test.sh,b.test.sh --green-at "$BHC3" --log /logs/T3-green.log >/dev/null
expect_eq    "(hd4) …and its ready line names the suites the person named, where a landing that named none says none" \
  "a.test.sh,b.test.sh|none" \
  "$(bh_all | grep '|ev=ready|row=T3|' | sed 's/.*|suites=\([^|]*\)|.*/\1/')|$(bh_all | grep '|ev=ready|row=T1|' | sed 's/.*|suites=\([^|]*\)|.*/\1/')"

BHT4="$(new_tree "$BH" wt/bh-T4)"; mkdir -p "$BHT4/tests"; printf '# the wave-40 run said so\n' > "$BHT4/tests/cited.sh"; git -C "$BHT4" add tests && git -C "$BHT4" commit -qm "T4: a cited comment"; BH_REFS4="$(refs_of "$BH")"
OUTHL="$(bh_land "$BHT4" --by-hand --reason "landed on the report")"; RCHL=$?
expect_eq    "(hl1) a hand landing whose added comment cites the run exits 2 with ready's LINT line, and no ref moved" "2|LINT wt/bh-T4 tests/cited.sh:1 wave|same" "$RCHL|$(printf '%s\n' "$OUTHL" | grep '^LINT ')|$([ "$BH_REFS4" = "$(refs_of "$BH")" ] && echo same)"
# A hand landing behind an entry still proving waits on it, and builds its candidate once for each base it is given.
BHT5="$(new_tree "$BH" wt/bh-T5)"; BHX="$(git -C "$BH" commit-tree -p wave/fixture -m ahead "$(git -C "$BH" rev-parse 'wave/fixture^{tree}')")"; BHAT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'run/v1|ev=ready|row=T9|name=-|commit=%s|branch=-|tree=-|suites=none|debt=-|carrier=%s:|at=%s\nrun/v1|ev=candidate|row=T9|base=%s|commit=%s|tree=-|at=%s\n' "$BHX" "$$" "$BHAT" "$(git -C "$BH" rev-parse wave/fixture)" "$BHX" "$BHAT" >> "$BHLOG"
bh_land "$BHT5" --by-hand --reason "behind an entry" >/dev/null & BHPID=$!
sleep 3; printf 'run/v1|ev=returned|row=T9|why=red|detail=-|at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$BHLOG"; wait "$BHPID"; RCHW=$?
expect_eq    "(hd3b) a hand landing held 3 s behind an entry lands, with one candidate on the entry's and one on the head it published onto" \
  "0|${BHX} $(git -C "$BH" rev-parse wave/fixture^1)" "$RCHW|$(bh_all | grep '|ev=candidate|row=wt/bh-T5|' | sed 's/.*|base=\([^|]*\)|.*/\1/' | paste -sd' ' -)"
section "§CHECK-FILES: what a range changes of the check's files is the declared list met with the range"
CF="$(new_repo "$TMP/check-files")"; mkdir -p "$CF/chk/sub" "$CF/lib"
: > "$CF/chk/a.sh"; : > "$CF/chk/sub/c.sh"; : > "$CF/lib/b.sh"; : > "$CF/lib/d.sh"
git -C "$CF" add chk lib && git -C "$CF" commit -qm "the files"; CF0="$(git -C "$CF" rev-parse HEAD)"
for f in chk/a.sh chk/sub/c.sh lib/b.sh lib/d.sh file.txt; do echo x >> "$CF/$f"; done
git -C "$CF" commit -qam "a range that changes each"; CF1="$(git -C "$CF" rev-parse HEAD)"
printf 'release-check: bash chk/a.sh\nrelease-check-files: chk/*.sh lib/b.sh\n' > "$CF/.bionic/config.yaml"
expect_eq "(cf1) a glob names the files of its own directory, a path itself, and an undeclared file nothing (rc 0)" \
  "0|chk/a.sh,lib/b.sh" "$(o="$(_wt_check_judge "$CF" "$CF0" "$CF1")"; echo "$?|$o")"
printf 'release-check: bash chk/a.sh\nrelease-check-files: docs/*.md\n' > "$CF/.bionic/config.yaml"
expect_eq "(cf2) a declaration the range changes no file of says nothing (rc 1)" "1|" \
  "$(o="$(_wt_check_judge "$CF" "$CF0" "$CF1")"; echo "$?|$o")"
printf 'release-check: bash chk/a.sh\n' > "$CF/.bionic/config.yaml"
expect_eq "(cf3) with no declared list the check has no files, whatever its command names (rc 1)" "1|" \
  "$(o="$(_wt_check_judge "$CF" "$CF0" "$CF1")"; echo "$?|$o")"
section "§SUCCESSOR: a tree spawned under one session lands by ready from another; the tree's own record names its run"
#
# THE TREE DESCRIBES ITSELF. `create --for` gives a tree its own record (its plan, its row, its worker and the
# spawning session), and `ready` reads it before the session's binding: a conversation cleared between the spawn
# and the landing leaves a new session id with no binding and no roster, and the row still lands. The launch row
# is found on the spawning session's roster when the asking session's holds none.
# FIXTURE FIDELITY: the landing line's model world (tests/lib/world.sh), built by the landing-line prelude's own
# `ll_world`, `ll_launch` and `ll_carrier_env`, read by name; every row tree here is made by `spawn-worktree.sh
# create --for`, the verb whose record it stands for.
# fails-when: `ready` from a successor session refuses `no-bound-plan` or `no-launch-row`.
# This suite's own `bind_plan` (Group 7) writes a bare marker and prints the plan; the world binds through the real
# one (lib/binding.sh, by tests/lib/bound-marker.sh), so the suite's is put away before the world is built.
unset -f bind_plan
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/world.sh"
wt_import_fn() {  # <name> -> the function, defined here, read out of the landing-line prelude
  local body
  body="$(awk -v n="$1" 'index($0, n "() {") == 1 { p = 1 } p { print } p && /^}/ { exit }' "$(dirname "$0")/landing-line.prelude.sh")"
  [ -n "$body" ] || { echo "wt_import_fn: no $1 in landing-line.prelude.sh" >&2; return 1; }
  eval "$body"
}
LL_HERE="$(cd "$(dirname "$0")" && pwd -P)"   # the prelude sets it at its top and its builders read it; the suite reads the builders, not the top
for f in ll_world ll_launch ll_carrier_env; do wt_import_fn "$f" || no "($f is read out of landing-line.prelude.sh)" "absent"; done
ll_plan() { printf '%s/.bionic/docs/plans/epic-x/wave-x.plan.md' "$1"; }; ll_log() { printf '%s/.bionic/docs/record/wave-x/run.log' "$1"; }
ll_carrier_env
sc_spawn() {  # <root> <row> <sid> -> the tree `create --for wx-<row>` made under <sid>, its plan row, its dispatch and one commit of its own
  local r="$1" t="$2" s="$3" p out tree
  p="$(ll_plan "$r")"
  printf '| %s | 4 | build | row %s | — | 10 | REQ-1 | %s.txt | — |\n' "$t" "$t" "$t" >> "$p"
  printf 'run/v1|ev=dispatch|row=%s|name=wx-%s|at=2026-10-04T00:1%s:00Z\n' "$t" "$t" "${t#T}" >> "$(ll_log "$r")"
  mkdir -p "$r/.bionic/docs/record/wave-x/briefs"
  printf '<!-- brief: rendered from row %s for %s; sum %064d; render it again to change it, never edit it -->\n' "$t" "wx-$t" 0 > "$r/.bionic/docs/record/wave-x/briefs/wx-$t.md"
  out="$( cd "$r" && CLAUDE_CODE_SESSION_ID="$s" bash "$SPAWN" create "$(git -C "$r" rev-parse wave/x)" "wt/$t" --for "wx-$t" 2>/dev/null )" || return 1
  tree="$(printf '%s\n' "$out" | tr ' ' '\n' | sed -n 's/^path=//p')"
  [ -d "$tree" ] || return 1
  printf '%s work\n' "$t" > "$tree/$t.txt"
  git -C "$tree" add "$t.txt" && git -C "$tree" commit -qm "$t: one commit" || return 1
  printf '%s' "$tree"
}
sc_ready() {  # <tree> <sid> -> SC_OUT, SC_RC: ready from the tree, as <sid>
  case "$1" in "$WORLD_ROOT"/*) [ -d "$1" ] || { SC_OUT="no tree at $1"; SC_RC=99; return; } ;; *) SC_OUT="not a world tree: $1"; SC_RC=99; return ;; esac
  SC_OUT="$( cd "$1" && CLAUDE_CODE_SESSION_ID="$2" bash "$SPAWN" ready 2>&1 )"; SC_RC=$?
}
sc_head() {  # <ready's output> -> its LANDED line's first two words, else its first line's
  local l
  l="$(printf '%s\n' "$1" | grep -m1 '^LANDED ')" || l="$(printf '%s\n' "$1" | head -1)"
  printf '%s\n' "$l" | cut -d' ' -f1-2
}
SUCC="33333333-4444-4555-8666-777777777777"     # the successor: no binding, no roster
SUCC2="44444444-5555-4666-8777-888888888888"    # a successor rebound to the same plan, its roster empty

SC="$(ll_world)"; SC_P="$(ll_plan "$SC")"
SC_T3="$(sc_spawn "$SC" T3 "$WORLD_SID")"; ll_launch "$SC" T3 a.test.sh
expect_match "(su0) the spawned tree's own record names its plan, its row, its worker and the spawning session" \
  "tree/v1|path=${SC_T3}|plan=${SC_P}|row=T3|worker=wx-T3|spawned-by=${WORLD_SID}|at=*" "$(worktree_tree_record "$SC_T3" 2>/dev/null)"
expect_false "(su0b) …and the successor holds no binding of its own" test -e "$SC/.bionic/tmp/engaged-${SUCC}.state"
sc_ready "$SC_T3" "$SUCC"
expect_eq "(su1) ready from a successor session with no binding lands the tree a predecessor spawned (exit 0)" "0 LANDED T3" \
  "$SC_RC $(sc_head "$SC_OUT")"
[ "$SC_RC" = 0 ] || printf '      ready said: %s\n' "$SC_OUT"
SC_K3="$(git -C "$SC" rev-parse wave/x)"
expect_contains "(su2) …and the landing is marked on the launch row, on the spawning session's roster" "|landed=${SC_K3}|" \
  "$(grep '|name=wx-T3|' "$SC/.bionic/tmp/roster-${WORLD_SID}.state" | tail -1)"
# The binding still decides for a tree that carries no record of its own: the world's T1 was made by `git worktree add`.
sc_ready "$SC/.worktrees/T1" "$SUCC"
expect_eq "(su3) a tree with no record of its own, from the same successor, is refused by the binding as before (exit 2)" \
  "2 spawn-worktree: REFUSED" "$SC_RC $(sc_head "$SC_OUT")"
expect_contains "(su3b) …naming the fallback" "reason=no-bound-plan state=fallback" "$SC_OUT"
# A successor bound to the same plan, whose own roster holds no row: the launch row is the spawning session's.
bound_marker "$SC" "$SUCC2" "$SC_P" >/dev/null
SC_T4="$(sc_spawn "$SC" T4 "$WORLD_SID")"; ll_launch "$SC" T4 b.test.sh
sc_ready "$SC_T4" "$SUCC2"
expect_eq "(su4) ready from a rebound successor whose roster holds no row lands on the spawning session's launch row (exit 0)" \
  "0 LANDED T4" "$SC_RC $(sc_head "$SC_OUT")"
[ "$SC_RC" = 0 ] || printf '      ready said: %s\n' "$SC_OUT"
expect_contains "(su4b) …proved on that launch row's suite" "|ev=ready|row=T4|" \
  "$(grep '|suites=b.test.sh|' "$SC/.bionic/docs/record/wave-x/run.log" 2>/dev/null)"

section "§MISMATCH: a tree whose record names another plan than the binding is refused naming both; close-out's own last landing on a closed plan is admitted"
#
# The binding is a check on the tree's record: a session bound to a different plan than the tree's is refused,
# naming both, and nothing moves. A closed plan is admitted only for the session bound to it, the one close-out
# lands its last rows from; any other session is refused naming the closed plan.
# fails-when: a stale tree lands on the wrong plan silently, or close-out's last landing is refused.
SC_Q="$SC/.bionic/docs/plans/epic-x/wave-y.plan.md"
printf -- '---\ncanonical_sdlc_version: 15\nworking-branch: wave/x\n---\n# another run\n' > "$SC_Q"
mkdir -p "$SC/.bionic/docs/record/wave-y"; printf 'run/v1|ev=step|n=4|at=2026-10-04T00:00:00Z\n' > "$SC/.bionic/docs/record/wave-y/run.log"
SQ="55555555-6666-4777-8888-999999999999"
bound_marker "$SC" "$SQ" "$SC_Q" >/dev/null
SC_T5="$(sc_spawn "$SC" T5 "$WORLD_SID")"; ll_launch "$SC" T5 a.test.sh
SC_REFS="$(git -C "$SC" for-each-ref --format='%(refname) %(objectname)')"
sc_ready "$SC_T5" "$SQ"
expect_eq "(mm1) ready from a session bound to another plan is refused (exit 2)" "2 spawn-worktree: REFUSED" "$SC_RC $(sc_head "$SC_OUT")"
expect_contains "(mm1b) …naming the tree's plan and the session's" \
  "reason=plan-mismatch tree-plan=${SC_P} session-plan=${SC_Q}" "$SC_OUT"
expect_eq "(mm1c) …and no ref moved" "$SC_REFS" "$(git -C "$SC" for-each-ref --format='%(refname) %(objectname)')"
sc_ready "$SC_T5" "$WORLD_SID"
expect_eq "(mm2) the same tree from the session bound to its plan lands (exit 0)" "0 LANDED T5" "$SC_RC $(sc_head "$SC_OUT")"
[ "$SC_RC" = 0 ] || printf '      ready said: %s\n' "$SC_OUT"

SD="$(ll_world)"; SD_P="$(ll_plan "$SD")"
SD_T3="$(sc_spawn "$SD" T3 "$WORLD_SID")"; ll_launch "$SD" T3 a.test.sh
# Delivered at current 9, as close-out leaves it; T3 is a fix born of a finding of the review the judge reads failing,
# the one landing a judged run admits (lib/worktree.sh, THE RUN HAS BEEN JUDGED FOR INTEGRATION), in the shape
# `proof-add review` and `task-add --born` write.
SD_H="$(git -C "$SD" rev-parse wave/x)"; SD_B="$(git -C "$SD" rev-parse main)"
mkdir -p "$SD/.bionic/docs/record/wave-x"
printf 'reviewed: %s..%s\nquestion: structure\nresult: fail\nscope: piece\n\nfindings: 1\nfinding: 1 S1 off T3.txt:1 the row is wrong\nshown: 1 cat T3.txt\n' \
  "$SD_B" "$SD_H" > "$SD/.bionic/docs/record/wave-x/rev.md"
SD_B="$SD_B" awk '/^working-branch: / && !fm { fm = 1; print; print "rigor: single"; print "scale: task"; print "base-sha: " ENVIRON["SD_B"]; next }
  { print }' "$SD_P" > "$SD_P.n" && mv "$SD_P.n" "$SD_P"
printf 'run/v1|ev=%s|at=%s\n' "proof|kind=review|head=$SD_H|evidence=record/wave-x/rev.md|question=structure|reader=w-rev|result=fail|scope=piece" \
  2026-10-20T00:00:00Z 'born|row=T3|reason=review S1 off|finding=record/wave-x/rev.md#1' 2026-10-20T00:00:00Z \
  'step|n=9|delivered=2026-10-24T00:00:00Z' 2026-10-24T00:00:00Z >> "$(ll_log "$SD")"
expect_eq "(mc0) the plan is closed" "closed" "$( . "$REPO/payload/scripts/lib/run.sh" && { run_open "$SD_P" && echo open || echo closed; } )"
SD_REFS="$(git -C "$SD" for-each-ref --format='%(refname) %(objectname)')"
sc_ready "$SD_T3" "$SUCC"
expect_eq "(mc1) ready on a closed plan from a session not bound to it is refused (exit 2)" "2 spawn-worktree: REFUSED" \
  "$SC_RC $(sc_head "$SC_OUT")"
expect_contains "(mc1b) …naming the closed plan" "reason=plan-closed plan=${SD_P}" "$SC_OUT"
expect_eq "(mc1c) …and no ref moved" "$SD_REFS" "$(git -C "$SD" for-each-ref --format='%(refname) %(objectname)')"
sc_ready "$SD_T3" "$WORLD_SID"
expect_eq "(mc2) close-out's own last landing, from the session bound to the closed plan, is admitted (exit 0)" "0 LANDED T3" \
  "$SC_RC $(sc_head "$SC_OUT")"
[ "$SC_RC" = 0 ] || printf '      ready said: %s\n' "$SC_OUT"

section "§HAND: a hand landing writes the person's verdicts before it publishes, so the born row's landing closes the review's ask"
#
# `land --by-hand` with --suites records what the person says of the writer's run as green verdicts, and writes them
# before the publish: the publish reads the reviews the row answers again once the row
# reads landed, judging the row by those verdicts. T3 is born of the one finding of a failing adversarial review that
# `proof-add review` registered, which opened the waiver ask.
# fails-when: the ask stays open after the hand landing's publish, or the verdicts follow the published line.
HN="$(ll_world)"; HN_P="$(ll_plan "$HN")"; HN_RD="$HN/.bionic/docs/record/wave-x"; mkdir -p "$HN_RD"
HN_T3="$(sc_spawn "$HN" T3 "$WORLD_SID")"
HN_H="$(git -C "$HN" rev-parse wave/x)"; HN_B="$(git -C "$HN" rev-parse main)"
# The planner's frontmatter: the rigor and scale the judge deals by, and where the work started, the base an
# adversarial chain is held from.
HN_B="$HN_B" awk '/^working-branch: / && !fm { fm = 1; print; print "rigor: single"; print "scale: task"; print "base-sha: " ENVIRON["HN_B"]; next } { print }' \
  "$HN_P" > "$HN_P.n" && mv "$HN_P.n" "$HN_P"
printf 'reviewed: %s..%s\nquestion: adversarial\nresult: fail\nscope: piece\n\nfindings: 1\nfinding: 1 S1 off T3.txt:1 the row is wrong\nshown: 1 cat T3.txt\n' \
  "$HN_B" "$HN_H" > "$HN_RD/rev.md"
printf '%s|questions=adversarial\n' "$(roster_row_fixture session="$WORLD_SID" name=w-rev agent_id=a-w-rev subagent_type=bionic:critic \
  launched_at=2026-10-01T00:00:00Z deliverable="$HN_RD/rev.md")" >> "$HN/.bionic/tmp/roster-$WORLD_SID.state"
HN_PA="$( cd "$HN" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$REPO/hooks/session-poker.sh" proof-add review record/wave-x/rev.md --question adversarial --reader w-rev 2>&1 )"; HN_PARC=$?
printf 'run/v1|ev=born|row=T3|reason=review S1 off|finding=record/wave-x/rev.md#1|at=2026-10-20T00:00:00Z\n' >> "$HN_RD/run.log"
hn_ask() { bash -c '. "$1/roots.sh" && . "$1/owed.sh" && owed_lines "$2" "$3"' _ "$REPO/payload/scripts/lib" "$HN_P" "$HN" 2>/dev/null \
  | awk -F'|' '{ k = s = b = ""; for (i = 2; i <= NF; i++) { if ($i ~ /^key=/) k = substr($i, 5); if ($i ~ /^state=/) s = substr($i, 7); if ($i ~ /^by=/) b = substr($i, 4) } } k == "waive:adversarial" { l = s "|" b } END { print l }'; }
expect_eq "(hn0) proof-add registers the failing review (exit 0) and its waiver ask is open" "0|open|" "$HN_PARC|$(hn_ask)"
[ "$HN_PARC" = 0 ] || printf '      proof-add said: %s\n' "$HN_PA"
HN_C="$(git -C "$HN_T3" rev-parse HEAD)"; printf 'a.test.sh: 1/1 passed\n' > "$HN_RD/T3-green.log"
HN_OUT="$( cd "$HN" && CLAUDE_CODE_SESSION_ID="$WORLD_SID" bash "$SPAWN" land "$HN_T3" --by-hand --reason "landed on the report" \
  --suites a.test.sh --green-at "$HN_C" --log "$HN_RD/T3-green.log" 2>&1 )"; HN_RC=$?
expect_eq "(hn1) the hand landing of the born row exits 0" "0" "$HN_RC"
[ "$HN_RC" = 0 ] || printf '      land said: %s\n' "$HN_OUT"
HN_REC="$HN_RD/run.log"
expect_eq "(hn2) the row's verdict is written before its published line" "verdict published" \
  "$(awk -F'|' '$3 == "row=T3" && ($2 == "ev=verdict" || $2 == "ev=published") { sub(/^ev=/, "", $2); printf "%s%s", s, $2; s = " " }' "$HN_REC" 2>/dev/null)"
expect_eq "(hn3) …and the review's waiver ask is closed by the landing, with no regression and no waiver" "closed|landing T3" "$(hn_ask)"

finish
