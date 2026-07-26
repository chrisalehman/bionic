#!/usr/bin/env bash
# Tests for tests/decision-baseline.sh — the corpus scorer.
#
# The scorer's headline numbers come from the user's live transcript corpus,
# which cannot be asserted against: it grows while the script runs and it is not
# in the repository. So this suite builds a FROZEN synthetic corpus with a
# hand-computed answer and asserts every emitted metric exactly. That pins the
# arithmetic — turn segmentation, correction attribution, the de-duplication,
# and the verdict — without depending on anyone's session history.
#
# The synthetic corpus is authored here. No transcript content is copied, and
# the suite asserts the scorer emits no fixture text of its own.
#
# It also exercises `BIONIC_CORPUS_DIR`, which existed but was never tested:
# pointing the scorer at a frozen directory is what lets a later re-run
# reproduce a number bit-exact. Live remains the default — a stored snapshot as
# the primary artifact is what the standing ruling forbids.
#
# Usage: bash tests/decision-baseline.test.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCORER="$REPO/tests/decision-baseline.sh"
PASS=0; FAIL=0; TOTAL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; }

# ---------- the frozen corpus ----------
CORPUS="$TMP/corpus"; mkdir -p "$CORPUS"
F="$CORPUS/frozen.jsonl"
: > "$F"

