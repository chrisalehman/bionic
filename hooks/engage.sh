#!/bin/bash
# ENGAGE: the one act that puts a session inside bionic.
#
# task-engaged-session (Chris, 2026-09-03): "all guardrails imposed by bionic should only
# apply when exercising bionic. Nothing should apply until bionic is triggered" — and the
# trigger is the canonical-sdlc skill, nothing else. 1.4.0 shipped walls scoped by
# `active_run <repo>` alone, so any session in a repo with an open plan was walled by a run
# it never asked for. This hook records the entry, mechanically, at the
# instant the skill is invoked; every other bionic hook asks `engaged_session` before it
# asks anything else.
#
# TWO PATHS, because invocation has two shapes and only one of them is a tool call:
#   PreToolUse / tool_name "Skill" / tool_input.skill   the model-invoked path
#   UserPromptExpansion / command_name                  the user-typed slash-command path
# A typed `/bionic:canonical-sdlc` is NOT a Skill tool call and NOT a plain
# UserPromptSubmit prompt (measured across every transcript on this machine,
# record/task-engaged-session/research-callsites.md §5.2): it reaches the model as a
# `<command-message>` wrapper, so a prompt-prefix test would never match it. The harness
# fires UserPromptExpansion for exactly that expansion, with the command name as a
# first-class field (docs: "UserPromptExpansion | command name | your skill or command
# names"). Both spellings of the name are accepted, qualified and bare, with or without
# the leading slash the typed form carries.
#
# THE FAIL DIRECTION IS INVERTED HERE, deliberately, and it is the only place in this tree
# where it is. Everywhere else an unreadable state CLOSES a wall; the marker this writes is
# the one artifact whose PRESENCE opens them. So every doubt resolves to NOT engaging: a
# name that is not exactly canonical-sdlc, a root that will not resolve, a session id that
# is empty or misshapen, a symlink anywhere on the path. The cost of not engaging is one
# more invocation; the cost of engaging wrongly is every wall in the fleet binding a
# session that never consented, which is the bug this exists to fix.
#
# IT NEVER BLOCKS, AND SPEAKS ONCE. Exit is 0 on every hook path — a trigger that could refuse
# the skill it exists to notice would be a wall in front of the front door. (The typed verb
# `engage.sh --root <dir>`, below, exits 2 on its own misuse: no hook ever passes it.) What it
# says is said to the MODEL, once per invocation, as one object on stdout,
# `hookSpecificOutput.additionalContext`, holding up to two things: why the count rule declined
# a run another live session holds (see THE HELD RUN below), and, when the invocation's argument
# is a handoff file, the one resume command to run, whole (see THE RESUME COMMAND below).
# Registered twice in hooks/hooks.json.
#
# [WALL: tests/engage.test.sh]

set -u

command -v jq >/dev/null 2>&1 || exit 0

