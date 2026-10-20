#!/bin/bash
# Tests for canonical-sdlc-governing-skill.sh
#
# Strategy: build synthetic Write/Edit tool_input payloads that target
# files in a temp project dir. No HOME override needed — the hook only
# inspects the posted JSON and, for Edit, reads the file at the given
# path.
#
# Usage: bash tests/canonical-sdlc-governing-skill.test.sh

set -euo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/plan-fixture.sh"
. "$(dirname "$0")/lib/assert.sh"
# The column counter for the AC-E1.3 sweep: the em dash is three bytes and one column,
# so a byte count would pass a line that wraps.
. "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/width.sh"
# THE ONE BOUND-MARKER BUILDER (AC-24). Two hand-written markers in this file survived that
# consolidation — they happened to match `bind_plan`'s output byte for byte, which is exactly
# the agreement a shared builder makes true by construction instead of by luck (Step-6
# duplication review D-6).
. "$(dirname "$0")/lib/bound-marker.sh"

HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"

cleanup_dirs=()
cleanup() {
  for d in "${cleanup_dirs[@]}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

# Incident 0001: the audit file lives under $HOME, never in the project tree.
# The fake HOME is a SIBLING of every sandbox project, never a child — the
# "nothing under the project tree" assertion uses `find "$project"`, which a
# nested home would satisfy falsely. Every invocation of the hook runs with
# HOME pointed here, or the suite would append to the developer's real
# ~/.claude/logs. Projects are distinct mktemp paths, so each gets its own slug
# directory under the one fake home — no cross-case contamination.
FAKE_HOME=$(mktemp -d)
cleanup_dirs+=("$FAKE_HOME")
# Slug must match hooks/canonical-sdlc-governing-skill.sh audit_path() byte for byte.
slug_for() { printf '%s-%s' "$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')" \
                            "$(printf '%s' "$1" | cksum | cut -d' ' -f1)"; }

# A fixture project is a REAL git repository at a PHYSICAL path (AC-10).
#
# git init: the hook computes the project root from `git rev-parse
# --git-common-dir`, so a bare temp directory would resolve to whatever repo
# the runner's cwd sits in, not to the fixture. Real projects using this
# lifecycle are git repos; the fixture now matches.
#
# pwd -P: mktemp -d hands back /var/... on macOS, a symlink to /private/var/...,
# and git answers with the PHYSICAL path. Comparing the hook's resolved
# DOCS_ROOT against a logical fixture path would mismatch on the symlink alone.
make_project() {
  local dir
  dir=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$dir/.bionic/docs/plans/epic-01-demo"
  mkdir -p "$dir/.bionic/docs/specs/epic-01-demo"
  mkdir -p "$dir/.bionic/docs/adrs/epic-01-demo"
  git -C "$dir" init -q .
  engage "$dir"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# ---------- engagement (task-engaged-session, AC-7) ----------
#
# Since 2026-09-03 this hook asks one question before the four-clause project
# disjunction below it: did this session invoke the canonical-sdlc skill? (Chris: "all
# guardrails imposed by bionic should only apply when exercising bionic. Nothing should
# apply until bionic is triggered.") hooks/engage.sh answers it by writing
# `.bionic/tmp/engaged-<sid>.state` under the project root — and, in a project that has
# no `.bionic/` yet, by creating the directory to hold it.
#
# EVERY FIXTURE IN THIS FILE IS AN ENGAGED SESSION, because every assertion in it is
# about what this wall does to an artifact written during a canonical-sdlc run. The
# unengaged world is the section at the bottom, which drives every clause of the
# disjunction with the marker removed.
#
# THE MARKER GOES UNDER THE ARTIFACT'S ROOT, never the runner's cwd: this hook resolves
# `PROJECT_ROOT_FROM_PATH` from the target path and reads the marker there, so a fixture
# whose artifact lives in another tree engages THAT tree.
GS_SID="5e4d3c2b-1a09-4876-9b5c-4d3e2f1a0b9c"
engage()   { mkdir -p "$1/.bionic/tmp" && : > "$1/.bionic/tmp/engaged-$GS_SID.state"; }
unengage() { rm -f "$1/.bionic/tmp/engaged-$GS_SID.state"; }

# Runs hook with a synthetic Write payload for $FILE with $CONTENT.
HOOK_VSTDERR=""

# AC-E1.3, SWEPT AT THE DRIVER (task 13). Every refusal this wall makes is checked for
# the criterion's shape as it happens, so no migrated site can be left without an eval
# and no arm has to be written twice. The counters are read in the section at the end.
GS_E1_SEEN=0; GS_E1_BAD_SHAPE=""; GS_E1_BAD_LINES=""; GS_E1_BAD_COLS=""
GS_E1_RE='^bionic: [a-z-]+ refused — .+ \(.{1,40}\)$'
gs_e1_sweep() {
  [ "$HOOK_EXIT" = "2" ] || return 0
  # THE RENDERED REFUSAL, not the whole stream: this hook also prints its own
  # run-resolution diagnostic before it decides, and that line is not a refusal.
  local _l
  _l=$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ' || true)
  [ -n "$_l" ] || return 0
  GS_E1_SEEN=$((GS_E1_SEEN + 1))
  printf '%s' "$_l" | /usr/bin/grep -qE "$GS_E1_RE" \
    || GS_E1_BAD_SHAPE="${GS_E1_BAD_SHAPE}[$_l] "
  [ "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep -c '^bionic: ')" = "1" ] \
    || GS_E1_BAD_LINES="${GS_E1_BAD_LINES}[$HOOK_STDERR] "
  [ "$(bionic_cols "$_l")" -le 100 ] \
    || GS_E1_BAD_COLS="${GS_E1_BAD_COLS}[$_l] "
}

run_write() {
  local file_path="$1" content="$2"
  local input
  # THE ENVIRONMENT AGREES WITH THE PAYLOAD, because on the machine it does: lib/session.sh
  # takes the env value as primary and the payload as a witness, so a runner leaving the
  # real session id in the environment would send this hook looking for a marker no
  # fixture here ever wrote.
  input=$(jq -n \
    --arg p "$file_path" \
    --arg c "$content" \
    --arg s "$GS_SID" \
    '{session_id: $s, tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  local tmp_err
  tmp_err=$(mktemp)
  if HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  gs_e1_sweep
  # THE SAME WRITE AGAIN, WITH THE KNOB (task 13, ruling D-1). This wall's refusal is
  # now ONE line — `bionic: write refused — <fact> (<fix>)` — and the artifact name, the
  # path and the Fix block this suite reads are `detail`, which reaches a reader only
  # under BIONIC_WALL_VERBOSE=1. `$HOOK_STDERR` is the line; `$HOOK_VSTDERR` is the line
  # plus the detail. The hook writes no state, so a second drive changes nothing.
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    HOOK_VSTDERR=$(HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" BIONIC_WALL_VERBOSE=1 \
      bash "$HOOK" <<< "$input" 2>&1 >/dev/null) || true
  fi
  rm -f "$tmp_err"
}

# run_edit <file> <old_string> <new_string> [replace_all] [interp]
#
# `replace_all` defaults to false and is posted either way, because the hook now APPLIES the
# edit to decide (REQ-8) and the flag is part of what it applies. The CLI posts the same three
# keys verbatim (spec §5 assumption 6).
#
# `interp` defaults to "bash" — PATH resolution, same as every pre-existing call site — and is
# overridable so a fixture can drive the hook under a NAMED interpreter (e.g. `/bin/bash` or
# `/opt/homebrew/bin/bash`), because the substitution the hook applies to derive an Edit's
# post-edit body (REQ-8) is interpreter-version-sensitive: bash 5.2 turned on
# `patsub_replacement`, under which an unquoted replacement treats an unescaped `&` as the
# matched text (review R1, wave-15-fixit-182).
run_edit() {
  local file_path="$1" old_str="$2" new_str="$3" all="${4:-false}" interp="${5:-bash}"
  local input
  input=$(jq -n \
    --arg p "$file_path" \
    --arg o "$old_str" \
    --arg n "$new_str" \
    --argjson r "$all" \
    --arg s "$GS_SID" \
    '{session_id: $s, tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n, replace_all: $r}}')
  local tmp_err
  tmp_err=$(mktemp)
  if HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" "$interp" "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  gs_e1_sweep
  # THE SAME WRITE AGAIN, WITH THE KNOB (task 13, ruling D-1). This wall's refusal is
  # now ONE line — `bionic: write refused — <fact> (<fix>)` — and the artifact name, the
  # path and the Fix block this suite reads are `detail`, which reaches a reader only
  # under BIONIC_WALL_VERBOSE=1. `$HOOK_STDERR` is the line; `$HOOK_VSTDERR` is the line
  # plus the detail. The hook writes no state, so a second drive changes nothing.
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    HOOK_VSTDERR=$(HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" BIONIC_WALL_VERBOSE=1 \
      "$interp" "$HOOK" <<< "$input" 2>&1 >/dev/null) || true
  fi
  rm -f "$tmp_err"
}

# gs_find_bash52 — prints the path to a bash >= 5.2 interpreter (the version that turned on
# `patsub_replacement`, review R1) if one is reachable, and fails silently otherwise. Checked in
# this order because /opt/homebrew/bin/bash is the ONE named in the review's own measurement,
# but a machine without Homebrew may still have a modern bash first on PATH.
gs_find_bash52() {
  local cand resolved ver major minor
  for cand in /opt/homebrew/bin/bash /usr/local/bin/bash bash; do
    resolved=$(command -v "$cand" 2>/dev/null) || continue
    ver=$("$resolved" -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null) || continue
    major="${ver%%.*}"
    minor="${ver#*.}"
    case "$major$minor" in *[!0-9]*) continue ;; esac
    if [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 2 ]; }; then
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

# Same semantics as the framework's expect_eq (label, expected, actual;
# string equality) -- delegated rather than reimplemented so the counting
# and section-floor bookkeeping run through the ONE definition (AC-12, A-16).
assert_eq() { expect_eq "$1" "$2" "$3"; }

# Asserts $3 (haystack, typically $HOOK_STDERR) contains substring $2. Same
# semantics as the framework's expect_contains (literal substring via a
# quoted case glob, same argument order) -- delegated for the same reason.
assert_contains() { expect_contains "$1" "$2" "$3"; }

# Builds a valid canonical-sdlc artifact. All config via KEY=VALUE args
# (bash-3.2 arg parse):
#   intent/rigor/scale — triple values (default build/double/wave);
#     value OMIT drops the line entirely (missing-field cases).
#   step    — sdlc-step (default 3).
#   version — canonical_sdlc_version (default 14); OMIT drops the line.
#   mode    — if set, inject a `mode:` line (split-brain guard case).
#   omit    — space-separated flag names to drop (missing-flag cases).
#   matrix  — yes|no; drop the "## Verification Matrix" section when no.
#   walk    — if set, inject a `walk: <value>` line (default OMIT, no line).
#   override — if set, inject the given full `rigor-override: ...` line
#              verbatim (default OMIT, no line).
#   waived  — if set, inject the given full `design-waived: ...` line verbatim
#             (default OMIT). Only the cases that write this fixture to a
#             *.spec.md path need it: the design wall (wave-02) applies to
#             wave/epic-scale SPEC artifacts, so a spec fixture that is not
#             about design must satisfy that arm to keep testing its own
#             subject. Plan-targeting cases never set it.
build_plan() {
  local intent=build rigor=double scale=wave step=3 version=14 mode="OMIT" omit=" " matrix=yes
  local skill="superpowers:writing-plans"
  local walk="OMIT" override="OMIT" waived="OMIT"
  # goal: yes (default) | no | empty — K5.4. "yes" injects a real '## Goal' paragraph as
  # the body's first section, so every PRE-EXISTING call site (none of which is about
  # K5.4) keeps satisfying the new arm without being touched, the same precedent
  # SPEC_DESIGN_WAIVER set when the design wall (wave-02) landed. "no" omits the section
  # entirely (first-section fails-when); "empty" leaves the heading with no paragraph
  # (empty-section fails-when) — the K5.4 section below is the only caller of either.
  local goal=yes
  local arg
  for arg in "$@"; do
    case "$arg" in
      intent=*)  intent="${arg#intent=}" ;;
      rigor=*)   rigor="${arg#rigor=}" ;;
      scale=*)   scale="${arg#scale=}" ;;
      step=*)    step="${arg#step=}" ;;
      version=*) version="${arg#version=}" ;;
      mode=*)    mode="${arg#mode=}" ;;
      omit=*)    omit=" ${arg#omit=} " ;;
      matrix=*)  matrix="${arg#matrix=}" ;;
      skill=*)   skill="${arg#skill=}" ;;
      walk=*)    walk="${arg#walk=}" ;;
      override=*) override="${arg#override=}" ;;
      waived=*)  waived="${arg#waived=}" ;;
      goal=*)    goal="${arg#goal=}" ;;
    esac
  done

  local out='---
