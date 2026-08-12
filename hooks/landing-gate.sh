#!/bin/bash
# THE LANDING GATE — epic-16 wave-01.
#
# SubagentStop. On every subagent stop, during an active wave: read back the landing
# verdict for the stopping agent's contract and refuse the stop ONCE if the named
# artifacts are not on disk. Outside an active wave, or on any ambiguity along the way,
# the stop passes through untouched.
#
# Why a gate at all: every contract this machinery checks at LAUNCH
# (hooks/dispatch-preflight.sh's deliverable wall) has until now gone unchecked at
# LANDING — an agent could be dispatched under a declared deliverable, stop without
# writing it, and nothing in the session would notice until an orchestrator went looking.
# The wave's goal is the symmetry: same machinery, same named artifacts, both ends.
#
# IT OWNS NO PREDICATE. The question "did this contract land" is answered by
# `hooks/session-sweeper.sh verdict <name>`, and this gate parses that verb's machine line
# for `state=` and `detail=`. It never stats a deliverable, never reads the roster's
# contract fields, never forms an opinion about staleness or liveness. A gate with its own
# copy of the predicate is a gate that can disagree with the verb an orchestrator reads by
# hand — which is the one failure this design cannot tolerate, because the two answers
# would be given to different people about the same contract.
#
# FAIL DIRECTIONS (slice 5 normative text, pinned by hooks/landing-gate.test.sh):
#   - not a SubagentStop payload                        -> pass, silent (relevance hoist)
#   - agent_type empty (the phantom stops of capture
#     probe §4: an internal auxiliary agent fires these
#     three times per teammate run)                     -> pass, silent
#   - stop_hook_active true                             -> pass, silent (blocks ONCE)
#   - cwd/repo unresolvable, or no session_id, or a
#     session_id that is not shaped like one             -> pass, silent (ambiguity)
#   - no roster for this session                         -> pass, silent
#   - no active wave                                     -> pass, silent
#   - the sweeper is absent                              -> pass, silent
#   - the verdict exits anything but 1, or prints no
#     line at all (refusal, error, MET, WAIVED,
#     STILL-LIVE, AMBIGUOUS, name on no row)             -> pass, silent
#   - the verdict's line says UNMET                      -> REFUSE, quoting its detail
#
# AMBIGUOUS is the one that is worth spelling out: two contracts on this roster share the
# stopping agent's name, so no reader can tell which is its own. Passing is the recoverable
# error there; blocking the wrong agent, with the wrong artifact named, is not.
#
# Exit code 2 = block the stop in Claude Code hooks; stderr goes back to the stopping
# agent, which is why the refusal must name the artifacts rather than the rule.
# [WALL: hooks/landing-gate.test.sh]
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

INPUT=$(cat)
_jq() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

# ---------- relevance first: the cheapest checks, before any git resolution ----------

# Registered for SubagentStop alone, so this only fires on a hand-run or a future
# registration change; an absent field is not treated as a mismatch.
EVENT=$(_jq '.hook_event_name')
[ -z "$EVENT" ] || [ "$EVENT" = "SubagentStop" ] || exit 0

# THE NAME IS THE ONLY JOIN KEY. Capture probe §3-D/§5: the id namespaces differ across
# payloads (`agent_id` here is the transcript form, the roster's launch row carries the
# `@session-` form, `background_tasks[].id` is a third), and nothing bridges them by id.
# `agent_type` is the teammate's name, which is what the roster is keyed on.
NAME=$(_jq '.agent_type')
[ -n "$NAME" ] || exit 0
# NON-EMPTY IS NOT ENOUGH: the sweeper's verdict scopes on clean("$NAME")
# (session-sweeper.sh clean()), and a raw name made up only of the characters clean() folds
# to nothing (`|`, whitespace, tab, CR, control) scopes to the EMPTY predicate — which widens
# the verb to a BARE verdict, one line per name, and the head -1 below would then read the
# FIRST roster row's foreign contract and block this agent citing it. So a name that cleans
# to empty is guarded here the same way the session key is below (Step-6 critic F-1): fold the
# same set clean() folds and, if nothing is left, pass silent — the ambiguity direction.
case "$(printf '%s' "$NAME" | tr -d '[:space:][:cntrl:]|')" in "") exit 0 ;; esac