# ---------- THE VERB: `engage.sh --root <dir>` (wave-36 T4; D11, AC-5.4) ----------
#
# THE FAULT (research-landing-and-walls.md C44). The root below is CLAUDE_PROJECT_DIR, else the
# payload's cwd, walked up to the nearest `.bionic`. A walker's scratch project inside this
# project's tree therefore engaged THIS project, and no verb engaged an outside root. `--root
# <dir>` engages <dir> itself: the root is <dir>, never walked up and never overridden by
# CLAUDE_PROJECT_DIR, and the marker goes under `<dir>/.bionic/tmp`. Every hook whose root
# resolves to <dir> afterwards (the walk stops at the `.bionic` made here) reads it engaged, the
# recorder's scratch line included.
#
# THE VERB IS THE TRIGGER. hooks.json passes no argument, so `--root` arrives only from a command
# someone typed: that is the consent the trigger test below asks for, and no payload is read. The
# session id is the environment's (L-SESSION: env primary), as for every hook.
#
# MISUSE EXITS 2 WITH ONE LINE: no operand, an operand that is not a directory, no session id.
# The hook paths still exit 0 on every path; a verb that failed silently would leave its caller
# believing a root is engaged. Past argument checking the verb takes the hook's own path, so its
# refusals (a linked `.bionic`, an unwritable tmp) are the hook's, and the one line it prints on
# success is printed only when the marker is there.
ROOT_ARG=""
ROOT_MODE=0
if [ "${1:-}" = "--root" ]; then
  ROOT_MODE=1
  if [ $# -ne 2 ] || [ -z "${2:-}" ]; then
    echo "engage: usage: engage.sh --root <dir> — engages <dir> for this session (CLAUDE_CODE_SESSION_ID)" >&2
    exit 2
  fi
  ROOT_ARG="$(cd "$2" 2>/dev/null && pwd -P)" || ROOT_ARG=""
  if [ -z "$ROOT_ARG" ] || [ ! -d "$ROOT_ARG" ]; then
    echo "engage: --root $2 is not a directory — nothing engaged" >&2
    exit 2
  fi
  if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    echo "engage: --root needs this session's id in CLAUDE_CODE_SESSION_ID — nothing engaged" >&2
    exit 2
  fi
  INPUT=""
else
  INPUT=$(cat)
fi

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- IS THIS THE TRIGGER? ----------
#
# Asked before anything else is read, and before a single byte is written anywhere: this
# hook is delivered on every Skill call and every command expansion in every project on
# the machine, and for all but one name it must cost nothing and do nothing.
if [ "$ROOT_MODE" -eq 0 ]; then
  NAME=""
  case "$(_jq '.hook_event_name')" in
    PreToolUse)
      [ "$(_jq '.tool_name')" = "Skill" ] || exit 0
      NAME=$(_jq '.tool_input.skill')
      ;;
    UserPromptExpansion)
      NAME=$(_jq '.command_name')
      ;;
    *) exit 0 ;;
  esac

  # `^(bionic:)?canonical-sdlc$`, anchored at both ends, plus the leading slash the typed
  # form may carry. `canonical-sdlc-notes` and `other:canonical-sdlc` are not this skill.
  case "${NAME#/}" in
    canonical-sdlc|bionic:canonical-sdlc) ;;
    *) exit 0 ;;
  esac
fi

if [ "$ROOT_MODE" -eq 1 ]; then
  CWD="$ROOT_ARG"
else
  CWD="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$CWD" ]; then
    CWD=$(_jq '.cwd')
  fi
fi
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

# ---------- the library ----------
#
# The stub below sources the one loader, payload/scripts/lib/loader.sh. FAIL OPEN: a trigger that refused the
# invocation it exists to record would be worse than one that misses it. A missed
# engagement leaves the session unwalled, which is exactly the state it was in a moment
# ago; a refused `/canonical-sdlc` is a broken front door.
BIONIC_LIB_WANT="root.sh run.sh session.sh binding.sh patrol.sh"
# Find the library through lib/loader.sh beside this hook; payload/scripts/lib/loader.sh says how.
_bl_dir="$(dirname "$0")"; _bl_l="$_bl_dir/../scripts/lib/loader.sh"; [ -r "$_bl_l" ] || _bl_l="$_bl_dir/../payload/scripts/lib/loader.sh"
# shellcheck source=/dev/null
if [ -r "$_bl_l" ]; then . "$_bl_l"; bionic_load; else
  BIONIC_LIB=""; BIONIC_LIB_MISSING="${BIONIC_LIB_WANT%% *}"; BIONIC_LIB_CANDS="$_bl_dir/../scripts/lib, $_bl_dir/../payload/scripts/lib"
  loader_fail_open() { echo "$1: library $BIONIC_LIB_MISSING not found at $BIONIC_LIB_CANDS — hook stepping aside; run /bionic:doctor" >&2; exit 0; }
  loader_fail_closed() { set -- "$1"; [ "${#1}" -le 25 ] || set -- "${1:0:24}…"; echo "bionic: load refused — $1 cannot load the bionic library (run /bionic:doctor)" >&2; exit 2; }
fi
if [ -n "$BIONIC_LIB_MISSING" ]; then loader_fail_open "engage"; fi
# shellcheck source=/dev/null
. "$BIONIC_LIB/root.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/run.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/session.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/binding.sh"
# shellcheck source=/dev/null
. "$BIONIC_LIB/patrol.sh"   # patrol_live_session_ids — the sweeper's liveness (T13)

# ---------- ROOT, SESSION ID, MARKER PATH — the three facts, each from its one owner ----
#
# The env value is primary and the payload is a witness (L-SESSION): the marker filename is
# what sixteen hooks will later build from their own `session_id` answer, so a trigger that
# preferred the payload would write a file nobody reads. `engaged_marker_path` owns the
# whole shape rule — empty, `unknown`, and any character outside [A-Za-z0-9_-] are refused
# there, once, rather than restated here.
# Under `--root` the root is the directory named, never the walk's answer: the walk is what
# carried a nested scratch directory up into the project around it (C44).
if [ "$ROOT_MODE" -eq 1 ]; then
  REPO="$ROOT_ARG"