governing-skill: '"$skill"'
sdlc-step: '"$step"'
epic: epic-01-demo
wave: wave-01-x
'
  [ "$version" = OMIT ] || out+="canonical_sdlc_version: $version"$'\n'
  [ "$mode" = OMIT ]    || out+="mode: $mode"$'\n'
  [ "$intent" = OMIT ]  || out+="intent: $intent"$'\n'
  [ "$rigor" = OMIT ]   || out+="rigor: $rigor"$'\n'
  [ "$scale" = OMIT ]   || out+="scale: $scale"$'\n'
  [ "$walk" = OMIT ]    || out+="walk: $walk"$'\n'
  [ "$override" = OMIT ] || out+="$override"$'\n'
  [ "$waived" = OMIT ]   || out+="$waived"$'\n'

  local flags=("cleanup_on_finish:true" "use_worktree:false" \
    "surface_type:none" "language:none" "has_ui:false" \
    "multi_agent:false" "deploy_target:none" \
    "model_plan:orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh" \
    "parallel-budget:writers=8 suites=4 worktrees=32 test_jobs=8 source=probe")
  local kv key val
  for kv in "${flags[@]}"; do
    key="${kv%%:*}"; val="${kv#*:}"
    case "$omit" in *" $key "*) continue ;; esac
    out+="${key}: ${val}"$'\n'
  done
  out+='---
