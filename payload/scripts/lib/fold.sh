#!/bin/bash
# payload/scripts/lib/fold.sh — THE ONE COMPOSITION RULE FOR A MULTI-CHECK EVENT
# (epic-23 wave-11-lean-spine, REQ-1f (iv); spec Design §1 "TurnEndVerdict", §2 D4;
# ADR-004 "One process on Stop and SubagentStop, one composed verdict").
#
# WHAT IT OWNS. One sentence, and the whole file is it:
#
#     any block is a block · all reasons print · blocks before advisories
#
# Four hooks used to fire on Stop, each with its own verdict, and NO RULE said how
# four verdicts combine when more than one had something to say. The platform
# collected whichever arrived; an operator debugging a stuck session reconciled up to
# four outputs and learned about the second reason only on a later turn. This file is
# that missing rule, written once.
#
# IT KNOWS NOTHING ABOUT Stop, DELIBERATELY. `bionic_fold` takes an event name as an
# opaque string and hands it to every function it runs; it makes no decision on it.
# That is not generality for its own sake — T23 folds the five PreToolUse|Bash walls
# by this same function, and a fold carrying a Stop-shaped assumption would have to
# be rewritten to get there. tests/fold.test.sh §11 drives an event name this
# repository has never registered and asserts it composes like any other.
#
# ── THE CONTRACT A FOLDED FUNCTION SIGNS ─────────────────────────────────────
#
#   fold_block <mode> <verb> <fact> <fix> <detail>   stage a refusal, then `return 2`
#   fold_advise <text>                               stage an advisory, then `return 1`
#   (stage nothing)                                                    then `return 0`
#
# THE RETURN CODE IS THE VERDICT AND THE STAGED TEXT IS ONLY THE WORDS FOR IT. A
# function that stages a block and returns 0 has said nothing, and its staged text is
# discarded rather than leaking into a later function's verdict — the fold clears the
# staging slots after every call, so one function can never speak through another's.
#
# A FUNCTION MUST NOT CALL `exit`. It is run in the CALLER'S SHELL, so an `exit`
# there takes the whole process down with it, the functions after it never run, and
# nothing is composed. A shell cannot intercept its own `exit`, so this is a contract
# and not a guard; tests/fold.test.sh §6 drives the violation and pins its
# consequence so that a function that acquires an `exit` fails a suite instead of
# silently truncating a turn's verdict.
#
# WHY THE CALLER'S SHELL, AND NOT A SUBSHELL. A subshell per function would be the
# obvious way to contain a stray `exit`, and it would cost three things that matter
# more: state one function sets could not be read by the next (the four Stop
# functions share `bionic_context`'s eight values and one of them reads a file
# another may have just written), a staged refusal could not be seen by the fold at
# all — the staging variables would die with the subshell — and the violation above
# would look like a clean `return` instead of the truncation it is. So the functions
# run here, and `local` in each of them is what keeps them out of each other's way.
#
# ── THE CHANNEL, WHICH IS THE ONE THING THAT NEEDED DECIDING ──────────────────
#
# `refuse` is the ONE renderer of a refusal (payload/scripts/lib/refuse.sh;
# tests/cross-gate-agreement.test.sh pins that no hook prints one directly), and it
# takes a MODE that decides the wire. The walls this fold serves do not agree on one:
# landing-gate refuses with `exit2`, patrol-duties-gate and patrol-revive with
# `block`, and T23's walls bring `deny`. The modes are not interchangeable —
# `exit2`'s cell `model_only` is `no`, which is refuse.sh's way of recording that
# that channel has ONE stream for the user line and the model, so ruling D-1 spends
# it on the line and the `detail` is not emitted at all.
#
# So: ONE BLOCKER RENDERS ITS OWN OBJECT, VERBATIM — same mode, same verb, fact, fix
# and detail, same exit status. That is what makes the merge a refactor rather than a
# rewrite: on every payload where exactly one check speaks, the bytes on both streams
# are the ones that hook produced before it became a function.
#
# TWO OR MORE BLOCKERS compose, and only then. The verb, fact and fix are the FIRST
# blocker's; every blocker's detail follows in the order the functions were named;
# and the mode is the first blocker's mode whose `model_only` cell says the channel
# carries `detail` at all, because composing onto a channel that drops it would
# discard the very reasons the fold exists to keep. The rule is READ OUT OF
# refuse.sh's channel table rather than hardcoded here, so a mode added there is
# ranked by its own measured cell and not by a second opinion in this file.
#
# THE RETURN VALUE IS THE STATUS THE PROCESS SHOULD EXIT WITH, which is the status
# the chosen channel exits with — 2 for `exit2`, 0 for `block` and `deny`, 0 when
# nothing blocked. It is deliberately NOT a fixed 2: on Stop the `block` channel
# blocks the turn with status 0, by the platform's own design as measured on CLI
# 2.1.263, and a fold that forced a 2 would change the wire under every wall that
# uses it. "Any block is a block" is a statement about the refusal being rendered,
# never about the integer.
#
# ADVISORIES RIDE AFTER THE REFUSAL, which is why `refuse` is called through a
# capture here rather than allowed to exit in place: it does not return, so anything
# printed after it would never be printed at all. The capture reads its two streams
# separately — `block` and `deny` put JSON on stdout and the user line on stderr —
# replays them in that order, then puts the advisories on stderr, then exits with the
# status `refuse` chose. Nothing is reformatted on the way through.
#
# BASH 3.2. No associative arrays, no `mapfile`. Accumulation is string
# concatenation, and the modes are a space-joined list.
#
# SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME — the rule every library in this
# directory follows, for lib/context.sh's reason: callers read library answers through
# `$( )` and anything printed on the way in corrupts the first field of every one.
#
# IT BRINGS ITS OWN DEPENDENCY, guarded on the function rather than the file, so a
# caller that already sourced refuse.sh pays nothing and one that named only
# `fold.sh` in BIONIC_LIB_WANT still gets a working renderer.
#
# [WALL: tests/fold.test.sh]

