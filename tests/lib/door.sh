# tests/lib/door.sh — the door fixture: a repository that carries the declared release check's whole closure,
# so a test pushes a landing through the real door and the check that judges it is the repository's own copy.
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_SCRIPTS_DIR names the tree under test
#     . "$(dirname "$0")/lib/assert.sh"
#     . "$(dirname "$0")/lib/door.sh"               # sources tests/lib/world.sh when no world is open
#
# THE INTERFACE (every door suite builds on these; their names, arguments and output are the contract):
#
#   door_world <dir>               builds the fixture repository at <dir> (absent or empty, under WORLD_ROOT) and
#                                  prints one line, `<root> <accepted head>`: the physical path and the 40-hex head
#                                  of the working branch `wave/x`, checked out at <root>. Build it once per suite.
#   door_world_single <dir>        the same fixture, its plan at `rigor: single`: the run a single-rigor review reads,
#                                  where one critic answers the evidence question and no auditor is dealt.
#   door_copy <root> <dir>         copies a built fixture to <dir>, binds the copy's own plan, and prints the same
#                                  line for the copy. A section that changes the fixture changes a copy.
#   door_piece <root> <row>        cuts the tree <root>/.worktrees/<row> on `wt/<row>` off the accepted head, with
#                                  its `.bionic` link, and prints its path. The plan's rows are T1 and T2.
#   door_release <root> <tree>     commits the release in <tree>: CHANGELOG.md gains the DOOR_VERSION entry whose
#                                  landing numbers `release-note` renders at the accepted head, and plugin.json
#                                  carries DOOR_VERSION. Prints the instant the numbers were rendered for.
#   door_run <root> <cmd> [args]   runs <cmd> from <root> as the bound session, with every exported variable that
#                                  names the tree under test unset and PATH stripped of it. Sets DOOR_OUT
#                                  (stdout and stderr) and DOOR_RC.
#   door_land <root> <tree> [why]  lands <tree> by hand through the tree under test's door, as door_run runs it:
#                                  `spawn-worktree.sh land <tree> --by-hand --reason <why>`. Sets DOOR_OUT and DOOR_RC.
#   door_readers <root> <commit>   writes a green verdict for each reader of the release set (lib/proof.sh
#                                  `_proof_release_readers`) at <commit> through lib/line.sh's writer, as the release
#                                  row's ready over them records them: the fixture holds none of those suites.
#   door_seen                      prints the sentinel file's lines, one per run of the fixture's check:
#                                  `pwd=<physical cwd> script=<physical path of the script that ran>`.
#
#   DOOR_VERSION, DOOR_NAME, DOOR_SEEN, DOOR_PLAN_REL: the release the plan names, the one entry in the names list,
#   the sentinel file, and the plan's path under <root>.
#
#   DOOR_LIVE_ROW=1, set for a door_world call, gives the plan the one live criterion a planner writes for a run's close:
#   a close row T9 at step 9, an Eval design row of a second requirement whose eval is `landing-report --hand-holds` at
#   the close, and its matrix row at tier T3, pending. It is owed at the close, which writes it. Unset, the plan is as before.
#
# WHAT THE FIXTURE HOLDS, at its accepted head, committed: hooks/ and payload/scripts/ copied whole from the tree
# under test, with the payload/hooks link; tests/run.sh and tests/lib/ whole, so the check and the name scan are
# the copies a relative `bash tests/lib/release-check.sh` opens there; CHANGELOG.md as the tree under test's HEAD
# commits it, the real file of more than a pipe's buffer, never a filler; payload/.claude-plugin/plugin.json.
# Ignored and so never landed: .bionic/config.yaml declaring `release-check: bash tests/lib/release-check.sh
# <list>`, the list a file beside <dir>, outside every checkout, and the check's files as bionic declares its own,
# `release-check-files:`; the bound plan with `release: DOOR_VERSION`,
# `working-branch: wave/x`, `base-sha:` the accepted head (the release range is what lands after it), and rows T1
# (build) and T2 (the release). The plan is a planner's Step-3 state, so it also carries what only the planner
# writes and no verb creates: `rigor: double` (`single` from door_world_single) and `scale: wave`, without which
# the judge cannot deal the readings a run owes, and the matrix skeleton, one `## Eval design` row and its
# `## Verification Matrix` table row at tier T1, which matrix-render, matrix-set and discharge fill. Every later
# state of the plan is a verb's.
#
# WHICH COPY RAN. The fixture's committed release-check.sh carries one line more than the tree under test's, after
# its shebang: when DOOR_SEEN names a file, it appends where it ran and which script it is. A run of the tree
# under test's copy, or of a piece's rewritten copy, appends nothing, so a test that reads the sentinel tells the
# copies apart. The door itself, spawn-worktree.sh and session-poker.sh, is the tree under test's: it is the code
# under test, as an installed plugin is to a project.
#
# bash 3.2 (ADR-001).