'
  case "$goal" in
    yes)   out+='
## Goal

A concise paragraph describing this fixture'"'"'s goal.
' ;;
    empty) out+='
## Goal
' ;;
    no)    : ;;
  esac
  if [ "$matrix" = yes ]; then
    out+='
## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
'
  else
    out+='
# Plan body without a matrix section
'
  fi
  printf '%s' "$out"
}

VALID_FRONTMATTER="$(build_plan)"

# A wave-scale spec must satisfy the design wall (wave-02 AC-2). Cases below
# that write a plan fixture to a *.spec.md path are not about design, so they
# carry the waiver token and keep testing their own subject.
SPEC_DESIGN_WAIVER='design-waived: test-fixture 2026-08-02 covered by the design-wall cases'
VALID_SPEC_FRONTMATTER="$(build_plan waived="$SPEC_DESIGN_WAIVER")"

MISSING_FM='# Plan body, no frontmatter
'

EMPTY_GOVERNING='---
governing-skill:
sdlc-step: 3
---
body
'

# ---------- cases ----------

project=$(make_project)

echo "Write: plan file with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"

echo "Write: plan file missing frontmatter → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$MISSING_FM"

echo "Write: plan file with empty governing-skill → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$EMPTY_GOVERNING"

echo "Write: spec file with valid frontmatter → allow"
run_write "$project/.bionic/docs/specs/epic-01-demo/wave-01-x.spec.md" "$VALID_SPEC_FRONTMATTER"

echo "Write: adr file with valid frontmatter → allow"
run_write "$project/.bionic/docs/adrs/epic-01-demo/adr-001-x.md" "$VALID_FRONTMATTER"

echo "Write: continuation.md with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation.md" "$VALID_FRONTMATTER"

echo "Write: continuation-checkpoint.md with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation-checkpoint.md" "$VALID_FRONTMATTER"

echo "Write: README.md under plans dir, no frontmatter → allow (not an enforced artifact)"
run_write "$project/.bionic/docs/plans/epic-01-demo/README.md" "# some notes"

echo "Write: .plan.md OUTSIDE any .bionic/-rooted project → allow (hook scope is path-gated)"
outside=$(mktemp -d)
cleanup_dirs+=("$outside")
run_write "$outside/random.plan.md" "$MISSING_FM"

echo "Write: adr-named file under adrs/ missing frontmatter → block"
run_write "$project/.bionic/docs/adrs/epic-01-demo/adr-007-x.md" "$MISSING_FM"

echo "Edit: existing file with valid frontmatter → allow"
existing="$project/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md"
printf '%s' "$VALID_FRONTMATTER" > "$existing"
run_edit "$existing" "Plan body" "Updated body"

echo "Edit: existing file missing frontmatter → block"
bad="$project/.bionic/docs/plans/epic-01-demo/wave-03-z.plan.md"
printf '%s' "$MISSING_FM" > "$bad"
run_edit "$bad" "Plan body" "Updated body"

echo "Edit: file doesn't exist (Edit would fail anyway) → block"
run_edit "$project/.bionic/docs/plans/epic-01-demo/does-not-exist.plan.md" "x" "y"

echo "Bash tool (non-Write/Edit) → allow"
input=$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')
HOOK_EXIT=0
if ! HOME="$FAKE_HOME" bash "$HOOK" <<< "$input" >/dev/null 2>&1; then
  HOOK_EXIT=$?
fi