# BLOCKS ONCE, and this is the whole mechanism. Claude Code re-enters the stop with
# stop_hook_active true after a hook blocked it; refusing again would wedge an agent in a
# loop it has no way out of. One refusal names the artifacts; the second stop is the
# agent's to decide about. (jq's `//` folds `false` to empty, so a literal "true" is the
# only value that can match here — which is the comparison we want anyway.)
[ "$(_jq '.stop_hook_active')" = "true" ] && exit 0

# ---------- ambiguity: cannot locate the repo or the session -> pass, silent ----------
CWD=$(_jq '.cwd')
[ -n "$CWD" ] || exit 0
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$REPO" ] || exit 0

# The PAYLOAD's session key, never the ambient environment's: this gate runs inside a hook
# process whose env is not a documented carrier of the session id, and the payload is the
# authority on whose roster this stop belongs to. It is passed to the sweeper below for the
# same reason.
SID=$(_jq '.session_id')
[ -n "$SID" ] || exit 0
# SHAPE-CHECKED BEFORE IT BECOMES A PATH, exactly as hooks/dispatch-preflight.sh checks it.
# This value is interpolated into `roster-${SID}.state` below and exported to the sweeper,
# which builds its own ledger and findings paths from it; the symlink guards on those paths
# check the state directory and the exact filenames, so a key carrying separators does not
# trip a guard — it leaves the directory the guards protect. Session ids are harness-minted
# UUIDs today and nothing reaches this, but every other payload value on this path is
# sanitized and this one was not (Step-6 review S-4).
case "$SID" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

# Existence only, and only to avoid spawning the sweeper on a session that has dispatched
# nothing. Whether this name is ON the roster is the verdict verb's question, not this
# gate's — a second copy of that lookup here is exactly the divergence the design forbids.
[ -e "$REPO/.bionic/tmp/roster-${SID}.state" ] || exit 0