if [ -z "${BIONIC_SCRIPTS_DIR:-}" ]; then
  echo "door.sh: BIONIC_SCRIPTS_DIR is unset — source tests/lib/resolve-roots.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
if [ -z "${WORLD_ROOT:-}" ]; then
  # shellcheck source=/dev/null
  . "${BIONIC_SCRIPTS_DIR}/tests/lib/world.sh" || return 1
fi
if ! type -t bound_marker >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "${BIONIC_SCRIPTS_DIR}/tests/lib/bound-marker.sh" || return 1
fi

DOOR_VERSION="99.0.0"
# The listed name is built, never written whole: the fixture commits this file, and the name scan reads every
# file in a landing's range, so a literal here would be a hit in the fixture's own closure.
DOOR_NAME="zq-door-$((5000 + 521))"
DOOR_SEEN="$WORLD_ROOT/door-seen"
DOOR_PLAN_REL=".bionic/docs/plans/epic-x/wave-x.plan.md"
DOOR_SPAWN="${BIONIC_SCRIPTS_DIR}/payload/scripts/spawn-worktree.sh"
DOOR_POKER="${BIONIC_SCRIPTS_DIR}/hooks/session-poker.sh"
export DOOR_SEEN

# A fixture path is a directory under WORLD_ROOT: a command run from anywhere else would act on a real checkout.
_door_inside() {  # <path> -> 0 when it lies under WORLD_ROOT
  local p w
  p="$(cd "${1:-/nonexistent}" 2>/dev/null && pwd -P)" && w="$(cd "$WORLD_ROOT" && pwd -P)" || return 1
  case "$p/" in "$w"/?*) return 0 ;; esac
  return 1
}

door_world() { _door_world door_world double "${1:-}"; }          # <dir> -> `<root> <accepted head>`
door_world_single() { _door_world door_world_single single "${1:-}"; }   # <dir> -> the same, at `rigor: single`

# _door_world <name> <rigor> <dir> -> the fixture at <dir>, its plan at <rigor>; <name> heads every refusal
_door_world() (
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  local src="$BIONIC_SCRIPTS_DIR" me="$1" rigor="$2" dir="${3:-}" root list head plan
  case "$dir" in ''|*[[:space:]]*) echo "$me: name a directory, without blanks" >&2; exit 2 ;; esac
  mkdir -p "$dir" && root="$(cd "$dir" && pwd -P)" || exit 1
  _door_inside "$root" || { echo "$me: $root is outside WORLD_ROOT" >&2; exit 2; }
  [ -z "$(ls -A "$root")" ] || { echo "$me: $root is not empty" >&2; exit 2; }
  git -C "$root" init --quiet && git -C "$root" symbolic-ref HEAD refs/heads/main || exit 1
  [ "$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" = "$root" ] \
    || { echo "$me: git's toplevel is not $root — refusing" >&2; exit 1; }
  # The repository's own identity: a hand landing records `by=` from it, so no person's name reaches the record.
  git -C "$root" config user.name door && git -C "$root" config user.email door@example.invalid \
    && git -C "$root" config commit.gpgsign false || exit 1

  mkdir -p "$root/payload/.claude-plugin" "$root/tests"
  cp -R "$src/hooks" "$root/hooks" && cp -R "$src/payload/scripts" "$root/payload/scripts" \
    && cp -R "$src/tests/lib" "$root/tests/lib" && cp "$src/tests/run.sh" "$root/tests/run.sh" \
    && cp "$src/payload/.claude-plugin/plugin.json" "$root/payload/.claude-plugin/plugin.json" \
    && ln -s ../hooks "$root/payload/hooks" || exit 1
  git -C "$src" show HEAD:CHANGELOG.md > "$root/CHANGELOG.md" || exit 1
  # The sentinel, one line after the shebang: it runs before the check can exit, and only when DOOR_SEEN is set.
  awk 'NR == 1 { print; print "[ -z \"${DOOR_SEEN:-}\" ] || printf '\''pwd=%s script=%s\\n'\'' \"$(pwd -P)\" \"$(cd \"$(dirname \"$0\")\" && pwd -P)/${0##*/}\" >> \"$DOOR_SEEN\""; next } { print }' \
    "$src/tests/lib/release-check.sh" > "$root/tests/lib/release-check.sh" || exit 1
  printf '.bionic\n.bionic/\n.worktrees/\n' > "$root/.gitignore"
  git -C "$root" add -A && git -C "$root" commit --quiet -m "door: the check's closure" || exit 1
  git -C "$root" checkout --quiet -b wave/x || exit 1
  head="$(git -C "$root" rev-parse HEAD)" || exit 1

  list="$root-names.list"
  printf '%s\n' "$DOOR_NAME" > "$list" || exit 1
  mkdir -p "$root/.bionic/tmp" "$root/.bionic/docs/record/wave-x"
  printf 'release-check: bash tests/lib/release-check.sh %s\nrelease-check-files: %s\n' "$list" \
    'tests/lib/*.sh payload/scripts/lib/*.sh hooks/session-poker.sh hooks/poker/*.sh' > "$root/.bionic/config.yaml"
  plan="$root/$DOOR_PLAN_REL"
  mkdir -p "${plan%/*}"
  local live_step="" live_row="" live_eval="" live_ac=""
  if [ "${DOOR_LIVE_ROW:-}" = 1 ]; then
    live_step='