a_turn() { jq -nc --arg t "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$F"; }
u_turn() { jq -nc --arg t "$1" '{type:"user", message:{role:"user", content:$t}}' >> "$F"; }
u_fix()  { jq -nc --arg t "### DECISION REFRAME ###
Reframe this at a higher conceptual level." '{type:"user", message:{role:"user", content:$t}}' >> "$F"; }

WORK1='Wired the parser into the loader. Three files touched, all 41 tests pass.'
ASK1='Both shapes fit the constraint. Should we cache the parsed value, or re-read it every time?'
ASK2='The container suite needs a daemon this box does not have. Can you run it on yours?'
WORK2='Extracted the boundary check into its own function and replaced the three call sites. The suite is green at 41/41.'

# turn 1 — ordinary work, user moves on        → uncorrected, no fire
a_turn "$WORK1"; u_turn 'thanks, carry on'
# turn 2 — an ask, user corrects the framing   → corrected, fires
a_turn "$ASK1";  u_fix
# turn 3 — an ask, user simply answers it      → uncorrected, fires
a_turn "$ASK2";  u_turn 'yes, ran it, all green'
# turn 4 — ordinary work, user corrects anyway → corrected, no fire
a_turn "$WORK2"; u_fix
# turn 5 — the SAME ask text as turn 2         → corrected, fires, and de-duplicates
a_turn "$ASK1";  u_fix

# Records that must be invisible to the scorer: a subagent turn (a different
# Stop surface) and a system-injected user record (not the human speaking).
jq -nc --arg t 'Should we do it this way, or the other way?' \
  '{type:"assistant", isSidechain:true, message:{role:"assistant", content:[{type:"text", text:$t}]}}' >> "$F"
jq -nc --arg t '### DECISION REFRAME ###' \
  '{type:"user", isMeta:true, message:{role:"user", content:$t}}' >> "$F"

score() { BIONIC_CORPUS_DIR="$CORPUS" bash "$SCORER" 2>/dev/null; }

echo "Known-answer: every metric on a hand-computed frozen corpus"
OUT=$(score)
expect() {  # $1=key $2=expected value
  local got
  got=$(printf '%s\n' "$OUT" | awk -v k="$1" -F'\t' '$1 == k { print $2; exit }')
  if [ "$got" = "$2" ]; then pass "$1 = $2"; else fail "$1 = $2" "got '$got'"; fi
}

# 5 turns; 3 ask (2,3,5); 3 corrections (2,4,5); of the corrected, 2 fire (2,5).
expect decision.transcripts                      1
expect decision.turns                            5
expect decision.request_turns                    3
expect decision.request_turn_pct                 60.0
expect decision.correction_invocations           3
expect decision.corrections_per_100_request_turns 100.0
expect decision.corrected_turns                  3
expect decision.corrected_turns_detected         2
expect decision.ac3_agreement_pct                66.7
expect decision.ac3_threshold_pct                70
# Turns 2 and 5 carry identical text, so the distinct ground truth is 2 rows,
# of which 1 fires. This is the exact collapse that moved the live reading from
# 76.3% to 66.7% and triggered the re-plan — pinned here so it cannot regress.
expect decision.corrected_turns_distinct         2
expect decision.ac3_agreement_dedup_pct          50.0
expect decision.uncorrected_turns                2
expect decision.uncorrected_fire_pct             50.0
# 66.7 < 70. The live corpus passes, so only a fixture can prove the verdict is
# capable of saying no.
expect decision.ac3_verdict                      BELOW-THRESHOLD

echo
echo "Straddle case: raw and dedup rates disagree across the 70% threshold"
# The known-answer corpus above cannot discriminate which rate drives the
# verdict — raw (66.7) and dedup (50.0) are both under 70, so a verdict wired
# to either one reads BELOW-THRESHOLD. This corpus is built so the two rates
# land on OPPOSITE sides of the threshold: 8 duplicate corrected turns on the
# firing ASK1 text plus 2 duplicate corrected turns on the non-firing WORK1
# text give a raw rate of 8/10 = 80.0 (clears 70), but collapsed to distinct
# fingerprints that is 1 firing of 2 distinct = 50.0 (misses it). Only this
# shape proves the verdict is reading the de-duplicated column.
CORPUS2="$TMP/corpus2"; mkdir -p "$CORPUS2"
F="$CORPUS2/frozen.jsonl"; : > "$F"
for i in 1 2 3 4 5 6 7 8; do a_turn "$ASK1";  u_fix; done
for i in 1 2;             do a_turn "$WORK1"; u_fix; done

OUTS=$(BIONIC_CORPUS_DIR="$CORPUS2" bash "$SCORER" 2>/dev/null)
expect_straddle() {  # $1=key $2=expected value
  local got
  got=$(printf '%s\n' "$OUTS" | awk -v k="$1" -F'\t' '$1 == k { print $2; exit }')
  if [ "$got" = "$2" ]; then pass "straddle: $1 = $2"; else fail "straddle: $1 = $2" "got '$got'"; fi
}
expect_straddle decision.ac3_agreement_pct       80.0
expect_straddle decision.ac3_agreement_dedup_pct 50.0
expect_straddle decision.ac3_verdict             BELOW-THRESHOLD

echo
echo "The verdict never sets the exit code"
# A red script invites tuning the detector until it goes green, which is the
# defect this wave exists to prevent.
BIONIC_CORPUS_DIR="$CORPUS" bash "$SCORER" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && pass "exit 0 even when the verdict is BELOW-THRESHOLD" || fail "exit 0 on BELOW-THRESHOLD" "got $rc"

echo
echo "Sidechain and isMeta records are invisible"
# Both planted records would move the numbers if counted: the sidechain turn
# asks a question, and the isMeta record carries the correction marker.
metric() { printf '%s\n' "$OUT" | awk -v k="$1" -F'\t' '$1 == k { print $2; exit }'; }
[ "$(metric decision.turns)" = "5" ] \
  && pass "planted sidechain turn did not become a turn" \
  || fail "planted sidechain turn was counted" "turns=$(metric decision.turns)"
[ "$(metric decision.correction_invocations)" = "3" ] \
  && pass "planted isMeta correction was not counted" \
  || fail "planted isMeta correction was counted" "invocations=$(metric decision.correction_invocations)"

echo
echo "BIONIC_CORPUS_DIR: a frozen corpus reproduces bit-exact"
# The live corpus drifts because the running session appends to it. The override
# is what makes a number re-checkable later; it is not a replacement for the
# live default.
A=$(score); B=$(score)
TOTAL=$((TOTAL + 1))
if [ "$A" = "$B" ]; then
  PASS=$((PASS + 1)); printf '  PASS  two runs over a frozen corpus are byte-identical\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  two runs over a frozen corpus differ\n'
  diff <(printf '%s\n' "$A") <(printf '%s\n' "$B") | sed 's/^/        /'
fi

echo
echo "Absent corpus emits n/a, never 0"
# A missing corpus must not read as "measured, and the answer was zero".
OUT2=$(BIONIC_CORPUS_DIR="$TMP/nope" bash "$SCORER" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && pass "exit 0 with no corpus" || fail "exit 0 with no corpus" "got $rc"
for k in decision.turns decision.request_turns decision.ac3_agreement_pct; do
  got=$(printf '%s\n' "$OUT2" | awk -v k="$k" -F'\t' '$1 == k { print $2; exit }')
  [ "$got" = "n/a" ] && pass "$k = n/a" || fail "$k = n/a" "got '$got'"
done

echo
echo "Output is counts and rates only — no corpus content"
TOTAL=$((TOTAL + 1))
leak=""
for w in cache parser boundary container daemon Reframe; do
  case "$OUT" in *"$w"*) leak="$leak $w" ;; esac
done
if [ -z "$leak" ]; then
  PASS=$((PASS + 1)); printf '  PASS  no fixture text appears in the emitted metrics\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  fixture text leaked into the output:%s\n' "$leak"
fi

echo
echo "Every row is well-formed TSV: <key>\\t<value>\\t<unit>"
TOTAL=$((TOTAL + 1))
bad=$(printf '%s\n' "$OUT" | awk -F'\t' 'NF != 3 || $1 !~ /^decision\./ { c++ } END { print c + 0 }')
if [ "$bad" -eq 0 ]; then
  PASS=$((PASS + 1)); printf '  PASS  all %s rows well-formed\n' "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
else
  FAIL=$((FAIL + 1)); printf '  FAIL  %s malformed row(s)\n' "$bad"
fi

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
[ "$FAIL" -eq 0 ]
