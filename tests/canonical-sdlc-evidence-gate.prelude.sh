# tests/canonical-sdlc-evidence-gate.prelude.sh — the shared half of the two
# evidence-gate shards (wave-30 T3, D8b). NOT A SUITE: the name does not end in
# `.test.sh`, so the roster glob never launches it.
#
# tests/canonical-sdlc-evidence-gate.test.sh (Sections 1-28) and
# tests/canonical-sdlc-evidence-gate-2.test.sh (Section 29 onward) each source this file.
# It holds what both halves read: the fixture runners and assertion helpers that were this
# suite's header, then the plan strings and plan builders that Section 17 and a few later
# sections of the first half define and the second half reads (hoisted verbatim, moved not
# copied).
#
# IT IS SOURCED BEFORE tests/lib/assert.sh, NOT AFTER. assert.sh derives, at its own load,
# every `expect_*` the suite's FILE calls and refuses a name that is neither defined yet nor
# defined in that file; a helper that lives here would be "called but never defined" if this
# file came second. Nothing below calls `ok`/`no` at load time, only inside function bodies.
#
#
# Strategy: every runner pins HOME to a temp sandbox and pins the hook's
# project to a temp fixture, so no case can reach the developer's real
# ~/.claude/ or any real plan file.
#
# make_home() doubles as the simplest project fixture: the single-argument
# runner (run_hook) posts cwd=$home_dir, so the hook resolves PROJECT_DIR to the
# sandbox HOME and its docs root to $home_dir/.bionic/docs — which is where
# write_plan() puts plans. The sandbox also carries an EMPTY ~/.claude/plans/,
# the directory this gate deliberately does NOT search (2026-07-28); the cases
# that plant something there use write_global_note().

# ---------- helpers ----------

cleanup_dirs=()
cleanup() {
  for d in "${cleanup_dirs[@]}"; do
    # A row below locks a plan folder at mode 000; `rm -rf` cannot descend into it.
    chmod -R u+rwx "$d" 2>/dev/null
    rm -rf "$d"
  done
}
trap cleanup EXIT

# Incident 0001: the audit file lives under $HOME, never in the project tree.
# Every runner in this suite already pins HOME to a make_home sandbox, so the
# relocated writes stay off the developer's real ~/.claude/logs. The sandbox
# HOME is always a SIBLING of the make_project fixtures (both are bare
# mktemp -d), never a parent — Section 21a's "nothing under the project tree"
# assertion depends on that.
# Slug must match hooks/canonical-sdlc-evidence-gate.sh audit_path() byte for byte.
slug_for() { printf '%s-%s' "$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')" \
                            "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }
# $1 = sandbox HOME, $2 = the audit_root the hook resolved (the plan's project).
# THE SLUG IS TAKEN OVER THE CANONICAL PATH (bionic 1.4.0, task ADOPT). The hook
# now resolves its root through lib/root.sh's `project_root`, which answers with
# `pwd -P` — so on a machine where the fixture root sits under a symlinked prefix
# (macOS: /var/folders -> /private/var/folders, which mktemp -d hands back
# unresolved) the hook's cksum and this helper's cksum are taken over two spellings
# of one directory, and every audit-file assertion looks for a file that was
# written one slug over.
audit_file_for() {
  local proj; proj=$(cd "$2" 2>/dev/null && pwd -P) || proj="$2"
  printf '%s/.claude/logs/%s/sdlc-audit.md' "$1" "$(slug_for "$proj")"
}

# Creates an isolated $HOME-equivalent that is ALSO usable as the project the
# single-argument runners gate against: an empty ~/.claude/plans/ (never
# searched — see write_global_note) plus an empty .bionic/docs/plans/ (searched).
#
# Also seeds the one shared proof file (1a, D5) that every fixture matrix's
# `evidence: record/generic-evidence.md` line resolves to — write_generic_evidence()
# below is the single writer, so a fixture needing a DIFFERENT evidence path
# (or none at all) still gets this default for free and only overrides it when
# the case is actually about the evidence arm itself (Section 39).
make_home() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.claude/plans" "$dir/.bionic/docs/plans"
  write_generic_evidence "$dir"
  engage "$dir"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# The default proof file every 'evidence: record/generic-evidence.md' fixture
# line resolves to (1a, D5) — non-empty, so it also clears the file-existence
# check, never the file-content check (this gate demands no content shape).
write_generic_evidence() {
  local dir="$1"
  mkdir -p "$dir/.bionic/docs/record"
  printf 'generic fixture proof — this suite tests the gate, not the artifact.\n' \
    > "$dir/.bionic/docs/record/generic-evidence.md"
}

# THE FIXTURE HEAD (wave-26 T4, D5; AC-3.2). Step-5 evidence names the head its run read,
# and the gate refuses a `head:` that is not a commit, or that the release head does not
# contain — so every green Step-5 block below carries `head: ${EG_HEAD}`, and the directory
# its commit is driven from must be a repository holding that commit. `eg_head_repo` makes
# one: an empty commit with a fixed author, committer, date and message, so every fixture
# repository has the SAME head and one constant serves every block. `write_plan` and
# `write_project_plan` plant it for any plan that carries the line; a fixture whose plan
# does not is left a plain directory, exactly as before this wave.
eg_head_repo() {  # <dir> — makes <dir> a repository whose HEAD is $EG_HEAD (idempotent)
  [ -e "$1/.git" ] && return 0
  git -C "$1" init -q 2>/dev/null || return 1
  GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' \
    git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null \
      commit -q --allow-empty -m 'fixture head' 2>/dev/null
}
EG_HEAD="$(_d=$(mktemp -d); eg_head_repo "$_d"; git -C "$_d" rev-parse HEAD 2>/dev/null; rm -rf "$_d")"
eg_head_plant() {  # <dir> <plan content> — a plan naming the fixture head gets its repository
  case "$2" in *"head: ${EG_HEAD}"*) eg_head_repo "$1" ;; esac
  return 0
}

