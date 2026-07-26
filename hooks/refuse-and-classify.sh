#!/bin/bash
# REFUSE-AND-CLASSIFY: a Stop hook that refuses a turn which asks the human for
# something, and hands back a prompt making the agent classify and try to
# resolve the request itself.
#
# The hook does NOT judge whether the request was well-framed, nor which
# category it belongs to. It detects only that a request to the human is
# PRESENT — that is hooks/request-to-human-detector.sh, sourced, never
# re-implemented here. Classification and resolution are handed back to the
# model in the reason string. Detection is mechanical; judgement is not.
#
# Loop safety (AC-4): `stop_hook_active` is checked FIRST, before the turn text
# is read or the detector runs. One refusal per decision, then the turn goes
# through. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` is a CLI-side backstop and is NOT
# the safety argument — this check is.
#
# Turn text: `last_assistant_message` is CONDITIONAL — the key is absent when
# there is no message, which this repo's own captured Stop stdin demonstrates
# (see hooks/context-spend.test.sh:9). Prefer it, fall back to the
# transcript_path walk proven by hooks/context-spend.sh. Never assume presence.
#
# Failure mode: SILENCE. Missing jq, unreadable payload, absent detector,
# detector error → exit 0, no block, nothing on stdout. A hook meant to improve
# decisions must never break a session. A Stop hook's stdout can carry a block
# payload, so stdout is written on exactly one path: a confirmed hit.
#
# NOT registered in MANAGED_HOOKS. Installing the file is bootstrap's business;
# wiring it to the Stop event is a user decision at Step 9, because a live
# blocking hook affects every session on the machine.

set -u

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat) || exit 0
[ -n "$INPUT" ] || exit 0

# ── loop safety, before anything else ──────────────────────────────────────
# On a parse failure the fallback is "active", i.e. do not block. Every
# ambiguity in this hook resolves toward letting the turn through.
ACTIVE=$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.stop_hook_active // false) else true end' 2>/dev/null) || ACTIVE=true
[ "$ACTIVE" = "false" ] || exit 0

# ── the completed turn's text ──────────────────────────────────────────────
TURN=$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.last_assistant_message // empty) else empty end' 2>/dev/null) || TURN=""

if [ -z "${TURN//[[:space:]]/}" ]; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.transcript_path // empty) else empty end' 2>/dev/null) || TRANSCRIPT=""
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
  # House pattern (context-spend.sh): bounded tail, `fromjson?` swallows
  # malformed lines. Each candidate is emitted as ONE JSON-encoded line so the
  # last one survives `tail -1` — a turn spans many lines, and joining first
  # would make `tail` pick a fragment rather than a turn. Sidechain entries are
  # subagent turns, a different Stop surface.
  _enc=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr '
    fromjson? | select(.isSidechain != true) | select(.type == "assistant") |
    select((.message | type) == "object") |
    ([.message.content[]? | select(.type == "text") | .text] | join("\n")) |
    select(length > 0) | @json
  ' 2>/dev/null | tail -1) || _enc=""
  [ -n "$_enc" ] || exit 0
  TURN=$(printf '%s' "$_enc" | jq -r . 2>/dev/null) || exit 0
fi
[ -n "${TURN//[[:space:]]/}" ] || exit 0

# ── the single detector, sourced from the same directory ───────────────────
DETECTOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/request-to-human-detector.sh"
[ -f "$DETECTOR" ] || exit 0
# shellcheck source=/dev/null
. "$DETECTOR" 2>/dev/null || exit 0
command -v detect_request_to_human >/dev/null 2>&1 || exit 0

printf '%s' "$TURN" | detect_request_to_human >/dev/null 2>&1 || exit 0

# ── the refusal ────────────────────────────────────────────────────────────
# Ships near-verbatim from the spec's `### The injected prompt`. Four
# properties are load-bearing and may not be dropped: the approval-list
# carve-out, the one-line receipt on self-resolution, the problem-space clause,
# and the ACTION/DECISION REQUIRED label plus the Consequence line. The paired
# test extracts this prompt from the spec at run time and fails on drift.
#
# The reframe body is the USER's own text, carried literally by the spec. It is
# not paraphrasable and not an implementer's to tune: an earlier spec revision
# described it with a placeholder, which made "ship it verbatim" unexecutable.
# Change it in the spec, never here — the paired test asserts the two are equal.
read -r -d '' REASON <<'PROMPT'
Before asking me for anything, classify what you need.

**An action?** If you have the tools and it isn't on my approval list — pushes to main, destructive migrations, secrets, billing — do it. Don't ask.

**A decision?** Check whether standing principles auto-resolve it: most elegant over expedient, simple over complex, right level over brute force, lower operational burden over higher. If they do — decide, proceed, and tell me the call in one line.

Only if it survives both: label it `ACTION REQUIRED` or `DECISION REQUIRED`, then:

`### DECISION REFRAME ###` Reframe the decision(s) at a higher conceptual level in plain language. Represent the problem space at the abstraction level best suited to maximize the quality of the decision. What are the numbered options, your recommendation(s), and the accompanying rationale? Include significance of the decision(s), downstream and compounding impacts. Be as concise as possible.

Close with **Consequence** — what each option triggers, one line each, so I know what I am setting in motion before I answer.
PROMPT

jq -nc --arg r "$REASON" '{decision: "block", reason: $r}' 2>/dev/null || exit 0
exit 0
