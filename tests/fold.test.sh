#!/bin/bash
# Tests for payload/scripts/lib/fold.sh — THE ONE COMPOSITION RULE
# (epic-23 wave-11-lean-spine, REQ-1f (iv), ADR-004, T12 ruling R3).
#
# THE MECHANISM UNDER TEST, AND NOTHING ELSE. `bionic_fold <event> <fn>...` runs
# every named function, in order, in the CURRENT SHELL, with no short-circuit,
# and composes their verdicts by one rule:
#
#     any block is a block · all reasons print · blocks before advisories
#
# It is EVENT-AGNOSTIC by construction and this suite proves it that way: every
# function here is a stub, no hook is involved, and the event is an opaque string
# the fold only ever hands on. T23 applies the same function to the five
# PreToolUse|Bash walls, so a fold that knew anything about Stop would have to be
# rewritten to get there.
#
# WHY THE CURRENT SHELL, SAID OUT LOUD (R3). A subshell would give each function a
# private copy of the environment, and three things would break at once: state one
# function sets could not be read by the next, the fold could not see a staged
# refusal at all, and `exit` inside a function would look like a clean `return`
# instead of the contract violation it is. §5 drives the state visibility directly
# and §6 drives the violation.
#
# THE STAGING VERBS. A folded function never renders and never exits — it stages
# its verdict and returns a code:
#
#     fold_block <mode> <verb> <fact> <fix> <detail>   … then `return 2`
#     fold_advise <text>                               … then `return 1`
#     (nothing)                                        … then `return 0`
#
# THE RETURN CODE IS THE VERDICT; the staged text is only the words for it. A
# function that stages a block and returns 0 has said nothing, and §7 asserts that
# rather than leaving it to be discovered.
#
# WHAT `bionic_fold` RETURNS is the status the PROCESS should exit with, which is
# the status the chosen refusal channel exits with — 2 for `exit2`, 0 for `block`
# and `deny`, 0 when nothing blocked. It is deliberately NOT a fixed 2: on Stop the
# `block` channel blocks the turn with status 0 by the platform's own design
# (payload/scripts/lib/refuse.sh's channel table, measured on CLI 2.1.263), so a
# fold that forced a 2 would change the wire for every wall that uses it.
#
# Usage: bash tests/fold.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

LIB="${BIONIC_FOLD_LIB_UNDER_TEST:-${BIONIC_SCRIPTS_DIR}/payload/scripts/lib}"

command -v jq >/dev/null 2>&1 || { echo "fold: jq absent — suite cannot run"; exit 1; }

# NOT VACUOUS. Most assertions below read "rc 0 and nothing printed", which a
# MISSING library also produces once the shell's own 127 is discarded.
[ -f "$LIB/fold.sh" ] || { echo "fold: no library at $LIB/fold.sh — suite refuses to run"; exit 1; }
bash -n "$LIB/fold.sh" || { echo "fold: $LIB/fold.sh does not parse — suite refuses to run"; exit 1; }

# ---------- driving the fold ----------

FOLD_OUT=""
FOLD_ERR=""
FOLD_RC=0
FOLD_ERRFILE="$(mktemp)"

# drive <stub-definitions> <event> <fn>... — writes a scratch driver that sources
# the real library, defines the stubs given, and folds. A SCRATCH FILE and not an
# inline `bash -c`, so a stub body may contain any quoting it likes and the suite
# reads back exactly what a hook would produce.
drive() {  # <stub script text> <event> <fn>...
  local body="$1" event="$2"; shift 2
  local d; d=$(mktemp -d)
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'set -uo pipefail'
    printf '. "%s/refuse.sh"\n' "$LIB"
    printf '. "%s/fold.sh"\n' "$LIB"
    printf '%s\n' "$body"
    printf 'bionic_fold "%s"' "$event"
    printf ' %s' "$@"
    printf '\nexit $?\n'
  } > "$d/drive.sh"
  FOLD_OUT=$(bash "$d/drive.sh" 2>"$FOLD_ERRFILE")
  FOLD_RC=$?
  FOLD_ERR=$(cat "$FOLD_ERRFILE" 2>/dev/null)
  rm -rf "$d"
}