# THE READINGS A RUN AT STEP 6 OR LATER OWES (wave-27 T14; D3, D19). From `current: 6` the gate
# admits a commit only when the section holds, for each reading question the dealing owes, a
# `proved: kind=review … question=<q>` line whose newest is not `result=fail`, or a later waiver.
# Every fixture in this suite at Step 6..9 is about something else, so the two plan writers below
# hand it what a run there has: one passing reading of each question, in the product writer's
# shape (lib/proof.sh `proof_line`), placed after `current:`. A plan that already carries a
# `proved:` or `waived:` line, or one below Step 6, is written as given; EG_NO_READINGS=1 writes
# every plan as given, for the rows about the readings themselves (25gT, and bash-walls §EG-6).
eg_readings() {  # <plan content> -> the content, with the readings a Step-6+ run owes
  if [ -n "${EG_NO_READINGS:-}" ] || printf '%s\n' "$1" | grep -qE '^(proved|waived):'; then
    printf '%s' "$1"; return 0
  fi
  printf '%s' "$1" | EG_H="$EG_HEAD" awk '
    { print }
    !done && /^[[:space:]]*current[[:space:]]*:[[:space:]]*[6-9][ab]?[[:space:]]*$/ {
      for (i = 1; i <= 3; i++) {
        q = (i == 1 ? "evidence" : (i == 2 ? "adversarial" : "structure"))
        printf "proved: kind=review head=%s at=2026-10-04T12:00:00Z evidence=record/w27/%s.md question=%s reader=w-read result=pass scope=piece\n", ENVIRON["EG_H"], q, q
      }
      done = 1
    }'
}

# ---------- engagement (task-engaged-session, AC-6) ----------
#
# Since 2026-09-03 this gate asks one question before it asks anything else: did this
# session invoke the canonical-sdlc skill? (Chris: "all guardrails imposed by bionic
# should only apply when exercising bionic. Nothing should apply until bionic is
# triggered.") hooks/engage.sh answers it by writing `.bionic/tmp/engaged-<sid>.state`
# under the project root at the instant of invocation, and lib/run.sh's `engaged_session`
# is the only reader.
#
# EVERY FIXTURE BELOW IS AN ENGAGED SESSION, because every assertion below is about what
# this gate does to a commit inside a canonical-sdlc run — which is a run somebody
# invoked. The unengaged world is its own section at the bottom of the file, driven on
# the same plans and the same commands, and it is where the marker's absence is proved.
EG_SID="4c3b2a19-8e7d-4f65-9a0b-1c2d3e4f5061"
engage()   { mkdir -p "$1/.bionic/tmp" && : > "$1/.bionic/tmp/engaged-$EG_SID.state"; }
unengage() { rm -f "$1/.bionic/tmp/engaged-$EG_SID.state"; }

