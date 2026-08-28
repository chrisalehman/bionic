#!/bin/bash
# THE PATROL SELF-HEAL — epic-19 wave-01, spec AC-F6; design ledger D4, ratified
# 2026-08-27 ("Simply update the user in the terminal of the issue, and reload the
# Patrol").
#
# WHAT IT IS FOR. The CLI holds its cron table in PROCESS MEMORY, with no file
# behind it (payload/scripts/lib/patrol.sh's own honest limit, and doctor's). A
# `claude plugin update`, a `/reload-plugins`, a session continue or a
# `/clear`+resume can therefore delete the Patrol job and leave nothing that says
# so: the run keeps working, the poker never ticks again, no row is ever judged
# against its declared duration, and the fleet dies quiet. The stamp goes stale one
# window later — but only where somebody LOOKS, and until this hook existed the
# only two places that looked were a dispatch attempt (hooks/dispatch-preflight.sh's
# arming wall) and a hand-run `/bionic:doctor`. Between them, nothing observed it
# and nothing told anyone. This hook is the thing that looks, every turn.
#
# WHY THE STOP CHANNEL, and not one of the stop hooks that already exist. The
# detection has to fire on the run's own rhythm rather than on a dispatch — that is
# the whole gap. `Stop` is the only recurring orchestrator event there is: it fires
# once per turn, whatever the turn contained, and it keeps firing on turns the skill
# was not re-invoked on (hooks/landing-gate.sh depends on and documents those exact
# properties). hooks/stop-guard.sh is `PreToolUse|TaskStop` — it fires when the
# orchestrator stops an AGENT, which is neither recurring nor about the session's
# clock; hooks/stop-check.sh is not registered on any channel at all. So the choice
# was Stop or nothing.
#
# WHY A BLOCK AND NOT A PRINT. A shell hook cannot call `CronCreate` — that is a
# model tool, and re-creating the cron job is half of what "reload the Patrol"
# means. What a Stop hook CAN do is refuse the stop once with a `reason`, which the
# CLI renders into the operator's terminal and hands to the model as the next thing
# to act on. One mechanism therefore carries both halves of AC-F6: the reason IS the
# terminal notice, and it is also the instruction that gets the Patrol re-armed. The
# pattern is hooks/patrol-duties-gate.sh's, registered beside it on the same channel.
#
# IT MUST NEVER ARM THE STAMP ITSELF, and this is the sharpest edge in the file. A
# hook that ran `session-poker.sh arm` would freshen the stamp over a cron table
# that still holds nothing — buying a Patrol that reads alive to the arming wall,
# to doctor and to this hook, and that never fires again. That is strictly worse
# than the death it was meant to heal, because the death is at least detectable.
# So this gate READS, exactly like every other gate (TDD §3.2), and the re-arm is
# named in the reason with its cron half FIRST. tests/patrol-revive.test.sh Group 5
# pins the stamp's mtime across a firing.
#
# THE THREE STAMP STATES, and why only one of them speaks:
#   absent  -> silent. Never armed, OR deliberately disarmed — `session-poker.sh
#              disarm` removes the stamp, which is how a run says its Patrol was
#              ended on purpose. Never-armed is a real finding, but it is the ARMING
#              WALL's to make at the moment a dispatch is attempted; raised here it
#              would nag every session that has the skill armed and has not engaged
#              a run yet, which is the first turn of every run.
#   fresh   -> silent. Firings are landing; a monitor with nothing to say says so
#              by saying nothing.
#   stale   -> THE NOTICE. Something armed a Patrol on THIS session and the clock
#              has stopped.
#
# SCOPE — WHAT "AN ACTIVE RUN" IS HERE, and the alternative that was rejected. Two
# conditions, and no third. First, this hook is registered in
# skills/canonical-sdlc/SKILL.md's own frontmatter, so it is live exactly while the
# governing skill is armed — the same self-limiting scope hooks/patrol-duties-gate.sh
# relies on. Second, a stamp EXISTS for this session, which by doctrine
# (SKILL.md §Dispatch) happens at the Step-0 confirmation of a new run or the resume
# ritual of an open one, and at no other moment. An armed-then-stale stamp is
# therefore already the statement "a run engaged on this session and its clock died".
# REJECTED: also reading the newest plan's `## SDLC State` `current:`, the way
# hooks/dispatch-preflight.sh scopes its own walls. It would add a fifth copy of
# that block for no verdict this hook would change, and it would import a MEASURED
# silent-inert mode — a marker-less `*.md` winning the newest-file race disarmed the
# dispatch wall repo-wide for ~15 minutes on 2026-08-15
# (record/session-20260815-landing-supervision/t8-forensic-read.md). A monitor whose
# job is to notice silence must not acquire a new way to go silent.
#
# FAIL DIRECTIONS (pinned by tests/patrol-revive.test.sh):
#   - jq absent                                       -> pass, silent
#   - not a Stop payload (SubagentStop included)      -> pass, silent
#   - stop_hook_active true                           -> pass, silent (ONE block per
#                                                        turn, not one per session)
#   - no session_id, or one not shaped like one       -> pass, silent
#   - no cwd, or no resolvable project root           -> pass, silent
#   - no stamp, or a symlink where the stamp goes     -> pass, silent (never armed,
#                                                        or deliberately disarmed)
#   - no poker on either lane, or no readable interval-> pass, silent (no threshold)
#   - the stamp's mtime unreadable                    -> pass, silent
#   - stamp age within 2x the poker-interval          -> pass, silent
#   - stamp age past it                               -> BLOCK, naming the re-arm
#
# THREE ACCEPTED LIMITS. First, inherited from the stamp and shared with the arming
# wall: this attests that Patrol FIRINGS ARE LANDING and cannot see the cron table,
# so a job deleted moments ago still looks alive for up to one stale window — the
# notice is late by design rather than wrong. Second, and now CLOSED where it
# used to be unbounded: a deliberate stop was indistinguishable from a death.
# Nothing in production removed a stamp, so a Patrol the run ended on purpose —
# the run-close `CronDelete`, or the poker's own DISARM decision, which is reached
# on every quiet stretch between dispatch batches — left an aging stamp behind and
# was reported dead here on EVERY remaining turn of the session. This notice does
# not "block once" in the sense that matters: `stop_hook_active` suppresses only
# the second stop WITHIN one turn and resets at the next, so the blocks are one
# per turn, forever, and the CLI's own override after 8 CONSECUTIVE blocks can
# never engage above us because one-per-turn blocks are never consecutive. There
# is no backstop; the stamp going away is the whole of the exit (critic C-2,
# epic-19 w1). `session-poker.sh disarm` is what makes it go away: the run-close
# ritual (SKILL.md §Dispatch) and a DISARM tick both take it, and an ABSENT stamp
# is silent here by design. WHAT REMAINS is a disarm that FORGOT the verb — a
# `CronDelete` with no `disarm` beside it — which still reads as a death; its cost
# is one re-armed clock on a run that was nearly over, against a fleet nobody is
# waiting on for the opposite error. Third, THIS HOOK SHARES THE FAILURE MODE IT MONITORS.
# It is registered in skills/canonical-sdlc/SKILL.md's own frontmatter, so it is
# live exactly while the governing skill is armed — and a skill's hooks die with
# the conversation that armed them (SKILL.md §Dispatch). Three of the four events
# that kill the Patrol — a session continue, a `/clear`+resume, a `/reload-plugins`
# — also deregister this hook itself, silently and at the same moment. The resume
# ritual's re-invoke of the governing skill is the standing cure for those three,
# re-arming this hook along with everything else it re-arms; a `claude plugin
# update` mid-session, which leaves the skill armed and the hook alone stale, is
# this hook's real coverage.
#
# Registered on the Stop channel in skills/canonical-sdlc/SKILL.md; live only while
# that skill is armed.
# [WALL: tests/patrol-revive.test.sh]

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)