_fold_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

# RESOLVED AT SOURCE TIME, for lib/context.sh's reason at `_CONTEXT_LIB_DIR`:
# `${BASH_SOURCE[0]%/*}` is RELATIVE when the file was sourced by a relative path, and
# a soft source that re-derived it later would read against whatever the caller's cwd
# had become.
_FOLD_LIB_DIR="$(cd "$(_fold_self_dir)" && pwd -P)"

if ! declare -F refuse >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_FOLD_LIB_DIR/refuse.sh"
fi

# ─── The staging verbs ───────────────────────────────────────────────────────

# fold_block <mode> <verb> <fact> <fix> <detail> — stage THIS function's refusal.
# It does not render, does not exit, and does not decide: the caller's `return 2` is
# what makes it a verdict.
fold_block() {
  _BF_PEND_MODE="${1:-}"
  _BF_PEND_VERB="${2:-}"
  _BF_PEND_FACT="${3:-}"
  _BF_PEND_FIX="${4:-}"
  _BF_PEND_DETAIL="${5:-}"
}

# fold_advise <text> — stage advisory text. Called more than once in one function,
# the lines accumulate in order; a function may stage an advisory AND a block, which
# is what landing-gate does when a row's reconciliation goes inert on the same sweep
# that another row refuses.
fold_advise() {
  if [ -z "${_BF_PEND_ADVICE:-}" ]; then
    _BF_PEND_ADVICE="${1:-}"
  else
    _BF_PEND_ADVICE="$_BF_PEND_ADVICE
${1:-}"
  fi
}

# fold_context <text> — stage a MODEL-FACING advisory: text that must ride
# `hookSpecificOutput.additionalContext` on stdout rather than the user's stream.
#
# WHY THERE ARE TWO ADVISORY VERBS. `fold_advise` is words for the person reading the
# terminal. This is words for the model and nobody else — the channel
# hooks/farm-out-reminder.sh has answered on since epic-08 wave-04 (ADR-002), where
# the reader never sees the nudge and the next turn does. They are not the same
# stream and one verb could not choose between them without guessing.
#
# THE MERGE IS THE WHOLE REASON IT LIVES HERE. Before T23 one process emitted one
# such object; five walls in one process could emit several, and several JSON
# documents on one stdout is not a wire any reader parses — it is the fail-OPEN
# direction, since an unparseable verdict is no verdict. So the fold owns the channel
# the way it already owns the refusal: whatever the number of speakers, ONE object.
fold_context() {
  if [ -z "${_BF_PEND_CONTEXT:-}" ]; then
    _BF_PEND_CONTEXT="${1:-}"
  else
    # A BLANK LINE, as between composed reasons: each nudge is a paragraph and run
    # together they would read as one speaker's.
    _BF_PEND_CONTEXT="$_BF_PEND_CONTEXT

${1:-}"
  fi
}