# ============================================================
# canonical_sdlc_version: exactly one supported value
# ============================================================
#
# The hook supports canonical_sdlc_version: 14 and nothing else. Every other
# value blocks with exit 2 and a message naming the value found. One
# table-driven case over representative bad values — an older number, a much
# older number, a legacy single digit, a far-future number, an empty value,
# and non-numeric garbage — because there is one behavior here, not one per
# value.

project=$(make_project)

for bad_version in 13 12 11 9 2 99 "" "banana" "12.0" "v12"; do
  label="${bad_version:-<empty>}"
  run_write "$project/.bionic/docs/plans/epic-01-demo/unsupported.plan.md" \
    "$(build_plan version="$bad_version")"
  assert_eq "unsupported version '$label' blocks" 2 "$HOOK_EXIT"
  assert_contains "unsupported version '$label' names the value found" \
    "canonical_sdlc_version: '$bad_version'" "$HOOK_VSTDERR"
done

echo "canonical_sdlc_version line absent entirely → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-version.plan.md" "$(build_plan version=OMIT)"
assert_eq "absent version blocks" 2 "$HOOK_EXIT"

# ============================================================
# intent × rigor × scale triple + universal structural contract
# ============================================================
#
# Governance keys off the triple: presence + whole-value enum validation,
# the `mode:` split-brain guard, the 5 discriminator + 2 opt-in flags,
# `model_plan`, and a `## Verification Matrix` at sdlc-step >= 3 for
# wave/epic plans.
#
# Enums: intent ∈ {build,bugfix,refactor,tune,spike,incident-response};
#        rigor ∈ {single,double,double}; scale ∈ {task,wave,epic}.
#
# No intent × scale cell is barred (T9, epic-18-w1): every combination that
# clears the enum + flag + matrix checks writes cleanly, including the three
# cells a prior version refused (bugfix·epic, spike·epic,
# incident-response·epic) — the triple is the user's whole call, not a
# derivable refusal.

project=$(make_project)

echo "valid plan (full triple + flags + model_plan + matrix) → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/valid.plan.md" "$(build_plan)"
assert_eq "accepts_valid_plan exit 0" 0 "$HOOK_EXIT"

echo "missing intent → block, error names intent"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-intent.plan.md" "$(build_plan intent=OMIT)"
assert_eq "blocks_missing_intent exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_intent names intent" "intent" "$HOOK_STDERR"

echo "missing rigor → block, error names rigor"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-rigor.plan.md" "$(build_plan rigor=OMIT)"
assert_eq "blocks_missing_rigor exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_rigor names rigor" "rigor" "$HOOK_STDERR"

echo "missing scale → block, error names scale"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-scale.plan.md" "$(build_plan scale=OMIT)"
assert_eq "blocks_missing_scale exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_scale names scale" "scale" "$HOOK_STDERR"

echo "bad intent enum (intent: feature) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/bad-intent.plan.md" "$(build_plan intent=feature)"
assert_eq "blocks_bad_intent_enum exit 2" 2 "$HOOK_EXIT"

echo "bad rigor enum (rigor: reviewed) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/bad-rigor.plan.md" "$(build_plan rigor=reviewed)"
assert_eq "blocks_bad_rigor_enum exit 2" 2 "$HOOK_EXIT"

echo "bad scale enum (scale: session) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/bad-scale.plan.md" "$(build_plan scale=session)"
assert_eq "blocks_bad_scale_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_bad_scale_enum lists allowed" "task|wave|epic" "$HOOK_VSTDERR"

echo "enum substring (intent: rebuild) → block (whole-value equality, not substring)"
run_write "$project/.bionic/docs/plans/epic-01-demo/substr.plan.md" "$(build_plan intent=rebuild)"
assert_eq "blocks_enum_substring exit 2" 2 "$HOOK_EXIT"

echo "mode: present (split-brain) → block, error names mode"
run_write "$project/.bionic/docs/plans/epic-01-demo/mode.plan.md" "$(build_plan mode=autonomous)"
assert_eq "blocks_mode_present exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_mode_present names mode" "mode" "$HOOK_STDERR"

echo "formerly-barred cell bugfix × epic → allow (T9: barred-cell check removed)"
run_write "$project/.bionic/docs/plans/epic-01-demo/bugfix-epic.plan.md" "$(build_plan intent=bugfix scale=epic)"
assert_eq "allows_formerly_barred_bugfix_epic exit 0" 0 "$HOOK_EXIT"

echo "formerly-barred cell spike × epic → allow (T9: barred-cell check removed)"
run_write "$project/.bionic/docs/plans/epic-01-demo/spike-epic.plan.md" "$(build_plan intent=spike scale=epic)"
assert_eq "allows_formerly_barred_spike_epic exit 0" 0 "$HOOK_EXIT"

echo "formerly-barred cell incident-response × epic → allow (T9: barred-cell check removed)"
run_write "$project/.bionic/docs/plans/epic-01-demo/incident-epic.plan.md" "$(build_plan intent=incident-response scale=epic)"
assert_eq "allows_formerly_barred_incident_epic exit 0" 0 "$HOOK_EXIT"

echo "allowed cell build × epic → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/build-epic.plan.md" "$(build_plan intent=build scale=epic)"
assert_eq "allows_build_epic exit 0" 0 "$HOOK_EXIT"

echo "missing a discriminator flag (surface_type) → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-flag.plan.md" "$(build_plan omit=surface_type)"
assert_eq "blocks_missing_flag exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_flag names surface_type" "surface_type" "$HOOK_VSTDERR"

echo "missing an opt-in flag (use_worktree) → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-optin.plan.md" "$(build_plan omit=use_worktree)"
assert_eq "blocks_missing_opt_in exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_opt_in names use_worktree" "use_worktree" "$HOOK_VSTDERR"

echo "missing model_plan → block, error names model_plan"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-mp.plan.md" "$(build_plan omit=model_plan)"
assert_eq "blocks_missing_model_plan exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_model_plan names model_plan" "model_plan" "$HOOK_VSTDERR"

