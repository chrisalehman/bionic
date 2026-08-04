#!/bin/bash
# Tests for hooks/stop-check.sh — THE OBSERVATION (epic-15 wave-01R, AC-3).
#
# The observation is a PRODUCER, not a hook: the orchestrator runs it by hand
# before stopping an agent. Its whole contract is "resolve the target, print the
# evidence tier, decide NOTHING" (design/orchestrator-subagent-coordination.md
# §4 "The observation"). These tests hold it to exactly that — including the
# negative half, that no verdict vocabulary ever appears in its output.
#
# HERMETIC. Every run happens inside a mktemp'd sandbox with its own HOME and
# its own git repo. Nothing here touches the operator's real ~/.claude, the real
# projects directory, or the live installed hooks, and no test invokes the
# TaskStop tool.
#
# Usage: bash hooks/stop-check.test.sh

set -uo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/stop-check.sh"
PASS=0
FAIL=0
TOTAL=0

# `cd … && pwd` normalizes the path: $TMPDIR carries a trailing slash on
# macOS, and a doubled separator would slugify differently from the cwd the
# script under test actually sees.
SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/stop-check-test.XXXXXX")" && pwd)"
trap 'rm -rf "$SANDBOX"' EXIT

# ---------- assertions ----------

ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; }

expect_contains() {  # <label> <needle> <haystack>
  if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else no "$1" "missing: $2"; fi
}

expect_matches() {   # <label> <ERE> <haystack>
  if printf '%s' "$3" | grep -qE -- "$2"; then ok "$1"; else no "$1" "no match for: $2"; fi
}

expect_absent() {    # <label> <needle> <haystack>
  if printf '%s' "$3" | grep -qiF -- "$2"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi
}

expect_status() {    # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected exit $2, got $3"; fi
}

# ---------- fixtures ----------
#
# FIXTURE FIDELITY (declared per checklist §A / spec §Design).
#
# Source of truth: .bionic/docs/record/epic-15-kill-interception-experiment.md
# (CLI 2.1.220 verbatim captures), corroborated by a direct read of this
# machine's own projects directory on 2026-08-04.
#
#   * Directory layout — FAITHFUL. §2.5 captures
#     `agent_transcript_path: ".../<session-id>/subagents/agent-<agent-id>.jsonl"`;
#     the sibling `agent-<agent-id>.meta.json` is captured verbatim in §2.8. The
#     same layout was read live at
#     ~/.claude/projects/-Users-admin-workspace-personal-bionic/<sid>/subagents/.
#   * meta.json field set — FAITHFUL to §2.8 for the anonymous case
#     (`agentType`, `description`, `name`, `toolUseId`, `spawnDepth`). The live
#     read added `model`, `taskKind`, `teamName`, `customAgentType`,
#     `permissionMode` for named in-process teammates; both shapes appear below
#     so the resolver is proven against each. `name` is the field the resolver
#     keys on in both.
#   * agent-id shape — FAITHFUL to both observed forms: the anonymous
#     `a567bd5c6d1e03d67` (§2.2/§2.8) and the name-prefixed
#     `aw1r-records-researcher-38fccb01411afdd2` read live.
#   * Working-log line shape — FAITHFUL to the live read: JSONL, one object per
#     line, assistant turns carrying `.message.content[]` entries of type
#     `text` or `tool_use`.
#   * SYNTHESIZED, and declared as such: the message TEXT, the deliverable
#     files, and the git history. None of them are platform surfaces — they are
#     ordinary content this script reads, and nothing about their bytes is
#     platform-determined.

slugify() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'; }

# make_world <name> — a sandbox HOME + a git repo, echoing "<home>|<repo>|<slug>"
make_world() {
  local name="$1"
  local home="$SANDBOX/$name/home" repo="$SANDBOX/$name/repo"
  mkdir -p "$home" "$repo"
  git -C "$repo" init -q 2>/dev/null
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name "T"
  echo "seed" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm "seed commit" 2>/dev/null
  printf '%s|%s|%s\n' "$home" "$repo" "$(slugify "$repo")"
}