# THE ENGAGED SESSION IS BOUND TO THE RUN IT IS IN (wave-23-fixit-1810, REQ-1, D1; spec Δ1).
# `engage` plants an EMPTY marker — engaged and unbound — and since this wave an unbound
# session's newest-plan fallback is announced and never acted on: the gate judges no commit
# for it at all. Every case in this file is a commit inside a run, so the three runners
# below bind this suite's session to the root's newest OPEN run right before each drive —
# the run `fallback` used to hand it — and re-take that answer on every drive, because cases
# rewrite and add plans between drives. A root with no open run gets its empty marker back,
# which is the `none` path, unchanged. A marker a case wrote itself is left alone, and so is
# a root a case unengaged or planted a symlink in. §35 drives the unbound session on purpose,
# under its own session ids and its own runner, which this never touches.
EG_AUTOBOUND=""
eg_autobind() {  # <dir> — a project dir, or a linked worktree of one
  local r m p
  # THE ROOT THE GATE RESOLVES: a linked worktree maps back onto its main repository, where
  # the marker lives (`project_root`, the library's own answer).
  r=$(project_root "$1" 2>/dev/null); [ -n "$r" ] || r="$1"
  set -- "$r"
  m="$1/.bionic/tmp/engaged-$EG_SID.state"
  [ -f "$m" ] && [ ! -L "$m" ] || return 0
  if [ -s "$m" ] && ! printf '%s\n' "$EG_AUTOBOUND" | grep -qxF "$1"; then return 0; fi
  p=$(active_run "$1" 2>/dev/null) || p=""
  if [ -n "$p" ]; then
    bound_marker "$1" "$EG_SID" "$p"
    printf '%s\n' "$EG_AUTOBOUND" | grep -qxF "$1" || EG_AUTOBOUND="${EG_AUTOBOUND}
$1"
  else
    : > "$m"
  fi
}

# Creates an isolated project dir with .bionic/docs/plans/ ready to receive
# plan files. Returned path plays the CLAUDE_PROJECT_DIR role.
make_project() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans"
  write_generic_evidence "$dir"
  engage "$dir"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# Writes $2 as a plan file inside $1/.bionic/docs/plans/ (project-local dir).
write_project_plan() {
  local project_dir="$1" content="$2" name="${3:-active.md}"
  local path="$project_dir/.bionic/docs/plans/$name"
  eg_head_plant "$project_dir" "$content"
  printf '%s\n' "$(eg_readings "$content")" > "$path"
  touch "$path"
  echo "$path"
}

# Writes $2 as the content of a plan file in the sandbox HOME's OWN docs root
# ($1/.bionic/docs/plans/) — the plan directory the single-argument runners
# (run_hook, which posts cwd=$home_dir) make the hook search.
# Touches mtime to "now" so it becomes the newest.
write_plan() {
  local home_dir="$1" content="$2" name="${3:-active.md}"
  local path="$home_dir/.bionic/docs/plans/$name"
  eg_head_plant "$home_dir" "$content"
  printf '%s\n' "$(eg_readings "$content")" > "$path"
  # Ensure mtime > any prior plan in this test by nudging forward.
  touch "$path"
  echo "$path"
}

# Writes $2 into the sandbox's ~/.claude/plans/ — the harness's own,
# project-AGNOSTIC plan directory, which this gate has NOT searched since
# 2026-07-28. Whatever lands here must be invisible to the hook; the fixtures
# using it assert exactly that. Newest mtime by construction, so a case that
# calls it last is planting the newest .md on the machine.
write_global_note() {
  local home_dir="$1" content="$2" name="${3:-note.md}"
  local path="$home_dir/.claude/plans/$name"
  printf '%s\n' "$content" > "$path"
  touch "$path"
  echo "$path"
}