# fold_update_input <json-object> — stage a MEANING-PRESERVING rewrite of `tool_input`:
# text that must ride `hookSpecificOutput.updatedInput` on stdout (epic-23 wave-13-fixit-180
# T3, spec D4). The argument is already-built JSON (an object), never text to be escaped —
# the one caller (`wall_background_suite_guard`'s repair arm) builds it with `jq` because
# the shape is `tool_input` plus one changed field, not a string this file has any business
# constructing.
#
# WHY A SEPARATE VERB FROM `fold_context`. The two channels are not the same claim: a nudge
# is a sentence for the model to read and act on NEXT turn; a repair is a change to THIS
# call, already decided, that the harness applies before the tool runs. Merging them into
# one staged string would make `_fold_emit_context` guess which one it was holding.
#
# LAST WRITE WINS, undecorated — unlike `fold_context`'s accumulation. Exactly one of the
# five walls ever calls this (background-suite-guard), so there is only ever one write; a
# second caller would need this file to also invent an ORDER for two rewrites of the same
# `tool_input`, which nothing here is asked to do yet.
fold_update_input() {
  _BF_PEND_UPDATED_INPUT="${1:-}"
}

_fold_clear_pending() {
  _BF_PEND_MODE=""; _BF_PEND_VERB=""; _BF_PEND_FACT=""
  _BF_PEND_FIX=""; _BF_PEND_DETAIL=""; _BF_PEND_ADVICE=""; _BF_PEND_CONTEXT=""
  _BF_PEND_UPDATED_INPUT=""
}

# _fold_emit_context <event> <context-text> [<updated-input-json>] — the one object, on
# stdout, whichever of the two staged channels is present.
#
# THROUGH `jq`, DELIBERATELY, where refuse.sh escapes JSON by hand. The two have
# different callers: refuse.sh must format a refusal on a machine that has lost `jq`,
# because a wall that cannot format its refusal must not therefore fail open. This is
# an ADVISORY — losing it costs a nudge — and going through `jq` keeps the bytes
# identical to the emitter this replaces, which is what makes the merge a refactor on
# the one payload where a single wall speaks. With no `jq` the text is not dropped:
# the caller puts it on the user's stream instead (`updatedInput` has no such fallback
# — see `bionic_fold`'s own comment on that, below).
#
# BOTH ARGUMENTS CAN BE NON-EMPTY (T3, D4):
# farm-out-reminder's `additionalContext` reads `agent_type`, background-suite-guard's
# `updatedInput` reads `agent_id`, and a payload that carries one field without the other
# is not ruled out (research-R2-walls.md §4 measured only `agent_id` as confirmed present
# on a subagent call). One `jq -n` builds whichever fields are non-empty into one document
# rather than letting two callers each own the wire and the second overwrite the first.
_fold_emit_context() {
  local _e="${1:-}" _c="${2:-}" _u="${3:-}"
  if [ -n "$_u" ]; then
    if [ -n "$_c" ]; then
      jq -n --arg e "$_e" --arg c "$_c" --argjson u "$_u" \
        '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c,updatedInput:$u}}' 2>/dev/null
    else
      jq -n --arg e "$_e" --argjson u "$_u" \
        '{hookSpecificOutput:{hookEventName:$e,updatedInput:$u}}' 2>/dev/null
    fi
  else
    jq -n --arg e "$_e" --arg c "$_c" \
      '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null
  fi
}

# ─── The fold ────────────────────────────────────────────────────────────────