# make_agent <home> <slug> <session-id> <agent-id> <name> <last-text> [meta-extra-json]
make_agent() {
  local home="$1" slug="$2" sid="$3" aid="$4" aname="$5" text="$6" extra="${7:-}"
  local dir="$home/.claude/projects/$slug/$sid/subagents"
  mkdir -p "$dir"
  : > "$home/.claude/projects/$slug/$sid.jsonl"
  # meta.json — field set per §2.8 plus the live named-teammate fields.
  if [ -n "$extra" ]; then
    printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0,%s}\n' \
      "$aname" "$extra" > "$dir/agent-$aid.meta.json"
  else
    printf '{"agentType":"general-purpose","description":"a test agent","name":"%s","toolUseId":"toolu_01TEST","spawnDepth":0}\n' \
      "$aname" > "$dir/agent-$aid.meta.json"
  fi
  # working log — JSONL, assistant turns with .message.content[]
  {
    printf '{"type":"user","message":{"content":[{"type":"text","text":"go"}]}}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}\n'
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":%s}]}}\n' "$(printf '%s' "$text" | jq -Rs .)"
  } > "$dir/agent-$aid.jsonl"
  printf '%s\n' "$dir"
}

# run_check <home> <repo> [args...]
run_check() {
  local home="$1" repo="$2"; shift 2
  ( cd "$repo" && HOME="$home" bash "$CHECK" "$@" 2>&1 )
}

# ============================================================
echo ""
echo "=== Section 1: target resolution against on-disk metadata (AC-3) ==="
# ============================================================

IFS='|' read -r H1 R1 S1 <<< "$(make_world w1)"
make_agent "$H1" "$S1" "11111111-1111-1111-1111-111111111111" \
  "aw1r-slice-4-3-3202dd476c0b4a5e" "w1r-slice-4-3" \
  "I already completed this review — resending now." \
  '"model":"opus","taskKind":"in_process_teammate","teamName":"session-11111111","customAgentType":"senior-implementor"' >/dev/null

OUT=$(run_check "$H1" "$R1" "w1r-slice-4-3"); ST=$?
expect_status "resolving by name exits 0" 0 "$ST"
expect_contains "resolves a target typed as a NAME to its agent id" "aw1r-slice-4-3-3202dd476c0b4a5e" "$OUT"

OUT=$(run_check "$H1" "$R1" "aw1r-slice-4-3-3202dd476c0b4a5e"); ST=$?
expect_status "resolving by agent id exits 0" 0 "$ST"
expect_contains "resolves a target typed as an AGENT ID" "aw1r-slice-4-3-3202dd476c0b4a5e" "$OUT"

# P5: `name@team` is a legal TaskStop reference, so the observation must accept it.
OUT=$(run_check "$H1" "$R1" "w1r-slice-4-3@session-11111111"); ST=$?
expect_status "resolving by name@team exits 0" 0 "$ST"
expect_contains "resolves a target typed as name@team" "aw1r-slice-4-3-3202dd476c0b4a5e" "$OUT"

OUT=$(run_check "$H1" "$R1" "no-such-agent"); ST=$?
expect_status "unresolvable target exits 1" 1 "$ST"
expect_contains "unresolvable target says so" "unresolved" "$OUT"

# Ambiguity: the same NAME in two different sessions of the same project.
make_agent "$H1" "$S1" "22222222-2222-2222-2222-222222222222" \
  "a567bd5c6d1e03d67" "w1r-slice-4-3" "older run" >/dev/null
OUT=$(run_check "$H1" "$R1" "w1r-slice-4-3"); ST=$?
expect_status "ambiguous target exits 1" 1 "$ST"
expect_contains "ambiguous target says so" "ambiguous" "$OUT"
expect_contains "ambiguous target lists candidate 1" "aw1r-slice-4-3-3202dd476c0b4a5e" "$OUT"
expect_contains "ambiguous target lists candidate 2" "a567bd5c6d1e03d67" "$OUT"

# ============================================================
echo ""
echo "=== Section 2: the evidence tier is printed (AC-3) ==="
# ============================================================

IFS='|' read -r H2 R2 S2 <<< "$(make_world w2)"
DIR2=$(make_agent "$H2" "$S2" "33333333-3333-3333-3333-333333333333" \
  "aquiet-reviewer-deadbeefdeadbeef" "quiet-reviewer" \
  "I already completed this review — resending now.")
echo "the deliverable body, with substance" > "$R2/report.md"

OUT=$(run_check "$H2" "$R2" "quiet-reviewer" "report.md" "missing-report.md")