# ---------- active-wave detection ----------
# DELIBERATELY DUPLICATED, byte for byte where the logic overlaps, from
# hooks/dispatch-preflight.sh's copy (stop-guard and the evidence gate hold the others). A
# shared library is rejected by design (TDD §9): a sourced file the installer misses is a
# silently inert wall. The copies are held together by tests/cross-gate-agreement.test.sh.
resolve_docs_root() {
  local proj="$1" config="$1/.bionic/config.yaml" override
  if [ -f "$config" ]; then
    override=$(grep -E '^[[:space:]]*docs-root[[:space:]]*:' "$config" 2>/dev/null \
      | head -1 \
      | sed -E 's/^[[:space:]]*docs-root[[:space:]]*:[[:space:]]*//' \
      | sed -E "s/^['\"]//;s/['\"]\$//" \
      | sed -E 's/[[:space:]]+$//')
    if [ -n "$override" ]; then
      case "$override" in
        /*) echo "$override" ;;
        *)  echo "$proj/$override" ;;
      esac
      return
    fi
  fi
  echo "$proj/.bionic/docs"
}

DOCS_ROOT=$(resolve_docs_root "$REPO")
PLAN=""
for d in "$DOCS_ROOT/plans" "$DOCS_ROOT/incidents"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' f; do
    if [ -z "$PLAN" ] || [ "$f" -nt "$PLAN" ]; then PLAN="$f"; fi
  done < <(find "$d" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
done
[ -n "$PLAN" ] && [ -f "$PLAN" ] || exit 0

# The run-state marker, read exactly as the evidence gate, stop-guard and the dispatch gate
# read it: the fence-aware ## SDLC State section, then its `current:` value. Line endings
# TRANSLATED, never deleted — see .claude/rules/hook-authoring.md (a CR-only file deleted by
# `tr -d '\r'` collapses to one line and every line-anchored match misses, going silently
# inert with a wave live).
CURRENT=$(awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$PLAN" 2>/dev/null | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { flag=1; next }
  /^## / { flag=0 }
  flag' \
  | grep -E '^[[:space:]]*current[[:space:]]*:' \
  | head -1 \
  | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
  | tr -d '[:space:]')
echo "$CURRENT" | grep -qE '^([0-9]+[ab]?|T[0-9]+)$' || exit 0

# ---------- a wave is active: take the verdict ----------

# The sweeper is this gate's SIBLING — claude-bootstrap.sh installs every hooks/*.sh into
# one directory, so the same resolution holds in the repo and in ~/.claude/hooks/. No PATH
# lookup (a hook's PATH is not ours to trust) and no environment override (a seam on the
# path under test would leave the production path unverified).
SWEEPER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/session-sweeper.sh"
[ -f "$SWEEPER" ] || exit 0

# Run from the repo, because the sweeper resolves its own state directory from the working
# directory, and with the payload's session key. `|| exit 9` keeps a failed `cd` out of the
# exit-1 band: exit 1 is the verb's "at least one UNMET row", and nothing else may be
# allowed to spell it.
VERDICT=$( cd "$REPO" 2>/dev/null || exit 9
           CLAUDE_CODE_SESSION_ID="$SID" bash "$SWEEPER" verdict "$NAME" 2>/dev/null )
VERDICT_RC=$?

# EVERY OTHER EXIT IS A PASS: 0 (nothing UNMET, including a name on no row), 2 (a refusal —
# the verb was redirected away from the roster and says so), 3 (no session key), or any
# error at all. A gate that blocked on an answer it did not get would be refusing on its own
# authority, which is the one thing it has none of.
[ "$VERDICT_RC" -eq 1 ] || exit 0

# THE LINE THE SCOPED VERB RETURNED, and no second lookup by name. `verdict <name>` answers
# for that name alone and folds the roster to one row per name (plan assumption 8), so its
# output carries at most one machine line and taking the first IS taking this contract's.
#
# It used to be re-matched here with `grep -F "|name=${NAME}|"` on the RAW `agent_type`,
# which was a second reader of the same key with different normalization: the verb stores and
# prints `clean()`-ed names, so any name whose stored form differed from its payload form
# missed the line and the gate exited 0 — a silent disarm, and a disagreement between two
# readers of one key is the class this wave exists to close (Step-6 review C-5). Deleting the
# reader closes it structurally; there is nothing left to normalize. This reverses assumption
# 29's defence-in-depth, deliberately: the defence cost more than it bought.
LINE=$(printf '%s\n' "$VERDICT" | grep -F 'landing-verdict/v1|' | head -1)
[ -n "$LINE" ] || exit 0

_field() {  # <key> — by key, never by position, as every reader of these lines does
  printf '%s' "$LINE" | tr '|' '\n' | grep "^$1=" | head -1 | cut -d= -f2-
}

[ "$(_field state)" = "UNMET" ] || exit 0

# AN ACKED ROW IS CLOSED FOR EVERY READER (epic-16 wave-02 slice S3, R2). The orchestrator
# verified this agent's completion and made that durable; refusing its stop over artifacts
# a human has already accounted for is the false alarm this wave exists to end.
#
# READ OFF THE VERDICT LINE, and this gate owns no more of it than it owns the state beside
# it (S9). Until S9 the answer came from a `ledger_acked()` this file carried — one of three
# byte-identical copies, each opening the sweeper's ledger and matching a name in it, which
# is three readers of one file and three chances to disagree about it. The verb owns the
# ledger; the verb was already being run for `state=`; the answer rides back on the same
# line, keyed by the same cleaned name the verb prints. Asked LAST, after the state is known
# to be UNMET, so the pass paths pay nothing for it.
[ "$(_field acked)" = "yes" ] && exit 0

# The refusal is the verb's own detail, unedited. It names every failing conjunct —
# `missing=`, `empty=`, `stale=` with both stamps — because a stopping agent that is told
# only "unmet" has nothing to act on, and the second stop passes whatever it does.
echo "LANDING CONTRACT UNMET — $(_field detail). Land the contract (write the named artifacts), or stop again to pass — this gate blocks once." >&2
exit 2