# reason_of — the model's half of a `block` or `deny` verdict, which is where the
# composed detail rides. Read through jq, never by substring, so a test that passes
# on malformed JSON is not possible.
reason_of() {
  printf '%s' "$FOLD_OUT" | jq -r '(.reason // .hookSpecificOutput.permissionDecisionReason) // ""' 2>/dev/null
}

# index_of <needle> — the byte offset of <needle> in the composed reason, or -1.
# ORDERING IS ASSERTED BY OFFSET rather than by a regex over the whole text,
# because "blocks before advisories" is a claim about position and nothing else.
index_of() {
  local hay; hay=$(reason_of)
  local pre="${hay%%$1*}"
  if [ "$pre" = "$hay" ]; then printf '%s' "-1"; else printf '%s' "${#pre}"; fi
}

# The three stub families every section below composes from. Each is a complete
# function definition; `drive` concatenates the ones a case needs.
STUB_QUIET='q1() { return 0; }
q2() { return 0; }
q3() { return 0; }'

STUB_BLOCK_A='blockA() {
  fold_block block stop "the first fact" "fix the first" "REASON-ALPHA for the model"
  return 2
}'

STUB_BLOCK_B='blockB() {
  fold_block block stop "the second fact" "fix the second" "REASON-BETA for the model"
  return 2
}'

STUB_BLOCK_EXIT2='blockE() {
  fold_block exit2 stop "the exit2 fact" "fix the exit2" "REASON-EXIT2 for the model"
  return 2
}'

STUB_ADVISE='adviseA() {
  fold_advise "ADVISORY-ONE from a function with no refusal"
  return 1
}'

STUB_ADVISE_B='adviseB() {
  fold_advise "ADVISORY-TWO from a second function"
  return 1
}'

# A witness: every function the fold runs appends its own name to a file, so "every
# function always runs, in order" is read off the file rather than inferred from the
# output of the ones that happened to speak.
stub_witness() {  # <file> <name> <return code>
  printf 'w_%s() { printf %s%s%s >> "%s"; return %s; }\n' \
    "$2" "'" "$2 " "'" "$1" "$3"
}

require_helpers drive reason_of index_of stub_witness

# ─────────────────────────────────────────────────────────────────────────────
section "1: nothing to say — silence, and the status of a turn that passes"

drive "$STUB_QUIET" Stop q1 q2 q3
expect_status "1a: three quiet functions exit 0" "0" "$FOLD_RC"
expect_empty "1b: …with nothing on stdout" "$FOLD_OUT"
expect_empty "1c: …and nothing on stderr" "$FOLD_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "2: any block is a block — and EVERY reason prints"

# THE CASE THE ADR EXISTS FOR, and the one that goes RED against any
# first-block-wins draft: two functions block on one event, and BOTH reasons are in
# the composed verdict.
drive "$STUB_BLOCK_A
$STUB_BLOCK_B" Stop blockA blockB
expect_status "2a: two blocks compose to the block channel's own status" "0" "$FOLD_RC"
expect_contains "2b: the FIRST blocker's reason is in the composed verdict" \
  "REASON-ALPHA" "$(reason_of)"
expect_contains "2c: the SECOND blocker's reason is too — not just the first" \
  "REASON-BETA" "$(reason_of)"
expect_true "2d: …and in that order, by offset" \
  test "$(index_of REASON-ALPHA)" -lt "$(index_of REASON-BETA)"
expect_contains "2e: the user stream carries the one rendered line" \
  "bionic: stop refused — the first fact (fix the first)" "$FOLD_ERR"
expect_eq "2f: …exactly one of them, however many functions blocked" \
  "1" "$(printf '%s\n' "$FOLD_ERR" | /usr/bin/grep -c '^bionic: ')"

# ─────────────────────────────────────────────────────────────────────────────
section "3: blocks before advisories"

drive "$STUB_ADVISE
$STUB_BLOCK_A" Stop adviseA blockA
expect_contains "3a: the block's reason is rendered" "REASON-ALPHA" "$(reason_of)"
expect_contains "3b: the advisory reaches the stream too — it is not dropped" \
  "ADVISORY-ONE" "$FOLD_ERR"