else
  REPO=$(project_root "$CWD")
fi
[ -n "$REPO" ] && [ -d "$REPO" ] || exit 0

SID=$(session_id "$(_jq '.session_id')" 2>/dev/null) || SID=""
[ -n "$SID" ] || exit 0

MARKER=$(engaged_marker_path "$REPO" "$SID") || exit 0

# ---------- THE TREE ----------
#
# NOTHING IN THE PAYLOAD OWNS TREE CREATION TODAY — only SKILL.md's Step-0 prose, which is
# a model instruction, not a mechanism. A first run in a fresh project would engage and
# then find nowhere to put the marker, so the walls would stay off for the whole session:
# the fail-open direction turning into a silent no-op precisely where a run is starting.
# The tree is therefore created here, and `.gitignore` = `*` goes with it because
# `.bionic/` is machine-local by decision and a project that committed it would carry
# another machine's session markers.
#
# A SYMLINKED .bionic IS REFUSED, not followed. `project_root` already skips a symlinked
# `.bionic` on its walk, so this is the case where the root came from the git-toplevel
# fallback — and writing through it would put a session's engagement wherever the link
# points.
BDIR="$REPO/.bionic"
[ -L "$BDIR" ] && exit 0

FRESH=no
[ -d "$BDIR" ] || FRESH=yes

mkdir -p "$BDIR/tmp" 2>/dev/null || {
  echo "engage: cannot create $BDIR/tmp — this session stays unengaged" >&2
  exit 0
}
if [ "$FRESH" = "yes" ] && [ ! -e "$BDIR/.gitignore" ]; then
  printf '*\n' > "$BDIR/.gitignore" 2>/dev/null || :
fi

# An existing .bionic/tmp that is not a real writable directory is REPORTED and then let
# go. Never blocked: whatever is wrong with the tree, refusing the skill invocation is not
# the repair, and stderr on a zero exit reaches a debug log rather than the turn.
TMP="$BDIR/tmp"
if [ -L "$TMP" ] || [ ! -d "$TMP" ] || [ ! -w "$TMP" ]; then
  echo "engage: $TMP is not a writable directory — this session stays unengaged" >&2
  exit 0
fi

# ---------- THE MARKER ----------
#
# A symlink at the marker path is refused before it is followed — the guard idiom every
# writer of the state directory takes, and it matters more here: a planted link would let a
# hostile repo have this hook clobber a file outside the tree, on the one write bionic
# performs at the invocation the user just typed.
[ -L "$MARKER" ] && exit 0

# THE PLAN IS A FIELD, NOT A PRECONDITION. Step 0 of a new run precedes its plan file, and
# engagement is what decides WHETHER a hook acts while the binding decides WHAT — so a
# marker written before any plan exists is the normal opening state, not a degraded one.
#
# WHICH plan the field names changed in wave-session-bound-run (2026-09-04, spec §Design
# "Session binding"; AC-7). This used to be `active_run` — the NEWEST open plan in the root
# — written unconditionally on every invocation, and that was the bug: two sessions in one
# repository got one run identity, and a plan landing mid-session silently moved a live
# session onto it. The rule now, in two lines:
#
#   a marker for this session exists -> LEAVE ITS BINDING. Re-engagement decides nothing.
#   no marker yet (first engagement)  -> EXACTLY ONE live run: bind to it; else `none`
#
# (The first line read "the marker already names a plan" until wave-23-fixit-1810 T15; see
# FIRST ENGAGEMENT ONLY below for why `plan=none` is now a binding this hook keeps too.)
#
# A BINDING SURVIVES RE-ENGAGEMENT WHETHER OR NOT ITS PLAN IS STILL OPEN (S10a, review C-1).
# It used to survive only while `session_run` said `bound-open`; a `bound-closed` binding
# fell to the count rule, and when the root held exactly one open run that run belonged to
# ANOTHER SESSION. A session whose own wave had just closed re-invoked the skill and was
# silently moved onto the neighbour's plan, after which its evidence gate gated on that
# plan — symptom 1 of the bug this wave was opened on, reached through the engagement door
# instead of the scan. A binding is a commitment (AC-6) and a dead commitment is still not
# somebody else's: the operator ends it with `session-poker.sh bind <plan>`, not the hook.
#
# SO THE VERDICT IS NOT ASKED FOR HERE, ONLY THE FIELD. `session_plan` reads two lines off
# disk and answers "is this session bound"; `session_run` would additionally rule on whether
# the plan is open, and on an UNBOUND session it walks the whole tree through `active_run` to
# produce a `fallback` this hook then discards. That walk was one of three (review P1): a
# bound session now does NONE, and an unbound one does the two `open_runs` walks the count
# rule and the writer's own membership check each need.
#
# SEVERAL OPEN RUNS BINDS NOTHING, deliberately. Picking the newest would be the old bug
# with extra steps; the session is left unbound, session-start lists every candidate, and
# the operator chooses with `session-poker.sh bind <plan>`. An unbound session still
# resolves by `active_run`, out loud, as `fallback`.
#
# THE WRITE ITSELF IS NOT HERE. `payload/scripts/lib/binding.sh` is the single writer —
# shape, mode 600, the symlink refusal and open-run membership are its invariants, shared
# with poker's `bind` verb and the governing skill's bind-on-first-write. This hook only
# decides WHICH plan, and never blocks on the answer: every path below exits 0.
BOUND=0
ENGAGE_HELD_BY=""; ENGAGE_HELD_PLAN=""
if PLAN=$(session_plan "$REPO" "$SID" 2>/dev/null); then
  BOUND=1
