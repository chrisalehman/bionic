#!/usr/bin/env bash
#
# tests/decision-baseline.sh — re-runnable corpus baseline for decision quality.
#
# Emits one TSV row per metric: <key>\t<value>\t<unit>, the same contract as
# tests/metrics.sh. The SCRIPT is the durable artifact; a stored snapshot is
# not. Re-run it at any point in the epic and the numbers are reproducible.
#
#   bash tests/decision-baseline.sh                  # TSV to stdout
#   bash tests/decision-baseline.sh > before.tsv     # snapshot for a diff
#   BIONIC_CORPUS_DIR=/path/to/jsonl bash tests/decision-baseline.sh
#
# NOTHING MEASURED ENTERS THE REPOSITORY. The corpus is the user's real session
# data and bionic is open-source and project-silent: counts and rates go to
# stdout, transcript text never leaves the temp directory, which is removed on
# exit. Never add a metric that emits matched text.
#
# What it measures, and why each number exists:
#
#   turns              assistant turns closed by a real user message. The unit
#                      is the turn the Stop hook sees — the LAST assistant
#                      message before the user speaks, mirroring
#                      `last_assistant_message`. Not every assistant record: a
#                      turn is one hand-back to the human.
#   request_turns      turns where the detector fires. The wave's numerator.
#   correction_*       user invocations of the literal `DECISION REFRAME`
#                      prompt. A floor, never a total — a badly-framed decision
#                      answered anyway leaves no trace (spec §Assumptions).
#   ac3_agreement_pct  of the turns the user actually corrected, the share the
#                      detector fires on. THE FALSIFIER. The threshold was
#                      pre-registered in the plan's `## Assumptions` and is
#                      TRACKED here as `AC3_THRESHOLD`, so the verdict is
#                      computable on a bare clone. The plan copy is still the
#                      provenance record and is checked against this constant
#                      by tests/decision-baseline.test.sh, which skips that
#                      one check loudly when `.bionic/` is absent.
#   uncorrected_fire_pct  fire rate on turns the user did NOT correct. An UPPER
#                      BOUND on false positives, not the false-positive rate: a
#                      well-framed ask the user simply answered fires
#                      correctly. Reported because a detector that fires on
#                      everything would clear the AC-3 bar trivially and be
#                      worthless.
#
# The corpus is LIVE: the session running this script is itself appending to it,
# so turn counts drift by a few between consecutive runs. That is the cost of
# measuring the real thing rather than a snapshot, and it is why the script is
# the artifact. Compare runs, not digits.
#
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

DETECTOR="$REPO/hooks/request-to-human-detector.sh"

emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

# Percentage with one decimal, or n/a when the denominator is zero — a rate out
# of nothing is not 0.0, it is unmeasured.
pct() { # $1=numerator $2=denominator
  [ "${2:-0}" -gt 0 ] 2>/dev/null || { printf 'n/a'; return; }
  awk -v n="$1" -v d="$2" 'BEGIN { printf "%.1f", (n * 100) / d }'
}

# Claude Code's per-project transcript directory: the absolute project path with
# every non-alphanumeric byte replaced by a dash.
corpus_dir() {
  if [ -n "${BIONIC_CORPUS_DIR:-}" ]; then printf '%s' "$BIONIC_CORPUS_DIR"; return; fi
  printf '%s/projects/%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" \
    "$(printf '%s' "$REPO" | sed 's/[^A-Za-z0-9]/-/g')"
}

CORPUS="$(corpus_dir)"

if [ ! -d "$CORPUS" ] || ! command -v jq >/dev/null 2>&1 || [ ! -f "$DETECTOR" ]; then
  for k in transcripts turns request_turns correction_invocations corrected_turns \
           corrected_turns_detected uncorrected_turns; do emit "decision.$k" n/a count; done
  for k in request_turn_pct ac3_agreement_pct ac3_threshold_pct uncorrected_fire_pct; do
    emit "decision.$k" n/a pct; done
  emit decision.corrections_per_100_request_turns n/a rate
  emit decision.ac3_verdict n/a verdict
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ── extract: JSONL → SOH-delimited turn stream ─────────────────────────────
# House pattern from hooks/context-spend.sh: `jq -Rr 'fromjson?'` streams the
# transcript line by line and swallows malformed lines rather than aborting.
# Sidechain records are subagent turns — a different Stop surface — and are
# excluded. isMeta user records are system-injected, not the human speaking.
JQ='
fromjson?
| select((.message | type) == "object")
| select(.isSidechain != true)
| if .type == "assistant" then
    ([.message.content[]? | select(.type == "text") | .text] | join("\n"))
    | select(length > 0)
    | "\u0001A\n" + .
  elif .type == "user" and (.isMeta != true) then
    (if (.message.content | type) == "string" then .message.content
     else ([.message.content[]? | select(.type == "text") | .text] | join("\n")) end)
    | select(length > 0)
    | "\u0001U" + (if test("(^|\n)#+[ ]*DECISION REFRAME") then "1" else "0" end)
  else empty end
'