# Runs hook with HOME set to $1 and the given bash-tool-call command $2.
# Sets globals HOOK_EXIT and HOOK_STDERR. The hook is stderr-only on block,
# silent on allow — no need to capture stdout.
# THE RESOLUTION ANNOUNCEMENT IS ITS OWN CHANNEL (wave-session-bound-run, AC-3/AC-6).
# The gate now says out loud which run it resolved and how — one line when an unbound
# session fell back to the newest plan, one when a bound session's plan is closed. Those
# lines are a REPORT, not a refusal, and they ride the only channel a hook has, so every
# `expect_allow` in this file (which asserts stderr is empty) would fail on a fixture
# whose marker carries no binding — which is every fixture above, because `engage` plants
# an empty marker.
#
# So the runners split the stream instead of loosening the assertion: HOOK_RESOLUTION
# holds the announcements and HOOK_STDERR holds EVERYTHING ELSE, still asserted empty on
# an allow. Section 35 reads the announcements on a whole stream of its own (`s35_run`),
# so nothing here can hide a line that was never printed: the pairing is a positive
# assertion that the line IS there for an unbound session and a negative that it is NOT
# for a bound one.
# The unbound advisory is lib/run.sh's one sentence, unprefixed since wave-23-fixit-1810 (D1).
EG_RESOLUTION_RE='^(evidence-gate: bound plan closed|run resolved by newest-plan fallback)'
split_stderr() {  # <file> -> HOOK_RESOLUTION + HOOK_STDERR
  local raw
  raw=$(cat "$1")
  HOOK_RESOLUTION=$(printf '%s\n' "$raw" | grep -E "$EG_RESOLUTION_RE" || true)
  HOOK_STDERR=$(printf '%s\n' "$raw" | grep -v -E "$EG_RESOLUTION_RE" || true)
}

# THE VERBOSE STREAM (task 13, ruling D-1). This gate's refusal is now ONE line —
# `bionic: commit refused — <fact> (<fix>)` — and everything this suite reads off a
# refusal (the task id, the rigor values, the matrix row, the evidence key, the walk
# path, the missing fields, the plan path, the Fix prose) is `detail`, which reaches a
# reader only under BIONIC_WALL_VERBOSE=1. `$HOOK_STDERR` is the line; `$HOOK_VSTDERR`
# is the line plus the detail, with the resolution announcements split off the same way.
HOOK_VSTDERR=""
eg_knob() {  # <raw verbose stderr>
  HOOK_VSTDERR=$(printf '%s\n' "$1" | grep -v -E "$EG_RESOLUTION_RE" || true)
}