_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# THIS SCRIPT'S OWN DIRECTORY, so the poker it measures against and the poker it
# NAMES are the same file — resolved the way hooks/dispatch-preflight.sh resolves
# its sibling, never through PATH (a hook's PATH is not ours to trust) and never
# through an env seam (a seam on the path under test leaves the production path
# unverified).
HOOK_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$HOOK_DIR" ] || HOOK_DIR="$(dirname "$0")"

# ---------- relevance hoist ----------
# SubagentStop is deliberately NOT accepted. A subagent arms no Patrol — SKILL.md
# §Dispatch, "subagents stay timerless" — so a worker's turn end can prove nothing
# about the orchestrator's clock, and refusing it would hold a worker hostage to
# its dispatcher's obligations.
[ "$(_jq '.hook_event_name')" = "Stop" ] || exit 0

# BLOCKS ONCE PER TURN, which is not the same as once. Claude Code re-enters the
# stop with stop_hook_active true after a hook blocked it; refusing a second time
# would wedge the turn with no way out. One refusal names the re-arm; the second
# stop is the orchestrator's to decide about. That re-entry is this hook's safety
# valve — nothing it demands can ever be unsatisfiable, because stopping again
# always passes — but the flag resets at the NEXT turn, so a stamp that stays
# stale is a notice that returns turn after turn. What ends it is the stamp: a
# re-arm freshens it, `session-poker.sh disarm` removes it, and nothing else does.
[ "$(_jq '.stop_hook_active')" = "true" ] && exit 0