FILES=0
for f in "$CORPUS"/*.jsonl; do [ -f "$f" ] && FILES=$((FILES + 1)); done

: > "$TMP/corrected"
for f in "$CORPUS"/*.jsonl; do
  [ -f "$f" ] || continue
  jq -Rr "$JQ" "$f" 2>/dev/null
done | awk -v corrf="$TMP/corrected" -v cntf="$TMP/invocations" -v fpf="$TMP/fingerprints" '
  BEGIN { SOH = sprintf("%c", 1); seq = 0; pend = 0; inv = 0; last = 0; buf = ""; lastkey = "" }
  # Exact-duplicate key for a turn: the text flattened to one line, so the
  # aggregate can tell 12 emissions of one stock sentence from 12 distinct
  # turns. Stays in $TMP, is never emitted.
  function fingerprint(s) { gsub(/[\n\t]/, " ", s); gsub(/  +/, " ", s); return s }
  substr($0, 1, 2) == SOH "A" { pend = 1; buf = ""; next }
  substr($0, 1, 2) == SOH "U" {
    c = substr($0, 3, 1)
    if (c == "1") inv++
    if (pend && buf ~ /[^ \t]/) {
      seq++
      printf "%s%d\n%s\n", SOH, seq, buf
      last = seq; lastkey = fingerprint(buf)
      if (c == "1") { print seq > corrf; print seq "\t" lastkey > fpf }
    } else if (c == "1" && last > 0) {
      # Consecutive user messages: the turn that IMMEDIATELY PRECEDED this
      # correction is the one already emitted. Attribute it there rather than
      # dropping the ground-truth row.
      print last > corrf; print last "\t" lastkey > fpf
    }
    pend = 0; buf = ""
    next
  }
  pend { buf = (buf == "" ? $0 : buf "\n" $0) }
  END {
    if (pend && buf ~ /[^ \t]/) { seq++; printf "%s%d\n%s\n", SOH, seq, buf }
    print inv > cntf
  }
' > "$TMP/turns"

bash "$DETECTOR" --batch < "$TMP/turns" > "$TMP/verdicts" 2>/dev/null

INVOCATIONS=$(cat "$TMP/invocations" 2>/dev/null || echo 0)
[ -n "$INVOCATIONS" ] || INVOCATIONS=0

touch "$TMP/fingerprints"
read -r TURNS REQ CT CTD UNC UNCF DCT DCTD <<EOF
$(awk -v corrf="$TMP/corrected" -v fpf="$TMP/fingerprints" '
  FILENAME == corrf { corr[$1] = 1; next }
  FILENAME == fpf   { fp[$1] = substr($0, index($0, "\t") + 1); next }
  { turns++
    if ($2 == 1) req++
    if ($1 in corr) {
      ct++; if ($2 == 1) ctd++
      # De-duplicated ground truth: a stock sentence the agent emitted a dozen
      # times is ONE distinct framing failure, not a dozen. Counting it a dozen
      # times would let one repeated trivial positive carry the agreement rate.
      k = fp[$1]
      if (!(k in seen)) { seen[k] = 1; dct++; if ($2 == 1) dctd++ }
    } else { unc++; if ($2 == 1) uncf++ } }
  END { printf "%d %d %d %d %d %d %d %d", turns, req, ct, ctd, unc, uncf, dct, dctd }
' "$TMP/corrected" "$TMP/fingerprints" "$TMP/verdicts")
EOF

# The pre-registered threshold, TRACKED here rather than read out of the plan.
#
# It used to be read from the plan at runtime, and the plan lives in `.bionic/`,
# which is gitignored. On any clone of this repo the read returned nothing, the
# threshold went empty, and `ac3_verdict` degraded to `n/a` — the instrument
# reported no verdict at all for every consumer, while looking healthy on the
# author's machine.
#
# The plan remains the PROVENANCE record and is still the place the threshold
# was pre-registered. It is now compared against this constant by the paired
# test (a drift check that skips loudly when the plan is absent), rather than
# being the value the verdict depends on. That also removes an odd property of
# the old arrangement: the gate could be moved by editing an untracked file
# that leaves no reviewable diff.
AC3_THRESHOLD=70
THRESHOLD="$AC3_THRESHOLD"

AGREE=$(pct "$CTD" "$CT")
AGREE_DEDUP=$(pct "$DCTD" "$DCT")

emit decision.transcripts            "$FILES"       count
emit decision.turns                  "$TURNS"       count
emit decision.request_turns          "$REQ"         count
emit decision.request_turn_pct       "$(pct "$REQ" "$TURNS")" pct
emit decision.correction_invocations "$INVOCATIONS" count
emit decision.corrections_per_100_request_turns "$(pct "$INVOCATIONS" "$REQ")" rate
emit decision.corrected_turns          "$CT"        count
emit decision.corrected_turns_detected "$CTD"       count
emit decision.ac3_agreement_pct        "$AGREE"     pct
emit decision.ac3_threshold_pct        "${THRESHOLD:-n/a}" pct
# The same measurement with exact-duplicate turns collapsed. Emitted because the
# pre-registered denominator counts a stock one-liner once per emission, and a
# repeated trivial positive can carry the headline rate on its own. Reported
# ALONGSIDE the pre-registered number, never instead of it — the pre-registered
# metric is the one the threshold was written against.
emit decision.corrected_turns_distinct "$DCT"       count
emit decision.ac3_agreement_dedup_pct  "$AGREE_DEDUP" pct
emit decision.uncorrected_turns        "$UNC"       count
emit decision.uncorrected_fire_pct     "$(pct "$UNCF" "$UNC")" pct

# The verdict is emitted, never enforced by exit code: a missed threshold is a
# valid, valuable result that triggers a re-plan. A non-zero exit here would
# invite someone to tune the detector until the script goes green, which is the
# exact defect this wave exists to prevent.
#
# Computed from the DE-DUPLICATED rate, not the raw one: the user ruled the
# de-duplicated reading governs the gate, since a stock sentence emitted a
# dozen times must not carry the verdict on its own repetition.
if [ -z "$THRESHOLD" ] || [ "$AGREE_DEDUP" = "n/a" ]; then
  emit decision.ac3_verdict n/a verdict
else
  emit decision.ac3_verdict \
    "$(awk -v a="$AGREE_DEDUP" -v t="$THRESHOLD" 'BEGIN { print (a + 0 >= t + 0) ? "pass" : "BELOW-THRESHOLD" }')" \
    verdict
fi