# THE ORDERING CLAIM. The advisory function ran FIRST and still prints after the
# block, which is the whole content of "blocks before advisories": it is a rule
# about the OUTPUT order, not about the run order.
expect_true "3c: the refusal line precedes the advisory on the user stream" \
  test "$(awk '/^bionic: /{print NR; exit}' <<<"$FOLD_ERR")" -lt \
       "$(awk '/ADVISORY-ONE/{print NR; exit}' <<<"$FOLD_ERR")"

# ─────────────────────────────────────────────────────────────────────────────
section "4: no short-circuit — every function always runs"

W="$(mktemp)"
: > "$W"
drive "$(stub_witness "$W" one 2)
$(stub_witness "$W" two 0)
$(stub_witness "$W" three 1)
fold_shim() { :; }" Stop w_one w_two w_three
expect_eq "4a: a function that BLOCKS does not stop the ones after it" \
  "one two three " "$(cat "$W")"

# The same claim from the other side: the fold's verdict still reflects the blocker.
expect_ne "4b: …and the blocking one still decided the verdict" "" "$FOLD_OUT$FOLD_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "5: the CURRENT shell — state one function sets is visible to the next"

drive 'setter() { FOLD_WITNESS=set-by-the-first; return 0; }
reader() {
  if [ "${FOLD_WITNESS:-unset}" = "set-by-the-first" ]; then
    fold_advise "READBACK-OK"
  else
    fold_advise "READBACK-FAILED: ${FOLD_WITNESS:-unset}"
  fi
  return 1
}' Stop setter reader
expect_contains "5a: the second function reads what the first set (no subshell)" \
  "READBACK-OK" "$FOLD_ERR"
expect_absent "5b: …and the failure spelling is absent (the assertion is not vacuous)" \
  "READBACK-FAILED" "$FOLD_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "6: a function that EXITS is a contract violation, and it is visible"

# The consequence of running in the current shell is that `exit` inside a folded
# function takes the whole process down. That is caught here by its OBSERVABLE
# effect — the functions after it never run and nothing is composed — rather than
# by a guard the fold cannot have: a shell cannot intercept its own `exit`.
W2="$(mktemp)"
: > "$W2"
drive "exiter() { printf 'exiter ' >> \"$W2\"; exit 7; }
$(stub_witness "$W2" after 0)" Stop exiter w_after
expect_status "6a: the process carries the exiting function's status, not the fold's" \
  "7" "$FOLD_RC"
expect_eq "6b: …and the functions after it never ran" "exiter " "$(cat "$W2")"

# ─────────────────────────────────────────────────────────────────────────────
section "7: the return code is the verdict; staged text alone says nothing"

drive 'liar() {
  fold_block block stop "a fact nobody claimed" "do nothing" "STAGED-BUT-UNCLAIMED"
  return 0
}' Stop liar
expect_status "7a: a function that stages a block and returns 0 blocks nothing" "0" "$FOLD_RC"
expect_absent "7b: …and its staged text is discarded, not leaked into a later verdict" \
  "STAGED-BUT-UNCLAIMED" "$FOLD_OUT$FOLD_ERR"

# ─────────────────────────────────────────────────────────────────────────────
section "8: one blocker renders its OWN object, verbatim"

# THE DIFFERENTIAL'S FOUNDATION. With exactly one blocker there is nothing to
# compose, so the fold must produce byte-for-byte what that function's own `refuse`
# call produced before the merge — including the channel, which differs across the
# walls this fold serves.
drive "$STUB_BLOCK_EXIT2" Stop blockE
expect_status "8a: a lone exit2 blocker exits 2, as that channel does" "2" "$FOLD_RC"
expect_eq "8b: …with the one line on stderr and nothing else" \
  "bionic: stop refused — the exit2 fact (fix the exit2)" "$FOLD_ERR"
expect_empty "8c: …and nothing on stdout, as exit2 has no JSON wire" "$FOLD_OUT"

drive "$STUB_BLOCK_A" Stop blockA
expect_status "8d: a lone block blocker exits 0, as that channel does" "0" "$FOLD_RC"
expect_contains "8e: …with its detail on the JSON wire" "REASON-ALPHA" "$(reason_of)"