echo "*.plan.md at sdlc-step 3 without matrix → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-matrix.plan.md" "$(build_plan step=3 matrix=no)"
assert_eq "blocks_missing_matrix exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_matrix names the matrix" "Verification Matrix" "$HOOK_STDERR"

echo "*.plan.md at sdlc-step 2 without matrix → allow (matrix locks at Step 3)"
run_write "$project/.bionic/docs/plans/epic-01-demo/step2.plan.md" "$(build_plan step=2 matrix=no)"
assert_eq "matrix_not_required_before_step3 exit 0" 0 "$HOOK_EXIT"

echo "scale: task at sdlc-step 3 without matrix → allow (task plans carry a ledger)"
run_write "$project/.bionic/docs/plans/epic-01-demo/task.plan.md" "$(build_plan scale=task step=3 matrix=no)"
assert_eq "task_scale_exempt_from_matrix exit 0" 0 "$HOOK_EXIT"

echo "spec at sdlc-step 3 without matrix → allow (matrix is a plan-body artifact)"
run_write "$project/.bionic/docs/specs/epic-01-demo/no-matrix.spec.md" \
  "$(build_plan step=3 matrix=no waived="$SPEC_DESIGN_WAIVER")"
assert_eq "spec_exempt_from_matrix exit 0" 0 "$HOOK_EXIT"

echo "continuation.md at sdlc-step 3 without matrix → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation.md" "$(build_plan step=3 matrix=no)"
assert_eq "continuation_exempt_from_matrix exit 0" 0 "$HOOK_EXIT"

# ============================================================
# walk: enum (epic-14 AC-3)
# ============================================================
#
# `walk:` is optional at THIS hook — absence is never blocked here; the
# evidence-gate hook fail-closes on absence at Step 5 (A1/A7,
# .bionic/docs/plans/epic-14-verification-power/wave-01-cheapest-first.plan.md
# — division of labor between the two hooks). When the key IS present, only
# the literal values `required` and `exempt` are legal; anything else blocks,
# naming both legal values.

echo
section "walk: enum (epic-14 AC-3)"

echo "walk: required → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/walk-required.plan.md" \
  "$(build_plan walk=required)"
assert_eq "walk_required exit 0" 0 "$HOOK_EXIT"

echo "walk: exempt → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/walk-exempt.plan.md" \
  "$(build_plan walk=exempt)"
assert_eq "walk_exempt exit 0" 0 "$HOOK_EXIT"

echo "walk: rquired (typo) → block, names both legal values"
run_write "$project/.bionic/docs/plans/epic-01-demo/walk-typo.plan.md" \
  "$(build_plan walk=rquired)"
assert_eq "walk_typo exit 2" 2 "$HOOK_EXIT"
assert_contains "walk_typo names required" "required" "$HOOK_STDERR"
assert_contains "walk_typo names exempt" "exempt" "$HOOK_STDERR"

echo "no walk: key → allow (this hook does not demand presence)"
run_write "$project/.bionic/docs/plans/epic-01-demo/walk-absent.plan.md" \
  "$(build_plan)"
assert_eq "walk_absent exit 0" 0 "$HOOK_EXIT"

# ============================================================
# CRLF and CR-only line endings must parse
# ============================================================
#
# CRLF (\r\n) previously defeated the hook's exact-match awk frontmatter
# parser (`$0=="---"` never matches "---\r"), so a CRLF artifact's
# frontmatter read as entirely absent — false-BLOCKed as "missing a YAML
# frontmatter block" even with every required field present. The earlier fix
# `tr -d '\r'` then broke CR-only (classic-Mac) artifacts by deleting every
# line break, collapsing the file to ONE line. The parser now TRANSLATES \r
# to \n, matching the evidence-gate hook's normalize_newlines.

# Inserts a literal CR before each newline. Bash-3.2-safe ANSI-C quoting
# embeds a real CR byte in the sed script itself (BSD sed's replacement text
# does not interpret the two-character "\r" as an escape).
to_crlf() {
  printf '%s' "$1" | sed $'s/$/\r/'
}

# Replaces each \n with a bare \r (no \n remains).
to_cr_only() {
  printf '%s' "$1" | tr '\n' '\r'
}

echo "CRLF plan with full valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/crlf.plan.md" "$(to_crlf "$(build_plan)")"
assert_eq "crlf_full exit 0" 0 "$HOOK_EXIT"

echo "CRLF plan missing model_plan → block for the RIGHT reason (parses, then flags model_plan)"
run_write "$project/.bionic/docs/plans/epic-01-demo/crlf-no-mp.plan.md" "$(to_crlf "$(build_plan omit=model_plan)")"
assert_eq "crlf_no_mp exit 2" 2 "$HOOK_EXIT"
assert_contains "crlf error names model_plan (not 'missing frontmatter')" "model_plan" "$HOOK_VSTDERR"

echo "CR-only plan with full valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/cr-only.plan.md" "$(to_cr_only "$(build_plan)")"
assert_eq "cr_only_full exit 0" 0 "$HOOK_EXIT"

echo "CR-only plan missing model_plan → block for the RIGHT reason"
run_write "$project/.bionic/docs/plans/epic-01-demo/cr-only-no-mp.plan.md" "$(to_cr_only "$(build_plan omit=model_plan)")"
assert_eq "cr_only_no_mp exit 2" 2 "$HOOK_EXIT"
assert_contains "cr-only error names model_plan" "model_plan" "$HOOK_VSTDERR"

echo "CR-only plan with a bad enum → block on the enum, proving the triple parsed"
run_write "$project/.bionic/docs/plans/epic-01-demo/cr-only-enum.plan.md" "$(to_cr_only "$(build_plan intent=feature)")"
assert_eq "cr_only_enum exit 2" 2 "$HOOK_EXIT"

