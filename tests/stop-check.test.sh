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
# Usage: bash tests/stop-check.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

CHECK="${BIONIC_HOOKS_DIR}/stop-check.sh"
# The roster's WRITER. Section 8 reads rows; §8(g) drives this script to produce
# one, because a hand-written row cannot prove the reader is reading a field the
# writer can actually emit (Step-6 six-axis review, axis-3 FAIL).
WRITER="${BIONIC_HOOKS_DIR}/dispatch-preflight.sh"
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
  if grep -qF -- "$2" <<<"$3"; then ok "$1"; else no "$1" "missing: $2"; fi
}

expect_matches() {   # <label> <ERE> <haystack>
  if grep -qE -- "$2" <<<"$3"; then ok "$1"; else no "$1" "no match for: $2"; fi
}

expect_absent() {    # <label> <needle> <haystack>
  if grep -qiF -- "$2" <<<"$3"; then no "$1" "unexpectedly present: $2"; else ok "$1"; fi
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
  ( cd "$repo" && HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" CLAUDE_CODE_SESSION_ID= \
      bash "$CHECK" "$@" 2>&1 )
}

# run_check_as <own-session-id> <home> <repo> [args...] — like run_check, but with
# CLAUDE_CODE_SESSION_ID explicitly set: the channel stop-check.sh reads to learn
# "this session's own id" for roster classification (slice 4/5), mirroring the
# same resolution hooks/preflight-probe.sh already makes. run_check ALWAYS pins
# this variable (empty above) rather than leaving it to the ambient shell — this
# suite is run inside a real Claude Code session, which exports its own real
# CLAUDE_CODE_SESSION_ID, and an unpinned test would silently vary its
# classification verdict with whatever session happens to be running it.
run_check_as() {
  local sid="$1" home="$2" repo="$3"; shift 3
  ( cd "$repo" && HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" CLAUDE_CODE_SESSION_ID="$sid" \
      bash "$CHECK" "$@" 2>&1 )
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

# Ambiguity: the same NAME in two different sessions of the same project.
make_agent "$H1" "$S1" "22222222-2222-2222-2222-222222222222" \
  "a567bd5c6d1e03d67" "w1r-slice-4-3" "older run" >/dev/null
OUT=$(run_check "$H1" "$R1" "w1r-slice-4-3"); ST=$?
expect_status "ambiguous target exits 1" 1 "$ST"
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

# Last message — the agent's own words, the third evidence channel (§2.2).
expect_contains "last message from the agent printed" "I already completed this review" "$OUT"

# Repo activity.
expect_contains "repo activity printed" "seed commit" "$OUT"

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

# And the positive pair: an agent under THIS repo's slug resolves with no note.
make_agent "$H4" "$S4" "55555555-5555-5555-5555-555555555555" \
  "alocal-1234567890abcdef" "local" "hi" >/dev/null
OUT=$(run_check "$H4" "$R4" "local"); ST=$?
expect_status "an agent under this project's slug resolves" 0 "$ST"

# ============================================================
echo ""
echo "=== Section 5: usage and hostile inputs ==="
# ============================================================

OUT=$(run_check "$H1" "$R1"); ST=$?
expect_status "no target argument exits 1" 1 "$ST"

# A target string that is a glob must not expand into a match.
OUT=$(run_check "$H2" "$R2" '*'); ST=$?
expect_status "a glob target does not resolve" 1 "$ST"

# Run from OUTSIDE any git repo (checklist A1: the fix command must be runnable
# from any cwd). Resolution is rooted at the configured metadata directory, not
# at the cwd, so it still works; repo activity is simply reported as
# unavailable.
OUT=$( cd "$SANDBOX" && HOME="$H2" CLAUDE_CONFIG_DIR="$H2/.claude" bash "$CHECK" "quiet-reviewer" 2>&1 ); ST=$?
expect_status "runs from a non-repo cwd without crashing" 0 "$ST"

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

# (b) A fresh artifact: absolute last-write, seconds-scale age, size.
OUT6_FRESH=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG")
# (d) Contracted but never written.
OUT6_MISS=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG_DIR/never-written.progress"); ST=$?
expect_status "a missing progress artifact is not an error" 0 "$ST"

# (d2) A CONTRACTED PATH IS RESOLVED, and by the evidence gate's rule (A-6.6 (c)).
#
# WHAT WAS WRONG. Every path this command stats arrives as brief prose, and the spelling
# briefs use is `record/epic-NN-wM/x.md` — the form the Step-5 contract and the evidence
# gate publish for an artifact under the docs root. This command resolved nothing: a
# relative path was stat'd against whatever directory the observer stood in, so a present
# progress artifact printed `ABSENT` and `progress_state=absent`. An observation that
# decides nothing had still decided wrongly, and a reader acting on it would have stopped
# an agent that was writing.
#
# THE RULE, THREE ARMS: `record/`-led resolves under the docs root, a bare relative path
# against the project root (unchanged), absolute stands (unchanged). Each carries its
# paired negative, because "it printed PRESENT" and "it stopped looking" render alike.
mkdir -p "$R6/.bionic/docs/record/epic-17-w6"
DOCS_PROG="$R6/.bionic/docs/record/epic-17-w6/w6.progress"
printf 'step 1 done\n' > "$DOCS_PROG"

OUT6_REC=$(run_check "$H6" "$R6" "long-runner" --progress "record/epic-17-w6/w6.progress")
expect_contains "…and the machine line says present, not absent" "progress_state=present" "$OUT6_REC"
expect_contains "…and the path is reported as the contract spelled it" \
  "progress=record/epic-17-w6/w6.progress" "$OUT6_REC"

# Paired negative: nothing under the docs root, and the same row reads ABSENT again.
rm -f "$DOCS_PROG"
OUT6_REC_GONE=$(run_check "$H6" "$R6" "long-runner" --progress "record/epic-17-w6/w6.progress")
expect_contains "…machine line agrees" "progress_state=absent" "$OUT6_REC_GONE"

# NOT the repo-root copy. `<repo>/record/…` is the placement the old resolution taught;
# if it satisfied a record/-led path the fix would be an alias, not a correction.
mkdir -p "$R6/record/epic-17-w6"
printf 'the appeasement copy\n' > "$R6/record/epic-17-w6/w6.progress"
OUT6_REC_REPO=$(run_check "$H6" "$R6" "long-runner" --progress "record/epic-17-w6/w6.progress")
expect_matches "a repo-root copy does not answer for a record/-led path" \
  '^progress: record/epic-17-w6/w6\.progress  ABSENT' "$OUT6_REC_REPO"
rm -rf "$R6/record"
printf 'step 1 done\n' > "$DOCS_PROG"

# A bare relative path is still the project root's — unchanged by the rule.
printf 'plain\n' > "$R6/plain.progress"
OUT6_PLAIN=$(run_check "$H6" "$R6" "long-runner" --progress "plain.progress")
expect_matches "a bare relative progress path still resolves against the project root" \
  '^progress: plain\.progress  last-write' "$OUT6_PLAIN"
rm -f "$R6/plain.progress"
OUT6_PLAIN_GONE=$(run_check "$H6" "$R6" "long-runner" --progress "plain.progress")
expect_matches "…paired negative: removed, it reads ABSENT" \
  '^progress: plain\.progress  ABSENT' "$OUT6_PLAIN_GONE"

# An absolute path is unchanged: (b) above already proves the positive; this is the pin
# that the new rule did not reach it.
expect_matches "an absolute progress path is untouched by the rule" \
  '^progress: .*w6\.progress  last-write' \
  "$(run_check "$H6" "$R6" "long-runner" --progress "$PROG")"

# THE DELIVERABLES OBEY THE SAME RULE, for the same reason and out of the same resolver:
# `Expected artifact: record/<x>` is the line briefs actually write.
OUT6_DEL=$(run_check "$H6" "$R6" "long-runner" "record/epic-17-w6/w6.progress")
expect_contains "…and the machine line names it present, as contracted" \
  "present:record/epic-17-w6/w6.progress" "$OUT6_DEL"
rm -f "$DOCS_PROG"
OUT6_DEL_GONE=$(run_check "$H6" "$R6" "long-runner" "record/epic-17-w6/w6.progress")
expect_matches "…paired negative: removed, the deliverable reads ABSENT" \
  'record/epic-17-w6/w6\.progress — ABSENT' "$OUT6_DEL_GONE"

# (e) One path, or it is a usage error — a second flag is ambiguous about which
# artifact the contract named, and guessing is the failure this whole design
# exists to prevent.
OUT6_TWO=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG" --progress "$PROG"); ST=$?
expect_status "a second --progress flag exits 1" 1 "$ST"

OUT6_BARE=$(run_check "$H6" "$R6" "long-runner" --progress); ST=$?
expect_status "--progress with no path exits 1" 1 "$ST"

# An EMPTY value is the same failure as a missing one, and worse in its output:
# `--progress "$PROG"` with PROG unset is the ordinary trigger, and a token that
# follows is not a path that was named. Printing `progress: ABSENT` for it states
# an authoritative fact about an artifact nobody contracted, which is the exact
# false negative D-6 exists to prevent — the reader concludes wedged and routes a
# healthy agent into the non-response procedure (Step-6 critic, issue B).
OUT6_EMPTY=$(run_check "$H6" "$R6" "long-runner" --progress ""); ST=$?
expect_status "--progress with an empty path exits 1" 1 "$ST"

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

# The usage error is an error: nothing on stdout, everything on stderr, so a
# caller reading the observation's output gets no half-formed tier.
OUT6_LEAD_STDOUT=$( cd "$R6" && HOME="$H6" CLAUDE_CONFIG_DIR="$H6/.claude" \
  bash "$CHECK" --progress "$PROG" "long-runner" 2>/dev/null )
expect_equal "a usage error writes nothing to stdout" "" "$OUT6_LEAD_STDOUT"

OUT6_TYPO=$(run_check "$H6" "$R6" "long-runner" --progres "$PROG"); ST=$?
expect_status "a mistyped flag exits 1 instead of becoming a deliverable" 1 "$ST"
expect_absent "a mistyped flag is never reported as a deliverable" "--progres —" "$OUT6_TYPO"

OUT6_EQ=$(run_check "$H6" "$R6" "long-runner" "--progress=$PROG"); ST=$?
expect_status "--progress=<path> exits 1 (one spelling, the one the recorder reads)" 1 "$ST"

OUT6_HELP=$(run_check "$H6" "$R6" --help); ST=$?
expect_status "--help exits 1" 1 "$ST"

# Position is not the point — an unknown flag is a usage error wherever it sits,
# including after a well-formed --progress pair.
OUT6_TRAIL=$(run_check "$H6" "$R6" "long-runner" --progress "$PROG" -x); ST=$?
expect_status "an unknown flag after a valid --progress pair exits 1" 1 "$ST"

# ============================================================
echo ""
echo "=== Section 7: the machine line — printed on success, on nothing else ==="
# ============================================================
#
# hooks/execution-recorder.sh reads this line and nothing else, so its presence
# IS the claim "an observation ran and produced an evidence tier". The whole C6
# closure rests on the second half of that: every path that shows the operator no
# evidence tier must print no line (spec AC-3; the residual it replaces is pinned
# in tests/cross-gate-agreement.test.sh §C case 6).

IFS='|' read -r H7 R7 S7 <<< "$(make_world w7)"
S7DIR=$(make_agent "$H7" "$S7" "77777777-7777-7777-7777-777777777777" \
  "amachine-7777777777777777" "machine" "working")
PROG7="$R7/.bionic/tmp/w7.progress"
mkdir -p "$R7/.bionic/tmp"; printf 'stage 1\n' > "$PROG7"
printf 'a report\n' > "$R7/report7.md"

MLINE_OF() { printf '%s\n' "$1" | grep '^stop-check-observation/' ; }

OUT7=$(run_check "$H7" "$R7" "machine"); ST=$?
expect_status "a successful observation exits 0" 0 "$ST"
M7=$(MLINE_OF "$OUT7")
expect_matches "a successful run prints ONE versioned machine line" \
  '^stop-check-observation/v1\|' "$M7"
expect_equal "exactly one machine line, never two" "1" "$(printf '%s\n' "$OUT7" | grep -c '^stop-check-observation/')"
expect_contains "the machine line names the RESOLVED target" \
  "target=amachine-7777777777777777" "$M7"
expect_contains "the machine line names the target AS TYPED" "typed=machine" "$M7"
expect_contains "the machine line names the working log it read" \
  "log=$S7DIR/agent-amachine-7777777777777777.jsonl" "$M7"
expect_matches "the machine line carries the activity level (mtime)" 'mtime=[0-9]+' "$M7"
expect_matches "the machine line carries the activity level (size)" 'size=[0-9]+' "$M7"
expect_contains "with no --progress the progress state is 'unnamed', not blank" \
  "progress_state=unnamed" "$M7"

# The file facts the operator READ are the file facts the line CARRIES. One
# computation, two renderings — this is what removes the F-1 divergence class.
OUT7_SIZE=$(printf '%s\n' "$OUT7" | grep -E '^  size:' | grep -oE '[0-9]+' | head -1)
expect_equal "the size printed for the reader is the size carried for the machine" \
  "$OUT7_SIZE" "$(printf '%s' "$M7" | tr '|' '\n' | grep '^size=' | cut -d= -f2)"

# Contract state rides along, for the D-6 comparison slices 4/5 and 4/6 make.
OUT7B=$(run_check "$H7" "$R7" "machine" report7.md nosuch.md --progress "$PROG7")
M7B=$(MLINE_OF "$OUT7B")
expect_contains "each deliverable's state is carried, present" "present:report7.md" "$M7B"
expect_contains "each deliverable's state is carried, absent" "absent:nosuch.md" "$M7B"
expect_contains "a named-and-present progress artifact is 'present'" "progress_state=present" "$M7B"
expect_matches "a present progress artifact carries its mtime" 'progress_mtime=[0-9]+' "$M7B"
OUT7C=$(run_check "$H7" "$R7" "machine" --progress "$R7/.bionic/tmp/never-written")
expect_contains "a named-but-missing progress artifact is 'absent', not 'unnamed'" \
  "progress_state=absent" "$(MLINE_OF "$OUT7C")"

# EVERY REFUSAL CLASS PRINTS NO LINE. Each of these is a run whose operator saw
# no evidence tier; each must leave the recorder nothing to copy.
check_no_line() {  # <label> <args…>
  local label="$1"; shift
  local out st
  out=$(run_check "$H7" "$R7" "$@"); st=$?
  if [ "$st" -eq 0 ]; then
    no "$label — and the run itself failed" "expected a non-zero exit, got 0"
  elif [ -z "$(MLINE_OF "$out")" ]; then
    ok "$label"
  else
    no "$label" "printed: $(MLINE_OF "$out")"
  fi
}
check_no_line "no arguments at all prints no machine line" ""
check_no_line "a leading flag prints no machine line" --progress "$PROG7" machine
check_no_line "a mistyped flag prints no machine line" machine --progres "$PROG7"
check_no_line "the =-joined spelling prints no machine line" machine "--progress=$PROG7"
check_no_line "an unknown flag prints no machine line" machine --unknown
check_no_line "a second --progress prints no machine line" \
  machine --progress "$PROG7" --progress "$PROG7"
check_no_line "a --progress with no value prints no machine line" machine --progress
check_no_line "an UNRESOLVED target prints no machine line" no-such-agent

# Ambiguity: two agents answering to one name. The operator gets a candidate list
# and no evidence tier, so there is nothing to record.
make_agent "$H7" "$S7" "77777777-7777-7777-7777-777777777777" \
  "atwin-1111111111111111" "twin" "working" >/dev/null
make_agent "$H7" "$S7" "77777777-7777-7777-7777-777777777777" \
  "atwin-2222222222222222" "twin" "working" >/dev/null
check_no_line "an AMBIGUOUS target prints no machine line" twin

# The line is pipe-delimited and read by key, so no operator-supplied value may
# carry a `|` into it and forge a field.
make_agent "$H7" "$S7" "77777777-7777-7777-7777-777777777777" \
  "apipe-3333333333333333" "apipe-3333333333333333" "working" >/dev/null
OUT7D=$(run_check "$H7" "$R7" "apipe-3333333333333333" 'rep|ort.md')
M7D=$(MLINE_OF "$OUT7D")
expect_absent "a deliverable path carrying a pipe does not forge a field" \
  "rep|ort" "$M7D"
expect_equal "the forged-field attempt still yields one line" "1" \
  "$(printf '%s\n' "$OUT7D" | grep -c '^stop-check-observation/')"

# ============================================================
echo ""
echo "=== Section 8: roster classification, contract-from-roster, P2 claims (slice 4/5, AC-6) ==="
# ============================================================
#
# The roster's SCHEMA is hooks/dispatch-preflight.sh's (roster-state/v1); its
# ROWS here are hand-built rather than produced by that gate, exactly like
# tests/cross-gate-agreement.test.sh's verdict_er() — this suite's job is the
# READER, and tests/dispatch-preflight.test.sh already owns the writer.

IFS='|' read -r H8 R8 S8 <<< "$(make_world w8)"
OWN8="88888888-0000-0000-0000-000000000001"
FOREIGN8="88888888-0000-0000-0000-000000000002"
DEAD8="88888888-0000-0000-0000-000000000003"
mkdir -p "$R8/.bionic/tmp"

# --- (a) OURS: a roster row names the target; contract state is SOURCED from it ---
make_agent "$H8" "$S8" "$OWN8" "aours-1111111111111111" "ours-target" "working away" >/dev/null
echo "the deliverable body" > "$R8/deliv-a.md"
echo "progress line" > "$R8/prog-a.progress"
{
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
  printf 'roster-state/v1|status=confirmed|session=%s|name=ours-target|agent_id=aours-1111111111111111|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=%s|duration=~10 minutes|progress=%s|claims=|absent=|tool_use_id=toolu_A\n' \
    "$OWN8" "$R8/deliv-a.md" "$R8/prog-a.progress"
} > "$R8/.bionic/tmp/roster-${OWN8}.state"

OUT8A=$(run_check_as "$OWN8" "$H8" "$R8" "ours-target")
M8A=$(printf '%s\n' "$OUT8A" | grep '^stop-check-observation/')
expect_contains "OURS: machine line carries classification=ours" "classification=ours" "$M8A"
expect_contains "OURS: machine line carries deliverable_source=roster" "deliverable_source=roster" "$M8A"
expect_contains "OURS: machine line carries progress_source=roster" "progress_source=roster" "$M8A"

# --- (b) OURS, but the CLI overrides: the override wins, the mismatch is printed, not judged ---
echo "another deliverable" > "$R8/deliv-b.md"
echo "another progress" > "$R8/prog-b.progress"
OUT8B=$(run_check_as "$OWN8" "$H8" "$R8" "ours-target" "$R8/deliv-b.md" --progress "$R8/prog-b.progress")
M8B=$(printf '%s\n' "$OUT8B" | grep '^stop-check-observation/')
expect_contains "OURS+override: machine line carries deliverable_source=args" "deliverable_source=args" "$M8B"
expect_contains "OURS+override: machine line carries progress_source=args" "progress_source=args" "$M8B"

# --- (c) FOREIGN: metadata filed under another session, whose transcript is on disk.
# Labelled `foreign-live` until slice 4/9, which is a liveness the existence check
# never established — see Section 9 (d). ---
make_agent "$H8" "$S8" "$FOREIGN8" "aforeign8-2222222222222222" "foreign-target" "hi" >/dev/null
OUT8C=$(run_check_as "$OWN8" "$H8" "$R8" "foreign-target")
M8C=$(printf '%s\n' "$OUT8C" | grep '^stop-check-observation/')
expect_contains "FOREIGN: machine line carries classification=foreign" "|classification=foreign|" "$M8C"

# --- (d) DEAD HISTORY: the bb20f616 shape — metadata answering to a live-looking
# name, from a session whose own transcript is gone. ---
make_agent "$H8" "$S8" "$DEAD8" "adead8-3333333333333333" "dead-target" "old run" >/dev/null
rm -f "$H8/.claude/projects/$S8/$DEAD8.jsonl"
OUT8D=$(run_check_as "$OWN8" "$H8" "$R8" "dead-target")
M8D=$(printf '%s\n' "$OUT8D" | grep '^stop-check-observation/')
expect_contains "DEAD HISTORY: machine line carries classification=dead-history" "classification=dead-history" "$M8D"

# --- (e) UNKNOWN: no own session id at all — classification never guesses ---
OUT8E=$(run_check "$H8" "$R8" "foreign-target")
M8E=$(printf '%s\n' "$OUT8E" | grep '^stop-check-observation/')
expect_contains "UNKNOWN: machine line carries classification=unknown" "classification=unknown" "$M8E"

# --- (f) P2: claimed-process liveness via an explicit --claims pattern, a REAL process ---
MARKER="$H8/claims-marker-w8"
ln -sf "$(command -v sleep)" "$MARKER"
"$MARKER" 30 &
CLAIM_PID=$!
sleep 0.3 2>/dev/null || true
OUT8F=$(run_check_as "$OWN8" "$H8" "$R8" "ours-target" --claims "$MARKER")
expect_contains "P2: a live matching process reports live: yes" "live:     yes" "$OUT8F"
kill "$CLAIM_PID" 2>/dev/null
wait "$CLAIM_PID" 2>/dev/null

OUT8G=$(run_check_as "$OWN8" "$H8" "$R8" "ours-target" --claims "$MARKER")
expect_contains "P2: after the process exits, live: no" "live:     no" "$OUT8G"

# --- (g) P2 + cadence, over a row the REAL WRITER wrote from a REAL brief ---
#
# THIS CASE IS DELIBERATELY NOT HERMETIC-TO-THIS-SCRIPT, and that is the point.
# Until the Step-6 six-axis review, this section hand-wrote a row carrying
# `claims=<pattern>` — a field NO writer could produce, since
# hooks/dispatch-preflight.sh's label table had no `claims` and no `cadence`
# entry. The suite was green about a field that could not exist: a fixture
# pinning away its own test (.claude memory: fixtures-can-pin-away-the-test),
# and the reader it was pinning was dead substrate. So the row below is produced
# by running the real start gate over a real dispatch brief, and the reader is
# then driven over whatever that writer actually wrote. If the label grammar
# regresses, this goes red HERE, where the display lives, rather than staying
# green while the field silently vanishes from every live roster.
#
# The brief's shape is the ratified liveness contract's (SKILL.md §Dispatch):
# a progress path with a cadence beside it, plus a conditional subprocess claim.
make_agent "$H8" "$S8" "$OWN8" "aours-4444444444444444" "ours-claims" "working" >/dev/null
MARKER2="$H8/claims-marker-w8-roster"
ln -sf "$(command -v sleep)" "$MARKER2"
"$MARKER2" 30 &
CLAIM_PID2=$!
sleep 0.3 2>/dev/null || true

# What the start gate needs before it will journal anything: an active wave and
# this session's own attestation. Both are fixtures of the WRITER's
# preconditions, never of the value under test — the row itself is lifted from
# the brief by the real extractor.
mkdir -p "$R8/.bionic/docs/plans/epic-99"
{
  printf -- '---\n'
  printf 'governing-skill: canonical-sdlc\ncanonical_sdlc_version: 14\n'
  printf 'intent: build\nrigor: audited\nscale: wave\n'
  printf -- '---\n\n# Fixture plan\n\n## SDLC State\n\nintegration-branch: main\ncurrent: 4\n'
} > "$R8/.bionic/docs/plans/epic-99/wave-01.md"
printf 'version=v1\nsession_id=%s\n' "$OWN8" > "$R8/.bionic/tmp/preflight-${OWN8}.state"
# …and this session's Patrol stamp, the third writer precondition since epic-17 W5 4/4: the
# start gate refuses a dispatch whose session has no fresh one, and this case needs the gate
# to actually JOURNAL a row. Also a fixture of the writer's preconditions, never of the value
# under test.
printf 'patrol-stamp/v1|at=%s|session=%s|verb=arm\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OWN8" > "$R8/.bionic/tmp/patrol-${OWN8}.state"
chmod 600 "$R8/.bionic/tmp/patrol-${OWN8}.state"
# …and this session's engagement marker, the fourth writer precondition (task-engaged-session):
# the start gate asks `engaged_session` before it asks anything else, and this case needs it
# to actually JOURNAL a row. A fixture of the writer's preconditions, never of the value
# under test.
: > "$R8/.bionic/tmp/engaged-${OWN8}.state"

echo "progress line" > "$R8/prog-g.progress"
BRIEF_G="Canonical-sdlc Step 4, slice 4/12 of epic-99 wave-01; build · audited · wave.
Expected artifact: $R8/deliv-a.md
Expected duration: ~30 minutes. Progress: $R8/prog-g.progress, cadence ~6m.
Subprocess claim: \`$MARKER2\` → $H8/claims-out.log
Exit condition: the artifact exists."
jq -n --arg s "$OWN8" --arg c "$R8" --arg p "$BRIEF_G" \
  '{session_id:$s, transcript_path:"/irrelevant.jsonl", cwd:$c,
    hook_event_name:"PreToolUse", tool_name:"Agent",
    tool_input:{description:"the claimed-process case", subagent_type:"implementor",
                prompt:$p, name:"ours-claims", model:"opus", run_in_background:true},
    tool_use_id:"toolu_01W8G"}' \
  | ( cd "$R8" && HOME="$H8" CLAUDE_CONFIG_DIR="$H8/.claude" \
        CLAUDE_CODE_SESSION_ID="$OWN8" bash "$WRITER" >/dev/null 2>&1 )

W8G_ROW=$(grep -v '^#' "$R8/.bionic/tmp/roster-${OWN8}.state" 2>/dev/null | grep 'name=ours-claims' | tail -1)
expect_contains "the real start gate journalled the dispatch this case reads" \
  "name=ours-claims" "$W8G_ROW"
expect_contains "…and the row it wrote carries the claimed pattern the brief declared" \
  "claims=$MARKER2" "$W8G_ROW"
expect_contains "…and the cadence declared beside the progress path" "cadence=~6m." "$W8G_ROW"

OUT8H=$(run_check_as "$OWN8" "$H8" "$R8" "ours-claims")
expect_contains "P2 roster-sourced: a live matching process reports live: yes" "live:     yes" "$OUT8H"
kill "$CLAIM_PID2" 2>/dev/null
wait "$CLAIM_PID2" 2>/dev/null

# --- (h) --claims grammar mirrors --progress: one path, never zero, never two ---
OUT8J=$(run_check "$H8" "$R8" "ours-target" --claims); ST=$?
expect_status "--claims with no pattern exits 1" 1 "$ST"

OUT8K=$(run_check "$H8" "$R8" "ours-target" --claims "$MARKER" --claims "$MARKER"); ST=$?
expect_status "a second --claims exits 1" 1 "$ST"

# ============================================================
echo ""
echo "=== Section 9: ownership is the OWNING SESSION DIRECTORY (slice 4/9, AC-6) ==="
# ============================================================
#
# Three defects that only live operation could produce, each reproduced here on
# the shape it really took (plan §"Step-5 live findings", record/w3-walk.md §2).
#
# What slice 4/5 keyed ownership on was ROSTER MEMBERSHIP: a row matched by
# `agent_id=`, falling back to `name=`. Both arms failed live and in opposite
# directions.
#
#   D1 (false OURS). Every roster row in a session that has not restarted since
#      the recorder shipped is `status=intended` with an EMPTY `agent_id=`, so the
#      id arm never matches and the NAME arm is the only one live. A name is not
#      an identity — it is reused across waves — so a three-day-dead agent from
#      another session was called OURS off this session's unconfirmed row, and the
#      display then handed it THIS session's contracted progress path.
#
#   D2 (false FOREIGN). An agent this session really did launch, dispatched before
#      the roster hook existed, has no row at all and classified FOREIGN-LIVE with
#      "this session never launched it" — of an agent sitting in this session's own
#      subagents directory. (The observation was run from inside a subagent, which
#      changes nothing: CLAUDE_CODE_SESSION_ID inside a subagent is measured
#      identical to the orchestrator's own id, so the observer's identity was never
#      what this keyed on. WHO looked is recorded by the recorder's `observer=`.)
#
# The key is the metadata's own filing: an agent under <session>/subagents/ was
# launched by <session>. The roster stays the CONTRACT source for a target already
# established as ours, and a `confirmed` row still establishes ownership BY AGENT
# ID — an id is unambiguous by construction. It is never a name-oracle again.
#
#   D3 (false LIVE). `foreign-live` claimed a liveness the check never established:
#      it tests whether the owning session's transcript FILE EXISTS, and transcripts
#      are never deleted — measured, all 57 sessions with subagents under this
#      project read "live", including sessions finished days ago. The label is now
#      `foreign`, and it says what was actually looked at.

IFS='|' read -r H9 R9 S9 <<< "$(make_world w9)"
OWN9="99999999-0000-0000-0000-000000000001"
OTHER9="99999999-0000-0000-0000-000000000002"
GONE9="99999999-0000-0000-0000-000000000003"
mkdir -p "$R9/.bionic/tmp"
echo "our progress" > "$R9/prog-9.progress"

# --- (a) D1, the corpse collision: an UNCONFIRMED row (agent_id empty) and a
# same-NAME agent under ANOTHER session's directory. The row must grant nothing. ---
make_agent "$H9" "$S9" "$OTHER9" "acorpse-1111111111111111" "walker" "three days ago" >/dev/null
{
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
  printf 'roster-state/v1|status=intended|session=%s|name=walker|agent_id=|launched_at=2026-08-05T00:00:00Z|subagent_type=researcher|model=|deliverable=|duration=|progress=%s|absent=deliverable|tool_use_id=toolu_W\n' \
    "$OWN9" "$R9/prog-9.progress"
} > "$R9/.bionic/tmp/roster-${OWN9}.state"

OUT9A=$(run_check_as "$OWN9" "$H9" "$R9" "walker")
M9A=$(printf '%s\n' "$OUT9A" | grep '^stop-check-observation/')
expect_contains "D1: machine line carries classification=foreign" "|classification=foreign|" "$M9A"
expect_contains "D1: the display never hands it THIS session's contracted progress path" \
  "progress_source=none" "$M9A"
expect_absent "D1: …and the progress path itself never reaches the machine line" \
  "prog-9.progress" "$M9A"

# --- (b) D2: an agent under THIS session's own subagents directory, with NO roster
# row at all — the standing state for anything dispatched before the roster shipped. ---
make_agent "$H9" "$S9" "$OWN9" "asibling-2222222222222222" "sibling" "stopped a while back" >/dev/null
OUT9B=$(run_check_as "$OWN9" "$H9" "$R9" "sibling")
M9B=$(printf '%s\n' "$OUT9B" | grep '^stop-check-observation/')
expect_contains "D2: machine line carries classification=ours" "|classification=ours|" "$M9B"

# --- (c) the roster still establishes ownership BY AGENT ID, across directories:
# a CONFIRMED row is a fact this session wrote about its own launch. ---
make_agent "$H9" "$S9" "$OTHER9" "aconfirmed-3333333333333333" "elsewhere" "hi" >/dev/null
printf 'roster-state/v1|status=confirmed|session=%s|name=elsewhere|agent_id=aconfirmed-3333333333333333|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=%s|absent=|tool_use_id=toolu_C\n' \
  "$OWN9" "$R9/prog-9.progress" >> "$R9/.bionic/tmp/roster-${OWN9}.state"
OUT9C=$(run_check_as "$OWN9" "$H9" "$R9" "elsewhere")
M9C=$(printf '%s\n' "$OUT9C" | grep '^stop-check-observation/')
expect_contains "a CONFIRMED row keyed on agent id still establishes OURS" \
  "Classification: OURS" "$OUT9C"
expect_contains "…and its contract is sourced from that row" "progress_source=roster" "$M9C"

# --- (d) D3: the liveness label says what was looked at. Driven on its OWN target,
# foreign under the old rule AND the new one — no roster row of any kind names it,
# and it sits under another session's directory. Asserting this on (a) instead would
# be a fixture pinning away its own test: (a) resolves OURS before the fix, so every
# absence below would pass for the wrong reason. ---
make_agent "$H9" "$S9" "$OTHER9" "astranger-5555555555555555" "stranger" "hi" >/dev/null
OUT9D=$(run_check_as "$OWN9" "$H9" "$R9" "stranger")
M9D=$(printf '%s\n' "$OUT9D" | grep '^stop-check-observation/')
expect_contains "D3: the target is not ours under either rule" "Classification: FOREIGN" "$OUT9D"
expect_absent "D3: the retired token 'foreign-live' is gone from the machine line" \
  "foreign-live" "$M9D"

# --- (e) DEAD HISTORY is unchanged in meaning: the owning session's transcript is
# GONE, so nothing on disk still accounts for the agent. ---
make_agent "$H9" "$S9" "$GONE9" "aghost-4444444444444444" "ghost" "old run" >/dev/null
rm -f "$H9/.claude/projects/$S9/$GONE9.jsonl"
OUT9E=$(run_check_as "$OWN9" "$H9" "$R9" "ghost")
M9E=$(printf '%s\n' "$OUT9E" | grep '^stop-check-observation/')
expect_contains "…and the machine line carries classification=dead-history" \
  "|classification=dead-history|" "$M9E"

# ============================================================
echo ""
echo "=== Section 10: six-axis review remediations (C-1/S-3 glob, C-2 confirmed-by-id) ==="
# ============================================================

IFS='|' read -r H10 R10 S10 <<< "$(make_world w10)"
OWN10="10101010-0000-0000-0000-000000000001"
FOREIGN10="10101010-0000-0000-0000-000000000002"
mkdir -p "$R10/.bionic/tmp"

# --- (a) C-1/S-3: a roster deliverable is never GLOB-EXPANDED against the cwd ---
#
# The roster's `deliverable=` is comma-joined and expanded with IFS=',' — and
# setting IFS suppresses word splitting on other characters, never PATHNAME
# expansion. A brief writing `Deliverables: docs/*.md` stores that literal
# (ispath() accepts it, sanitize() does not strip `*`), and the unquoted
# expansion then let whatever happened to sit in the OBSERVER'S CWD be reported
# PRESENT and ride into the durable record as a confirmed deliverable. Repo
# content deciding what an observation asserts is the §8 direction that matters
# even when no wall opens: the human judgment this command exists to inform is
# the thing being fooled.
make_agent "$H10" "$S10" "$OWN10" "aours-1010101010101010" "glob-target" "working" >/dev/null
mkdir -p "$R10/docs"
echo "decoy a" > "$R10/docs/a.md"
echo "decoy b" > "$R10/docs/b.md"
{
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n'
  printf 'roster-state/v1|status=confirmed|session=%s|name=glob-target|agent_id=aours-1010101010101010|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=docs/*.md|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_G\n' \
    "$OWN10"
} > "$R10/.bionic/tmp/roster-${OWN10}.state"

OUT10A=$(run_check_as "$OWN10" "$H10" "$R10" "glob-target")
M10A=$(printf '%s\n' "$OUT10A" | grep '^stop-check-observation/')
expect_status "C-1: the machine line carries exactly one deliverable state" \
  "1" "$(printf '%s' "$M10A" | tr '|' '\n' | grep '^deliverables=' | tr ',' '\n' | grep -c .)"
expect_absent "C-1: no cwd file rides into the durable record as a deliverable" \
  "docs/a.md" "$M10A"

# --- (b) C-2: OURS-by-roster-id keys on a CONFIRMED row, not merely a non-empty id ---
#
# Both surfaces stated the invariant as "a `confirmed` roster row still
# establishes OURS, by agent id only" and enforced something weaker: any row
# whose `agent_id=` is non-empty. What made that safe was a property of a
# DIFFERENT file — hooks/dispatch-preflight.sh always emits `agent_id=` empty on
# `intended` rows. The stated invariant and the enforced one differing is the
# exact shape slice 4/9 was remediating, so it is enforced here.
make_agent "$H10" "$S10" "$FOREIGN10" "aforeign-1010101010101010" "id-target" "working" >/dev/null
printf 'roster-state/v1|status=intended|session=%s|name=other-name|agent_id=aforeign-1010101010101010|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_I\n' \
  "$OWN10" >> "$R10/.bionic/tmp/roster-${OWN10}.state"
OUT10B=$(run_check_as "$OWN10" "$H10" "$R10" "id-target")
expect_contains "C-2: an INTENDED row's id does not make a foreign agent ours" \
  "Classification: FOREIGN" "$OUT10B"

# …while a CONFIRMED row's id still does, which is the invariant slice 4/9 kept.
printf 'roster-state/v1|status=confirmed|session=%s|name=other-name|agent_id=aforeign-1010101010101010|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_I\n' \
  "$OWN10" >> "$R10/.bionic/tmp/roster-${OWN10}.state"
OUT10C=$(run_check_as "$OWN10" "$H10" "$R10" "id-target")
expect_contains "C-2: a CONFIRMED row's id still establishes OURS" \
  "Classification: OURS" "$OUT10C"

# …and so does an IDENTIFIED row's (epic-16 wave-01 slice 1). `confirmed` alone
# was an accepted set no teammate row could ever satisfy BY ID: the launch half
# learns only the addressing form `name@session-xxxx`, so a confirmed row's
# `agent_id=` is written empty in that mode by design (capture probe §3
# conclusion 3). The transcript-form id — the one every observation of that agent
# carries — arrives one state later, on SubagentStart. Refusing it here would
# leave this rule dead for every teammate dispatch while looking alive in the
# suite, because every fixture predating the wave was async-shaped.
make_agent "$H10" "$S10" "$FOREIGN10" "aforeign-2020202020202020" "id-target-2" "working" >/dev/null
printf 'roster-state/v1|status=identified|session=%s|name=started-name|agent_id=aforeign-2020202020202020|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_J\n' \
  "$OWN10" >> "$R10/.bionic/tmp/roster-${OWN10}.state"
OUT10E=$(run_check_as "$OWN10" "$H10" "$R10" "id-target-2")
expect_contains "an IDENTIFIED row's id establishes OURS — the state teammate ids arrive in" \
  "Classification: OURS" "$OUT10E"

# --- (c) C-2 regression guard: the PRE-RESTART world is untouched ---
#
# Every row in a session that has not restarted since the recorder shipped is
# `status=intended` with an EMPTY `agent_id=`, so the by-id clause never fired
# for them either way — their ownership rests on the 4/9 metadata-directory key
# and their CONTRACT still comes from the row by name. Tightening the by-id
# clause must not touch either, which is what this case pins.
make_agent "$H10" "$S10" "$OWN10" "aours-9090909090909090" "prerestart" "working" >/dev/null
echo "the deliverable" > "$R10/deliv-pre.md"
printf 'roster-state/v1|status=intended|session=%s|name=prerestart|agent_id=|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=%s|duration=|progress=|claims=|cadence=|absent=|tool_use_id=toolu_P\n' \
  "$OWN10" "$R10/deliv-pre.md" >> "$R10/.bionic/tmp/roster-${OWN10}.state"
OUT10D=$(run_check_as "$OWN10" "$H10" "$R10" "prerestart")
M10D=$(printf '%s\n' "$OUT10D" | grep '^stop-check-observation/')
expect_contains "C-2 regression: an unconfirmed row's own agent is still OURS by its directory" \
  "Classification: OURS" "$OUT10D"
expect_contains "C-2 regression: the contract still comes from the unconfirmed row" \
  "deliverable_source=roster" "$M10D"

# --- (d) OURS BY ADOPTION: a predecessor's agent this session took over ---
#
# WHAT `/clear`+resume LOSES is the conversation, never the agent: it is the same process,
# still working, still filed under the session that launched it. `session-poker.sh adopt`
# reads that row back and files an `identified` row carrying `adopted_from=` on THIS
# session's roster — the successor saying, on disk, that the contract is now its own.
#
# The by-id clause above already answers OURS for such a row, and that is the behaviour
# this pins first. What it must NOT do is answer it MUTELY: an adopted agent is ours by a
# different route than "we launched it", and an operator reading OURS about an agent
# sitting in another session's directory needs the reason on the same line — the provenance
# is what tells them which session's transcript the observe address will name.
ADOPTED10="10101010-0000-0000-0000-000000000003"
make_agent "$H10" "$S10" "$ADOPTED10" "aadoptee-3030303030303030" "adoptee" "still working" >/dev/null
printf 'roster-state/v1|status=identified|session=%s|name=adoptee|agent_id=aadoptee-3030303030303030|launched_at=2026-08-05T00:00:00Z|subagent_type=implementor|model=opus|deliverable=|source=adopted|duration=|progress=|claims=|cadence=|absent=|waiver=|tool_use_id=|teammate_id=adoptee@session-%s|adopted_from=%s\n' \
  "$OWN10" "${ADOPTED10:0:8}" "$ADOPTED10" >> "$R10/.bionic/tmp/roster-${OWN10}.state"

OUT10F=$(run_check_as "$OWN10" "$H10" "$R10" "adoptee@session-${ADOPTED10:0:8}")
M10F=$(printf '%s\n' "$OUT10F" | grep '^stop-check-observation/')
expect_contains "an ADOPTED row makes a predecessor's agent OURS" \
  "Classification: OURS" "$OUT10F"
expect_contains "…and the reason names the adoption, not a launch we never made" \
  "adopted_from=$ADOPTED10" "$OUT10F"
expect_contains "…while the machine line still reports it classification=ours" \
  "|classification=ours|" "$M10F"

# ONE SPELLING, AND IT IS THE LAUNCHING SESSION'S (T3 FINDING 1, live 2026-09-03). Both
# spellings were driven here for as long as `session-poker.sh adopt` printed both and
# neither was proven; the probe then picked the ADOPTING session's, reasoning that a
# `/clear` re-keys the session id. The live harness refused that string and named the
# launching session's in its place (`Running teammates: PROBE-AGENT@session-<launching 8>`),
# so adopt prints and records that one (tests/session-poker.test.sh §8a) and the fixture
# above carries it. This command's answer never depended on the suffix: it resolves on the
# base name and establishes ownership from the id, which is what the row above already pins.

# THE PAIRED NEGATIVE, without which the two assertions above pass over a fixture that
# would say OURS for any reason at all: the same by-id ownership with NO adoption on the
# row reports OURS and says nothing about a provenance it does not have.
expect_absent "a row that was never adopted claims no adoption" \
  "adopted_from=" "$(run_check_as "$OWN10" "$H10" "$R10" "id-target-2")"

# ============================================================
echo ""
echo "=== Section 11: one logical agent is not an ambiguity (epic-16 w2 S3, field 2026-08-11) ==="
# ============================================================
#
# The scan walks every session directory of the project, and one agent's metadata can be
# filed under more than one — the launching session's record and the agent's own runtime
# session are two rows about the SAME agent. Refusing that as an ambiguity sent the
# operator round a loop over a target that was never ambiguous. Two matches carrying one
# agent id are one match; only distinct ids are candidates.

IFS='|' read -r H11 R11 S11 <<< "$(make_world w11)"
LAUNCHER11="aaaaaaaa-1111-1111-1111-111111111111"
OWNRUN11="bbbbbbbb-2222-2222-2222-222222222222"
make_agent "$H11" "$S11" "$LAUNCHER11" "atwinned-1111111111111111" "twinned" "older copy" >/dev/null
make_agent "$H11" "$S11" "$OWNRUN11"  "atwinned-1111111111111111" "twinned" "the live copy" >/dev/null
# The launch record is the older of the two — stamped so, because a fixture whose two
# copies share a timestamp would leave "the freshest wins" untested while looking green.
touch -t 202608010000 \
  "$H11/.claude/projects/$S11/$LAUNCHER11/subagents/agent-atwinned-1111111111111111.jsonl"

OUT11=$(run_check "$H11" "$R11" "twinned"); ST11=$?
expect_status "one agent filed under two sessions RESOLVES, it does not refuse" 0 "$ST11"
expect_contains "…it is the same id either way" "atwinned-1111111111111111" "$OUT11"
# The surviving copy is the freshest log — the stale copy is a record of the same agent,
# and printing its evidence would be printing older facts about the very same target.
expect_contains "…and the evidence printed is the LIVE copy's" "the live copy" "$OUT11"

# THE PAIRED NEGATIVE: two DISTINCT ids under one name is a real ambiguity and still
# refuses. Nothing here widens what resolves; it narrows what counts as two agents.
make_agent "$H11" "$S11" "$LAUNCHER11" "areal-2222222222222222" "genuine" "one" >/dev/null
make_agent "$H11" "$S11" "$OWNRUN11"  "areal-3333333333333333" "genuine" "two" >/dev/null
OUT11B=$(run_check "$H11" "$R11" "genuine"); ST11B=$?
expect_status "two DIFFERENT agents under one name still refuse" 1 "$ST11B"
# And the candidate list now names an address the stopper can actually use.
expect_contains "…listing an address the stop primitive accepts" \
  "genuine@session-aaaaaaaa" "$OUT11B"
expect_contains "…for every candidate" "genuine@session-bbbbbbbb" "$OUT11B"

# ============================================================
echo ""
echo "──────────────────────────────────────────────"
echo "stop-check.sh: ${PASS}/${TOTAL} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