elif [ -e "$MARKER" ] || session_binding "$REPO" "$SID" >/dev/null 2>&1; then
  # A binding to none recorded beside the seal is that same answer, and it stands when the
  # marker has been removed: removing a file in the state folder is no first engagement.
  #
  # FIRST ENGAGEMENT ONLY (wave-23-fixit-1810 T15, critic N-1; spec D1 Δ5). A marker that
  # exists but names no plan — `plan=none`, or an older writer's empty file — is a binding
  # too: the answer this hook, or the operator, already gave. It is rewritten as `none`
  # through the one writer and never re-derived, because RE-DERIVING IT IS HOW A RUN CHANGES
  # HANDS. The held rule below leaves a bystander B at `none` beside A's live run. When A
  # `/clear`s, the CLI rewrites A's pid file with A2's id, so A's marker belongs to no live
  # session; had B's next skill invocation run the count rule again, it would find the run
  # unheld and bind B to it, and A2 would then be told B holds its own wave (critic N-1,
  # `clearrace.sh`): the seed's symptom by ownership transfer. Nothing that changes between
  # B's engagements — a holder dying, a /clear, a run opening or closing — is a reason for B
  # to own a run it never asked for, so the guess is made once, at the first engagement, and
  # a later binding is made by hand (`session-poker.sh bind <plan>`) or by the governing
  # skill's bind-on-first-write when B writes its own plan. A2 is a NEW session id with no
  # marker, so it is a first engagement and binds the now-unheld run.
  PLAN="none"