run_hook() {
  local home_dir="$1" command="$2"
  local input
  # Pin the hook's cwd to the sandbox HOME so PROJECT_DIR resolves via the
  # documented input-cwd path instead of falling through to the runner's real
  # pwd — otherwise the suite's verdicts would depend on whatever plan files
  # live under the ambient working directory (a hermeticity leak).
  # THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does. lib/session.sh
  # takes the env value as primary and the payload as a witness, so a runner that left the
  # real session id in the environment would have the gate looking for an engagement marker
  # no fixture here ever wrote — and every allow below would pass for the wrong reason.
  input=$(jq -n --arg c "$command" --arg cwd "$home_dir" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  local tmp_err
  tmp_err=$(mktemp)
  eg_autobind "$home_dir"
  # Capture exit code without letting errexit kill the test runner, and
  # without the `|| true` trick (which replaces $? with 0).
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  split_stderr "$tmp_err"
  HOOK_VSTDERR=""
  # Gated on the refusal: an ALLOWED commit can write a findings log, and a second
  # drive of one would double every line in it.
  if [ "$HOOK_EXIT" -ne 0 ]; then
    eg_knob "$(HOME="$home_dir" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$EG_SID" \
      BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$input" 2>&1 >/dev/null || true)"
  fi
  rm -f "$tmp_err"
}

# Like run_hook but also sets CLAUDE_PROJECT_DIR so the hook will scan
# project-local plan directories (.bionic/docs/plans/, docs/superpowers/plans/).
run_hook_with_project() {
  local home_dir="$1" project_dir="$2" command="$3"
  local input
  # CLAUDE_PROJECT_DIR (set below) already wins over cwd in the hook's
  # resolution, but pin cwd to the project sandbox anyway so the input is
  # hermetic and never consults the runner's real pwd.
  input=$(jq -n --arg c "$command" --arg cwd "$project_dir" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  local tmp_err
  tmp_err=$(mktemp)
  eg_autobind "$project_dir"
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  split_stderr "$tmp_err"
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    eg_knob "$(HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" CLAUDE_CODE_SESSION_ID="$EG_SID" \
      BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$input" 2>&1 >/dev/null || true)"
  fi
  rm -f "$tmp_err"
}

# THE PAYLOAD CWD AND CLAUDE_PROJECT_DIR PULL APART (wave-14 REQ-2, A-T2.5). Every runner
# above posts the SAME directory as both, which is a fixture choice and not how a dispatched
# writer's Bash call arrives: `bionic_context`'s ladder takes CLAUDE_PROJECT_DIR first
# (lib/context.sh:294-320), so on a real writer the environment names the session's project —
# the MAIN checkout — while the payload's own `.cwd` is the worktree the writer is standing
# in. That is the seam the row-step arm has to read, and a runner that could not express it
# would prove the arm works only on inputs the CLI never sends.
run_hook_cwd() {  # <home> <project_dir> <payload cwd> <command>
  local home_dir="$1" project_dir="$2" payload_cwd="$3" command="$4"
  local input tmp_err
  input=$(jq -n --arg c "$command" --arg cwd "$payload_cwd" --arg s "$EG_SID" \
            '{session_id: $s, tool_input: {command: $c}, cwd: $cwd}')
  tmp_err=$(mktemp)
  eg_autobind "$project_dir"
  if HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" CLAUDE_CODE_SESSION_ID="$EG_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  split_stderr "$tmp_err"
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    eg_knob "$(HOME="$home_dir" CLAUDE_PROJECT_DIR="$project_dir" CLAUDE_CODE_SESSION_ID="$EG_SID" \
      BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$input" 2>&1 >/dev/null || true)"
  fi
  rm -f "$tmp_err"
}

expect_allow() {
  local label="$1" home_dir="$2" command="$3"
  run_hook "$home_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
    ok "$label"
  else
    no "$label" "expected allow, exit 0, no stderr; got exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  fi
}

# THE TWO STREAMS, AND WHICH ONE EACH HALF READS (task 13, ruling D-1). A refusal is
# now ONE line on the user stream, `bionic: commit refused — <fact> (<fix>)`, and every
# value a caller here names — a task id, a rigor cell, a matrix row, an evidence key, a
# walk path, a missing field — is `detail`, which travels only under
# BIONIC_WALL_VERBOSE=1. So the SHAPE is asserted on `$HOOK_STDERR` (and it is asserted
# on every call, which is what makes AC-E1.3 hold for all thirty-one direct sites and
# both frames without an arm per site), while the caller's substring is looked for in
# `$HOOK_VSTDERR`. The default substring is the rendered prefix rather than the retired
# `BLOCKED` tag.
EG_LINE_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
EG_E1_SEEN=0; EG_E1_BAD_SHAPE=""; EG_E1_BAD_LINES=""
eg_e1_check() {  # -> 0 iff the user stream is one rendered refusal in the criterion's shape
  local line
  line=$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ' || true)
  EG_E1_SEEN=$((EG_E1_SEEN + 1))
  if ! printf '%s' "$line" | /usr/bin/grep -qE "$EG_LINE_RE"; then
    EG_E1_BAD_SHAPE="${EG_E1_BAD_SHAPE}[$HOOK_STDERR] "; return 1
  fi
  if [ "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep -c '^bionic: ')" != "1" ]; then
    EG_E1_BAD_LINES="${EG_E1_BAD_LINES}[$HOOK_STDERR] "; return 1
  fi
  return 0
}

expect_block() {
  local label="$1" home_dir="$2" command="$3" expected_substr="${4:-}"
  run_hook "$home_dir" "$command"
  if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
     && { [ -z "$expected_substr" ] || grep -q "$expected_substr" <<<"$HOOK_VSTDERR"; }; then
    ok "$label"
  else
    no "$label" "expected block exit 2, one rendered line, with substring '$expected_substr'; got exit=$HOOK_EXIT line='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
  fi
}

# Project-fixture twins of expect_allow/expect_block (run_hook_with_project instead of
# run_hook) — for cases whose subject needs a real file at a project-relative path
# (K5's 'requirements:' pointer among them), which a bare HOME sandbox cannot host.
expect_allow_p() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4"
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
    ok "$label"
  else
    no "$label" "expected allow, exit 0, no stderr; got exit=$HOOK_EXIT stderr='$HOOK_STDERR'"
  fi
}