# ============================================================
# floor-consistency checks (LOG-ONLY, D14)
# ============================================================
#
# On every artifact write the hook computes derivable rigor floors and
# appends one line per violation to
# $HOME/.claude/logs/<project-slug>/sdlc-audit.md — outside every consuming
# project tree (incident 0001) — AND echoes it to stderr, then exits 0 —
# findings NEVER block (R3/D14).
# Floors: incident-response floors at double; spike is capped at single;
# `rigor-minimum:` in .bionic/config.yaml (invalid value = its own finding);
# `rigor-minimum:` in the epic plan's frontmatter (fail-open on missing plan).
# Fixtures build temp project roots; the hook derives PROJECT_ROOT from the
# file path's .bionic walk-up and keys the audit file on it, so each fixture
# gets its own slug directory under the sandboxed HOME and the real repo —
# and the developer's real ~/.claude/logs — is never touched.
audit_file_for() {  # $1=project root → absolute audit-file path under the fake HOME
  printf '%s/.claude/logs/%s/sdlc-audit.md' "$FAKE_HOME" "$(slug_for "$1")"
}
read_audit() {
  local f; f=$(audit_file_for "$1")
  if [ -f "$f" ]; then cat "$f"; else echo ""; fi
}

echo "intent-minimum: incident-response + rigor single → log intent-minimum, exit 0"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/incident-floor.plan.md" "$(build_plan intent=incident-response rigor=single)"
assert_eq "floor_incident_below_double_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_incident stderr names intent-minimum" "intent-minimum" "$HOOK_STDERR"
assert_contains "floor_incident audit line names intent-minimum" "intent-minimum" "$(read_audit "$project")"
assert_contains "floor_incident audit line carries artifact path" "incident-floor.plan.md" "$(read_audit "$project")"

echo "spike-cap: spike + rigor double → log spike-cap, exit 0"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/spike-cap.plan.md" "$(build_plan intent=spike rigor=double)"
assert_eq "floor_spike_above_single_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_spike stderr names spike-cap" "spike-cap" "$HOOK_STDERR"
assert_contains "floor_spike audit names spike-cap" "spike-cap" "$(read_audit "$project")"

echo "project-minimum: config rigor-minimum double + plan rigor single → log project-minimum"
project=$(make_project)
printf 'rigor-minimum: double\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/proj-floor.plan.md" "$(build_plan intent=build rigor=single)"
assert_eq "floor_project_violation_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_project stderr names project-minimum" "project-minimum" "$HOOK_STDERR"
assert_contains "floor_project audit names project-minimum" "project-minimum" "$(read_audit "$project")"

echo "project-minimum satisfied: rigor double meets floor → silent (no audit, no stderr)"
project=$(make_project)
printf 'rigor-minimum: double\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/proj-ok.plan.md" "$(build_plan intent=build rigor=double)"
assert_eq "floor_project_satisfied_silent exit 0" 0 "$HOOK_EXIT"

echo "project-minimum invalid value: rigor-minimum: extreme → invalid-value finding, exit 0"
project=$(make_project)
printf 'rigor-minimum: extreme\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/proj-invalid.plan.md" "$(build_plan intent=build rigor=double)"
assert_eq "floor_project_invalid_value_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_project_invalid stderr names project-minimum" "project-minimum" "$HOOK_STDERR"
assert_contains "floor_project_invalid audit says invalid" "invalid rigor-minimum" "$(read_audit "$project")"

echo "epic-minimum: epic.plan.md rigor-minimum double + plan rigor single → log epic-minimum"
project=$(make_project)
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
rigor-minimum: double
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/epic-minimum.plan.md" "$(build_plan intent=build rigor=single)"
assert_eq "floor_epic_violation_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_epic stderr names epic-minimum" "epic-minimum" "$HOOK_STDERR"
assert_contains "floor_epic audit names epic-minimum" "epic-minimum" "$(read_audit "$project")"

echo "epic-minimum: epic names a plan that doesn't exist → silent (fail-open)"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/epic-missing.plan.md" "$(build_plan intent=build rigor=single)"
assert_eq "floor_epic_plan_missing_silent exit 0" 0 "$HOOK_EXIT"

echo "audit file + parent dir created on first finding"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/audit-create.plan.md" "$(build_plan intent=spike rigor=double)"
assert_eq "floor_audit_file_created exit 0" 0 "$HOOK_EXIT"
if [ -f "$(audit_file_for "$project")" ]; then
  ok "floor_audit_file_created (file + dir created)"
else
  no "floor_audit_file_created (file missing)"
fi
# Incident 0001 (AC-3): the SAME write that just landed above must leave no
# audit file anywhere under the project tree. Paired with the presence check
# directly above — an absence assertion alone passes when nothing was written
# at all, which is exactly the failure mode it exists to catch.

echo "all-violations fixture (intent + project + epic floors) → still exit 0, all three logged"
project=$(make_project)
printf 'rigor-minimum: double\n' > "$project/.bionic/config.yaml"
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
rigor-minimum: double
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/all-violations.plan.md" "$(build_plan intent=incident-response rigor=single)"
assert_eq "floor_never_blocks exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_never_blocks logs intent-minimum" "intent-minimum" "$(read_audit "$project")"
assert_contains "floor_never_blocks logs project-minimum" "project-minimum" "$(read_audit "$project")"
assert_contains "floor_never_blocks logs epic-minimum" "epic-minimum" "$(read_audit "$project")"

# ============================================================
# rigor-override: marker (epic-14 AC-10, AC-11)
# ============================================================
#
# Shape: `rigor-override: <user> <date> derived=<v> chosen=<v>`. Only
# PRESENCE of the key is detected — fields are never validated (matches the
# existing waiver-token precedent). With the marker, a floor-violation
# finding logs "user-overridden" instead of the violation text, and the
# write still succeeds cleanly either way (log-only never blocks). Without
# the marker, the existing violation log line is unchanged.

echo
section "rigor-override: marker (epic-14 AC-10, AC-11)"

RIGOR_OVERRIDE_LINE='rigor-override: chris 2026-08-01 derived=double chosen=single'