# Working-log recency as ABSOLUTE time and as AGE (both, per AC-3).
expect_matches "working-log recency printed as an absolute UTC timestamp" \
  '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$OUT"
expect_matches "working-log recency printed as an age" '\(age [0-9]' "$OUT"
expect_contains "working log path printed" "agent-aquiet-reviewer-deadbeefdeadbeef.jsonl" "$OUT"

# Last message — the agent's own words, the third evidence channel (§2.2).
expect_contains "last message from the agent printed" "I already completed this review" "$OUT"

# Repo activity.
expect_contains "repo activity printed" "seed commit" "$OUT"

# Contracted deliverables: existence AND substance.
expect_matches "present deliverable reported as present, with size" \
  'report\.md.*(PRESENT|present)' "$OUT"
expect_matches "present deliverable reports its byte size" 'report\.md.*[0-9]+ bytes' "$OUT"
expect_matches "absent deliverable reported as absent" \
  'missing-report\.md.*(ABSENT|absent)' "$OUT"

# ============================================================
echo ""
echo "=== Section 3: it decides NOTHING (AC-3, §4 'Never: stop anything, judge anything') ==="
# ============================================================

for verdict in "safe to stop" "do not stop" "recommend" "verdict" "you should" "it is dead" "hung"; do
  expect_absent "observation output carries no verdict: '$verdict'" "$verdict" "$OUT"
done
expect_contains "observation states that it decides nothing" "decides nothing" "$OUT"

# D-6 carve amendment (register 08-04): the progress-artifact check is WAVE 2.
# This pin fails if a future edit smuggles it into wave 1.
expect_absent "no D-6 progress-artifact check in wave 1" "progress artifact" "$OUT"

# ============================================================
echo ""
echo "=== Section 4: no seam — the default projects root is derived, not injected ==="
# ============================================================
# Seam-blindness (a substituted value leaves the production path unverified):
# every test above runs with only HOME redirected, so the projects-root
# derivation ($HOME/.claude/projects/<slugified-project-root>) is itself under
# test — there is no injected path anywhere in this suite. This section pins the
# derivation by its discriminating consequence: an agent under THIS project's
# slug resolves quietly, while one found only under another project's slug
# resolves with an explicit out-of-project note.

IFS='|' read -r H4 R4 S4 <<< "$(make_world w4)"
make_agent "$H4" "$(slugify "$SANDBOX/some-other-project")" \
  "44444444-4444-4444-4444-444444444444" "aforeign-1234567890abcdef" "foreign" "hi" >/dev/null
OUT=$(run_check "$H4" "$R4" "foreign"); ST=$?
expect_status "an agent found only outside this project still resolves" 0 "$ST"
expect_contains "an out-of-project match is flagged as such" "outside this project" "$OUT"

# And the positive pair: an agent under THIS repo's slug resolves with no note.
make_agent "$H4" "$S4" "55555555-5555-5555-5555-555555555555" \
  "alocal-1234567890abcdef" "local" "hi" >/dev/null
OUT=$(run_check "$H4" "$R4" "local"); ST=$?
expect_status "an agent under this project's slug resolves" 0 "$ST"
expect_absent "an in-project match carries no out-of-project note" "outside this project" "$OUT"

# ============================================================
echo ""
echo "=== Section 5: usage and hostile inputs ==="
# ============================================================

OUT=$(run_check "$H1" "$R1"); ST=$?
expect_status "no target argument exits 1" 1 "$ST"
expect_contains "no target argument prints usage" "Usage" "$OUT"

# A target string that is a glob must not expand into a match.
OUT=$(run_check "$H2" "$R2" '*'); ST=$?
expect_status "a glob target does not resolve" 1 "$ST"

# Run from OUTSIDE any git repo (checklist A1: the fix command must be runnable
# from any cwd). Resolution is HOME-derived, so it still works; repo activity is
# simply reported as unavailable.
OUT=$( cd "$SANDBOX" && HOME="$H2" bash "$CHECK" "quiet-reviewer" 2>&1 ); ST=$?
expect_status "runs from a non-repo cwd without crashing" 0 "$ST"
expect_contains "non-repo cwd still prints the working log evidence" "agent-aquiet-reviewer-deadbeefdeadbeef.jsonl" "$OUT"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "stop-check.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
