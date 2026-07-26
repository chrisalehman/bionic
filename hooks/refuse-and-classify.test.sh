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
PASS=0; FAIL=0; TOTAL=0; SKIP=0

TMP=$(mktemp -d)
# Incident 0001: the accrued record must live where a consuming project cannot
# commit it. The fake HOME is a SIBLING of the sandbox project, never a child —
# the "nothing under the project tree" assertion uses `find "$PROJ"`, which a
# nested home would satisfy falsely. Every invocation runs with HOME pointed
# here, or the suite would append to the developer's real ~/.claude/logs.
FAKE_HOME=$(mktemp -d)
PROJ="$TMP/proj"; mkdir -p "$PROJ"
trap 'rm -rf "$TMP" "$FAKE_HOME"' EXIT

# Must match hooks/refuse-and-classify.sh audit_path() byte for byte.
slug_for() { printf '%s-%s' "$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')" \
                            "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
record_for() { printf '%s/.claude/logs/%s/decision-quality.md' "$FAKE_HOME" "$(slug_for "$1")"; }

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; }

assert_contains() {  # $1=label $2=needle $3=haystack
  case "$3" in *"$2"*) pass "$1" ;; *) fail "$1" "missing: $2" ;; esac
}

# run_hook <stdin-json> → HOOK_EXIT, HOOK_STDOUT
run_hook() {
  HOOK_STDOUT=$(printf '%s' "$1" | HOME="$FAKE_HOME" bash "$HOOK" 2>/dev/null); HOOK_EXIT=$?
}