echo "project-minimum violated + rigor-override marker → writes cleanly, logs user-overridden, not the violation"
project=$(make_project)
printf 'rigor-minimum: double\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/override-present.plan.md" \
  "$(build_plan intent=build rigor=single override="$RIGOR_OVERRIDE_LINE")"
assert_eq "rigor_override_present exit 0" 0 "$HOOK_EXIT"
assert_contains "rigor_override_present stderr says user-overridden" "user-overridden" "$HOOK_STDERR"
assert_contains "rigor_override_present audit says user-overridden" "user-overridden" "$(read_audit "$project")"
expect_absent "rigor_override_present stderr does not name the violation text" "project minimum" "$HOOK_STDERR"
expect_absent "rigor_override_present audit does not name the violation text" "project minimum" "$(read_audit "$project")"

echo "project-minimum violated, NO marker → existing violation log unchanged"
project2=$(make_project)
printf 'rigor-minimum: double\n' > "$project2/.bionic/config.yaml"
run_write "$project2/.bionic/docs/plans/epic-01-demo/override-absent.plan.md" \
  "$(build_plan intent=build rigor=single)"
assert_eq "rigor_override_absent exit 0" 0 "$HOOK_EXIT"
expect_absent "rigor_override_absent audit does not say user-overridden" "user-overridden" "$(read_audit "$project2")"

# ============================================================
# AC-10: the project root is COMPUTED, never discovered
# ============================================================
#
# resolve_project_root computes the root from `git rev-parse
# --path-format=absolute --git-common-dir`. It never walks the ancestor chain
# looking for an existing `.bionic/`, which is why it answers in a project
# where `.bionic/` has never existed and why every linked worktree of one repo
# answers with the parent repo — one repo, one `.bionic/` tree.
#
# Fixture fidelity: real `git init` repos and a real `git worktree add` on
# disk. The behaviour under test is git's own path-format handling; a stubbed
# `git` would reproduce whatever the test author believed it does, which is
# the belief the AC exists to check.
echo
section "AC-10: computed root resolution"

# The five criteria below drive the HOOK, through its real stdin contract, on
# four fixture roots — so what they observe is the root the hook resolved and
# acted on, never a reimplementation of the walk.
#
# THE EXTRACTION THIS PARAGRAPH USED TO DESCRIBE IS GONE (close-out finding
# A-43, removed at T8). `ac10_src=$(awk '/^resolve_project_root\(\)/,/^\}/' ...)`
# was assigned here and never read, and it had been evaluating to the EMPTY
# STRING for as long as it stood: this hook defines no `resolve_project_root`
# — it calls `project_root`, which lib/root.sh owns. A dead assignment whose
# value was also empty is two kinds of nothing, and the comment above it was
# describing a seam the section does not use.

# main: a repo WITH .bionic/ (untracked, so the worktree checkout has none).
# wt:   a linked worktree of main, given its own .bionic/ on purpose — the
#       predecessor's ancestor walk would stop there.
# nb:   a repo where .bionic/ has NEVER existed.
# out:  a plain directory, no repo anywhere above it.
ac10_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac10_tmp")
ac10_main="$ac10_tmp/main"
mkdir -p "$ac10_main/.bionic/docs/plans/epic-01-demo" "$ac10_main/deep/sub/dir"
git -C "$ac10_main" init -q .
git -C "$ac10_main" commit -q --allow-empty -m init
git -C "$ac10_main" worktree add -q "$ac10_tmp/wt" -b ac10-wt
ac10_wt="$ac10_tmp/wt"
mkdir -p "$ac10_wt/.bionic/docs/plans/epic-01-demo"
ac10_nb="$ac10_tmp/nobionic"; mkdir -p "$ac10_nb"; git -C "$ac10_nb" init -q .
ac10_out="$ac10_tmp/outside"; mkdir -p "$ac10_out"
# Engaged on every root this section drives an artifact into. `ac10_out` has no repo and
# no `.bionic` above it at all, which is the arm that stays unengaged by construction —
# see the c5 assertion, which expects silence there for both reasons at once.
engage "$ac10_main"
engage "$ac10_nb"

# 1 — from the repo root, the repo root.

# 2 — from an arbitrary subdirectory, the same repo root: both when the target
# path lives in the subdirectory, and when the process cwd is the subdirectory.

# 3 — from inside a linked worktree, the PARENT repo root. `--git-common-dir`
# is what makes this true; `--git-dir` would name the worktree's private dir.

# 4 — a repo where .bionic/ has never existed. None of the target's parent
# directories exist either, which is the ordinary case for a PreToolUse gate.

# 5 — outside any repository: cwd, and no error.

# --- git < 2.31 (critic K2 / FIX 5) ----------------------------------------
#
# `--path-format` landed in git 2.31. On anything older rev-parse rejects it as
# an unknown option and exits 129 — indistinguishable, to the single-branch
# resolver this wave shipped, from "not a repository". The root then became the
# session's cwd, so EVERY canonical-sdlc artifact write on such a machine
# blocked as misplaced and the remediation line pointed the author at whatever
# directory the session started in. Plan assumption 6 claimed a
# `cd`-and-`pwd` fallback covered this; no such fallback existed.
#
# The shim rejects ONLY `--path-format=absolute` and `exec`s the real git for
# everything else, so these cases exercise real git's actual bare-form
# behaviour: `--git-common-dir` answers RELATIVE inside the main repo (`.git`,
# `../../.git`) and ABSOLUTE from a linked worktree. A stub git would encode
# the test author's belief about git, which is the belief under test.
# [WALL: hooks/canonical-sdlc-governing-skill.sh]
ac10_oldgit=$(mktemp -d); cleanup_dirs+=("$ac10_oldgit")
ac10_real_git=$(command -v git)
{
  printf '#!/bin/bash\n'
  printf 'for a in "$@"; do\n'
  printf '  [ "$a" = "--path-format=absolute" ] && exit 129\n'
  printf 'done\n'
  printf 'exec %s "$@"\n' "$ac10_real_git"
} > "$ac10_oldgit/git"
chmod +x "$ac10_oldgit/git"