# Every path below interpolates the session key, and the stamp filename is the
# whole of what this hook reads — so a key carrying a path separator would leave
# the directory the guards are about. Session ids are harness-minted UUIDs, so
# this refuses nothing real; it is the same belt hooks/dispatch-preflight.sh wears
# on the same value, taken in the same direction: pass, silent.
SID=$(_jq '.session_id')
[ -n "$SID" ] || exit 0
case "$SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

CWD=$(_jq '.cwd')
[ -n "$CWD" ] && [ -d "$CWD" ] || exit 0

# ---------- the pinned root ----------
#
# DELIBERATELY DUPLICATED, byte for byte, from hooks/dispatch-preflight.sh's copy
# (the origin is hooks/canonical-sdlc-governing-skill.sh; the family is compared
# copy-for-copy and answer-for-answer by tests/cross-gate-agreement.test.sh
# §N.1/§N.2, which this file joins as the eighth member). The fleet's no-shared-lib
# rule is why it is a copy rather than a source (TDD §9: a sourced file the
# installer misses is a silently inert wall).
#
# IT IS LOAD-BEARING HERE FOR THE SAME REASON IT WAS ADDED TO THE POKER. The stamp
# is written at the MAIN repository's root, mapped there through `--git-common-dir`,
# so a reader that rooted a worktree at its own tree would find no stamp and go
# silent for every turn a run spends inside one — a monitor inert exactly where the
# parallel-writer phases put it.
resolve_project_root() {  # $1=a path whose repo we want; $2=fallback (default pwd)
  local d common root
  d=$(dirname "$1")
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ] && [ -n "$d" ]; do
    d=$(dirname "$d")
  done
  if common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    dirname "$common"
    return
  fi
  if common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null); then
    case "$common" in
      /*) root=$(dirname "$common") ;;
      *)  root=$(cd "$d" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P) ;;
    esac
    if [ -n "$root" ]; then
      printf '%s\n' "$root"
      return
    fi
  fi
  # NO-GIT FALLBACK: the pin follows the TARGET, never the shell. Outside any
  # repository, walk up from the nearest existing ancestor of the target for
  # the nearest directory already carrying a `.bionic/` tree and answer there;
  # only when none exists does the supplied fallback (default pwd) win — which
  # preserves the first-write-into-a-fresh-project path and changes nothing
  # inside a git repository, where the arms above always answer first.
  root="$d"
  while [ -n "$root" ] && [ "$root" != "/" ] && [ "$root" != "." ]; do
    if [ -d "$root/.bionic" ]; then
      printf '%s\n' "$root"
      return
    fi
    root=$(dirname "$root")
  done
  printf '%s\n' "${2:-$(pwd)}"
}

REPO=$(resolve_project_root "$CWD/." "$CWD")
[ -n "$REPO" ] && [ -d "$REPO" ] || exit 0

# ---------- was a Patrol ever armed on this session ----------
#
# The filename is hooks/session-poker.sh's, and the two spellings are held together
# by tests/cross-gate-agreement.test.sh §P so a rename on one side cannot go quiet
# on the other. A symlink is not a stamp: it reads as ABSENT rather than being
# followed, which is the posture every other .bionic/tmp reader takes and the
# direction §8 requires — a hostile repo may CLOSE a wall and must never OPEN one.
STAMP_FILE="$REPO/.bionic/tmp/patrol-${SID}.state"
[ -L "$STAMP_FILE" ] && exit 0
[ -f "$STAMP_FILE" ] || exit 0

# ---------- the threshold ----------
#
# THE INTERVAL IS THE POKER'S OWN, obtained by invoking its `interval` verb rather
# than by re-reading `poker-interval:` here: one knob, one reader. A malformed
# override makes the poker refuse, and the fallback is its own built-in default
# asked for through `interval-default` — never a constant retyped here, which would
# drift the first time either side moved and leave this hook measuring against a
# threshold nobody configured.
#
# NO NUMBER MEANS NO FINDING. Where hooks/dispatch-preflight.sh still has a
# never-armed arm to run without a threshold, this hook's only question IS the
# threshold — so an unreadable interval leaves it with an ambiguity rather than a
# finding, and it takes the direction every start-side ambiguity in this fleet
# takes: pass, silent. A per-turn gate is also the worst possible place to be loud
# about a condition it cannot measure.
POKER="${HOOK_DIR}/session-poker.sh"
[ -f "$POKER" ] || POKER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/session-poker.sh"
[ -f "$POKER" ] || exit 0

INTERVAL=$( cd "$REPO" 2>/dev/null && bash "$POKER" interval 2>/dev/null )
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL="" ;; esac
if [ -z "$INTERVAL" ] || [ "$INTERVAL" -le 0 ]; then
  INTERVAL=$( bash "$POKER" interval-default 2>/dev/null )
  case "$INTERVAL" in ''|*[!0-9]*) INTERVAL="" ;; esac
fi
[ -n "$INTERVAL" ] && [ "$INTERVAL" -gt 0 ] || exit 0

# 2x, exactly as the arming wall measures it: a Patrol firing on its interval is,
# at any random instant, up to one whole interval stale while perfectly healthy.
LIMIT=$(( INTERVAL * 2 ))

MTIME=$(stat -f %m "$STAMP_FILE" 2>/dev/null || stat -c %Y "$STAMP_FILE" 2>/dev/null)
case "$MTIME" in ''|*[!0-9]*) exit 0 ;; esac
AGE=$(( $(date -u +%s) - MTIME ))
[ "$AGE" -lt 0 ] && AGE=0
[ "$AGE" -gt "$LIMIT" ] || exit 0

# ---------- the notice ----------
#
# WHAT IT OWES THE READER, in order: the fact, the measurement it rests on, the
# cause they can recognise, and the two commands that fix it. The path, the age and
# both numbers are interpolated through `jq --arg`, so nothing here has a
# JSON-quoting surface. The poker is named at its RESOLVED ABSOLUTE path, never as
# `<plugin-root>/...`: this text is read by a model that will type it into its own
# shell, where `${CLAUDE_PLUGIN_ROOT}` is unset, and a cron job carrying a
# placeholder fires into a `command not found` every interval and reports nothing
# (SKILL.md §Dispatch states the rule; this is the same rule obeyed by a hook that
# already knows the answer).
#
# THE CRON HALF IS FIRST because the order is a safety property, not a style: `arm`
# alone freshens the stamp and buys a Patrol that reads alive and never fires. And
# FIRST IS NOT ENOUGH, because step 1 is the refusable half — `CronCreate` is measured
# non-deterministically refused by the auto-mode classifier
# (.bionic/docs/record/epic-19/w1/t3-probes.md finding 1) — so the conditional is stated
# in the text a model acts on, not only in this header a model never reads. A step 2 run
# after a refused step 1 produces the exact state the header above argues is worse than
# the death: an undetectably dead Patrol. The way OUT is named too, because a notice that
# offers only "re-arm" to a run that meant to stop is the loop critic C-2 found.
REASON="The Patrol died mid-run and nothing said so.

Its last stamp is ${AGE}s old — past the ${LIMIT}s limit, which is 2x the ${INTERVAL}s poker-interval in force for this project:
    ${STAMP_FILE}

The CLI holds its cron table in process memory with no file behind it, so a plugin update, a /reload-plugins, a session continue or a /clear+resume deletes the job and leaves the stamp as the only trace. Nothing is ticking the poker now: no dispatched row is being judged against its declared duration, and anything this run launched is waiting on a clock that stopped.

Re-arm it — both halves, the clock FIRST, because arming the stamp over an empty cron table buys a Patrol that reads alive and never fires:
  1. CronCreate a RECURRING session job at the interval \`bash ${POKER} interval\` reports, carrying the patrol prompt (the canonical-sdlc skill's Dispatch section).
  2. ONLY IF step 1 succeeded and returned a job: bash ${POKER} arm

If step 1 is refused or fails, do NOT run step 2 — a fresh stamp over an empty cron table reads ALIVE to this hook, to the dispatch wall and to /bionic:doctor while nothing fires again, which is worse than the death this notice is reporting. Tell the user the Patrol is down and that CronCreate was refused, and leave the stamp stale.

If this Patrol was stopped ON PURPOSE, record that instead of re-arming: \`bash ${POKER} disarm\` removes the stamp, and this notice goes with it.

Then stop again — this notice blocks once per turn, and it returns on the next turn until the stamp is re-armed or removed."

# The JSON decision payload on STDOUT with exit 0 — the same Stop-hook block
# channel hooks/patrol-duties-gate.sh uses. (hooks/landing-gate.sh refuses through
# exit 2 + stderr instead; both are live in this CLI, and gates that share no code
# path deliberately do not share a mechanism either.)
jq -nc --arg r "$REASON" '{decision:"block",reason:$r}'
exit 0