# Real captured Stop stdin shape. last_assistant_message is added only where a
# case needs it, because the capture proves it is not always there.
payload() {  # $1=stop_hook_active $2=transcript_path [$3=last_assistant_message]
  if [ $# -ge 3 ]; then
    jq -nc --argjson a "$1" --arg t "$2" --arg c "$PROJ" --arg m "$3" \
      '{session_id:"scrubbed", transcript_path:$t, cwd:$c,
        hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}'
  else
    jq -nc --argjson a "$1" --arg t "$2" --arg c "$PROJ" \
      '{session_id:"scrubbed", transcript_path:$t, cwd:$c,
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
echo "AC-5: the shipped reason IS the ratified prompt, byte for byte"
# This is the strongest assertion in the wave, and it MUST execute for anyone
# who clones the repo. It used to read the prompt out of `.bionic/`, which is
# gitignored — so on a fresh clone this equality, the placeholder guard and the
# four reframe-body checks ALL silently vanished, six assertions at once, and
# the suite still reported green. An assertion that only runs on the author's
# machine is not evidence.
#
# The prompt is therefore vendored into a TRACKED fixture beside the hook. The
# fixture is derived FROM the spec, never dumped from the hook: the spec
# hard-wraps its blockquote for readability and the hook ships each paragraph
# on one line, so the fixture is the spec text REFLOWED. Generating it out of
# the implementation would have made this assertion tautological — it would
# compare the hook to itself and pass no matter what the prompt said.
FIXTURE="$HOOKDIR/refuse-and-classify.prompt.txt"

TOTAL=$((TOTAL + 1))
if [ -f "$FIXTURE" ]; then
  PASS=$((PASS + 1)); printf '  PASS  tracked prompt fixture present (needs no .bionic/)\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  tracked prompt fixture MISSING: %s\n' "$FIXTURE"
fi

# Byte-exact, not whitespace-normalised. The paragraph structure is part of the
# prompt the model receives.
printf '%s\n' "$REASON" > "$TMP/reason.actual"
TOTAL=$((TOTAL + 1))
if [ -f "$FIXTURE" ] && diff -u "$FIXTURE" "$TMP/reason.actual" > "$TMP/reason.diff" 2>&1; then
  PASS=$((PASS + 1))
  printf '  PASS  shipped reason EQUALS the tracked fixture, byte for byte (%d bytes)\n' \
    "$(wc -c < "$FIXTURE" | tr -d ' ')"
else
  FAIL=$((FAIL + 1)); printf '  FAIL  shipped reason EQUALS the tracked fixture\n'
  sed 's/^/        /' "$TMP/reason.diff" 2>/dev/null | head -30
fi

# The reframe body specifically — the user's own words, and the part an
# implementer is most likely to "improve". These never needed the spec, so they
# run unconditionally rather than riding along inside a conditional.
assert_contains "reframe body: opening sentence"  \
  "Reframe the decision(s) at a higher conceptual level in plain language" "$REASON"
assert_contains "reframe body: options and rationale" \
  "What are the numbered options, your recommendation(s), and the accompanying rationale?" "$REASON"
assert_contains "reframe body: significance and compounding impacts" \
  "Include significance of the decision(s), downstream and compounding impacts" "$REASON"
assert_contains "reframe body: brevity instruction" "Be as concise as possible" "$REASON"

echo
echo "AC-5 provenance: the fixture still matches the spec (drift guard)"
# THIS one is legitimately skippable, and it is the only part that is. Its sole
# job is catching divergence between the vendored copy and the spec it came
# from, and that genuinely requires the spec. The equality proof above does not
# depend on it and runs everywhere — which is the whole point of the split.
# Vendoring without this check would merely move the drift somewhere quieter.
if [ -f "$SPEC" ] && [ -f "$FIXTURE" ]; then
  # Blockquote under `### The injected prompt`, unwrapped. Stops at the first
  # line that is neither blockquote nor blank, so a later blockquote elsewhere
  # in the section cannot be swept in. Compared whitespace-normalised, because
  # the spec wraps for readability and the fixture is reflowed.
  spec_prompt=$(awk '
    /^### The injected prompt/ { f = 1; next }
    f && /^> / { seen = 1; sub(/^> /, ""); print; next }
    f && /^>$/ { print ""; next }
    f && seen && /^[[:space:]]*$/ { next }
    f && seen { exit }
  ' "$SPEC" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')
  fixture_norm=$(tr '\n' ' ' < "$FIXTURE" | sed 's/  */ /g; s/^ //; s/ $//')

  TOTAL=$((TOTAL + 1))
  if [ ${#spec_prompt} -gt 600 ]; then
    PASS=$((PASS + 1)); printf '  PASS  spec prompt extracted whole (%d chars)\n' "${#spec_prompt}"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  spec prompt extracted whole (got %d chars)\n' "${#spec_prompt}"
  fi

  # A placeholder must never come back: it is what made the prompt
  # unimplementable, and it would silently weaken everything downstream.
  TOTAL=$((TOTAL + 1))
  case "$spec_prompt" in
    *"<"*">"*) FAIL=$((FAIL + 1)); printf '  FAIL  spec prompt is literal, not a description (placeholder present)\n' ;;
    *)         PASS=$((PASS + 1)); printf '  PASS  spec prompt is literal, not a description\n' ;;
  esac

  TOTAL=$((TOTAL + 1))
  if [ "$fixture_norm" = "$spec_prompt" ]; then
    PASS=$((PASS + 1)); printf '  PASS  tracked fixture still matches the spec (no vendored drift)\n'
  else
    FAIL=$((FAIL + 1)); printf '  FAIL  tracked fixture still matches the spec\n'
    printf '        spec    (%d): %s\n' "${#spec_prompt}" "$spec_prompt"
    printf '        fixture (%d): %s\n' "${#fixture_norm}" "$fixture_norm"
  fi
else
  SKIP=$((SKIP + 3))
  printf '  SKIP  fixture-vs-spec drift guard (3 assertions) — spec not present\n'
  printf '        %s\n' "$SPEC"
  printf '        `.bionic/` is gitignored, so this is expected on a clone. The\n'
  printf '        byte-exact equality above DID run; only the provenance check\n'
  printf '        between the vendored copy and the spec is unavailable here.\n'
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
echo "AC-8: the hook accrues its own fire/no-fire record"
# Decision quality must stay measurable after the wave closes. The record is the
# only thing W6 will have — this wave's baseline comes from history, and history
# cannot be re-measured after behaviour changes.
REC=$(record_for "$PROJ")
rm -f "$REC"

T8="$TMP/t8.jsonl"; write_transcript "$T8" "$ASK"
run_hook "$(payload false "$T8" "$ASK")"
if [ -f "$REC" ]; then pass "record file created under \$HOME/.claude/logs/<slug>/"
else fail "record file created" "not found: $REC"; fi
line=$(tail -1 "$REC" 2>/dev/null || true)
assert_contains "record: source tag"   "refuse-and-classify:" "$line"
assert_contains "record: fired=1"      "fired=1"              "$line"
# The signal names are what make the accrued data diagnostic rather than a bare
# counter — W6 needs to know WHICH ask shape drove the rate.
assert_contains "record: carries signal names" "signals=question" "$line"
TOTAL=$((TOTAL + 1))
if printf '%s' "$line" | grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z '; then
  PASS=$((PASS + 1)); printf '  PASS  record: house line format (- <ISO8601> <source>: ...)\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  record: house line format — got: %s\n' "$line"
fi

echo "  (a non-firing turn is recorded too — no-fire is data, not absence of data)"
before=$(wc -l < "$REC" | tr -d ' ')
T9="$TMP/t9.jsonl"; write_transcript "$T9" "$WORK"
run_hook "$(payload false "$T9" "$WORK")"
after=$(wc -l < "$REC" | tr -d ' ')
[ "$after" -eq $((before + 1)) ] && pass "record: appended, never truncated" || fail "record appended" "$before → $after"
assert_contains "record: fired=0 on an ordinary turn" "fired=0" "$(tail -1 "$REC")"

echo "  (a suppressed re-entry is distinguishable from a genuine no-fire)"
run_hook "$(payload true "$T8" "$ASK")"
assert_contains "record: re-entry marked" "suppressed=re-entry" "$(tail -1 "$REC")"
[ -z "$HOOK_STDOUT" ] && pass "record: logging did not resurrect the block" || fail "re-entry still silent"

echo "  (S1: a crafted session id cannot forge a second record)"
# decision-quality.md is declared machine-parsed by W6 and is written one record
# per line. session_id is the only field on that line that comes from outside
# the hook, so it is the only place a newline could inject a whole extra record.
# Not a live vector today — the id is a harness-generated UUID — but the file is
# an input to something else, and an injectable line format stays injectable.
before=$(wc -l < "$REC" | tr -d ' ')
FORGED_ID='real-id
- 2099-01-01T00:00:00Z refuse-and-classify: fired=1 signals=question session=forged'
T10="$TMP/t10.jsonl"; write_transcript "$T10" "$WORK"
run_hook "$(jq -nc --arg t "$T10" --arg c "$PROJ" --arg m "$WORK" --arg s "$FORGED_ID" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"Stop",
    stop_hook_active:false, last_assistant_message:$m}')"