# Runs the extracted resolver with the old-git shim first on PATH. PATH is
# saved and restored around the call so nothing else in the suite is affected.

# Outside any repository BOTH forms fail, so the supplied fallback still wins —
# the fallback branch must not swallow the genuine no-repo case.

# Every answer is an ABSOLUTE path. The naive `dirname $(git rev-parse
# --git-common-dir)` yields `.` and `..`; a criterion that accepted a relative
# answer would pass the defect it exists to catch. The old-git arms are in
# scope here precisely because the bare form is what returns `.` and `..`.

# --- end-to-end through the hook (no extraction seam) ---

# Criterion 4 at the CALL SITE: a repo where .bionic/ has never existed. The
# predecessor's ancestor walk found no root here and the hook exited 0, so an
# unframed artifact went ungated. Computing the root gates it.
echo "e2e: unframed artifact in a repo where .bionic/ never existed → block"
run_write "$ac10_nb/.bionic/docs/plans/epic-01-demo/never-existed.plan.md" "$MISSING_FM"

# Criterion 3 at the CALL SITE, observed through the audit file's project key.
# A worktree-local .bionic/ is NOT the project's tree: resolution answers with
# main, so main's docs root does not contain this path.
#
# Task 1 left this as an exit-0 pass-through and flagged it as the exact
# misplacement class task 3 was to close. It is now a BLOCK naming main's
# docs root — every worktree of one repo shares one tree (AC-10), so an
# artifact written into a worktree-local .bionic/docs/ belongs in the parent
# repo's tree and the hook says where.
#
# The audit-file arm still stands and is now stronger: the write never
# happens, so nothing can be keyed on the worktree. Paired with the presence
# arm below, which writes the identical floor-violating plan under main and
# DOES produce main's audit file; alone, the absence arm would pass if the
# hook had written nothing at all.
echo "e2e: floor-violating plan under a worktree-local .bionic/ → blocks as misplaced, naming main's tree"
run_write "$ac10_wt/.bionic/docs/plans/epic-01-demo/wt-floor.plan.md" "$(build_plan intent=spike rigor=double)"
assert_eq "ac10_e2e_worktree exit 2 (misplaced)" 2 "$HOOK_EXIT"
assert_contains "ac10_e2e_worktree names the parent repo's docs root" \
  "$ac10_main/.bionic/docs/plans/" "$HOOK_VSTDERR"
run_write "$ac10_main/.bionic/docs/plans/epic-01-demo/main-floor.plan.md" "$(build_plan intent=spike rigor=double)"
assert_eq "ac10_e2e_worktree_pair exit 0" 0 "$HOOK_EXIT"
assert_contains "ac10_e2e_worktree_pair finding keyed on the main repo" "spike-cap" "$(read_audit "$ac10_main")"

# git < 2.31 at the CALL SITE (critic K2 / FIX 5). The unit arms above can only
# see what the function returns; this drives the hook through its real stdin
# contract with the shim on PATH and the process cwd deliberately somewhere
# else, which is the shape of the reproduction: a correctly-placed artifact was
# blocked as misplaced against the SESSION's cwd.
echo "e2e: git < 2.31 → a correctly-placed artifact is still correctly placed"
run_write_oldgit() {  # like run_write, with the old-git shim first on PATH and cwd elsewhere
  local file_path="$1" content="$2" input tmp_err
  input=$(jq -n --arg p "$file_path" --arg c "$content" --arg s "$GS_SID" \
    '{session_id: $s, tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  tmp_err=$(mktemp)
  if (cd "$ac10_out" && HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" PATH="$ac10_oldgit:$PATH" bash "$HOOK" <<< "$input") \
       >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  # THE SAME CALL AGAIN, WITH THE KNOB (task 13, ruling D-1): the values this suite
  # reads off the refusal are `detail` now. Guarded on the refusal and `|| true` because
  # the suite runs under `set -e` and the hook exits 2 when it refuses.
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    HOOK_VSTDERR=$( (cd "$ac10_out" && HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" \
      PATH="$ac10_oldgit:$PATH" BIONIC_WALL_VERBOSE=1 bash "$HOOK" <<< "$input") 2>&1 >/dev/null) || true
  fi
  rm -f "$tmp_err"
}
ac10_og="$ac10_tmp/oldgit"; mkdir -p "$ac10_og"; git -C "$ac10_og" init -q .
engage "$ac10_og"
run_write_oldgit "$ac10_og/.bionic/docs/plans/epic-01-demo/oldgit.plan.md" "$(build_plan)"
assert_eq "ac10_e2e_oldgit valid artifact allowed" 0 "$HOOK_EXIT"
# ...and misplacement still BLOCKS under old git, naming the artifact's OWN
# repo. A fallback that resolved everything to the cwd would pass the arm above
# by turning the hook off; this arm is what makes that impossible.
run_write_oldgit "$ac10_og/notes/rogue.plan.md" "$(build_plan)"
assert_eq "ac10_e2e_oldgit misplaced artifact blocked" 2 "$HOOK_EXIT"
assert_contains "ac10_e2e_oldgit names the artifact's own repo, not the session cwd" \
  "$ac10_og/.bionic/docs/plans/" "$HOOK_VSTDERR"

# ============================================================
# AC-11 / AC-12: tree creation on first lifecycle use
# ============================================================
#
# Task 2 (F4): creation hangs off the SAME frontmatter this hook already
# parses — a write carrying `governing-skill: canonical-sdlc` — not a
# SessionStart hook, which would create .bionic/ in every repo the user
# opens a session in. "First lifecycle use" is the first canonical-sdlc
# artifact write, not the first session.
#
# Fixture: a BARE repo (git init only, no .bionic/ anywhere), the same class
# AC-10's c4 fixture uses — a pre-created .bionic/docs/ (as make_project()
# gives every other section in this file) would hide the exact defect this
# AC guards.
echo
finish