- T9: pending dispatch — the close'
    live_row='
| T9 | 9 | close | the close. The run reads its own measure last. | orchestrator | — | | 10 | REQ-2 | .bionic/docs/record/wave-x/continuation.md | | | pending |'
    live_eval='
| REQ-2 | the close reads its measure | AC-2.1 | live | `bash payload/hooks/session-poker.sh landing-report --hand-holds` at the close → `total=0` | the close reads above zero |'
    live_ac='
| AC-2.1 | T3 | pending | — | — |'
  fi
  cat > "$plan" <<PLAN
---
working-branch: wave/x
base-sha: $head
release: $DOOR_VERSION
rigor: $rigor
scale: wave
canonical_sdlc_version: 14
---
# door fixture plan (tests/lib/door.sh)

## SDLC State

current: 4
approved-by: fixture 2026-10-04T00:00Z "approved"
- Step 4: started
- T1: active
- T2: active$live_step

## Tasks

| id | step | kind | task | agent | deps | reads | size | serves | Files | worktree | base | status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | a library change | dw-T1 | — | | 10 | REQ-1 | payload/scripts/lib/said.sh | .worktrees/T1 | | active |
| T2 | 4 | doc | the release $DOOR_VERSION | dw-T2 | — | | 10 | REQ-1 | CHANGELOG.md, payload/.claude-plugin/plugin.json | .worktrees/T2 | | active |$live_row

## Eval design