else
  PLAN="none"
  # wave-roster-lifecycle S2 (spec AC-2; design §2 "engage.sh"): the count rule counts
  # LIVE runs, not merely open ones — an open-but-quiet run is not "being worked", and
  # binding to it reproduces this hook's own bug one layer down. `live_runs ⊆ open_runs`
  # always (run.sh), so this is strictly narrower than the old open-run set; the `= "1"`
  # rule and the single `bind_plan` call site below are unchanged.
  RUNS=$(live_runs "$REPO" 2>/dev/null) || RUNS=""
  if [ -n "$RUNS" ] && [ "$(printf '%s\n' "$RUNS" | wc -l | tr -d ' ')" = "1" ]; then
    PLAN="$RUNS"
    # THE HELD RUN (wave-23-fixit-1810 T13, critic C-3; spec D1 Δ4, decided under autopilot,
    # reversible). "Exactly one live run" said nothing about WHOSE run it is. In the seed's
    # root shape — the only live run belongs to another session that is still running — the
    # count rule bound this session to it, and from then on every gate correctly charged it
    # for that session's ledger: `not launched: T13` at every turn end, the seed's symptom
    # through the engagement door. So before the guess is written, the other sessions'
    # markers are asked whether one names this plan (`bind_holders`, lib/binding.sh), and a
    # holder that is LIVE keeps it: this session is written `none` and told, below, how to
    # bind by hand if it really is joining that run.
    #
    # LIVE IS THE SWEEPER'S WORD, NOT A NEW ONE. `patrol_live_session_ids` (lib/patrol.sh) is
    # the set `patrol_dead_sessions` subtracts and `session-poker.sh sweep` deletes by: a
    # `sessions/<pid>.json` under the claude home whose pid answers `kill -0`. A `/clear`
    # rewrites that same pid file with the new id, so a predecessor's marker belongs to no
    # live session and a resume after `/clear` binds exactly as before. Asked only when a
    # holder exists, so the common case pays one glob of `.bionic/tmp` and nothing more.
    #
    # A BIND BY HAND IS NOT THIS RULE'S BUSINESS. `session-poker.sh bind` and the governing
    # skill's bind-on-first-write go straight to `bind_plan`, whose own refusals stand; this
    # declines a GUESS, never a choice.
    if bind_holders "$REPO" "$SID" "$PLAN"; then
      ENGAGE_LIVE=$(patrol_live_session_ids 2>/dev/null) || ENGAGE_LIVE=""
      while IFS= read -r _h; do
        [ -n "$_h" ] || continue
        # Newline-delimited containment — `patrol_dead_sessions`' own idiom, so an id that is
        # a PREFIX of a live one is not mistaken for it.
        case "
$ENGAGE_LIVE
" in
          *"
$_h
"*) ENGAGE_HELD_BY="$_h"; ENGAGE_HELD_PLAN="$PLAN"; PLAN="none"; break ;;
        esac
      done <<< "$BIND_HOLDERS"
    fi
  fi
fi

# ONE WRITE STATEMENT, AND THE RETRY RIDES IT. Read left to right: write the binding; if the
# writer refuses and this session was ALREADY BOUND, that refusal is the right answer and the
# marker stands (the bound plan has closed — a commitment is not somebody else's to reassign,
# AC-6); if it refuses and the session was UNBOUND, fall to `none`.
#
# THE UNBOUND RETRY IS NOT DEFENSIVE PADDING (S10a, review C-4). `PLAN` comes off a walk that
# has already finished and `bind_plan` walks AGAIN for its own membership check, so a run
# closing inside that window made the single write refuse and left the session with NO MARKER
# AT ALL — unengaged, and therefore unwalled, which is the one direction this hook's own
# fail-direction argument forbids. `none` is what the count rule would have said had the walk
# seen the close.
#
# ONE LINE, DELIBERATELY. tests/cross-gate-agreement.test.sh §B2 proves this hook writes
# through the single writer by replacing this call site with an inline redirect and requiring
# the marker's SHAPE to change; a second `bind_plan` statement on another line would leave
# that mutation replacing a call the fixture never reaches, and the proof would pass on the
# unmutated path. The shape of the code is holding the shape of the proof.
#
# THE ACT IS NAMED: `engage` is this hook's word in the run's bind event, which `bind_plan` appends
# beside the marker when the binding names a plan and the run does not hold this session yet — a
# re-engagement of a bound session appends it once, then never again.
bind_plan "$REPO" "$SID" "$PLAN" engage || [ "$BOUND" = 1 ] || bind_plan "$REPO" "$SID" none || :

# ---------- TELL THE MODEL WHY IT IS UNBOUND ----------
#
# Only when THE HELD RUN above declined a binding, and only after the marker says so. The
# channel is the event's own `hookSpecificOutput.additionalContext` on stdout — both events
# this hook is registered on carry it (PreToolUse and UserPromptExpansion, read off the CLI
# 2.1.288 bundle's hook-output schema) — because stderr on a zero exit reaches a debug log and
# not the turn, and the reader this sentence is for is the model about to act. The second
# line is `run_unbound_advisory`'s sentence, unchanged, so it reads as every gate's advisory
# reads; the first says why the bind it offers is not the obvious move.
ENGAGE_CTX=""
if [ -n "$ENGAGE_HELD_BY" ] && [ "$(session_plan "$REPO" "$SID" 2>/dev/null || echo none)" = "none" ]; then
  ENGAGE_CTX="bionic: this session was left unbound — the root's one live run is bound to live session $ENGAGE_HELD_BY; bind to it only if this session is joining that run.
$(run_unbound_advisory "$ENGAGE_HELD_PLAN")"
fi