expect_block_p() {
  local label="$1" home_dir="$2" project_dir="$3" command="$4" expected_substr="${5:-}"
  run_hook_with_project "$home_dir" "$project_dir" "$command"
  if [ "$HOOK_EXIT" -eq 2 ] && eg_e1_check \
     && { [ -z "$expected_substr" ] || grep -q "$expected_substr" <<<"$HOOK_VSTDERR"; }; then
    ok "$label"
  else
    no "$label" "expected block exit 2, one rendered line, with substring '$expected_substr'; got exit=$HOOK_EXIT line='$HOOK_STDERR' detail='$HOOK_VSTDERR'"
  fi
}

# Minimal valid frontmatter for fixtures whose subject is NOT the frontmatter.
# scale: wave + rigor: single keeps the wave-lane machinery (dispatch ledger,
# rigor lanes) out of the way so each fixture isolates the behavior under test.
FM='---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: single
scale: wave
deploy_target: none
use_worktree: false
has_ui: false
---'

# ---------- fixtures hoisted from the first half (wave-30 T3) ----------
#
# Defined in Sections 17-26 of the original single file and read by Section 29 onward. They are
# plan strings and plan builders, with no state of their own. Each is defined exactly once, here.

# `walk: exempt` here and in the other fixture builders below is deliberate and
# load-bearing: the walk arm (Section 26) is fail-closed, so an ABSENT key on a
# plan with a discharged row blocks. These fixtures are about matrix mechanics,
# not the walk, so they declare the exemption and keep isolating their own
# subject. The fail-closed default itself is pinned by 26e, which is the only
# fixture in the suite that leaves the key off on purpose.
matrix_frontmatter() {
  local has_ui="${1:-true}" deploy="${2:-none}" use_wt="${3:-false}"
  cat <<EOF
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
intent: build
rigor: double
scale: wave
deploy_target: ${deploy}
use_worktree: ${use_wt}
has_ui: ${has_ui}
walk: exempt
---
EOF
}

# Shared Step-5 block: tests floor + the required auditor pointer.
step5_base="  cmd: bash test.sh
  pass: 332
  total: 332
  head: ${EG_HEAD}
  output: .bionic/docs/plans/wave-01.plan.md#step-5
  auditor: 3 rows CONFIRMED — report .bionic/tmp/audit.md"

# Assemble a full plan: frontmatter + ## SDLC State (current + Step
# block) + a ## Verification Matrix section. $1 current, $2 Step-block
# body (indented lines), $3 full matrix section text.
plan() {
  printf '%s\n## SDLC State\ncurrent: %s\napproved-by: fixture 2026-09-07T00:00Z "approved"\nStep %s:\n%s\n\n%s\n' \
    "$(matrix_frontmatter true)" "$1" "$1" "$2" "$3"
}

# A pointer body for post-Verify steps (6..9): non-empty, non-placeholder.
step6_body="  review: .bionic/docs/plans/wave-01.plan.md#step-6-review"

# Complete, valid matrix: T3 (all five fields), T1 (tier-run+readback),
# waived T3 row. stack-health present. All auditor cells CONFIRMED/waived.
matrix_complete="## Verification Matrix

stack-health: process restarts 0 → 0 across walk; no crash/OOM state change

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T1 | discharged | see AC-2 | CONFIRMED |
| AC-3 | T3 | waived | waiver: dana 2026-07-16 env stale | waived |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval
AC-2:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: bash test.sh — unit suite
  readback: 332/332 asserted"

# Mixed matrix mid-walk: AC-1 discharged with full T3 evidence, AC-2 still
# pending with no AC block and an empty auditor cell.
v101_matrix_pending="## Verification Matrix

stack-health: before: process restarts 0; walk in progress

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T3 | discharged | see AC-1 | CONFIRMED |
| AC-2 | T3 | pending | see AC-2 |  |