after=$(wc -l < "$REC" | tr -d ' ')
TOTAL=$((TOTAL + 1))
if [ "$after" -eq $((before + 1)) ]; then
  PASS=$((PASS + 1)); printf '  PASS  record: newline-bearing session id appends exactly one line\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  record: newline-bearing session id appended %d lines\n' "$((after - before))"
fi
TOTAL=$((TOTAL + 1))
if grep -q 'session=forged' "$REC" 2>/dev/null; then
  FAIL=$((FAIL + 1)); printf '  FAIL  record: a forged record reached the stream\n'
else
  PASS=$((PASS + 1)); printf '  PASS  record: no forged record in the stream\n'
fi
# A tab is the other delimiter a parser is likely to reach for.
TOTAL=$((TOTAL + 1))
run_hook "$(jq -nc --arg t "$T10" --arg c "$PROJ" --arg m "$WORK" --arg s "$(printf 'id\twith\ttabs')" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"Stop",
    stop_hook_active:false, last_assistant_message:$m}')"
if printf '%s' "$(tail -1 "$REC")" | grep -q "$(printf '\t')"; then
  FAIL=$((FAIL + 1)); printf '  FAIL  record: a tab from session_id reached the record line\n'
else
  PASS=$((PASS + 1)); printf '  PASS  record: tabs are stripped from session_id\n'
fi

echo "  (a field separator smuggled into session_id cannot suppress the refusal)"
# The hook reads the whole payload in one jq spawn and frames the header fields
# on a unit separator. That framing is itself an injection surface: a separator
# inside an EARLIER field would slide every later field left, and one of those
# fields is stop_hook_active — the flag that decides whether the hook may block
# at all. session_id is therefore read LAST, where surplus fields fold into it
# harmlessly, and is charset-restricted on top.
T11="$TMP/t11.jsonl"; write_transcript "$T11" "$ASK"
SEP=$(printf '\037')
run_hook "$(jq -nc --arg t "$T11" --arg c "$PROJ" --arg m "$ASK" \
  --arg s "id${SEP}true${SEP}${PROJ}${SEP}${T11}" \
  '{session_id:$s, transcript_path:$t, cwd:$c, hook_event_name:"Stop",
    stop_hook_active:false, last_assistant_message:$m}')"
DEC=$(printf '%s' "$HOOK_STDOUT" | jq -r '.decision // empty' 2>/dev/null)
[ "$DEC" = "block" ] && pass "separator injection does not flip stop_hook_active" \
  || fail "separator injection does not flip stop_hook_active" "got: '$DEC'"
TOTAL=$((TOTAL + 1))
if printf '%s' "$(tail -1 "$REC")" | grep -q "$SEP"; then
  FAIL=$((FAIL + 1)); printf '  FAIL  record: a separator from session_id reached the record line\n'
