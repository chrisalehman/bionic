#!/bin/bash
# Tests for refuse-and-classify.sh — the Stop hook that refuses a turn which
# asks the human for something and hands back the classify-and-resolve prompt.
#
# Strategy: replay REAL captured Stop stdin. The key set
#   session_id, transcript_path, cwd, hook_event_name, stop_hook_active
# is the shape captured in this repo and already replayed by
# context-spend.test.sh — note that `last_assistant_message` is ABSENT from it,
# which is the corroboration that the key is conditional. Both variants are
# exercised here: the key present, and the key absent with the transcript walk
# carrying the turn.
#
# The re-entry case is the one that matters most. A Stop hook that re-fires on
# its own block wedges the session, and the CLI's consecutive-block cap is a
# backstop, never the safety argument — so `stop_hook_active` is asserted
# directly, on a payload that would otherwise certainly block.
#
# AC-5 is discharged by extracting the ratified prompt from the SPEC at test
# time and asserting the shipped reason EQUALS it, whole. That makes spec drift
# a test failure rather than a silent divergence, in both directions.
#
# The equality is only possible because the spec carries the reframe body
# literally. An earlier revision described it with a placeholder, which made
# "ship it verbatim" unexecutable and limited this test to the prose either
# side of the gap. A guard asserts the placeholder never returns: a spec that
# DESCRIBES a load-bearing string instead of CONTAINING it silently weakens
# every assertion here.
#
# Usage: bash hooks/refuse-and-classify.test.sh

set -uo pipefail

HOOKDIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HOOKDIR/refuse-and-classify.sh"
REPO="$(cd "$HOOKDIR/.." && pwd)"
SPEC="$REPO/.bionic/docs/specs/epic-11-harness-fitness/wave-02-decision-quality.spec.md"
PASS=0; FAIL=0; TOTAL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; }

assert_contains() {  # $1=label $2=needle $3=haystack
  case "$3" in *"$2"*) pass "$1" ;; *) fail "$1" "missing: $2" ;; esac
}

# run_hook <stdin-json> → HOOK_EXIT, HOOK_STDOUT
run_hook() {
  HOOK_STDOUT=$(printf '%s' "$1" | bash "$HOOK" 2>/dev/null); HOOK_EXIT=$?
}

# Real captured Stop stdin shape. last_assistant_message is added only where a
# case needs it, because the capture proves it is not always there.
payload() {  # $1=stop_hook_active $2=transcript_path [$3=last_assistant_message]
  if [ $# -ge 3 ]; then
    jq -nc --argjson a "$1" --arg t "$2" --arg m "$3" \
      '{session_id:"scrubbed", transcript_path:$t, cwd:"/scrubbed",
        hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}'
  else
    jq -nc --argjson a "$1" --arg t "$2" \
      '{session_id:"scrubbed", transcript_path:$t, cwd:"/scrubbed",
        hook_event_name:"Stop", stop_hook_active:$a}'
  fi
}

# A transcript whose LAST assistant entry carries the given text.
write_transcript() {  # $1=path $2=text
  : > "$1"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"scrubbed"}}' >> "$1"
  jq -nc --arg t 'An earlier assistant turn that is ordinary work.' \
    '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$1"
  jq -nc --arg t "$2" \
    '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$1"
}

ASK='Both shapes fit the constraint. Should we cache the parsed config, or re-read it every time?'
WORK='Wired the parser into the loader. Three files touched, all 41 tests pass. The cache key now includes the file mtime, which is what fixed the stale read.'

echo "Ordinary work turn: no block, no stdout"
T1="$TMP/t1.jsonl"; write_transcript "$T1" "$WORK"
run_hook "$(payload false "$T1" "$WORK")"
[ "$HOOK_EXIT" -eq 0 ] && pass "exit 0" || fail "exit 0" "got $HOOK_EXIT"
[ -z "$HOOK_STDOUT" ] && pass "empty stdout on a work turn" || fail "empty stdout on a work turn" "got: $HOOK_STDOUT"

echo
echo "Request-to-human turn: blocks with a reason"
T2="$TMP/t2.jsonl"; write_transcript "$T2" "$ASK"
run_hook "$(payload false "$T2" "$ASK")"
[ "$HOOK_EXIT" -eq 0 ] && pass "exit 0 (a Stop hook blocks via stdout, never via exit code)" || fail "exit 0" "got $HOOK_EXIT"
if printf '%s' "$HOOK_STDOUT" | jq -e . >/dev/null 2>&1; then pass "stdout is valid JSON"; else fail "stdout is valid JSON" "got: $HOOK_STDOUT"; fi
DEC=$(printf '%s' "$HOOK_STDOUT" | jq -r '.decision // empty' 2>/dev/null)
[ "$DEC" = "block" ] && pass "decision=block" || fail "decision=block" "got: $DEC"
REASON=$(printf '%s' "$HOOK_STDOUT" | jq -r '.reason // empty' 2>/dev/null)
[ -n "$REASON" ] && pass "reason is non-empty" || fail "reason is non-empty"