# ─────────────────────────────────────────────────────────────────────────────
section "9: mixed channels — the composed verdict rides the one that carries detail"

# `exit2` renders the line and DROPS the detail (refuse.sh's channel table:
# model_only=no, and the exit2 arm emits `user_out` alone). So when blockers
# disagree about the channel, composing onto exit2 would discard every reason the
# fold exists to keep. The rule is data-driven — the first blocker's mode whose
# `model_only` cell says yes — and not a hardcoded preference, so T23's `deny` walls
# compose by the same sentence.
drive "$STUB_BLOCK_EXIT2
$STUB_BLOCK_A" Stop blockE blockA
expect_contains "9a: the exit2 blocker's reason survives the mixed fold" \
  "REASON-EXIT2" "$(reason_of)"
expect_contains "9b: …and so does the block blocker's" "REASON-ALPHA" "$(reason_of)"
expect_true "9c: …in the order the functions were named" \
  test "$(index_of REASON-EXIT2)" -lt "$(index_of REASON-ALPHA)"
expect_eq "9d: the user line is the FIRST blocker's fact and fix" \
  "bionic: stop refused — the exit2 fact (fix the exit2)" \
  "$(printf '%s\n' "$FOLD_ERR" | /usr/bin/grep '^bionic: ')"

# ─────────────────────────────────────────────────────────────────────────────
section "10: advisories alone — in order, on stderr, exit 0"

drive "$STUB_ADVISE
$STUB_ADVISE_B" Stop adviseA adviseB
expect_status "10a: advisories do not block" "0" "$FOLD_RC"
expect_empty "10b: …and never write stdout" "$FOLD_OUT"
expect_contains "10c: the first advisory is on stderr" "ADVISORY-ONE" "$FOLD_ERR"
expect_contains "10d: the second is too" "ADVISORY-TWO" "$FOLD_ERR"
expect_true "10e: …in the order the functions were named" \
  test "$(awk '/ADVISORY-ONE/{print NR; exit}' <<<"$FOLD_ERR")" -lt \
       "$(awk '/ADVISORY-TWO/{print NR; exit}' <<<"$FOLD_ERR")"

# ─────────────────────────────────────────────────────────────────────────────
section "11: the event is handed on, and the fold reads nothing in it"

# EVENT-AGNOSTIC, ASSERTED (R3, and T23's precondition). The fold passes its first
# argument to every function and makes no decision on it — so an event name this
# repository has never heard of behaves exactly like `Stop`.
drive 'echoer() { fold_advise "EVENT=[$1]"; return 1; }' NotAnEventAnyoneRegistered echoer
expect_contains "11a: the event reaches the function verbatim" \
  "EVENT=[NotAnEventAnyoneRegistered]" "$FOLD_ERR"
expect_status "11b: …and an unknown event is not itself a verdict" "0" "$FOLD_RC"

drive "$STUB_BLOCK_A" SubagentStop blockA
expect_contains "11c: a block on any event composes the same way" \
  "REASON-ALPHA" "$(reason_of)"

# ─────────────────────────────────────────────────────────────────────────────
section "12: the model-facing advisory — one hookSpecificOutput object, merged"
#
# THE SECOND ADVISORY CHANNEL, and the one T23 needs (ruling R3). `fold_advise`
# puts words on the USER's stream; `hooks/farm-out-reminder.sh` has always put its
# nudge somewhere else entirely — `hookSpecificOutput.additionalContext` on stdout,
# which the user never sees and the model reads. Folding five walls into one
# process merges two streams that were never in one process before, so the fold has
# to own that channel the way it already owns the refusal: ONE object, whatever the
# number of speakers, with their strings joined by a blank line.
#
# ONE EMITTER EXISTS TODAY, so the merge is proven here by two stubs rather than by
# production — the case a second emitter would reach on its first day.

STUB_CONTEXT_A='ctxA() {
  fold_context "CONTEXT-ONE from the first speaker"
  return 1
}'
STUB_CONTEXT_B='ctxB() {
  fold_context "CONTEXT-TWO from the second speaker"
  return 1
}'
STUB_CONTEXT_MUTE='ctxM() {
  fold_context "CONTEXT-DISCARDED by a function that said nothing"
  return 0
}'

