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

expect_equal() {     # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else
    no "$1" "outputs differ:"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/      /'
  fi
}

expect_differ() {    # <label> <a> <b>
  if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "both renderings are identical: $2"; fi
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
#
# CLAUDE_CONFIG_DIR is redirected beside HOME, and for the same hermeticity
# reason: the observation reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects`,
# so on a machine where that variable is exported — this one exports it — a
# suite that redirected only HOME would read the REAL metadata root. It is
# pointed at "$home/.claude", the same directory make_agent plants under, so the
# derivation under test is unchanged; nothing here injects a projects path.
run_check() {
  local home="$1" repo="$2"; shift 2
  ( cd "$repo" && HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" bash "$CHECK" "$@" 2>&1 )
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

# ============================================================
echo ""
echo "=== Section 4: no seam — the default projects root is derived, not injected ==="
# ============================================================
# Seam-blindness (a substituted value leaves the production path unverified):
# every test above runs with only the two environment variables the production
# path itself reads redirected — HOME and CLAUDE_CONFIG_DIR, pointed at the same
# sandbox directory — so the projects-root derivation
# (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/<slugified-project-root>) is
# itself under test; there is no injected path anywhere in this suite. The
# CLAUDE_CONFIG_DIR half of that derivation is driven with the two roots
# DIFFERENT in tests/cross-gate-agreement.test.sh §C, which is where it can be
# compared against the other two renderings. This section pins the
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
# from any cwd). Resolution is rooted at the configured metadata directory, not
# at the cwd, so it still works; repo activity is simply reported as
# unavailable.
OUT=$( cd "$SANDBOX" && HOME="$H2" CLAUDE_CONFIG_DIR="$H2/.claude" bash "$CHECK" "quiet-reviewer" 2>&1 ); ST=$?
expect_status "runs from a non-repo cwd without crashing" 0 "$ST"
expect_contains "non-repo cwd still prints the working log evidence" "agent-aquiet-reviewer-deadbeefdeadbeef.jsonl" "$OUT"

# ============================================================
echo ""
echo "=== Section 6: the progress artifact — D-6's evidence level below the agent ==="
# ============================================================
#
# An hour-long command silences the working log for the whole hour — one tool
# call, one result at the end — so "quiet for 47 minutes" describes a healthy
# suite and a wedged one identically (design §5 D-6). The task's own byproducts
# are the level of evidence below the agent: the work contract names a progress
# path, and the observation prints that artifact's facts. Facts only — the
# section carries no verdict, exactly like every other channel here.

IFS='|' read -r H6 R6 S6 <<< "$(make_world w6)"
make_agent "$H6" "$S6" "66666666-6666-6666-6666-666666666666" \
  "along-runner-66666666666666aa" "long-runner" "running the suite" >/dev/null

PROG_DIR="$R6/.bionic/tmp"
mkdir -p "$PROG_DIR"
PROG="$PROG_DIR/w6.progress"
# Written before the baseline run, not between the two: the flagged and
# unflagged runs are compared below, and an untracked file appearing between
# them would move the repo-activity line for reasons that have nothing to do
# with this flag.
printf 'step 1 done\n' > "$PROG"   # 12 bytes, written just now

# (a) No flag, no section — and nothing else moves either. This is the wave-1
# carve pin arriving at its destination: while the D-6 check was deferred, the
# pin asserted the section was absent from the whole command; now that the
# check has landed, the same negative assertion is the no-flag case.
OUT6_NONE=$(run_check "$H6" "$R6" "long-runner")
expect_absent "no --progress flag prints no progress-artifact section" "progress artifact" "$OUT6_NONE"

# (b) A fresh artifact: absolute last-write, seconds-scale age, size.
OUT6_FRESH=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG")
expect_contains "the progress section prints its header" "-- progress artifact (D-6) --" "$OUT6_FRESH"
expect_contains "the progress section prints the contracted path" "$PROG" "$OUT6_FRESH"
expect_matches "a fresh artifact prints an absolute UTC last-write" \
  '^progress: .*last-write [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$OUT6_FRESH"
expect_matches "a fresh artifact prints a seconds-scale age" \
  '^progress: .*\([0-9]{1,2}s ago\)' "$OUT6_FRESH"
expect_matches "a fresh artifact prints its size in bytes" '^progress: .*size 12B' "$OUT6_FRESH"

# Without the flag the output is byte-unchanged: the section is purely
# additive. Compared with the volatile fields (ages, absolute timestamps)
# normalized, and the three added lines — the blank separator, the header, the
# fact line — removed from the flagged run.
norm_volatile() {
  printf '%s\n' "$1" | sed -E \
    -e 's/\(age [^)]*\)/(age NORMALIZED)/' \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/TIMESTAMP/g'
}
strip_progress() {   # drop the header, the fact line, and the blank line before them
  printf '%s\n' "$1" | awk '
    /^-- progress artifact \(D-6\) --$/ { hold = 0; skip = 1; next }
    skip == 1 { skip = 0; next }
    { if (hold) print held; held = $0; hold = 1 }
    END { if (hold) print held }'
}
expect_equal "everything outside the section is unchanged by --progress" \
  "$(norm_volatile "$OUT6_NONE")" "$(norm_volatile "$(strip_progress "$OUT6_FRESH")")"

# (c) The SAME artifact, ten minutes stale: the rendering must change on time
# alone. Same path, same bytes — the only difference between these two runs is
# when the file was last written, which is the whole point of the channel.
TEN_AGO=$(date -v-10M +%Y%m%d%H%M.%S 2>/dev/null || date -d '10 minutes ago' +%Y%m%d%H%M.%S 2>/dev/null)
if [ -z "$TEN_AGO" ]; then
  no "this platform's date can express a 10-minute-old timestamp" "neither date -v nor date -d worked"
else
  touch -t "$TEN_AGO" "$PROG"
  OUT6_STALE=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG")
  expect_matches "a stale artifact prints a minutes-scale age" \
    '^progress: .*\(10m [0-9]+s ago\)' "$OUT6_STALE"
  FRESH_LINE=$(printf '%s\n' "$OUT6_FRESH" | grep '^progress: ')
  STALE_LINE=$(printf '%s\n' "$OUT6_STALE" | grep '^progress: ')
  expect_differ "fresh and stale renderings of the same artifact are distinguishable" \
    "$FRESH_LINE" "$STALE_LINE"
fi

# (d) Contracted but never written.
OUT6_MISS=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG_DIR/never-written.progress"); ST=$?
expect_status "a missing progress artifact is not an error" 0 "$ST"
expect_matches "a missing progress artifact prints ABSENT" \
  '^progress: .*never-written\.progress  ABSENT' "$OUT6_MISS"

# Facts only: the section names no state of the agent.
for verdict in "safe to stop" "recommend" "verdict" "you should" "hung" "stalled" "alive"; do
  expect_absent "the progress section carries no verdict: '$verdict'" "$verdict" "$OUT6_FRESH"
done

# (e) One path, or it is a usage error — a second flag is ambiguous about which
# artifact the contract named, and guessing is the failure this whole design
# exists to prevent.
OUT6_TWO=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG" --progress "$PROG"); ST=$?
expect_status "a second --progress flag exits 1" 1 "$ST"
expect_contains "a second --progress flag prints usage" "Usage" "$OUT6_TWO"

OUT6_BARE=$(run_check "$H6" "$R6" "long-runner" --progress); ST=$?
expect_status "--progress with no path exits 1" 1 "$ST"
expect_contains "--progress with no path prints usage" "Usage" "$OUT6_BARE"

# An EMPTY value is the same failure as a missing one, and worse in its output:
# `--progress "$PROG"` with PROG unset is the ordinary trigger, and a token that
# follows is not a path that was named. Printing `progress: ABSENT` for it states
# an authoritative fact about an artifact nobody contracted, which is the exact
# false negative D-6 exists to prevent — the reader concludes wedged and routes a
# healthy agent into the non-response procedure (Step-6 critic, issue B).
OUT6_EMPTY=$(run_check "$H6" "$R6" "long-runner" --progress ""); ST=$?
expect_status "--progress with an empty path exits 1" 1 "$ST"
expect_contains "--progress with an empty path prints usage" "Usage" "$OUT6_EMPTY"
expect_absent "--progress with an empty path never prints a progress fact" "progress:" "$OUT6_EMPTY"

# The flag and its value are never mistaken for contracted deliverables.
echo "the deliverable body" > "$R6/report.md"
OUT6_BOTH=$(run_check "$H6" "$R6" "long-runner" "report.md" --progress "$PROG")
expect_matches "a deliverable named alongside --progress is still reported" \
  'report\.md — PRESENT' "$OUT6_BOTH"
expect_absent "the flag itself is never reported as a deliverable" "  --progress —" "$OUT6_BOTH"
expect_absent "the flag's value is never reported as a deliverable" "w6.progress — " "$OUT6_BOTH"

# (f) TARGET FIRST — the grammar is the one the RECORDER can parse.
#
# This command's run is observed by hooks/stop-guard.sh's Bash arm, which
# re-parses the same command line to decide WHICH agent was examined. That
# recorder skips leading `-*` tokens one at a time and takes the first non-flag
# token; it does not know that `--progress` consumes the token after it. So a
# leading `--progress <path> <agent>` makes the two halves disagree about the
# target — the operator looks at <agent> while the record says <path> — and a
# record naming an agent nobody examined is the wall opening on a look that was
# never taken (Step-6 review F-1, proven with a two-agent fixture).
#
# The producer is therefore narrowed to exactly what the recorder already reads:
# the target is the FIRST argument, `--progress <path>` may follow it, and any
# other `-`-leading token anywhere is a usage error rather than a silent
# deliverable. That last part is also F-2: `--progres` (one `s`) used to be
# reported as an ABSENT deliverable while the reader believed they had asked for
# a progress channel.

OUT6_LEAD=$(run_check "$H6" "$R6" --progress "$PROG" "long-runner"); ST=$?
expect_status "--progress BEFORE the target exits 1" 1 "$ST"
expect_contains "--progress before the target prints usage" "Usage" "$OUT6_LEAD"
expect_absent "--progress before the target prints no evidence tier" "OBSERVATION" "$OUT6_LEAD"

# The usage error is an error: nothing on stdout, everything on stderr, so a
# caller reading the observation's output gets no half-formed tier.
OUT6_LEAD_STDOUT=$( cd "$R6" && HOME="$H6" CLAUDE_CONFIG_DIR="$H6/.claude" \
  bash "$CHECK" --progress "$PROG" "long-runner" 2>/dev/null )
expect_equal "a usage error writes nothing to stdout" "" "$OUT6_LEAD_STDOUT"

OUT6_TYPO=$(run_check "$H6" "$R6" "long-runner" --progres "$PROG"); ST=$?
expect_status "a mistyped flag exits 1 instead of becoming a deliverable" 1 "$ST"
expect_contains "a mistyped flag prints usage" "Usage" "$OUT6_TYPO"
expect_absent "a mistyped flag is never reported as a deliverable" "--progres —" "$OUT6_TYPO"

OUT6_EQ=$(run_check "$H6" "$R6" "long-runner" "--progress=$PROG"); ST=$?
expect_status "--progress=<path> exits 1 (one spelling, the one the recorder reads)" 1 "$ST"
expect_contains "--progress=<path> prints usage" "Usage" "$OUT6_EQ"

OUT6_HELP=$(run_check "$H6" "$R6" --help); ST=$?
expect_status "--help exits 1" 1 "$ST"
expect_contains "--help reaches usage rather than target resolution" "Usage" "$OUT6_HELP"
expect_absent "--help is never treated as an agent name" "unresolved" "$OUT6_HELP"

# Position is not the point — an unknown flag is a usage error wherever it sits,
# including after a well-formed --progress pair.
OUT6_TRAIL=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG" -x); ST=$?
expect_status "an unknown flag after a valid --progress pair exits 1" 1 "$ST"
expect_contains "an unknown flag after a valid --progress pair prints usage" "Usage" "$OUT6_TRAIL"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "stop-check.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