echo
echo "AC-5: the four load-bearing properties are present in the reason"
# 1. approval-list carve-out — names where asking is CORRECT regardless of capability
assert_contains "1. carve-out: approval list"           "approval list"           "$REASON"
assert_contains "1. carve-out: pushes to main"          "pushes to main"          "$REASON"
assert_contains "1. carve-out: destructive migrations"  "destructive migrations"  "$REASON"
assert_contains "1. carve-out: secrets"                 "secrets"                 "$REASON"
assert_contains "1. carve-out: billing"                 "billing"                 "$REASON"
# 2. the receipt on self-resolution
assert_contains "2. receipt: tell me the call in one line" "tell me the call in one line" "$REASON"
# 3. the problem-space clause
assert_contains "3. problem-space clause" \
  "problem space at the abstraction level best suited to maximize the quality of the decision" "$REASON"
# 4. the label and the Consequence line
assert_contains "4. label: ACTION REQUIRED"    "ACTION REQUIRED"   "$REASON"
assert_contains "4. label: DECISION REQUIRED"  "DECISION REQUIRED" "$REASON"
assert_contains "4. Consequence line"          "Consequence"       "$REASON"
assert_contains "4. reframe marker"            "DECISION REFRAME"  "$REASON"

echo
echo "AC-5: the shipped reason IS the spec's ratified prompt, whole"
# The spec now carries the reframe body LITERALLY — an earlier revision
# described it with a placeholder, which made "ship it verbatim" unexecutable
# and forced this test to check only the prose either side of the gap. With the
# gap closed the assertion is equality over the WHOLE prompt, which is strictly
# stronger: no substring of the prompt can drift, including the reframe body
# that is the user's own text and the least paraphrasable part of it.
if [ -f "$SPEC" ]; then
  # Blockquote under `### The injected prompt`, unwrapped. Stops at the first
  # line that is neither blockquote nor blank, so a later blockquote elsewhere
  # in the section cannot be swept in.
  spec_prompt=$(awk '
    /^### The injected prompt/ { f = 1; next }
    f && /^> / { seen = 1; sub(/^> /, ""); print; next }
    f && /^>$/ { print ""; next }
    f && seen && /^[[:space:]]*$/ { next }
    f && seen { exit }
  ' "$SPEC" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
  norm_reason=$(printf '%s' "$REASON" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')

  TOTAL=$((TOTAL + 1))
  if [ ${#spec_prompt} -gt 600 ]; then
    PASS=$((PASS + 1)); printf '  PASS  spec prompt extracted whole (%d chars, no placeholder)\n' "${#spec_prompt}"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  spec prompt extracted whole (got %d chars)\n' "${#spec_prompt}"
  fi

  # A placeholder must never come back: it is what made the prompt
  # unimplementable, and it would silently weaken every assertion below.
  TOTAL=$((TOTAL + 1))
  case "$spec_prompt" in
    *"<"*">"*) FAIL=$((FAIL + 1)); printf '  FAIL  spec prompt is literal, not a description (placeholder present)\n' ;;
    *)         PASS=$((PASS + 1)); printf '  PASS  spec prompt is literal, not a description\n' ;;
  esac

  TOTAL=$((TOTAL + 1))
  if [ "$norm_reason" = "$spec_prompt" ]; then
    PASS=$((PASS + 1)); printf '  PASS  shipped reason EQUALS the spec prompt, byte for byte\n'
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  shipped reason EQUALS the spec prompt\n'
    printf '        spec  (%d): %s\n' "${#spec_prompt}" "$spec_prompt"
    printf '        hook  (%d): %s\n' "${#norm_reason}" "$norm_reason"
  fi

  # The reframe body specifically — the user's own words, the part an
  # implementer is most likely to "improve".
  assert_contains "reframe body: opening sentence"  \
    "Reframe the decision(s) at a higher conceptual level in plain language" "$REASON"
  assert_contains "reframe body: options and rationale" \
    "What are the numbered options, your recommendation(s), and the accompanying rationale?" "$REASON"
  assert_contains "reframe body: significance and compounding impacts" \
    "Include significance of the decision(s), downstream and compounding impacts" "$REASON"
  assert_contains "reframe body: brevity instruction" "Be as concise as possible" "$REASON"
else
  fail "spec present for the drift check" "not found: $SPEC"
fi

echo
echo "Loop safety: stop_hook_active=true never re-fires"
# The same payload that blocked above, replayed as the CLI would after a block.
run_hook "$(payload true "$T2" "$ASK")"
[ "$HOOK_EXIT" -eq 0 ] && pass "exit 0 on re-entry" || fail "exit 0 on re-entry" "got $HOOK_EXIT"
[ -z "$HOOK_STDOUT" ] && pass "NO re-fire when stop_hook_active is true" || fail "NO re-fire when stop_hook_active is true" "got: $HOOK_STDOUT"

echo
echo "Turn text: last_assistant_message is CONDITIONAL — the walk is the fallback"
T3="$TMP/t3.jsonl"; write_transcript "$T3" "$ASK"
run_hook "$(payload false "$T3")"
DEC=$(printf '%s' "$HOOK_STDOUT" | jq -r '.decision // empty' 2>/dev/null)
[ "$DEC" = "block" ] && pass "key absent: blocks via the transcript walk" || fail "key absent: blocks via the transcript walk" "got: '$DEC'"

T4="$TMP/t4.jsonl"; write_transcript "$T4" "$WORK"
run_hook "$(payload false "$T4")"
[ -z "$HOOK_STDOUT" ] && pass "key absent: silent when the walked turn is ordinary work" || fail "key absent: silent on ordinary work" "got: $HOOK_STDOUT"

echo "  (the walk takes the LAST assistant entry, not the first)"
T5="$TMP/t5.jsonl"; write_transcript "$T5" "$WORK"
run_hook "$(payload false "$T5")"
[ -z "$HOOK_STDOUT" ] && pass "earlier ordinary entry does not leak into the verdict" || fail "walk picks the last entry"

echo
echo "The hook uses the real detector, not a re-implementation"
FENCED='Here is the guard as it now stands.

```bash
# you must call this before the first read, or the mtime is unset
grep -qE '"'"'colou?r'"'"' "$path" && echo matched
```

It exits non-zero on a malformed key instead of defaulting to zero.'
T6="$TMP/t6.jsonl"; write_transcript "$T6" "$FENCED"
run_hook "$(payload false "$T6" "$FENCED")"
[ -z "$HOOK_STDOUT" ] && pass "fenced code carrying '?' and 'you' does not block" || fail "fenced code does not block" "got: $HOOK_STDOUT"

echo
echo "Fail silent: a decision-quality hook must never break a session"
run_hook '{"session_id":"x", not valid json'
[ "$HOOK_EXIT" -eq 0 ] && pass "malformed stdin: exit 0" || fail "malformed stdin: exit 0" "got $HOOK_EXIT"
[ -z "$HOOK_STDOUT" ] && pass "malformed stdin: no stdout" || fail "malformed stdin: no stdout" "got: $HOOK_STDOUT"

run_hook '{}'
[ "$HOOK_EXIT" -eq 0 ] && pass "empty payload: exit 0" || fail "empty payload: exit 0" "got $HOOK_EXIT"
[ -z "$HOOK_STDOUT" ] && pass "empty payload: no stdout" || fail "empty payload: no stdout" "got: $HOOK_STDOUT"

run_hook "$(payload false "$TMP/does-not-exist.jsonl")"
[ "$HOOK_EXIT" -eq 0 ] && pass "unreadable transcript + no message key: exit 0" || fail "unreadable transcript: exit 0" "got $HOOK_EXIT"
[ -z "$HOOK_STDOUT" ] && pass "unreadable transcript + no message key: no stdout" || fail "unreadable transcript: no stdout" "got: $HOOK_STDOUT"

echo "  (detector missing from the install dir → silent, not a broken session)"
ORPHAN="$TMP/orphan"; mkdir -p "$ORPHAN"; cp "$HOOK" "$ORPHAN/"
HOOK_STDOUT=$(printf '%s' "$(payload false "$T2" "$ASK")" | bash "$ORPHAN/refuse-and-classify.sh" 2>/dev/null); HOOK_EXIT=$?
[ "$HOOK_EXIT" -eq 0 ] && pass "detector absent: exit 0" || fail "detector absent: exit 0" "got $HOOK_EXIT"
[ -z "$HOOK_STDOUT" ] && pass "detector absent: no stdout" || fail "detector absent: no stdout" "got: $HOOK_STDOUT"

echo
echo "last_assistant_message present but EMPTY falls back to the walk"
T7="$TMP/t7.jsonl"; write_transcript "$T7" "$ASK"
run_hook "$(payload false "$T7" "")"
DEC=$(printf '%s' "$HOOK_STDOUT" | jq -r '.decision // empty' 2>/dev/null)
[ "$DEC" = "block" ] && pass "empty message key: falls back and blocks" || fail "empty message key: falls back" "got: '$DEC'"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
[ "$FAIL" -eq 0 ]