| Requirement | Approach | Criterion | Eval type | Eval | Fails when |
|---|---|---|---|---|---|
| REQ-1 | fixture run | AC-1.1 | hermetic | \`tests/run.sh\` | the whole run is red |$live_eval

## Verification Matrix

stack-health: n/a: no long-running serve

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1.1 | T1 | pending | — | — |$live_ac
PLAN
  bound_marker "$root" "$WORLD_SID" "$plan" || exit 1
  printf '%s %s\n' "$root" "$head"
)

door_copy() (  # <root> <dir> -> `<root> <accepted head>` of the copy
  local src="${1:-}" dir="${2:-}"
  case "$dir" in ''|*[[:space:]]*) echo "door_copy: name a directory, without blanks" >&2; exit 2 ;; esac
  [ -d "$src/.git" ] && [ ! -e "$dir" ] || { echo "door_copy: $src is no fixture or $dir exists" >&2; exit 2; }
  cp -R "$src" "$dir" && dir="$(cd "$dir" && pwd -P)" || exit 1
  [ "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" = "$dir" ] || exit 1
  bound_marker "$dir" "$WORLD_SID" "$dir/$DOOR_PLAN_REL" || exit 1
  printf '%s %s\n' "$dir" "$(git -C "$dir" rev-parse refs/heads/wave/x)"
)

door_piece() (  # <root> <row> -> the tree's path
  local t="$1/.worktrees/$2"
  _door_inside "$1" || { echo "door_piece: $1 is no fixture under WORLD_ROOT" >&2; exit 2; }
  git -C "$1" worktree add --quiet -b "wt/$2" "$t" wave/x >/dev/null 2>&1 || exit 1
  ln -s "$1/.bionic" "$t/.bionic" || exit 1
  printf '%s' "$t"
)

door_release() (  # <root> <tree> -> the instant the numbers were rendered for
  local root="$1" tree="$2" head now on note
  _door_inside "$tree" || { echo "door_release: $tree is no fixture under WORLD_ROOT" >&2; exit 2; }
  head="$(git -C "$root" rev-parse refs/heads/wave/x)" || exit 1
  # One second before now: the record's lines carry whole seconds and the report keeps a line written AT the
  # instant, so an instant in the landing's own first second would fold that landing's events into the numbers.
  now="$(date -u +%s)"
  on="$(date -u -r "$((now - 1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((now - 1))" +%Y-%m-%dT%H:%M:%SZ)" || exit 1
  door_run "$root" bash "$DOOR_POKER" release-note --at "$head" --on "$on" "$root/$DOOR_PLAN_REL"
  [ "$DOOR_RC" -eq 0 ] || { printf 'door_release: release-note refused: %s\n' "$DOOR_OUT" >&2; exit 1; }
  note="$(mktemp "$WORLD_ROOT/door-note.XXXXXX")" && printf '%s\n' "$DOOR_OUT" > "$note" || exit 1
  awk -v v="$DOOR_VERSION" -v nf="$note" '
    !done && /^## [0-9]/ { print "## " v " — 2026-10-20"; print ""; print "### The landing numbers"; print ""
      while ((getline l < nf) > 0) print l
      print ""; done = 1 }
    { print }' "$tree/CHANGELOG.md" > "$note.changelog" && mv "$note.changelog" "$tree/CHANGELOG.md" || exit 1
  jq --arg v "$DOOR_VERSION" '.version = $v' "$tree/payload/.claude-plugin/plugin.json" > "$note.plugin" \
    && mv "$note.plugin" "$tree/payload/.claude-plugin/plugin.json" || exit 1
  git -C "$tree" add CHANGELOG.md payload/.claude-plugin/plugin.json \
    && git -C "$tree" commit --quiet -m "the release $DOOR_VERSION" || exit 1
  printf '%s' "$on"
)

door_run() {  # <root> <cmd> [args] -> DOOR_OUT, DOOR_RC
  local root="$1"
  shift
  _door_inside "$root" || { DOOR_OUT="door_run: $root is no fixture under WORLD_ROOT"; DOOR_RC=97; return 97; }
  DOOR_OUT="$(t="$BIONIC_SCRIPTS_DIR"
    cd "$root" 2>/dev/null || exit 97
    unset OLDPWD
    for n in $(compgen -e); do
      [ "$n" = PATH ] && continue
      case "${!n}" in (*"$t"*) unset "$n" 2>/dev/null ;; esac
    done
    PATH="$(printf '%s\n' "$PATH" | awk -F: -v t="$t" '{ for (i = 1; i <= NF; i++) if (index($i, t) != 1) { printf "%s%s", s, $i; s = ":" } }')"
    export PATH CLAUDE_CODE_SESSION_ID="$WORLD_SID"
    "$@" 2>&1)"; DOOR_RC=$?
}

door_land() {  # <root> <tree> -> DOOR_OUT, DOOR_RC: the tree landed by hand through the door
  door_run "$1" bash "$DOOR_SPAWN" land "$2" --by-hand --reason "${3:-door fixture}"
}

door_readers() {  # <root> <commit>
  bash -c '. "$1/line.sh" && . "$1/proof.sh" || exit 1; for s in $(_proof_release_readers); do line_event "$2" verdict row=T2 "commit=$3" "suite=$s" result=green log=- admitted=- width=- || exit 1; done' \
    _ "$BIONIC_SCRIPTS_DIR/payload/scripts/lib" "$1/$DOOR_PLAN_REL" "$2"
}

door_seen() { cat "$DOOR_SEEN" 2>/dev/null; }