# ---------- THE RESUME COMMAND, WHOLE ----------
#
# The method's page names the resume command with no folder, and nothing a session is shown
# after a /clear carries the plugin's root, so a model left to find session-poker.sh searched
# for it and ran it through a variable. The farm-out wall cannot read a script held in a
# variable and reads that shape as a suite (payload/scripts/lib/cmd-class.sh, reading 4 of its
# header), so the resume's first call was refused. This hook knows its own folder; the model
# does not. So when the invocation's argument is a handoff file, the one command is said here,
# whole: `bash <this hooks folder as invoked, absolute>/session-poker.sh resume <the file, absolute>`,
# each word quoted when it holds a character the shell would split or expand, so the line
# pasted as written is one command of four words and the wall reads it as no suite.
#
# THE ARGUMENT, PER PATH (read off the CLI 2.1.329 bundle): the Skill tool's input is
# `{skill, args?}`, so PreToolUse carries `tool_input.args`; UserPromptExpansion carries
# `command_args`, the text typed after the command's name. The whole text, trimmed, is the
# path, so a file name holding a space is read whole.
#
# IS A HANDOFF is the door's reading in hooks/session-start.sh, its three conditions as they
# stand there: a regular file, not a symlink, whose first line is `bionic-handoff/v1`; a
# relative path is read against the project root, as the door and the resume verb read it.
#
# ANY DOUBT SAYS NOTHING: no argument, a control character in it, a path to no file, a file
# that fails the door's test, or no session-poker.sh beside this hook. Saying nothing leaves the
# model where it stood before; saying a command that does not run is a refusal of its own.
_engage_word() {  # <text> -> the text as one shell word
  case "$1" in
    *[!A-Za-z0-9_./:@%+=,-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}
if [ "$ROOT_MODE" -eq 0 ]; then
  ENGAGE_ARG=""
  case "$(_jq '.hook_event_name')" in
    PreToolUse)          ENGAGE_ARG=$(_jq '.tool_input.args') ;;
    UserPromptExpansion) ENGAGE_ARG=$(_jq '.command_args') ;;
  esac
  case "$ENGAGE_ARG" in *[[:cntrl:]]*) ENGAGE_ARG="" ;; esac
  ENGAGE_ARG="${ENGAGE_ARG#"${ENGAGE_ARG%%[![:space:]]*}"}"
  ENGAGE_ARG="${ENGAGE_ARG%"${ENGAGE_ARG##*[![:space:]]}"}"
  case "$ENGAGE_ARG" in
    '') ENGAGE_FILE="" ;;
    /*) ENGAGE_FILE="$ENGAGE_ARG" ;;
    *)  ENGAGE_FILE="$REPO/${ENGAGE_ARG#./}" ;;
  esac
  ENGAGE_POKER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-poker.sh" || ENGAGE_POKER=""
  if [ -n "$ENGAGE_FILE" ] && [ -f "$ENGAGE_FILE" ] && [ ! -L "$ENGAGE_FILE" ] \
     && [ "$(head -n 1 "$ENGAGE_FILE" 2>/dev/null)" = "bionic-handoff/v1" ] \
     && [ -n "$ENGAGE_POKER" ] && [ -f "$ENGAGE_POKER" ]; then
    ENGAGE_CTX="${ENGAGE_CTX:+$ENGAGE_CTX
}bionic: resume this run with this one command, as written: bash $(_engage_word "$ENGAGE_POKER") resume $(_engage_word "$ENGAGE_FILE")"
  fi
fi

# ONE OBJECT, whatever is said: two objects on one hook's stdout are not one answer.
if [ -n "$ENGAGE_CTX" ]; then
  ENGAGE_EVENT=$(_jq '.hook_event_name')
  if [ "$ROOT_MODE" -eq 1 ]; then
    # The verb has no event to answer on: its reader is whoever typed it, on stderr.
    printf '%s\n' "$ENGAGE_CTX" >&2
  else
    jq -nc --arg e "$ENGAGE_EVENT" --arg c "$ENGAGE_CTX" \
      '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || :
  fi
fi

# THE VERB SAYS WHAT IT ENGAGED, once, and only when the marker is there to say it.
if [ "$ROOT_MODE" -eq 1 ] && [ -f "$MARKER" ] && [ ! -L "$MARKER" ]; then
  printf 'engage: engaged %s for session %s\n' "$REPO" "$SID"
fi

exit 0