# bionic_fold <event> <fn>... -> the status the process should exit with.
#
# EVERY FUNCTION RUNS, ALWAYS, IN THE ORDER GIVEN. There is no short-circuit and
# there is no sorting: the caller's argument order IS the order reasons appear in,
# so a caller that wants today's manifest order spells today's manifest order.
bionic_fold() {
  local _event="${1:-}"
  shift 2>/dev/null || :

  BIONIC_FOLD_BLOCKS=0
  BIONIC_FOLD_MODES=""
  BIONIC_FOLD_MODE=""
  BIONIC_FOLD_VERB=""
  BIONIC_FOLD_FACT=""
  BIONIC_FOLD_FIX=""
  BIONIC_FOLD_DETAIL=""
  BIONIC_FOLD_ADVICE=""
  BIONIC_FOLD_CONTEXT=""
  BIONIC_FOLD_UPDATED_INPUT=""
  BIONIC_FOLD_LINES=""

  local _fn _rc _m _errf _out _rrc _ctx _bline
  for _fn in "$@"; do
    _fold_clear_pending
    # THE CALL. Unquoted-by-name, in this shell, with the event as its one argument.
    "$_fn" "$_event"
    _rc=$?

    case "$_rc" in
      2)
        BIONIC_FOLD_BLOCKS=$((BIONIC_FOLD_BLOCKS + 1))
        BIONIC_FOLD_MODES="${BIONIC_FOLD_MODES}${BIONIC_FOLD_MODES:+ }${_BF_PEND_MODE}"
        # THE FIRST BLOCKER OWNS THE LINE. Verb, fact and fix are already inside
        # refuse's budgets because that function's own refusal was; composing new
        # ones here would be this file inventing a sentence no wall wrote.
        if [ -z "$BIONIC_FOLD_MODE" ]; then
          BIONIC_FOLD_MODE="$_BF_PEND_MODE"
          BIONIC_FOLD_VERB="$_BF_PEND_VERB"
          BIONIC_FOLD_FACT="$_BF_PEND_FACT"
          BIONIC_FOLD_FIX="$_BF_PEND_FIX"
        fi
        # EVERY BLOCKER AFTER THE FIRST BRINGS ITS OWN LINE (T23). The composed object
        # keeps the FIRST blocker's verb, fact and fix, so without this the second
        # wall's SENTENCE — not just its detail — would be gone: a push refused
        # alongside a DROP would print the push and say nothing about the DROP, while
        # the two processes this replaced printed both. The line is built exactly as
        # `refuse` builds it, and it leads that blocker's own detail.
        if [ "$BIONIC_FOLD_BLOCKS" -gt 1 ]; then
          _bline="bionic: ${_BF_PEND_VERB} refused — ${_BF_PEND_FACT} (${_BF_PEND_FIX})"
          BIONIC_FOLD_LINES="${BIONIC_FOLD_LINES}${BIONIC_FOLD_LINES:+
}${_bline}"
          if [ -n "$_BF_PEND_DETAIL" ]; then
            _BF_PEND_DETAIL="${_bline}

${_BF_PEND_DETAIL}"
          else
            _BF_PEND_DETAIL="$_bline"
          fi
        fi
        # ONE TRAILING NEWLINE IS NOT A PARAGRAPH BREAK. Several walls build `detail` by
        # appending `…\n` per row, so the value arrives with a newline already on it; the
        # separator below would then read as two blank lines between reasons rather than
        # one. The trim is of trailing newlines only — nothing inside the text moves.
        while [ -n "$_BF_PEND_DETAIL" ] && [ "${_BF_PEND_DETAIL%$'\n'}" != "$_BF_PEND_DETAIL" ]; do
          _BF_PEND_DETAIL="${_BF_PEND_DETAIL%$'\n'}"
        done
        if [ -n "$_BF_PEND_DETAIL" ]; then
          if [ -z "$BIONIC_FOLD_DETAIL" ]; then
            BIONIC_FOLD_DETAIL="$_BF_PEND_DETAIL"
          else
            # A BLANK LINE BETWEEN REASONS. Each wall's detail is a paragraph or
            # several; run together they would read as one wall's text.
            BIONIC_FOLD_DETAIL="$BIONIC_FOLD_DETAIL

$_BF_PEND_DETAIL"
          fi
        fi
        ;;
      1) : ;;
      *) _fold_clear_pending ;;   # said nothing: its staged text is discarded
    esac

    # ADVISORIES SURVIVE A BLOCK as well as an advisory verdict, because a function
    # that refuses one row and went inert on another has two things to say.
    if [ "$_rc" -eq 1 ] || [ "$_rc" -eq 2 ]; then
      if [ -n "${_BF_PEND_ADVICE:-}" ]; then
        if [ -z "$BIONIC_FOLD_ADVICE" ]; then
          BIONIC_FOLD_ADVICE="$_BF_PEND_ADVICE"
        else
          BIONIC_FOLD_ADVICE="$BIONIC_FOLD_ADVICE
$_BF_PEND_ADVICE"
        fi
      fi
      # THE MODEL'S HALF, merged on the same rule and separated by a blank line.
      if [ -n "${_BF_PEND_CONTEXT:-}" ]; then
        if [ -z "$BIONIC_FOLD_CONTEXT" ]; then
          BIONIC_FOLD_CONTEXT="$_BF_PEND_CONTEXT"
        else
          BIONIC_FOLD_CONTEXT="$BIONIC_FOLD_CONTEXT

