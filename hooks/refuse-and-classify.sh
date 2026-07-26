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

# Incident 0001: the accrued stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable. Byte-identical to the copies in context-spend.sh,
# farm-out-reminder.sh, canonical-sdlc-governing-skill.sh and
# canonical-sdlc-evidence-gate.sh — divergence would give one project two audit
# directories. Deliberate per-hook duplication (no shared lib).
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-v11-audit.md' "$HOME" "$base" "$sum"
}

# Decision-quality records go to a SIBLING file in the same per-project
# directory, not into sdlc-v11-audit.md. The slug logic is shared verbatim so
# incident 0001 is honoured identically, but the streams stay separate: this one
# is per-TURN and machine-parsed by W6, while the audit stream is per-STEP and
# read by humans. Interleaving them would make both harder to use.
#
# Failure is silent and total — a hook that refuses to accrue is a lost data
# point; a hook that errors while accruing is a broken session.
accrue() {  # $1=fired(0|1) $2=signals $3=extra
  local dir f
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-}}"
  [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || return 0
  f=$(audit_path "$PROJECT_DIR") 2>/dev/null || return 0
  dir=$(dirname "$f")
  mkdir -p "$dir" 2>/dev/null || return 0
  # Signals and counts only. Turn text never reaches this file.
  printf -- '- %s refuse-and-classify: fired=%s signals=%s session=%s%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:--}" "$SESSION_ID" "${3:+ $3}" \
    >> "$dir/decision-quality.md" 2>/dev/null || return 0
}

# ── ONE read of the payload ────────────────────────────────────────────────
# Every field this hook needs, in a single `jq` spawn. It took four on the
# common path — session_id, stop_hook_active, cwd, last_assistant_message —
# plus a fifth for transcript_path on the fallback, and a Stop hook runs on
# EVERY turn, so the spawns are the cost that matters here.
#
# Framing: the header fields on line 1, joined on \037. That separator is a
# unit separator and, critically, NOT whitespace — `read` collapses runs of
# whitespace delimiters and would silently swallow an empty field, sliding
# every later field one position left. The turn text is the only field that can
# legitimately contain newlines, so it goes LAST and is carried raw as the
# whole remainder. `@tsv` would have been shorter and is wrong here: it escapes
# \t and \n into two-character sequences, and the detector matches per LINE, so
# an escaped turn is a differently-shaped turn.
#
# Every header field is flattened inside jq, and session_id is held to a
# stricter charset than the rest. Both are load-bearing, for different reasons:
# the framing above needs line 1 to stay one line, and session_id is the one
# header field that also reaches decision-quality.md — written one record per
# line and declared machine-parsed by W6.
#
# The fail-open asymmetry is preserved exactly. Both defaults are deliberate:
#   unparseable payload       → jq exits non-zero → ACTIVE "" → not "false"
#                               → treat as already-active, never block twice
#   valid JSON, not an object → the else branch → ACTIVE "true" → no block
#   well-formed object with
#     stop_hook_active ABSENT → `// false` → ACTIVE "false" → blocks, which is
#                               the first Stop of a turn and the whole point
_READ=$(printf '%s' "$INPUT" | jq -r '
  # Newlines and tabs out of every header field, or line 1 stops being one line
  # and part of the header is handed to the turn text.
  def flat: tostring | gsub("[\n\r\t]"; "");
  # session_id takes the house charset from audit_path() instead. A
  # control-character scrub is NOT enough for this field: the record line is
  # space-delimited, so it is the SPACE that lets a crafted id forge a second
  # field on a line it legitimately occupies. The allowlist leaves nothing that
  # can pass for a delimiter — no newline, no tab, no space, no `=`, and not
  # the unit separator either.
  def id: tostring | gsub("[^A-Za-z0-9._-]"; "-");
  if type == "object" then
    ([(.stop_hook_active // false | flat), (.cwd // "" | flat),
      (.transcript_path // "" | flat), (.session_id // "" | id)] | join("\u001f")),
    (.last_assistant_message // "")
  else
    (["true", "", "", ""] | join("\u001f")), ""
  end' 2>/dev/null) || _READ=""

# Everything after the first newline is the turn. When the turn is empty jq
# emits a trailing blank line, which the substitution strips — leaving no
# newline at all, which is the "no turn text" case rather than a short header.
_HDR=${_READ%%$'\n'*}
if [ "$_HDR" = "$_READ" ]; then TURN=""; else TURN=${_READ#*$'\n'}; fi
# Field ORDER is defensive, not cosmetic. `read` folds every surplus field into
# the LAST variable, so session_id going last means a separator smuggled into
# any field can only ever extend session_id — it can never shift the value of
# stop_hook_active, the one field that decides whether this hook may block.
IFS=$'\037' read -r ACTIVE CWD TRANSCRIPT SESSION_ID <<< "$_HDR"
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

# ── loop safety, before anything else ──────────────────────────────────────
# On a parse failure the fallback is "active", i.e. do not block. Every
# ambiguity in this hook resolves toward letting the turn through.
if [ "$ACTIVE" != "false" ]; then
  # Recorded as a distinct outcome: a suppressed re-entry is not the same fact
  # as a turn that had nothing to refuse, and conflating them would make the
  # accrued rate unreadable.
  accrue 0 - "suppressed=re-entry"
  exit 0
fi

# ── the completed turn's text ──────────────────────────────────────────────
# TURN and TRANSCRIPT both came out of the single read above. The key being
# ABSENT and the key being EMPTY are the same case here and always were: both
# fall back to the transcript walk, which is what makes a CONDITIONAL key safe
# to prefer.
if [ -z "${TURN//[[:space:]]/}" ]; then
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

# Signal names are captured, not discarded: they are what makes the accrued
# record diagnostic rather than a bare counter.
if SIGNALS=$(printf '%s' "$TURN" | detect_request_to_human 2>/dev/null); then
  FIRED=1
else
  FIRED=0; SIGNALS=""
fi
SIGNALS=$(printf '%s' "$SIGNALS" | tr ' ' ',')
accrue "$FIRED" "$SIGNALS" ""
[ "$FIRED" = "1" ] || exit 0

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