else
  PASS=$((PASS + 1)); printf '  PASS  record: separators are stripped from session_id\n'
fi

echo "  (incident 0001: nothing is written inside the project tree)"
TOTAL=$((TOTAL + 1))
stray=$(find "$PROJ" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$stray" -eq 0 ]; then
  PASS=$((PASS + 1)); printf '  PASS  record: zero files under the project tree\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  record: %s file(s) under the project tree\n' "$stray"
  find "$PROJ" -type f | sed 's/^/        /'
fi

echo "  (no transcript content reaches the record)"
TOTAL=$((TOTAL + 1))
if grep -qiF "cache the parsed config" "$REC" 2>/dev/null; then
  FAIL=$((FAIL + 1)); printf '  FAIL  record: turn text leaked into the accrued record\n'
else
  PASS=$((PASS + 1)); printf '  PASS  record: signals and counts only, no turn text\n'
fi

echo "  (logging can never break a session)"
UNWRIT=$(mktemp -d); chmod 500 "$UNWRIT"
HOOK_STDOUT=$(printf '%s' "$(payload false "$T8" "$ASK")" | HOME="$UNWRIT" bash "$HOOK" 2>/dev/null); HOOK_EXIT=$?
chmod 700 "$UNWRIT"; rm -rf "$UNWRIT"
[ "$HOOK_EXIT" -eq 0 ] && pass "unwritable HOME: exit 0" || fail "unwritable HOME: exit 0" "got $HOOK_EXIT"
DEC=$(printf '%s' "$HOOK_STDOUT" | jq -r '.decision // empty' 2>/dev/null)
[ "$DEC" = "block" ] && pass "unwritable HOME: the refusal still ships" || fail "unwritable HOME: refusal still ships" "got '$DEC'"

echo
echo "The fail-open asymmetry: two defaults pointing OPPOSITE ways, both deliberate"
# Collapsing the payload reads into one jq spawn is exactly the kind of change
# that quietly flattens this, so it is asserted directly rather than left to be
# inferred from an exit code.
#
# A well-formed object with stop_hook_active ABSENT is the FIRST Stop of a turn.
# `// false` makes it block, which is the entire purpose of the hook.
T12="$TMP/t12.jsonl"; write_transcript "$T12" "$ASK"
run_hook "$(jq -nc --arg t "$T12" --arg c "$PROJ" --arg m "$ASK" \
  '{session_id:"scrubbed", transcript_path:$t, cwd:$c,
    hook_event_name:"Stop", last_assistant_message:$m}')"
DEC=$(printf '%s' "$HOOK_STDOUT" | jq -r '.decision // empty' 2>/dev/null)
[ "$DEC" = "block" ] && pass "key ABSENT on a well-formed object: // false → blocks" \
  || fail "key ABSENT on a well-formed object: // false → blocks" "got: '$DEC'"

# An UNPARSEABLE payload resolves the other way: treat it as already-active, so
# a hook that cannot read the flag can never block a second time. Silence alone
# would not prove this — the hook has a dozen other ways to exit 0 — so the
# accrued marker is what pins which branch ran. CLAUDE_PROJECT_DIR supplies the
# project root that the unreadable payload cannot.
HOOK_STDOUT=$(printf '%s' '{"session_id":"x", not valid json' \
  | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>/dev/null); HOOK_EXIT=$?
assert_contains "unparseable payload: took the already-active path" \
  "suppressed=re-entry" "$(tail -1 "$REC")"
[ -z "$HOOK_STDOUT" ] && pass "unparseable payload: still no block" \
  || fail "unparseable payload: still no block" "got: $HOOK_STDOUT"

# Valid JSON that is not an object is the same fail-open direction.
HOOK_STDOUT=$(printf '%s' '"a bare string"' \
  | HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>/dev/null); HOOK_EXIT=$?
assert_contains "valid JSON but not an object: already-active path" \
  "suppressed=re-entry" "$(tail -1 "$REC")"
[ -z "$HOOK_STDOUT" ] && pass "valid JSON but not an object: no block" \
  || fail "valid JSON but not an object: no block" "got: $HOOK_STDOUT"

echo
# Skips are reported on the SAME line as the tally, never swallowed. A suite
# that quietly drops assertions when an input is missing reads exactly like a
# suite that ran them — that failure mode is what C1 was.
printf 'Results: %d/%d passed, %d failed, %d skipped\n' "$PASS" "$TOTAL" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