context_of() {  # the merged additionalContext, read through jq and never by substring
  printf '%s' "$FOLD_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
require_helpers context_of

drive "$STUB_CONTEXT_A" PreToolUse ctxA
expect_status "12a: a model-facing advisory does not block" "0" "$FOLD_RC"
expect_eq "12b: …it rides hookSpecificOutput on the event it was folded for" \
  "PreToolUse" "$(printf '%s' "$FOLD_OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)"
expect_eq "12c: …carrying the text verbatim" "CONTEXT-ONE from the first speaker" "$(context_of)"
expect_empty "12d: …and saying nothing on the user's stream" "$FOLD_ERR"

# THE MERGE. Two speakers, ONE object — never two JSON documents on one stdout,
# which is not a wire any reader parses.
drive "$STUB_CONTEXT_A
$STUB_CONTEXT_B" PreToolUse ctxA ctxB
expect_eq "12e: two model-facing advisories produce exactly one JSON document" "1" \
  "$(printf '%s' "$FOLD_OUT" | jq -s 'length' 2>/dev/null)"
expect_contains "12f: …carrying the first speaker's text" "CONTEXT-ONE" "$(context_of)"
expect_contains "12g: …and the second's" "CONTEXT-TWO" "$(context_of)"
expect_true "12h: …in the order the functions were named" \
  test "$(awk '/CONTEXT-ONE/{print NR; exit}' <<<"$(context_of)")" -lt \
       "$(awk '/CONTEXT-TWO/{print NR; exit}' <<<"$(context_of)")"
expect_regex "12i: …separated by a blank line, not run together" \
  'CONTEXT-ONE[^\n]*\n\nCONTEXT-TWO' "$(context_of)"

# THE RETURN CODE IS STILL THE VERDICT (§7's rule, on this channel too).
drive "$STUB_CONTEXT_MUTE" PreToolUse ctxM
expect_empty "12j: a function that stages context and returns 0 has said nothing" "$FOLD_OUT"

# THE TWO ADVISORY CHANNELS DO NOT COLLIDE: one is the user's stream, one is the
# model's, and a fold carrying both puts each where it belongs.
drive "$STUB_CONTEXT_A
$STUB_ADVISE" PreToolUse ctxA adviseA
expect_contains "12k: a user advisory still reaches stderr alongside a model one" \
  "ADVISORY-ONE" "$FOLD_ERR"
expect_contains "12l: …and the model one still reaches stdout" "CONTEXT-ONE" "$(context_of)"
expect_absent "12m: …neither leaking onto the other's stream" "CONTEXT-ONE" "$FOLD_ERR"

# A BLOCK ON THE exit2 CHANNEL LEAVES STDOUT FREE, so the context object rides it
# and the refusal rides stderr — the production shape when a push is refused on the
# same command a nudge fired for.
drive "$STUB_BLOCK_EXIT2
$STUB_CONTEXT_A" PreToolUse blockE ctxA
expect_status "12n: an exit2 block still exits 2 with a model advisory beside it" "2" "$FOLD_RC"
expect_contains "12o: …the refusal on the user's stream" "the exit2 fact" "$FOLD_ERR"
expect_eq "12p: …and the advisory as the one object on stdout" \
  "CONTEXT-ONE from the first speaker" "$(context_of)"

# A BLOCK THAT ALREADY OWNS STDOUT. `deny` and `block` render their own JSON there,
# and a second document beside it would make the whole wire unparseable — which is
# the fail-OPEN direction, since an unreadable deny is no deny. The refusal keeps
# the channel and the advisory degrades to the user's stream rather than being
# dropped or corrupting it.
drive "$STUB_BLOCK_A
$STUB_CONTEXT_A" PreToolUse blockA ctxA
expect_eq "12q: a JSON refusal keeps stdout to itself — one document" "1" \
  "$(printf '%s' "$FOLD_OUT" | jq -s 'length' 2>/dev/null)"
expect_contains "12r: …and that document is the refusal" "REASON-ALPHA" "$(reason_of)"
expect_contains "12s: …the displaced advisory is not lost, it degrades to stderr" \
  "CONTEXT-ONE" "$FOLD_ERR"

finish