$_BF_PEND_CONTEXT"
        fi
      fi
      # THE REPAIR HALF (T3, D4). Last write wins — see fold_update_input's own docblock
      # for why that is the whole rule with one caller.
      if [ -n "${_BF_PEND_UPDATED_INPUT:-}" ]; then
        BIONIC_FOLD_UPDATED_INPUT="$_BF_PEND_UPDATED_INPUT"
      fi
    fi
  done
  _fold_clear_pending

  # ── NOTHING BLOCKED ─────────────────────────────────────────────────────────
  #
  # A REPAIR ONLY EVER RIDES THIS BRANCH (T3, D4). `BIONIC_FOLD_UPDATED_INPUT` is read
  # nowhere else in this function: a call some OTHER wall blocked never runs, so rewriting
  # its `timeout` would repair a command the harness is about to refuse anyway — a
  # confusing wire nobody needs. `BIONIC_FOLD_BLOCKS -eq 0` here is that boundary.
  if [ "$BIONIC_FOLD_BLOCKS" -eq 0 ]; then
    if [ -n "$BIONIC_FOLD_CONTEXT" ] || [ -n "$BIONIC_FOLD_UPDATED_INPUT" ]; then
      _out=$(_fold_emit_context "$_event" "$BIONIC_FOLD_CONTEXT" "$BIONIC_FOLD_UPDATED_INPUT")
      if [ -n "$_out" ]; then
        printf '%s\n' "$_out"
      else
        # NO `jq`, SO NO OBJECT. A nudge degrades to a line a person can still read; a
        # repair has no such fallback and is simply not applied — the same unrepaired
        # state the wall found the call in. Unreachable in practice: hooks/bash-walls.sh's
        # own preamble already refuses to source this file without `jq` on the PATH.
        BIONIC_FOLD_ADVICE="${BIONIC_FOLD_ADVICE}${BIONIC_FOLD_ADVICE:+
}$BIONIC_FOLD_CONTEXT"
      fi
    fi
    [ -n "$BIONIC_FOLD_ADVICE" ] && printf '%s\n' "$BIONIC_FOLD_ADVICE" >&2
    return 0
  fi

  # ── THE CHANNEL, when the blockers disagree about it ────────────────────────
  #
  # Asked only when there is something to compose. With one blocker the mode is
  # already its own and the loop below re-selects the same value.
  if [ "$BIONIC_FOLD_BLOCKS" -gt 1 ]; then
    if [ "$(refuse_channel "$BIONIC_FOLD_MODE" model_only 2>/dev/null || echo no)" != "yes" ]; then
      for _m in $BIONIC_FOLD_MODES; do
        if [ "$(refuse_channel "$_m" model_only 2>/dev/null || echo no)" = "yes" ]; then
          BIONIC_FOLD_MODE="$_m"
          break
        fi
      done
    fi
  fi

  # ── THE ONE RENDER, CAPTURED ────────────────────────────────────────────────
  #
  # `refuse` does not return, so it is run in a subshell and its two streams are
  # replayed here — stdout first (the JSON wire, where there is one), then stderr
  # (the user line), then the advisories. Nothing is reformatted: the bytes the
  # renderer produced are the bytes that go out.
  # PRIVATE, AND CREATED BY mktemp (security F-2). The name this line used to build —
  # pid plus one `$RANDOM` draw — is 32,768 guesses per pid to a local attacker, and the
  # `2>` below creates through a symlink already sitting there, truncating its target. Every
  # composed refusal on the machine goes through this line. `mktemp` creates exclusively, at
  # a name nobody can pre-create, mode 600. A machine that cannot make a temp file at all
  # falls back to /dev/null: the render still happens and the user still gets the refusal —
  # only the replay of the renderer's own stderr is lost, which is the small half.
  # [WALL: tests/fold.test.sh §14]
  _errf="$(mktemp "${TMPDIR:-/tmp}/bionic-fold.XXXXXX" 2>/dev/null)" || _errf=/dev/null
  [ -n "$_errf" ] || _errf=/dev/null
  _out=$(refuse "$BIONIC_FOLD_MODE" "$BIONIC_FOLD_VERB" "$BIONIC_FOLD_FACT" \
                "$BIONIC_FOLD_FIX" "$BIONIC_FOLD_DETAIL" 2>"$_errf")
  _rrc=$?
  [ -n "$_out" ] && printf '%s\n' "$_out"
  [ -s "$_errf" ] && cat "$_errf" >&2
  [ "$_errf" = /dev/null ] || rm -f "$_errf" 2>/dev/null

  # ── THE OTHER BLOCKERS' LINES, WHERE NO STREAM AT ALL RECEIVED THEM ─────────
  #
  # THE TEST IS "DID THE DETAIL REACH A READER AT ALL", AND IT TAKES THREE CELLS NOW.
  # On `deny` and `block` the composed detail reaches the MODEL in full, every later
  # blocker's sentence with it (`model_only=yes`), and the user's one line is what
  # refuse.sh's channel table says it is — T12 pinned that shape (tests/fold.test.sh 2f,
  # tests/stop.test.sh 1e) and it stands.
  #
  # `exit2` USED TO BE THE CASE WITH NOWHERE TO PUT THEM: one wire for both readers,
  # spent on the headline under ruling D-1, `detail` never emitted at all. With one
  # blocker that was the ruling; with two it DELETED a wall's verdict outright — neither
  # reader learned the second wall had refused anything — while the processes this fold
  # replaced each printed their own line and a reader saw both. So the later blockers'
  # lines followed the headline on that stream: the same sentences, in manifest order.
  #
  # ADR-030 GAVE `exit2` SOMEWHERE TO PUT THEM (epic-23 wave-16 T4, 2026-09-19), and this
  # branch had to learn it. Field 9 is `yes` for that mode now, so `refuse` prints the
  # composed detail beneath the headline — and every later blocker's sentence LEADS its own
  # detail inside it (the loop above builds `_bline` into both places). Printing
  # `BIONIC_FOLD_LINES` as well put a second wall's sentence on the stream TWICE. A refusal
  # prints its detail once, so the branch stands down wherever the detail already reached
  # the reader: by the model's channel (`model_only`), by the user's (`detail_to_user`), or
  # by the knob, which puts the whole composed detail there through `refuse`.
  #
  # WHAT IS LEFT OF THE BRANCH, and why it is not deleted. Nothing in the shipped table
  # reaches it today: all three refusal channels now carry `detail` to one reader or the
  # other. It is the fail-SAFE side of a data-driven table — a mode added to
  # `BIONIC_REFUSE_TABLE` with `model_only=no` and `detail_to_user=no` would silently
  # delete a second wall's verdict again, which is precisely the defect T23 found — and it
  # costs one `refuse_channel` read on a path that has already refused.
  #
  # THE RESIDUAL, NAMED (A-T4.6). `refuse` bounds what it prints at
  # BIONIC_REFUSE_DETAIL_LINES lines plus a `+N more` count, so on `exit2` a later
  # blocker's sentence sitting past that bound is folded behind the count rather than
  # printed. That is a bounded, ANNOUNCED fold and not T23's silent deletion, and it is the
  # cost ADR-030 priced; §13's long-detail row measures it rather than leaving it to be
  # discovered.
  if [ -n "$BIONIC_FOLD_LINES" ] \
     && [ "${BIONIC_WALL_VERBOSE:-}" != "1" ] \
     && [ "$(refuse_channel "$BIONIC_FOLD_MODE" model_only 2>/dev/null || echo no)" != "yes" ] \
     && [ "$(refuse_channel "$BIONIC_FOLD_MODE" detail_to_user 2>/dev/null || echo no)" != "yes" ]; then
    printf '%s\n' "$BIONIC_FOLD_LINES" >&2
  fi

  # ── THE MODEL'S ADVISORIES, AND WHO OWNS STDOUT ─────────────────────────────
  #
  # A REFUSAL THAT ALREADY WROTE STDOUT KEEPS IT. `deny` and `block` put their JSON
  # there; a second document beside it leaves the whole stream unparseable, and an
  # unreadable refusal is no refusal — the fail-OPEN direction, which is never the
  # one to take by accident. So the advisory yields the channel and degrades to the
  # user's stream, where it is still read by someone, rather than being dropped or
  # corrupting the verdict. On `exit2` stdout is free and the object rides it.
  if [ -n "$BIONIC_FOLD_CONTEXT" ]; then
    _ctx=""
    [ -z "$_out" ] && _ctx=$(_fold_emit_context "$_event" "$BIONIC_FOLD_CONTEXT")
    if [ -n "$_ctx" ]; then
      printf '%s\n' "$_ctx"
    else
      BIONIC_FOLD_ADVICE="${BIONIC_FOLD_ADVICE}${BIONIC_FOLD_ADVICE:+
}$BIONIC_FOLD_CONTEXT"
    fi
  fi
  [ -n "$BIONIC_FOLD_ADVICE" ] && printf '%s\n' "$BIONIC_FOLD_ADVICE" >&2
  return "$_rrc"
}
