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
# functions share `bionic_context`'s seven values and one of them reads a file
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

_fold_clear_pending() {
  _BF_PEND_MODE=""; _BF_PEND_VERB=""; _BF_PEND_FACT=""
  _BF_PEND_FIX=""; _BF_PEND_DETAIL=""; _BF_PEND_ADVICE=""
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

  local _fn _rc _m _errf _out _rrc
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
    fi
  done
  _fold_clear_pending

  # ── NOTHING BLOCKED ─────────────────────────────────────────────────────────
  if [ "$BIONIC_FOLD_BLOCKS" -eq 0 ]; then
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
  _errf="${TMPDIR:-/tmp}/bionic-fold-$$-${RANDOM}.err"
  _out=$(refuse "$BIONIC_FOLD_MODE" "$BIONIC_FOLD_VERB" "$BIONIC_FOLD_FACT" \
                "$BIONIC_FOLD_FIX" "$BIONIC_FOLD_DETAIL" 2>"$_errf")
  _rrc=$?
  [ -n "$_out" ] && printf '%s\n' "$_out"
  [ -s "$_errf" ] && cat "$_errf" >&2
  rm -f "$_errf" 2>/dev/null
  [ -n "$BIONIC_FOLD_ADVICE" ] && printf '%s\n' "$BIONIC_FOLD_ADVICE" >&2
  return "$_rrc"
}