AC-1:
  fails-when: the planted defect this eval must go red on
  evidence: record/generic-evidence.md
  tier-run: https://app.example/panel — opened the panel
  fresh: origin A rebuilt token-9f3a; origin B cdn purged
  cold-client: fresh incognito profile, no SW cache
  contact: clicked open — panel closed → open
  readback: panel.visible === true via page eval"

# Post-Verify step bodies for the 7 / 8 / 9 cases (the shapes their own
# validators demand — 29a and 19's integrate fixtures pin these independently).
v9_step7_body="  n/a: no architectural decision in this wave"

v9_step8_body="  merge: merged wave/bionic-1.3.2 into main
  worktree-removed: n/a
  cleanup: n/a"

v9_step9_body="  delivered: close-out report and continuation.md written"

# Asserts the durable audit file exists under the sandbox HOME and carries a
# line matching $4 — pins the D14 file channel (not just the stderr echo).
expect_audit_line() {
  local label="$1" home_dir="$2" command="$3" substr="$4"
  run_hook "$home_dir" "$command"
  # run_hook posts cwd=$home_dir with CLAUDE_PROJECT_DIR="", and the plan lives
  # in that sandbox's own docs root, which is no git repository — so
  # audit_root() falls back to PROJECT_DIR == $home_dir. Incident 0001 keys the
  # file on that root but roots the file itself under HOME.
  local af; af=$(audit_file_for "$home_dir" "$home_dir")
  if [ "$HOOK_EXIT" -eq 0 ] && [ -f "$af" ] && grep -q "$substr" "$af"; then
    ok "$label"
  else
    no "$label" "expected exit 0 + audit-file line '$substr'; got exit=$HOOK_EXIT audit='$( [ -f "$af" ] && cat "$af" )'"
  fi
}

# Frontmatter carrying the triple. $1 scale, $2 deploy, $3 use_worktree,
# $4 epic (omitted when empty).
frontmatter() {
  local scale="${1:-wave}" deploy="${2:-none}" use_wt="${3:-false}" epic="${4:-}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 14\n'
  printf -- 'intent: build\n'
  printf -- 'rigor: double\n'
  printf -- 'scale: %s\n' "$scale"
  printf -- 'deploy_target: %s\n' "$deploy"
  printf -- 'use_worktree: %s\n' "$use_wt"
  printf -- 'has_ui: false\n'
  printf -- 'walk: exempt\n'  # see matrix_frontmatter — the walk arm is fail-closed
  [ -n "$epic" ] && printf -- 'epic: %s\n' "$epic"
  printf -- '---\n'
}

# A wave plan: frontmatter + ## SDLC State (current + Step
# block) + ## Verification Matrix. Reuses the Section-17 matrix fixtures.
wave_plan() {
  printf '%s\n## SDLC State\ncurrent: %s\napproved-by: fixture 2026-09-07T00:00Z "approved"\nStep %s:\n%s\n\n%s\n' \
    "$(frontmatter wave)" "$1" "$1" "$2" "$3"
}

# THE ONE TABLE, AT EITHER SCALE (wave-31 T24; REQ-1, D2). The task-scale fixtures this file
# carried were the retired shape: a five- or six-column `## Tasks` (`id | intent | rigor |
# description | status [| worktree]`) under `current: T<n>`. The gate reads one table now and a
# `current:` that is a step number, so a task-scale plan is tests/lib/plan-fixture.sh's, the one
# helper the shards share. That helper writes `rigor: single` and `multi_agent: false`; the arms
# keyed on the other values (the dispatch ledger at double + multi_agent) take them through this
# seam, which edits those two frontmatter lines and nothing else (A-T24-7).
. "$(dirname "$0")/lib/plan-fixture.sh"
EG_PF_DIR="$(mktemp -d)"; cleanup_dirs+=("$EG_PF_DIR")
# eg_pf_plan <current> <task|wave> <rigor> <multi_agent> <SDLC-State lines, or ""> [<row>...]
#   -> the plan text. The lines (a `- T<n>:` evidence line, say) land after `approved-by:`.
eg_pf_plan() {
  local cur="$1" sc="$2" rg="$3" ma="$4" extra="$5" p; shift 5
  p="$(plan_fixture --current "$cur" "$EG_PF_DIR/plans/epic-99-fixture/$sc-01-fixture.plan.md" "$sc" "$@")" || return 1
  sed -e "s/^rigor: single$/rigor: $rg/" -e "s/^multi_agent: false$/multi_agent: $ma/" "$p" \
    | EG_PF_X="$extra" awk '{ print } /^approved-by: / && ENVIRON["EG_PF_X"] != "" { print ENVIRON["EG_PF_X"] }'
}
# One row of the one table, in PLAN_FIXTURE_HEADER's order: <id> <agent> <status> [<worktree>].
eg_pf_row() {
  printf '| %s | 4 | build | the %s unit | %s | — | — | 30 | REQ-1 | %s.sh | %s | — | %s |' \
    "$1" "$1" "$2" "$1" "${4:-—}" "$3"
}

# A WAVE frontmatter carrying an explicit multi_agent field — the D7
# dispatch-ledger guard fires ONLY on double + multi_agent:true + wave or task.
# frontmatter sets NO multi_agent, so every prior wave fixture (19a/b/c,
# 19r, Section 20) is a guaranteed guard no-op. $1 rigor (default double),
# $2 multi_agent (default true).
d7_wave_frontmatter() {
  local rigor="${1:-double}" multi="${2:-true}"
  printf -- '---\n'
  printf -- 'governing-skill: canonical-sdlc\n'
  printf -- 'canonical_sdlc_version: 14\n'
  printf -- 'intent: build\n'
  printf -- 'rigor: %s\n' "$rigor"
  printf -- 'scale: wave\n'
  printf -- 'deploy_target: none\n'
  printf -- 'use_worktree: false\n'
  printf -- 'has_ui: false\n'
  printf -- 'walk: exempt\n'  # see matrix_frontmatter — the walk arm is fail-closed
  printf -- 'multi_agent: %s\n' "$multi"
  printf -- '---\n'
}

# A wave plan at current: 5 reaching the dispatcher with the SAME valid
# Step-5 body + matrix as 19b (so the ONLY variable under test is the
# dispatched-task ledger; validate_dispatch_ledger runs at the top of
# dispatch_modern, before the matrix machinery). $1 = ## Tasks section text
# (empty omits it); $2 = extra ## SDLC State lines, e.g. a `- T<n>:` evidence
# line (empty omits); $3 rigor (default double); $4 multi_agent (default true).
d7_wave_plan() {
  local tasks="$1" extra_state="$2" rigor="${3:-double}" multi="${4:-true}"
  printf '%s\n' "$(d7_wave_frontmatter "$rigor" "$multi")"
  [ -n "$tasks" ] && printf '%s\n\n' "$tasks"
  # Both K5 (this task) and K2 (task 16) scope-match this fixture (rigor:double +
  # multi_agent:true + wave, at current: 5 >= 4): K5/AC-K5.2 needs the Step-1
  # requirements: pointer (resolves to the plan file itself — project-relative; this
  # fixture's own subject is D7, not K5, so a real file is all the arm demands, not a
  # real requirements document); K2/AC-K2.4 needs approved-by: at current >= 4.
  printf '## SDLC State\ncurrent: 5\nStep 1: requirements: .bionic/docs/plans/active.md\napproved-by: fixture 2026-09-07T00:00Z approved\nStep 5:\n%s\n' "$step5_base"
  [ -n "$extra_state" ] && printf '%s\n' "$extra_state"
  printf '\n%s\n' "$matrix_complete"
}

tasks_one_done="## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh | landed |"

s24_marked_plan() {  # a plan carrying the run-state marker + a satisfied state
  printf -- '---\ngoverning-skill: superpowers:writing-plans\n'
  printf -- 'canonical_sdlc_version: 14\nintent: build\nrigor: single\nscale: wave\n---\n'
  printf -- '## SDLC State\ncurrent: 3\nStep 3: .bionic/docs/plans/wave-01.plan.md\n'
}

# Every row still pending: nothing has discharged, so the arm must not fire —
# a mid-discharge commit before the walk is written stays legal. No auditor
# pointer either (the Step-5 relaxation), which is the honest shape here.
walk_matrix_all_pending="## Verification Matrix

stack-health: before: process restarts 0; walk not yet run

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | pending | see AC-1 |  |
| AC-2 | T1 | pending | see AC-2 |  |"

