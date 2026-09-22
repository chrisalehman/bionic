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
#   intent/rigor/scale — triple values (default build/audited/wave);
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
  local intent=build rigor=audited scale=wave step=3 version=14 mode="OMIT" omit=" " matrix=yes
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
    "model_plan:orchestrator=fable-5-high; exec-complex=opus-fresh; exec-standard=sonnet-fresh; explore=sonnet-fresh")
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
#        rigor ∈ {tested,peer-reviewed,audited}; scale ∈ {task,wave,epic}.
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
# Floors: incident-response floors at audited; spike is capped at tested;
# `rigor-floor:` in .bionic/config.yaml (invalid value = its own finding);
# `rigor-floor:` in the epic plan's frontmatter (fail-open on missing plan).
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

echo "intent-floor: incident-response + rigor tested → log intent-floor, exit 0"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/incident-floor.plan.md" "$(build_plan intent=incident-response rigor=tested)"
assert_eq "floor_incident_below_audited_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_incident stderr names intent-floor" "intent-floor" "$HOOK_STDERR"
assert_contains "floor_incident audit line names intent-floor" "intent-floor" "$(read_audit "$project")"
assert_contains "floor_incident audit line carries artifact path" "incident-floor.plan.md" "$(read_audit "$project")"

echo "spike-cap: spike + rigor audited → log spike-cap, exit 0"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/spike-cap.plan.md" "$(build_plan intent=spike rigor=audited)"
assert_eq "floor_spike_above_tested_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_spike stderr names spike-cap" "spike-cap" "$HOOK_STDERR"
assert_contains "floor_spike audit names spike-cap" "spike-cap" "$(read_audit "$project")"

echo "project-floor: config rigor-floor audited + plan rigor tested → log project-floor"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/proj-floor.plan.md" "$(build_plan intent=build rigor=tested)"
assert_eq "floor_project_violation_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_project stderr names project-floor" "project-floor" "$HOOK_STDERR"
assert_contains "floor_project audit names project-floor" "project-floor" "$(read_audit "$project")"

echo "project-floor satisfied: rigor audited meets floor → silent (no audit, no stderr)"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/proj-ok.plan.md" "$(build_plan intent=build rigor=audited)"
assert_eq "floor_project_satisfied_silent exit 0" 0 "$HOOK_EXIT"

echo "project-floor invalid value: rigor-floor: extreme → invalid-value finding, exit 0"
project=$(make_project)
printf 'rigor-floor: extreme\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/proj-invalid.plan.md" "$(build_plan intent=build rigor=audited)"
assert_eq "floor_project_invalid_value_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_project_invalid stderr names project-floor" "project-floor" "$HOOK_STDERR"
assert_contains "floor_project_invalid audit says invalid" "invalid rigor-floor" "$(read_audit "$project")"

echo "epic-floor: epic.plan.md rigor-floor audited + plan rigor tested → log epic-floor"
project=$(make_project)
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
rigor-floor: audited
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/epic-floor.plan.md" "$(build_plan intent=build rigor=tested)"
assert_eq "floor_epic_violation_logs exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_epic stderr names epic-floor" "epic-floor" "$HOOK_STDERR"
assert_contains "floor_epic audit names epic-floor" "epic-floor" "$(read_audit "$project")"

echo "epic-floor: epic names a plan that doesn't exist → silent (fail-open)"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/epic-missing.plan.md" "$(build_plan intent=build rigor=tested)"
assert_eq "floor_epic_plan_missing_silent exit 0" 0 "$HOOK_EXIT"

echo "audit file + parent dir created on first finding"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/audit-create.plan.md" "$(build_plan intent=spike rigor=audited)"
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
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
rigor-floor: audited
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/all-violations.plan.md" "$(build_plan intent=incident-response rigor=tested)"
assert_eq "floor_never_blocks exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_never_blocks logs intent-floor" "intent-floor" "$(read_audit "$project")"
assert_contains "floor_never_blocks logs project-floor" "project-floor" "$(read_audit "$project")"
assert_contains "floor_never_blocks logs epic-floor" "epic-floor" "$(read_audit "$project")"

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

RIGOR_OVERRIDE_LINE='rigor-override: chris 2026-08-01 derived=audited chosen=tested'

echo "project-floor violated + rigor-override marker → writes cleanly, logs user-overridden, not the violation"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/override-present.plan.md" \
  "$(build_plan intent=build rigor=tested override="$RIGOR_OVERRIDE_LINE")"
assert_eq "rigor_override_present exit 0" 0 "$HOOK_EXIT"
assert_contains "rigor_override_present stderr says user-overridden" "user-overridden" "$HOOK_STDERR"
assert_contains "rigor_override_present audit says user-overridden" "user-overridden" "$(read_audit "$project")"
expect_absent "rigor_override_present stderr does not name the violation text" "project floor" "$HOOK_STDERR"
expect_absent "rigor_override_present audit does not name the violation text" "project floor" "$(read_audit "$project")"

echo "project-floor violated, NO marker → existing violation log unchanged"
project2=$(make_project)
printf 'rigor-floor: audited\n' > "$project2/.bionic/config.yaml"
run_write "$project2/.bionic/docs/plans/epic-01-demo/override-absent.plan.md" \
  "$(build_plan intent=build rigor=tested)"
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
run_write "$ac10_wt/.bionic/docs/plans/epic-01-demo/wt-floor.plan.md" "$(build_plan intent=spike rigor=audited)"
assert_eq "ac10_e2e_worktree exit 2 (misplaced)" 2 "$HOOK_EXIT"
assert_contains "ac10_e2e_worktree names the parent repo's docs root" \
  "$ac10_main/.bionic/docs/plans/" "$HOOK_VSTDERR"
run_write "$ac10_main/.bionic/docs/plans/epic-01-demo/main-floor.plan.md" "$(build_plan intent=spike rigor=audited)"
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
section "AC-11/AC-12: tree creation on first lifecycle use"

make_bare_project() {
  local dir
  dir=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$dir" init -q .
  # "BARE" NOW MEANS "no docs tree", not "no .bionic at all", and the change is forced by
  # the design rather than chosen: hooks/engage.sh creates `.bionic/tmp` in a project that
  # has none, so `.bionic/tmp` exists in EVERY engaged session by the time this wall runs.
  # What AC-11 still owns, and what the assertions below still measure, is the docs
  # subtree — specs/, plans/, adrs/, incidents/ — none of which engagement creates.
  engage "$dir"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

tree_exists() {  # $1=project root -> 0 if the full AC-11 tree exists
  [ -d "$1/.bionic/tmp" ] \
    && [ -d "$1/.bionic/docs/specs" ] \
    && [ -d "$1/.bionic/docs/plans" ] \
    && [ -d "$1/.bionic/docs/adrs" ] \
    && [ -d "$1/.bionic/docs/incidents" ]
}

echo "AC-11 c1: first write of governing-skill: canonical-sdlc into a repo with no .bionic/ -> full tree created"
ac11_p1=$(make_bare_project)
run_write "$ac11_p1/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc)"
assert_eq "ac11_c1 write allowed" 0 "$HOOK_EXIT"
ac11_c1_stderr="$HOOK_STDERR"

echo "AC-11 c3: no manual step, no prompt -- one hook invocation, no interactive/setup text on stderr"

echo "AC-11 c2: running the identical write again -> idempotent, no error, tree unchanged"
ac11_before_listing=$(cd "$ac11_p1/.bionic" && find . | sort)
run_write "$ac11_p1/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc)"
assert_eq "ac11_c2 second write still exits 0" 0 "$HOOK_EXIT"
ac11_after_listing=$(cd "$ac11_p1/.bionic" && find . | sort)

echo "AC-11 c4a: unrelated file written outside the docs-root -> no over-creation, no .bionic/ at all"
ac11_p2=$(make_bare_project)
run_write "$ac11_p2/README.md" "just some notes"
assert_eq "ac11_c4a write allowed (not an enforced artifact)" 0 "$HOOK_EXIT"

# A7 REGRESSION. Task 2 gated creation on `governing-skill: canonical-sdlc` —
# the artifact-AUTHOR field — and this case asserted the inverse of what is
# below: that a plan authored by another skill created NO tree.
#
# `.claude/rules/hook-authoring.md` (machine-local, gitignored, authored in place —
# no script recreates it, so absent from a fresh clone) § "Discriminators in enforcement hooks"
# names that exact pattern as a known failure: Step 3 plans legitimately
# declare `governing-skill: superpowers:writing-plans`, so gating on the
# self-skill makes the hook invisible to the artifacts the lifecycle itself
# produces. Recorded consequence: a hook that was a no-op for a whole epic.
#
# The concrete failure this pins: a fresh project whose FIRST artifact is a
# Step-3 plan gets no tree, and AC-11 requires creation on first lifecycle
# use. The discriminator is now `canonical_sdlc_version`, matching the schema
# enforcement below it in the same hook. Re-firing is free — `mkdir -p` is
# idempotent and the .gitignore write is `[ -f ]`-guarded (ac11_c2 pins that).
echo "AC-11 c4b (A7): Step-3 plan authored by superpowers:writing-plans WITH a valid version -> tree created"
ac11_p3=$(make_bare_project)
run_write "$ac11_p3/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=superpowers:writing-plans)"
assert_eq "ac11_c4b write allowed" 0 "$HOOK_EXIT"

# The no-over-creation arm the inverted case above used to carry. An artifact
# with NO `canonical_sdlc_version` is not a canonical-sdlc run artifact: it
# blocks on the version gate AND creates nothing. This is what keeps the fix
# from degenerating into "create on any frontmatter at all".
echo "AC-11 c4c: enforced artifact with NO canonical_sdlc_version -> blocks, and creates no tree"
ac11_p5=$(make_bare_project)
run_write "$ac11_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc version=OMIT)"
assert_eq "ac11_c4c write blocked" 2 "$HOOK_EXIT"

# AC-11 criterion 4, the general form (Step-6 findings C5 / F3 / S4). c4c above
# only covers the ONE block that fires before the version marker is read, so it
# passed while creation still ran ahead of every OTHER gate. A write carrying a
# version marker but failing any later part of the contract was blocked AND left
# a full tree plus .gitignore behind — a PreToolUse gate mutating the filesystem
# for a call it then refuses.
#
# Ruling (orchestrator, Step 6): the tree is created only for an artifact that
# passes the ENTIRE contract, not merely one carrying a version marker. So the
# three later gates each get an arm here.
#
# THE PROBE MOVED DOWN ONE LEVEL (task-engaged-session, 2026-09-03) and the claim did
# not: `.bionic/tmp` now exists in every engaged session because hooks/engage.sh made it
# at invocation, so the absence this AC owns is the DOCS tree — specs/, plans/, adrs/,
# incidents/ and the .gitignore beside them, none of which engagement creates and all of
# which a refused write must still leave unmade.
# [WALL: hooks/canonical-sdlc-governing-skill.sh]
echo "AC-11 c4d: blocked on the VERSION gate (wrong number) -> no tree"
ac11_p6=$(make_bare_project)
run_write "$ac11_p6/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan version=3)"
assert_eq "ac11_c4d write blocked" 2 "$HOOK_EXIT"
if [ -d "$ac11_p6/.bionic/docs" ]; then
  no "ac11_c4d no .bionic/ created for a wrong-version artifact" "found $ac11_p6/.bionic"
else
  ok "ac11_c4d no .bionic/ created for a wrong-version artifact"
fi

echo "AC-11 c4e: blocked on the TRIPLE gate (invalid intent) -> no tree"
ac11_p7=$(make_bare_project)
run_write "$ac11_p7/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan intent=definitely-not-an-intent)"
assert_eq "ac11_c4e write blocked" 2 "$HOOK_EXIT"
if [ -d "$ac11_p7/.bionic/docs" ]; then
  no "ac11_c4e no .bionic/ created for an invalid-triple artifact" "found $ac11_p7/.bionic"
else
  ok "ac11_c4e no .bionic/ created for an invalid-triple artifact"
fi

echo "AC-11 c4f: blocked on the required-FLAGS gate -> no tree"
ac11_p8=$(make_bare_project)
run_write "$ac11_p8/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan omit=has_ui)"
assert_eq "ac11_c4f write blocked" 2 "$HOOK_EXIT"
if [ -d "$ac11_p8/.bionic/docs" ]; then
  no "ac11_c4f no .bionic/ created for a flag-missing artifact" "found $ac11_p8/.bionic"
else
  ok "ac11_c4f no .bionic/ created for a flag-missing artifact"
fi

echo "AC-11 c4g: blocked on the MATRIX gate -> no tree"
ac11_p9=$(make_bare_project)
run_write "$ac11_p9/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan matrix=no)"
assert_eq "ac11_c4g write blocked" 2 "$HOOK_EXIT"
if [ -d "$ac11_p9/.bionic/docs" ]; then
  no "ac11_c4g no .bionic/ created for a matrix-less step-3 plan" "found $ac11_p9/.bionic"
else
  ok "ac11_c4g no .bionic/ created for a matrix-less step-3 plan"
fi

echo "AC-12 c1: .bionic/.gitignore exists and contains '*'"

echo "AC-12 c2: git check-ignore reports a file inside .bionic/ as ignored (the ignore BINDS)"
: > "$ac11_p1/.bionic/tmp/probe.txt"

echo "AC-12 c3: the project's OWN .gitignore is byte-identical before and after (hash, not eye)"
ac12_p4=$(make_bare_project)
printf 'node_modules/\n*.log\n' > "$ac12_p4/.gitignore"
ac12_before_hash=$(shasum -a 256 "$ac12_p4/.gitignore" | awk '{print $1}')
run_write "$ac12_p4/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc)"
assert_eq "ac12_c3 write allowed" 0 "$HOOK_EXIT"
ac12_after_hash=$(shasum -a 256 "$ac12_p4/.gitignore" | awk '{print $1}')

# AC-12 c4 (Step-6 finding C4): the .gitignore write must be SILENT when it
# cannot succeed. `printf '*\n' > "$f" 2>/dev/null` does not silence anything —
# the shell performs the redirection before printf runs, so the redirect's own
# failure is reported by the shell, not by printf. The paired `mkdir -p ...
# 2>/dev/null` above it IS correctly silenced, which is why the asymmetry reads
# as unintended rather than as a choice.
#
# Fixture: a DIRECTORY standing where `.bionic/.gitignore` must be written, so the
# redirect fails with EISDIR. It used to be `.bionic` itself as a regular file (ENOTDIR),
# which task-engaged-session made unreachable rather than merely inconvenient: an engaged
# session's marker lives at `.bionic/tmp/engaged-<sid>.state`, so in every session this
# wall now runs in, `.bionic` is a directory. The failing WRITE is the subject either way.
# A hook is a tool-call gate — stderr on an ALLOWED call is noise the agent has to
# interpret.
# [WALL: hooks/canonical-sdlc-governing-skill.sh]
echo "AC-12 c4 (C4): an unwritable .gitignore path leaks nothing on stderr"
ac12_p5=$(make_bare_project)
mkdir -p "$ac12_p5/.bionic/.gitignore"
run_write "$ac12_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan)"
assert_eq "ac12_c4 write still allowed" 0 "$HOOK_EXIT"
assert_eq "ac12_c4 ...and says nothing on stderr" "" "$HOOK_STDERR"

# ============================================================
# AC-13: misplacement blocks; absence never does
# ============================================================
#
# The fail-open this closes: an artifact that DECLARES itself a canonical-sdlc
# artifact but lives outside the project's computed docs root used to fall out
# of the `case "$FILE_PATH"` scope check and exit 0 — written, ungated, in the
# wrong place. Task 1 replaced the ancestor walk with resolve_project_root(),
# which always answers, so the historical `exit 0`-on-no-root is unreachable;
# the surviving fail-open is the scope check itself.
#
# The distinction the AC draws: MISPLACED is an error, ABSENT is not. A repo
# with no `.bionic/` at all is the normal first-run state and must never block
# — the absence arms below are what keep the fix from becoming a wall in front
# of every new project.
#
# "Outside the docs root" is the whole docs root, not just the four enforced
# subdirectories. `.bionic/docs/spikes/` and `.bionic/docs/record/` hold real
# files carrying canonical-sdlc frontmatter (task 6 put them there); they are
# placed, and c8 pins that they stay unblocked.
echo
section "AC-13: misplacement blocks; absence never does"

ac13_p=$(make_project)
ac13_docs="$ac13_p/.bionic/docs"

echo "AC-13 c1: valid artifact written OUTSIDE the computed docs-root -> block, naming the correct path"
run_write "$ac13_p/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c1 exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c1 names the correct path" "$ac13_docs/plans/" "$HOOK_VSTDERR"

echo "AC-13 c1b: 'governing-skill: canonical-sdlc' alone is enough to identify the artifact"
run_write "$ac13_p/notes/stray.md" '---
governing-skill: canonical-sdlc
---
body
'

echo "AC-13 c2: the SAME artifact written INSIDE the computed docs-root -> passes"
run_write "$ac13_docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c2 exit 0" 0 "$HOOK_EXIT"

echo "AC-13 c3: the named path follows the artifact kind (spec -> specs/, adr -> adrs/)"
run_write "$ac13_p/docs/wave-01-x.spec.md" "$VALID_FRONTMATTER"
assert_contains "ac13_c3 spec names specs/" "$ac13_docs/specs/" "$HOOK_VSTDERR"
run_write "$ac13_p/docs/adr-001-thing.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c3 adr exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c3 adr names adrs/" "$ac13_docs/adrs/" "$HOOK_VSTDERR"

echo "AC-13 c4: Edit of an already-misplaced artifact blocks too (not just Write)"
mkdir -p "$ac13_p/legacy"
printf '%s' "$VALID_FRONTMATTER" > "$ac13_p/legacy/wave-02-y.plan.md"
run_edit "$ac13_p/legacy/wave-02-y.plan.md" "old" "new"
assert_eq "ac13_c4 exit 2" 2 "$HOOK_EXIT"

echo "AC-13 c5: a file WITHOUT the frontmatter is unaffected, wherever it lives"
run_write "$ac13_p/notes.md" "just some notes, no frontmatter at all"
assert_eq "ac13_c5 plain file exit 0" 0 "$HOOK_EXIT"
run_write "$ac13_p/docs/bionic/plans/unrelated.plan.md" "$MISSING_FM"
assert_eq "ac13_c5 plan-named file with no frontmatter exit 0" 0 "$HOOK_EXIT"
run_write "$ac13_p/docs/other.md" '---
title: something else entirely
governing-skill-ish: canonical-sdlc
---
body
'
assert_eq "ac13_c5 unrelated frontmatter exit 0" 0 "$HOOK_EXIT"

echo "AC-13 c6: a fenced EXAMPLE of the frontmatter is documentation, not an artifact"
run_write "$ac13_p/docs/how-to-write-plans.md" '# How to write a plan

Prepend this block:

```
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 14
---
```
'
assert_eq "ac13_c6 fenced example exit 0" 0 "$HOOK_EXIT"

echo "AC-13 c7: ABSENCE never blocks -- a repo where .bionic/ has never existed"
ac13_bare=$(make_bare_project)
run_write "$ac13_bare/README.md" "a brand new project"
assert_eq "ac13_c7 plain write in a .bionic-less repo exit 0" 0 "$HOOK_EXIT"
run_write "$ac13_bare/src/main.sh" "#!/bin/bash"
assert_eq "ac13_c7 nested write in a .bionic-less repo exit 0" 0 "$HOOK_EXIT"
# The first artifact of a brand-new project targets the COMPUTED docs root,
# which does not exist yet. That is first-run, not misplacement.
run_write "$ac13_bare/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c7 first artifact into the computed docs-root exit 0" 0 "$HOOK_EXIT"

echo "AC-13 c7b: what blocks is the misplacement, not the absence -- same bare repo"
ac13_bare2=$(make_bare_project)
run_write "$ac13_bare2/docs/plans/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c7b exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c7b names the computed docs-root" "$ac13_bare2/.bionic/docs/plans/" "$HOOK_VSTDERR"

echo "AC-13 c8: under the docs-root but outside the four enforced subdirs -> placed, unblocked"
mkdir -p "$ac13_docs/spikes" "$ac13_docs/record"
run_write "$ac13_docs/spikes/spike-thing-20260101.md" "$VALID_FRONTMATTER"
run_write "$ac13_docs/record/wave-7-handoff.md" "$VALID_FRONTMATTER"

echo "AC-13 c9: 'the correct path' follows docs-root: in config.yaml, not a hardcoded .bionic/"
ac13_cfg=$(make_project)
printf 'docs-root: custom/docs\n' > "$ac13_cfg/.bionic/config.yaml"
mkdir -p "$ac13_cfg/custom/docs/plans/epic-01-demo"
run_write "$ac13_cfg/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c9 default location is now the misplaced one" 2 "$HOOK_EXIT"
assert_contains "ac13_c9 names the configured docs-root" "$ac13_cfg/custom/docs/plans/" "$HOOK_VSTDERR"
run_write "$ac13_cfg/custom/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c9 configured location passes" 0 "$HOOK_EXIT"

echo "AC-13 c10: a project reached through a SYMLINK is the same project"
# Task 1 flagged this and handed it here: `git` answers with the PHYSICAL
# root while FILE_PATH arrives as whatever path the session used. Under the
# old pass-through that mismatch was a silent bypass — artifacts quietly
# stopped being gated. Under AC-13's fail-closed rule the same mismatch would
# be worse: a CORRECTLY placed artifact false-blocked as misplaced, which is
# the fix turning into a wall in front of legitimate work.
#
# macOS makes this the common case, not an exotic one: /tmp and /var are
# themselves symlinks, so any project under them is reached through one.
ac13_sym=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac13_sym")
mkdir -p "$ac13_sym/real/.bionic/docs/plans/epic-01-demo"
git -C "$ac13_sym/real" init -q .
engage "$ac13_sym/real"
ln -s "$ac13_sym/real" "$ac13_sym/link"
run_write "$ac13_sym/link/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c10 correctly-placed artifact via a symlinked path exit 0" 0 "$HOOK_EXIT"
# The paired arm: resolving the symlink must not resolve away the enforcement.
run_write "$ac13_sym/link/docs/plans/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c10 misplaced artifact via a symlinked path still exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c10 misplaced-via-symlink names the real docs root" \
  "$ac13_sym/real/.bionic/docs/plans/" "$HOOK_VSTDERR"

# ============================================================
# AC-14: no session-state file
# ============================================================
#
# Live state is carried by the active plan's `## Handoff` and by
# `continuation.md`, and nothing else. Two halves:
#   (a) no `context.md`-shaped session-state file exists under the new layout;
#   (b) no shipped surface instructs anything to write one.
#
# `.bionic/docs/record/context.md` is EXEMPT: task 6 relocated the old file
# there as an operational record of what happened, not as live state. The
# whole point of the AC is that nothing reads or writes it as session state.
#
# This lives in the governing-skill suite because AC-13 and AC-14 are one
# task and this suite is the task's surface; the assertion is about the
# repo's shipped text, not about this hook. Homed here rather than in a new
# suite so `tests/run.sh`'s suite count is unchanged.
echo
section "AC-14: no session-state file under the new layout"

AC14_REPO="$(cd "$(dirname "$HOOK")/.." && pwd)"

echo "AC-14 a: the only context.md under the new docs layout is the exempt operational record"
ac14_stray=""
if [ -d "$AC14_REPO/.bionic/docs" ]; then
  ac14_stray=$(find "$AC14_REPO/.bionic/docs" -type f -name 'context.md' \
               ! -path "$AC14_REPO/.bionic/docs/record/context.md" 2>/dev/null)
fi
expect_empty "ac14_a no stray context.md under .bionic/docs (outside the exempt record)" "$ac14_stray"

echo "AC-14 b: no shipped surface instructs anything to write a session-state context.md"
# Shipped surfaces = what claude-bootstrap.sh installs into ~/.claude/ (hooks,
# commands, agents, skills) plus the always-loaded global instruction file.
# Matching is on the write VERBS, not on every mention: a comment naming
# context.md as retired is a record, not an instruction.
AC14_WRITE_VERB='(write|update|append|checkpoint|rotate|save)[^.]{0,40}context\.md'
AC14_SURFACES=()
for ac14_g in "$AC14_REPO"/hooks/*.sh "$AC14_REPO"/commands/*.md "$AC14_REPO"/agents/*.md \
              "$AC14_REPO"/claude-global.md; do
  [ -f "$ac14_g" ] || continue
  case "$ac14_g" in *.test.sh) continue ;; esac
  AC14_SURFACES+=("$ac14_g")
done
while IFS= read -r ac14_g; do
  AC14_SURFACES+=("$ac14_g")
done < <(find "$AC14_REPO/skills" -type f -name '*.md' 2>/dev/null)

# A vacuous glob would make this assertion pass by matching nothing. Pin the
# surface set as non-empty first, so "no hits" means "searched and found none".

ac14_hits=$(grep -nEi "$AC14_WRITE_VERB" "${AC14_SURFACES[@]}" 2>/dev/null || true)
expect_empty "ac14_b no shipped surface instructs a context.md write" "$ac14_hits"

# ============================================================
# design wall: the three-way rule (wave-02 AC-2, AC-3, AC-4)
# ============================================================
#
# A wave-or-epic-scale spec artifact must carry one of: a flush-left
# `## Design` section in place; a frontmatter `design:` pointer resolving to a
# real file that itself carries one; or a `design-waived:` token. Task-scale
# specs and non-spec artifacts never see the arm.
#
# FIXTURE FIDELITY (wave-02 design assumption 1). build_spec() is a
# copy-and-mutate of this wave's own real spec artifact,
# `.bionic/docs/specs/epic-14-verification-power/wave-02-design-before-build.spec.md`:
# same frontmatter key set and order (no `wave:` key — specs don't carry one;
# `created:` last), same body skeleton (`# <name> — spec`, `## Requirements`,
# `## Acceptance criteria`, `## Design` with its five sub-headings). It is
# EMBEDDED rather than read from disk at run time because the whole `.bionic/`
# tree is gitignored — a suite that read the real file would pass on this
# machine and vanish on a fresh clone. Re-derive it by hand if the artifact
# shape moves.
#
# Knobs: scale (default wave) · section=yes|no (the in-place `## Design`,
# default yes, as in the real artifact) · design=<value> injects a
# `design:` line · waived=<full line> injects it verbatim · goal=yes|no|empty
# (K5.4, default yes — same reasoning as build_plan()'s own goal= knob: a real
# '## Goal' paragraph opens the body by default so pre-existing design-wall cases keep
# passing the new K5.4 arm untouched; "no"/"empty" are for K5.4's own negative cases).
build_spec() {
  local scale=wave section=yes design="OMIT" waived="OMIT" step=2 adrs="OMIT" goal=yes
  local arg
  for arg in "$@"; do
    case "$arg" in
      scale=*)   scale="${arg#scale=}" ;;
      section=*) section="${arg#section=}" ;;
      design=*)  design="${arg#design=}" ;;
      waived=*)  waived="${arg#waived=}" ;;
      step=*)    step="${arg#step=}" ;;
      adrs=*)    adrs="${arg#adrs=}" ;;
      goal=*)    goal="${arg#goal=}" ;;
    esac
  done

  local out='---
governing-skill: canonical-sdlc
sdlc-step: '"$step"'
epic: epic-01-demo
canonical_sdlc_version: 14
intent: build
rigor: audited
scale: '"$scale"'
'
  [ "$design" = OMIT ] || out+="design: $design"$'\n'
  [ "$waived" = OMIT ] || out+="$waived"$'\n'
  [ "$adrs" = OMIT ] || out+="adrs: $adrs"$'\n'
  out+='surface_type: system
language: bash
has_ui: false
multi_agent: true
deploy_target: none
cleanup_on_finish: true
use_worktree: false
model_plan: orchestrator=fable-5; implementor=sonnet-fresh; auditor=opus-fresh
created: 2026-08-02
---

# wave-01-demo — spec

Source of requirements: the demo report.
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
  out+='
## Requirements

- **R1 — A requirement.** Body text.

## Acceptance criteria

AC-1: something observable.
  provenance: report §"a section"
'
  if [ "$section" = yes ]; then
    out+='
## Design

Design decisions below cite the requirements they serve (R-refs).

### Domain model

- **A thing** — what it is (serves R1).

### Boundaries and interfaces

- `some/file.sh` — what it owns (R1).

### Ownership table

| concept | owning module (SSoT) | rendering surfaces | agreement test |
|---|---|---|---|
| a thing | some/file.sh | one surface | a hermetic test |

### Rejected alternatives

- Something heavier — weight without value (vs R1).

### Assumptions

1. An assumption.
'
  fi
  printf '%s' "$out"
}

echo
section "design wall: three-way rule (wave-02 AC-2, AC-3, AC-4)"

design_project=$(make_project)
DESIGN_SPECS="$design_project/.bionic/docs/specs/epic-01-demo"

# Pointer targets. `with-design` carries the section; `no-design` is a real
# file that does not. `sibling` sits one level up so a `..` pointer that the
# hook NAIVELY resolved would find a satisfying file — the `..` case blocks on
# containment, not on the target being absent.
printf '%s' "$(build_spec)" > "$DESIGN_SPECS/with-design.spec.md"
printf '%s' "$(build_spec section=no)" > "$DESIGN_SPECS/no-design.spec.md"
printf '%s' "$(build_spec)" > "$design_project/.bionic/docs/specs/sibling.spec.md"

echo "c1: wave spec with none of the three arms → block, naming all three ways"
run_write "$DESIGN_SPECS/w1.spec.md" "$(build_spec section=no)"
assert_eq "design_none exit 2" 2 "$HOOK_EXIT"
assert_contains "design_none names the in-place section" "## Design" "$HOOK_STDERR"
assert_contains "design_none names the pointer" "design:" "$HOOK_VSTDERR"
assert_contains "design_none names the waiver" "design-waived:" "$HOOK_VSTDERR"

echo "c2: wave spec with a flush-left ## Design in place → allow"
run_write "$DESIGN_SPECS/w2.spec.md" "$(build_spec)"
assert_eq "design_in_place exit 0" 0 "$HOOK_EXIT"

echo "c3: design: pointer (docs-root-relative) to a file carrying ## Design → allow"
run_write "$DESIGN_SPECS/w3.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md)"
assert_eq "design_pointer_docsroot exit 0" 0 "$HOOK_EXIT"

echo "c3b: the same pointer spelled project-relative → allow"
run_write "$DESIGN_SPECS/w3b.spec.md" \
  "$(build_spec section=no design=.bionic/docs/specs/epic-01-demo/with-design.spec.md)"
assert_eq "design_pointer_projectrel exit 0" 0 "$HOOK_EXIT"

echo "c3c: the same pointer spelled absolute → allow"
run_write "$DESIGN_SPECS/w3c.spec.md" \
  "$(build_spec section=no design="$DESIGN_SPECS/with-design.spec.md")"
assert_eq "design_pointer_absolute exit 0" 0 "$HOOK_EXIT"

echo "c4: design: pointer to a file that does not exist → block, naming the resolved path"
run_write "$DESIGN_SPECS/w4.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/nowhere.spec.md)"
assert_eq "design_pointer_dangling exit 2" 2 "$HOOK_EXIT"
assert_contains "design_pointer_dangling names the raw value" "specs/epic-01-demo/nowhere.spec.md" "$HOOK_VSTDERR"
assert_contains "design_pointer_dangling still names the three-way rule" "design-waived:" "$HOOK_VSTDERR"

echo "c5: design: pointer to a real file WITHOUT ## Design → block"
run_write "$DESIGN_SPECS/w5.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/no-design.spec.md)"
assert_eq "design_pointer_no_section exit 2" 2 "$HOOK_EXIT"

echo "c6: design: path with a .. component → block even though it would resolve to a real design"
run_write "$DESIGN_SPECS/w6.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/../sibling.spec.md)"
assert_eq "design_pointer_dotdot exit 2" 2 "$HOOK_EXIT"
# Discrimination guard: the same target NAMED WITHOUT `..` passes, so c6's block
# is the containment refusal and not a dangling-target block in disguise.
run_write "$DESIGN_SPECS/w6b.spec.md" "$(build_spec section=no design=specs/sibling.spec.md)"
assert_eq "design_pointer_dotdot_control exit 0" 0 "$HOOK_EXIT"

echo "c7: design-waived: present → allow"
run_write "$DESIGN_SPECS/w7.spec.md" \
  "$(build_spec section=no waived='design-waived: chris 2026-08-02 prose-only wave, no design surface')"
assert_eq "design_waived exit 0" 0 "$HOOK_EXIT"

echo "c7b: design-waived: is presence-only — a bare key with no fields still quiets the wall"
run_write "$DESIGN_SPECS/w7b.spec.md" "$(build_spec section=no waived='design-waived:')"
assert_eq "design_waived_bare exit 0" 0 "$HOOK_EXIT"

echo "c8 (AC-4): task-scale spec with no design anything → allow (arm silent at task scale)"
run_write "$DESIGN_SPECS/t1.spec.md" "$(build_spec scale=task section=no)"
assert_eq "design_task_scale exit 0" 0 "$HOOK_EXIT"

echo "c9: epic-scale spec behaves as wave → block with none of the three"
run_write "$DESIGN_SPECS/e1.spec.md" "$(build_spec scale=epic section=no)"
assert_eq "design_epic_scale exit 2" 2 "$HOOK_EXIT"
assert_contains "design_epic_scale names the three-way rule" "design-waived:" "$HOOK_VSTDERR"

echo "c10: a wave-scale PLAN with no design → allow (the arm is spec-only)"
run_write "$design_project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan)"
assert_eq "design_plan_untouched exit 0" 0 "$HOOK_EXIT"

echo "c11: '## Designer notes' is not a design section → block; '## Design — v2' is → allow"
run_write "$DESIGN_SPECS/w11.spec.md" \
  "$(build_spec section=no)$(printf '\n## Designer notes\n\nnot the section.\n')"
assert_eq "design_near_miss_heading exit 2" 2 "$HOOK_EXIT"
run_write "$DESIGN_SPECS/w11b.spec.md" \
  "$(build_spec section=no)$(printf '\n## Design — v2\n\nthe real thing.\n')"
assert_eq "design_suffixed_heading exit 0" 0 "$HOOK_EXIT"

# A spec that EXPLAINS this contract will show `## Design` as an example, and an
# example is documentation, not a section. Both read paths are fence-aware, so
# both get a case; each is paired with a control that moves the same heading out
# of the fence, so the block is fence-awareness and not some other refusal.
echo "c12: an in-place '## Design' that exists only inside a fenced code block → block"
run_write "$DESIGN_SPECS/w12.spec.md" \
  "$(build_spec section=no)$(printf '\n%s\n## Design\n\nan example of the contract, not this spec.\n%s\n' '```markdown' '```')"
assert_eq "design_fenced_in_place exit 2" 2 "$HOOK_EXIT"
assert_contains "design_fenced_in_place names the three-way rule" "design-waived:" "$HOOK_VSTDERR"
run_write "$DESIGN_SPECS/w12b.spec.md" \
  "$(build_spec section=no)$(printf '\n%s\n## Design\n%s\n\n## Design\n\nthe real one, outside the fence.\n' '```markdown' '```')"
assert_eq "design_fenced_in_place_control exit 0" 0 "$HOOK_EXIT"

echo "c13: a pointer target whose only '## Design' is inside a fenced code block → block"
printf '%s' \
  "$(build_spec section=no)$(printf '\n%s\n## Design\n%s\n' '```markdown' '```')" \
  > "$DESIGN_SPECS/fenced-design.spec.md"
run_write "$DESIGN_SPECS/w13.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/fenced-design.spec.md)"
assert_eq "design_fenced_pointer_target exit 2" 2 "$HOOK_EXIT"
assert_contains "design_fenced_pointer_target names the target" "fenced-design.spec.md" "$HOOK_VSTDERR"
# Control: the same target with the heading moved out of the fence resolves.
printf '%s' \
  "$(build_spec section=no)$(printf '\n%s\n## Design\n%s\n\n## Design\n\nthe real one.\n' '```markdown' '```')" \
  > "$DESIGN_SPECS/unfenced-design.spec.md"
run_write "$DESIGN_SPECS/w13b.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/unfenced-design.spec.md)"
assert_eq "design_fenced_pointer_target_control exit 0" 0 "$HOOK_EXIT"

# The pointer target is read off disk, so it gets the same newline normalization
# `$CONTENT` gets — CR-only collapses a document to one record, and no heading is
# ever at a line start after that. CRLF passes either way (`[[:space:]]` eats the
# trailing \r), so CRLF coverage alone would not have caught this: the CR-only
# case is the one that discriminates, per `.claude/rules/hook-authoring.md`.
echo "c14: a CR-only pointer target carrying a real '## Design' → allow"
to_cr_only "$(build_spec)" > "$DESIGN_SPECS/cr-design.spec.md"
run_write "$DESIGN_SPECS/w14.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/cr-design.spec.md)"
assert_eq "design_pointer_cr_only exit 0" 0 "$HOOK_EXIT"

echo "c14b: a CRLF pointer target carrying a real '## Design' → allow (control)"
to_crlf "$(build_spec)" > "$DESIGN_SPECS/crlf-design.spec.md"
run_write "$DESIGN_SPECS/w14b.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/crlf-design.spec.md)"
assert_eq "design_pointer_crlf exit 0" 0 "$HOOK_EXIT"

echo "c14c: a CR-only pointer target WITHOUT '## Design' → still blocks (the fix is not a bypass)"
to_cr_only "$(build_spec section=no)" > "$DESIGN_SPECS/cr-no-design.spec.md"
run_write "$DESIGN_SPECS/w14c.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/cr-no-design.spec.md)"
assert_eq "design_pointer_cr_only_no_section exit 2" 2 "$HOOK_EXIT"

# PRECEDENCE (critic C-3). Pointer and in-place section are documented as a
# legitimate COMBINED shape — "the pointer names what governs, the local section
# carries only the delta" — and the Step-3 approval display prints the pointer's
# resolved path for the user to open. A pointer that is present is therefore
# never decorative: it validates whatever else the spec carries, so the four
# cases below hold in the combined shape exactly as c4/c5/c6 hold when the
# pointer is the sole arm. The waived path is untouched (c7 still short-circuits
# everything).
echo "c15: in-place '## Design' + a dangling pointer → block"
run_write "$DESIGN_SPECS/w15.spec.md" \
  "$(build_spec design=specs/epic-01-demo/nowhere.spec.md)"
assert_eq "design_combined_dangling exit 2" 2 "$HOOK_EXIT"
assert_contains "design_combined_dangling names the raw value" "specs/epic-01-demo/nowhere.spec.md" "$HOOK_VSTDERR"

echo "c15b: in-place '## Design' + a '..' pointer → block"
run_write "$DESIGN_SPECS/w15b.spec.md" \
  "$(build_spec design=specs/epic-01-demo/../sibling.spec.md)"
assert_eq "design_combined_dotdot exit 2" 2 "$HOOK_EXIT"

echo "c15c: in-place '## Design' + a pointer to a target that lacks the section → block"
run_write "$DESIGN_SPECS/w15c.spec.md" \
  "$(build_spec design=specs/epic-01-demo/no-design.spec.md)"
assert_eq "design_combined_no_section exit 2" 2 "$HOOK_EXIT"

echo "c15d: in-place '## Design' + a VALID pointer → allow (the documented combined shape)"
run_write "$DESIGN_SPECS/w15d.spec.md" \
  "$(build_spec design=specs/epic-01-demo/with-design.spec.md)"
assert_eq "design_combined_valid exit 0" 0 "$HOOK_EXIT"

# ============================================================
# K3 F4 / D6: the adrs: pointer arm (AC-K3.3)
# ============================================================
#
# A momentous decision's ADR is drafted at Step 2 alongside the spec and
# pointed to from the spec's own `adrs:` frontmatter (one path, or several
# joined by ` · `). The arm only checks the pointer RESOLVES — no in-place
# alternative, no waiver, unlike the three-way design rule above it — and it
# is scoped to `sdlc-step >= 3`: below that, the ADR and the pointer are
# typically authored in the same design pass and the file may not exist yet
# on the turn the spec names it, so a dangling path is not yet a defect.
#
# Fixture: a real ADR at `adrs/epic-01-demo/real.md` (make_project() already
# creates that directory); every case below points at it, or deliberately
# does not.
echo
section "K3 F4: adrs: pointer arm (AC-K3.3)"

ADRS_DIR="$design_project/.bionic/docs/adrs/epic-01-demo"
printf '# ADR 001 — a momentous decision\n\nStatus: Accepted\n' > "$ADRS_DIR/real.md"

echo "k3-1: sdlc-step 3, adrs: names a real file → allow"
run_write "$DESIGN_SPECS/k3-1.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 adrs=adrs/epic-01-demo/real.md)"
assert_eq "adrs_resolving_step3 exit 0" 0 "$HOOK_EXIT"

echo "k3-2: sdlc-step 3, adrs: names no file → block, naming the raw value and the resolved path"
run_write "$DESIGN_SPECS/k3-2.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 adrs=adrs/epic-01-demo/nowhere.md)"
assert_eq "adrs_dangling_step3 exit 2" 2 "$HOOK_EXIT"
assert_contains "adrs_dangling_step3 names the raw value" "adrs/epic-01-demo/nowhere.md" "$HOOK_VSTDERR"
assert_contains "adrs_dangling_step3 names the resolved path" "$ADRS_DIR/nowhere.md" "$HOOK_VSTDERR"

echo "k3-3: sdlc-step 2, adrs: names no file → allow (arm inert below step 3)"
run_write "$DESIGN_SPECS/k3-3.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=2 adrs=adrs/epic-01-demo/nowhere.md)"
assert_eq "adrs_dangling_step2_inert exit 0" 0 "$HOOK_EXIT"

echo "k3-4: sdlc-step 3, no adrs: line at all → allow (a wave with no momentous decision cites none)"
run_write "$DESIGN_SPECS/k3-4.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3)"
assert_eq "adrs_absent_step3 exit 0" 0 "$HOOK_EXIT"

echo "k3-5: sdlc-step 3, two adrs: paths joined by ' · ', one real one dangling → block naming the dangling one"
run_write "$DESIGN_SPECS/k3-5.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 \
    adrs="adrs/epic-01-demo/real.md · adrs/epic-01-demo/nowhere.md")"
assert_eq "adrs_multi_one_dangling exit 2" 2 "$HOOK_EXIT"
assert_contains "adrs_multi_one_dangling names the dangling entry, not the real one" \
  "adrs/epic-01-demo/nowhere.md" "$HOOK_VSTDERR"

echo "k3-6: sdlc-step 3, adrs: path with a '..' component → block even though it would resolve to a real file"
run_write "$DESIGN_SPECS/k3-6.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 adrs=adrs/epic-01-demo/../epic-01-demo/real.md)"
assert_eq "adrs_dotdot_step3 exit 2" 2 "$HOOK_EXIT"

echo "k3-7: sdlc-step 3, a task-scale spec with a dangling adrs: → allow (arm is wave/epic only, matching the design wall)"
run_write "$DESIGN_SPECS/k3-7.spec.md" \
  "$(build_spec section=no scale=task step=3 adrs=adrs/epic-01-demo/nowhere.md)"
assert_eq "adrs_task_scale_untouched exit 0" 0 "$HOOK_EXIT"

# ── THE TWO POINTERS AGREE ABOUT AN ABSOLUTE PATH (Step-6 review F-2) ─────────
#
# F-2 read `adrs:` refusing `..` while letting `/etc/passwd` through and called the
# pair inconsistent. It is not: `resolve_adrs_path` copies `resolve_design_path`
# clause for clause, and "absolute stands as written" is the project's rule for
# every frontmatter pointer — the `design:` arm pins it at c3c above
# ("the same pointer spelled absolute → allow"), and the evidence gate's
# `resolve_walk_path` and `resolve_requirements_path` open with the same `/*)` case.
# Absolute is not a hole in the `..` refusal, it is the OTHER spelling of a path the
# author states outright: `..` is refused because a climbing path is a spelling
# nobody should have to audit, not because the target must live under the docs root.
# The arm is presence-only — it neither reads nor writes the file it names — so a
# spec pointing `adrs:` at an unrelated readable file gets a green light and nothing
# else, which is the same thing `design:` has always done.
#
# CONSISTENT BY DESIGN, so these rows pin the agreement rather than change it. They
# are the two halves that F-2 saw separately, asserted side by side, so a later
# hardening pass moves both resolvers or fails here.
echo "k3-8: sdlc-step 3, adrs: spelled ABSOLUTE to a real file → allow (same as design: c3c)"
run_write "$DESIGN_SPECS/k3-8.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 adrs="$ADRS_DIR/real.md")"
assert_eq "adrs_absolute_real exit 0" 0 "$HOOK_EXIT"

echo "k3-8b: …and the design: pointer, spelled absolute in the same spec, agrees"
run_write "$DESIGN_SPECS/k3-8b.spec.md" \
  "$(build_spec section=no design="$DESIGN_SPECS/with-design.spec.md" step=3 adrs="$ADRS_DIR/real.md")"
assert_eq "adrs_and_design_absolute_agree exit 0" 0 "$HOOK_EXIT"

echo "k3-9: sdlc-step 3, adrs: spelled ABSOLUTE to a file that does not exist → block"
run_write "$DESIGN_SPECS/k3-9.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 adrs="$ADRS_DIR/nowhere-abs.md")"
assert_eq "adrs_absolute_dangling exit 2" 2 "$HOOK_EXIT"
assert_contains "adrs_absolute_dangling names the path it could not find" \
  "$ADRS_DIR/nowhere-abs.md" "$HOOK_VSTDERR"

echo "k3-9b: …and the design: pointer, spelled absolute and dangling, blocks the same way"
run_write "$DESIGN_SPECS/k3-9b.spec.md" \
  "$(build_spec section=no design="$DESIGN_SPECS/nowhere-abs.spec.md" step=3)"
assert_eq "design_absolute_dangling exit 2" 2 "$HOOK_EXIT"

echo "k3-10: sdlc-step 3, adrs: spelled ABSOLUTE with a '..' component → still refused (the climb rule is not about the leader)"
run_write "$DESIGN_SPECS/k3-10.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/with-design.spec.md step=3 adrs="$ADRS_DIR/../epic-01-demo/real.md")"
assert_eq "adrs_absolute_dotdot exit 2" 2 "$HOOK_EXIT"

# ============================================================
# AC-13: the pinned-root wall
# ============================================================
#
# AC-10's e2e case above (ac10_e2e_worktree) already pins the frontmatter-
# declaring arm: a canonical *.plan.md written into a worktree's own
# .bionic/ blocks and names the parent repo's docs root. This section covers
# what that arm structurally cannot: an OPERATIONAL artifact (no
# canonical-sdlc frontmatter — a record/ note, exactly the shape this very
# report is written as) written under a non-pinned `.bionic` tree used to
# fall straight through unblocked (the RED capture on disk at
# .bionic/docs/record/w2-s8-pinnedroot-RED.txt). Two wrong-root shapes are
# fixture-real, never mocked: a real `git worktree add` (AC-13's explicit
# demand) and a plain `cd`-into-subdir stray `.bionic` inside the SAME repo
# (no worktree involved at all) — the wall's TARGET_BIONIC/PINNED_BIONIC
# comparison is agnostic to which kind of "wrong tree" it is.
echo
section "AC-13: pinned-root wall"

ac13_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac13_tmp")
ac13_main="$ac13_tmp/main"
mkdir -p "$ac13_main/.bionic/docs/record" "$ac13_main/subdir"
git -C "$ac13_main" init -q .
engage "$ac13_main"
git -C "$ac13_main" commit -q --allow-empty -m init
# Absolute worktree path from the repo root, per .claude/rules/git-worktree-
# docs.md — `git worktree add` resolves relative paths against pwd, not the
# repo root.
git -C "$ac13_main" worktree add -q "$ac13_tmp/wt" -b ac13-wt
ac13_wt="$ac13_tmp/wt"

ac13_record_body='# operational artifact — no canonical-sdlc frontmatter at all'

echo "ac13-1: real worktree — operational write under the worktree's OWN .bionic/ → block, names pinned root"
run_write "$ac13_wt/.bionic/docs/record/w2-s8-ac13.md" "$ac13_record_body"
assert_contains "ac13_wt_write names the pinned root" "Pinned root: $ac13_main/.bionic" "$HOOK_VSTDERR"

echo "ac13-2: paired positive — the IDENTICAL write to the pinned root passes"
run_write "$ac13_main/.bionic/docs/record/w2-s8-ac13.md" "$ac13_record_body"
# AC-4 (wave-session-bound-run): the refusal above was only ever half a wall. Asserted
# here so a hook that learned to refuse EVERYTHING under a `.bionic/` — the regression a
# session-scoped rewrite of this file could plausibly introduce — cannot pass this suite
# on the strength of the negative alone.
assert_eq "ac13-2 (AC-4) the identical write to the PINNED root passes" 0 "$HOOK_EXIT"
assert_eq "ac13-2 (AC-4) ...and says nothing about it" "" "$HOOK_STDERR"

echo "ac13-3: plain cd-into-subdir — a stray .bionic a level down in the SAME repo (no worktree) → block, names pinned root"
# NOT a subshell: run_write sets HOOK_EXIT/HOOK_STDERR as globals the assert
# calls below read, and a `(cd ... && run_write ...)` subshell would strand
# those assignments where the assertions can never see them. cd back
# immediately after, before any other test in this file runs.
ac13_orig_pwd=$(pwd)
cd "$ac13_main/subdir"
run_write "$ac13_main/subdir/.bionic/docs/record/w2-s8-ac13-sub.md" "$ac13_record_body"
cd "$ac13_orig_pwd"
assert_contains "ac13_subdir_write names the pinned root" "Pinned root: $ac13_main/.bionic" "$HOOK_VSTDERR"

echo "ac13-4: paired positive — the IDENTICAL subdir-case write to the pinned root passes"
run_write "$ac13_main/.bionic/docs/record/w2-s8-ac13-sub.md" "$ac13_record_body"

# ---------- ac13-6..9: the wall folds `..` lexically (cs review S-2) ----------
#
# The wall used to compare a path whose `..` segments had never been folded. physicalize()
# resolves only the EXISTING ancestor prefix, so any component that does not yet exist
# strands the rest of the path — its `..` segments included — as an unresolved literal, and
# the `.bionic` the comparison then found was the PINNED one sitting harmlessly at the front
# of the string. The Write tool creates parent directories, so a non-existent segment is no
# obstacle to the write itself: only to the wall seeing where the write lands. Measured
# escape, cs review S-2, with the file landing outside the repository.
#
# The fix folds `.`/`..` lexically before any comparison, which is what
# hooks/dispatch-preflight.sh's resolve_in_repo() already does for the deliverable path —
# two walls in one wave had disagreed about how to resolve a path, and the weaker one was
# the newer one.
#
# A LEXICAL fold is deliberate, not an approximation of realpath: `<symlink>/..` folds to
# the symlink's parent rather than its target's parent. That is the same reading
# resolve_in_repo takes, and for a hygiene wall the question is which tree the path NAMES.

ac13_sibling="$ac13_tmp/other"

echo "ac13-6: traversal through a NON-EXISTENT segment escapes to a sibling .bionic → block"
run_write "$ac13_main/.bionic/nonexistent/../../../other/.bionic/docs/record/w2-r4-esc.md" \
  "$ac13_record_body"
assert_contains "ac13_traversal_missing names the escaped-to tree" \
  "$ac13_sibling/.bionic" "$HOOK_VSTDERR"
assert_contains "ac13_traversal_missing names the pinned root" \
  "Pinned root: $ac13_main/.bionic" "$HOOK_VSTDERR"

echo "ac13-7: the same escape through EXISTING segments (control) still blocks"
# ENGAGED ON THE ENCLOSING TEMP DIRECTORY, because that is the root this path resolves to.
# Every segment on the way out exists, so `..` folds the whole thing down to
# `$ac13_tmp/other/...`, and the nearest real `.bionic` above THAT is none — project_root
# answers `$ac13_tmp`. The marker has to live where the hook will look for it, which is
# the resolved root and never the root the path was written relative to. ac13-6 above
# needs no such line: its missing segment stops the fold at `$ac13_main`, which
# make_project already engaged.
engage "$ac13_tmp"
# The control the cs review used to prove the first case was about resolution, not about
# escaping: identical destination, every segment on the way there real.
run_write "$ac13_main/.bionic/docs/../../../other/.bionic/docs/record/w2-r4-esc2.md" \
  "$ac13_record_body"
assert_contains "ac13_traversal_existing names the escaped-to tree" \
  "$ac13_sibling/.bionic" "$HOOK_VSTDERR"

echo 'ac13-8: paired positive — a climbing path that folds back ONTO the pinned root passes'
# The discriminator against a fix that refuses every climb outright: folding is not
# refusing, and a legitimate write spelled with a climb through a segment that does not
# exist yet — the exact shape ac13-6 escapes through — still lands.
run_write "$ac13_main/.bionic/nonexistent/../docs/record/w2-r4-legit.md" \
  "$ac13_record_body"

echo "ac13-9: a NESTED .bionic inside the pinned tree is a phantom tree too → block"
# DISPOSITION DECIDED HERE (cs review rated this arguably-in-scope; R4 rules it IN).
# `%%` took the SHORTEST prefix, so a path naming a second `.bionic` deeper inside the
# pinned one compared equal to the pinned root and passed. It is the same defect ac13-3
# blocks one directory over: a stray `.bionic` created a level down is a tree nobody
# reads, whether the level down is inside `subdir/` or inside `.bionic/tmp/`. The wall's
# own stated scope — "a stray `.bionic` created a level down inside a subdirectory of the
# main repo" — covers it, and the comparison now takes the DEEPEST `.bionic` segment the
# path names, which is the one the write actually lands in. Cost of the stricter reading:
# a write to a genuinely intended nested `.bionic` is blocked with a message naming where
# to write instead. No such path exists in this repo or in the artifact conventions.
run_write "$ac13_main/.bionic/tmp/scratch/.bionic/docs/record/w2-r4-nested.md" \
  "$ac13_record_body"
assert_contains "ac13_nested names the pinned root" \
  "Pinned root: $ac13_main/.bionic" "$HOOK_VSTDERR"

echo "ac13-10: paired positive — the pinned tree's own operational path is untouched"
# The nested rule must not catch the ordinary write it sits next to.
run_write "$ac13_main/.bionic/tmp/scratch/notes.md" "$ac13_record_body"
assert_eq "ac13_nested_pair exit 0" 0 "$HOOK_EXIT"

echo "ac13-5: canonical (frontmatter-declaring) misplacement is still the AC-10 arm, unchanged — this wall is additive"
run_write "$ac13_wt/.bionic/docs/plans/epic-01-demo/w2-s8-ac13-canon.plan.md" \
  "$(build_plan intent=spike rigor=audited)"
assert_eq "ac13_canonical_still_ac10_arm exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_canonical_still_ac10_arm names the pinned docs root, AC-10's shape" \
  "$ac13_main/.bionic/docs/plans/" "$HOOK_VSTDERR"

echo
section "AC-14: no-git fallback walks up from the TARGET, not the shell"
#
# session-20260812-bionic-root-pin. resolve_project_root()'s no-git fallback used to answer
# `pwd` unconditionally, so a session whose shell cwd sat somewhere else entirely pinned the
# wall to the WRONG project (live repro: .bionic/docs/record/session-20260812-bionic-root-pin/
# ac1-red-live.md). ac14_ws is deliberately never `git init`'d — this is the arm the AC-13
# fixtures above (all real git repos) never exercise.

ac14_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac14_tmp")
ac14_ws="$ac14_tmp/ws"
mkdir -p "$ac14_ws/.bionic/docs/record"
engage "$ac14_ws"
ac14_unrelated="$ac14_tmp/unrelated"
mkdir -p "$ac14_unrelated"
ac14_record_body='# operational artifact — no canonical-sdlc frontmatter at all'

echo "ac14-1 (REPRO): hook cwd in an unrelated dir, Write into the workspace's OWN .bionic/ → exit 0 (walk-up finds the real tree; exit 2 before the fix)"
ac14_orig_pwd=$(pwd)
cd "$ac14_unrelated"
run_write "$ac14_ws/.bionic/docs/record/ac14-repro.md" "$ac14_record_body"
cd "$ac14_orig_pwd"

echo "ac14-2 (CONTAINMENT): same workspace, Write targeting a .bionic one level down that does NOT exist on disk → still exit 2 (phantom tree refused; the pin is ac14_ws, the target names ac14_ws/sub/.bionic)"
ac14_orig_pwd=$(pwd)
cd "$ac14_unrelated"
run_write "$ac14_ws/sub/.bionic/docs/record/ac14-phantom.md" "$ac14_record_body"
cd "$ac14_orig_pwd"
assert_contains "ac14_phantom names the pinned root (the real workspace tree)" \
  "Pinned root: $ac14_ws/.bionic" "$HOOK_VSTDERR"

# ============================================ WALLS: parallel-budget + worktree cwd
# (spec AC-14 and AC-26; plan task WALLS.)
#
# TWO FACTS, one about the header this hook validates and one about where the write
# was made from.
#
# `parallel-budget:` is Step 0's resource ceiling, written into the plan's frontmatter
# from the same probe the preflight attestation records (L-RESOURCES/2). This hook
# neither requires it nor parses it — a plan with it and a plan without it both write.
# The line is READ by hooks/dispatch-preflight.sh, which is where a budget can actually
# refuse something; validating it here would put a second opinion about the same string
# in a second file (assumption WALLS/5).
#
# The worktree arm is the other half of AC-14's pair. A plan is the run's own artifact
# and it lives under the MAIN checkout; a plan write issued from inside a leased tree is
# an orchestrator that has moved into a writer's workspace, and the tree's branch is
# where that edit would land. Refused, naming the main checkout. An agent context is
# allowed — a writer in its own tree that touches the plan is a different question, and
# the ledger discipline, not this wall, is what governs it.

echo
echo "--- WALLS: parallel-budget in the header, and the worktree-cwd arm ---"

# run_write_from <file_path> <content> <cwd> [agent_type] — a Write payload carrying the
# `cwd` field the harness sends, and optionally the `agent_type` a dispatched agent's
# payload carries.
run_write_from() {
  local file_path="$1" content="$2" cwd="$3" atype="${4:-}"
  local input
  input=$(jq -n --arg p "$file_path" --arg c "$content" --arg d "$cwd" --arg a "$atype" --arg s "$GS_SID" \
    '{session_id: $s, tool_name: "Write", cwd: $d, tool_input: {file_path: $p, content: $c}}
     + (if $a == "" then {} else {agent_type: $a} end)')
  local tmp_err
  tmp_err=$(mktemp)
  if HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
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
    HOOK_VSTDERR=$(HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" BIONIC_WALL_VERBOSE=1 \
      bash "$HOOK" <<< "$input" 2>&1 >/dev/null) || true
  fi
  rm -f "$tmp_err"
}

# A fixture project with a real linked worktree under `.worktrees/`. `git worktree add`
# needs a commit to point at, which make_project's bare `git init` does not leave.
walls_project=$(make_project)
git -C "$walls_project" config user.email t@example.com
git -C "$walls_project" config user.name "T"
echo seed > "$walls_project/README.md"
git -C "$walls_project" add README.md
git -C "$walls_project" commit -qm seed
git -C "$walls_project" worktree add -q -b wt/walls-fixture "$walls_project/.worktrees/one" >/dev/null 2>&1
walls_tree="$walls_project/.worktrees/one"
walls_plan="$walls_project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"

# The header, with and without the budget line. Inserted after the opening `---`, which
# is how Step 0 writes it.
WALLS_PLAN_WITH_BUDGET=$(printf '%s' "$VALID_FRONTMATTER" | awk '
  NR == 1 && $0 == "---" { print; print "parallel-budget: writers=22 suites=18 worktrees=32 test_jobs=18 source=probe"; next }
  { print }')

echo "Write: plan header WITHOUT parallel-budget: → allow (unchanged)"
run_write "$walls_plan" "$VALID_FRONTMATTER"
assert_eq "walls-1 a plan with no parallel-budget: writes" 0 "$HOOK_EXIT"

echo "Write: plan header WITH parallel-budget: → allow"
run_write "$walls_plan" "$WALLS_PLAN_WITH_BUDGET"
assert_eq "walls-2 a plan carrying parallel-budget: writes" 0 "$HOOK_EXIT"
assert_eq "walls-2b …and the hook says nothing about it" "" "$HOOK_STDERR"

echo "Write: plan write with the main checkout as cwd → allow (the control)"
run_write_from "$walls_plan" "$WALLS_PLAN_WITH_BUDGET" "$walls_project"
assert_eq "walls-3 a plan write from the main checkout passes" 0 "$HOOK_EXIT"

echo "Write: plan write whose cwd is inside the linked worktree → block"
run_write_from "$walls_plan" "$WALLS_PLAN_WITH_BUDGET" "$walls_tree"
assert_eq "walls-4 a plan write from inside a linked worktree is refused" 2 "$HOOK_EXIT"
assert_contains "walls-4b …naming the main checkout" "main checkout: $walls_project" "$HOOK_VSTDERR"
assert_contains "walls-4c …and the tree it came from" "$walls_tree" "$HOOK_VSTDERR"

echo "Write: the same write from an agent context → allow"
run_write_from "$walls_plan" "$WALLS_PLAN_WITH_BUDGET" "$walls_tree" "senior-implementor"
assert_eq "walls-5 an agent context writing from its own tree is allowed" 0 "$HOOK_EXIT"

echo "Write: a non-plan artifact from a worktree cwd → allow (the arm is plan-scoped)"
run_write_from "$walls_project/.bionic/docs/specs/epic-01-demo/wave-01-x.spec.md" \
  "$VALID_SPEC_FRONTMATTER" "$walls_tree"
assert_eq "walls-6 a spec write from a worktree cwd is not this arm's business" 0 "$HOOK_EXIT"

# ============================================================
# AC-7: the session never invoked the skill — every clause of the disjunction
# ============================================================
#
# Chris, 2026-09-03: "all guardrails imposed by bionic should only apply when exercising
# bionic. Nothing should apply until bionic is triggered." This wall is armed by the
# PROJECT rather than by a run, through a four-clause disjunction — an open run under the
# root, a `.bionic/` tree at the root, a target path inside one, or content declaring
# `canonical_sdlc_version:` outside the docs root. Every one of those can be true in a
# session that never invoked the skill; a bystander editing a plan in a repo where
# somebody else ran a wave was the reproduction. So engagement is asked FIRST and each
# clause below is driven twice: without the marker, and with it.
#
# WHAT THE TWO HALVES PROVE, precisely. The marker-less half isolates a clause: the
# fixture is built so that clause is what would arm the wall, and the wall says nothing.
# The marker-present half is a CONTROL on the same fixture, and it does not isolate
# anything — planting the marker creates `.bionic/tmp`, so clause 2 is true in every
# engaged project by construction. That is the design, not a fixture accident: engagement
# creates the tree it records itself in, and the disjunction's later clauses only ever
# mattered for a project that had none.

echo
section "AC-7: no engagement marker → silent on every clause of the project disjunction"

AC7_BAD_PLAN=$(build_plan intent=definitely-not-an-intent)

ac7_silent() {  # <label> — asserts on the last run_write
  if [ "$HOOK_EXIT" -eq 0 ] && [ -z "$HOOK_STDERR" ]; then
    ok "$1"
  else
    no "$1" "exit=$HOOK_EXIT stderr=$HOOK_STDERR"
  fi
}

ac7_refused() {  # <label> — the control on the same fixture, marker restored
  expect_eq "$1" 2 "$HOOK_EXIT"
}

# --- clause 1: an OPEN RUN under this root ---
ac7_p1=$(make_project)
mkdir -p "$ac7_p1/.bionic/docs/plans/epic-01-demo"
printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in flight\n' \
  > "$ac7_p1/.bionic/docs/plans/epic-01-demo/open.plan.md"
unengage "$ac7_p1"
run_write "$ac7_p1/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_silent "ac7 clause 1 (open run): an invalid triple passes an unengaged session"
engage "$ac7_p1"
run_write "$ac7_p1/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_refused "ac7 clause 1 control: the same write, marker restored, is REFUSED"

# --- clause 2: a `.bionic/` TREE at this root, and no run in it ---
ac7_p2=$(make_project)
unengage "$ac7_p2"
run_write "$ac7_p2/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_silent "ac7 clause 2 (.bionic tree, no run): an invalid triple passes an unengaged session"
engage "$ac7_p2"
run_write "$ac7_p2/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_refused "ac7 clause 2 control: the same write, marker restored, is REFUSED"

# --- clause 3: the FIRST-ARTIFACT case — the target is inside a `.bionic/` that does
# not exist yet, which is the one clause that arms this wall in a project with no tree.
ac7_p3=$(make_bare_project)
unengage "$ac7_p3"
rm -rf "$ac7_p3/.bionic"
run_write "$ac7_p3/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_silent "ac7 clause 3 (path inside a .bionic that does not exist): passes an unengaged session"
if [ -d "$ac7_p3/.bionic" ]; then
  no "ac7 clause 3 ...and creates no tree on the way past"
else
  ok "ac7 clause 3 ...and creates no tree on the way past"
fi
engage "$ac7_p3"
run_write "$ac7_p3/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_refused "ac7 clause 3 control: the same write, marker planted, is REFUSED"

# --- clause 4: SELF-DECLARING CONTENT outside the docs root — the misplacement wall ---
ac7_p4=$(make_bare_project)
unengage "$ac7_p4"
rm -rf "$ac7_p4/.bionic"
mkdir -p "$ac7_p4/notes"
run_write "$ac7_p4/notes/rogue.plan.md" "$(build_plan)"
ac7_silent "ac7 clause 4 (canonical_sdlc_version: outside the docs root): passes an unengaged session"
engage "$ac7_p4"
run_write "$ac7_p4/notes/rogue.plan.md" "$(build_plan)"
ac7_refused "ac7 clause 4 control: the same write, marker planted, is REFUSED as misplaced"

# --- the shapes that are NOT engagement, on a fixture that otherwise refuses ---
ac7_p5=$(make_project)
unengage "$ac7_p5"
ln -s "$ac7_p1/.bionic/tmp/engaged-$GS_SID.state" "$ac7_p5/.bionic/tmp/engaged-$GS_SID.state"
run_write "$ac7_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_silent "ac7 a SYMLINK at the marker path is not engagement"
rm -f "$ac7_p5/.bionic/tmp/engaged-$GS_SID.state"

: > "$ac7_p5/.bionic/tmp/engaged-deadbeef-0000-0000-0000-000000000000.state"
run_write "$ac7_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN"
ac7_silent "ac7 another session's marker is not engagement"

# THE MARKER IS READ UNDER THE ARTIFACT'S ROOT, not the invoking session's cwd. Engaging
# a DIFFERENT project does not arm this wall over ac7_p5's artifact.
run_write_from "$ac7_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$AC7_BAD_PLAN" "$ac7_p1"
ac7_silent "ac7 engagement in the cwd's project does not arm the wall over another project's artifact"

echo
section "AC-9: bind-on-write, and the run verdict this hook now reads"

# WHY THIS SECTION EXISTS (wave-session-bound-run, 2026-09-04). Until this wave every
# hook answered "which run am I in" by scanning the project root for the newest plan, so
# two engaged sessions in one repository shared one run identity. The binding is what
# separates them, and the act that CREATES a run is the first Write of its plan file —
# which this hook is already delivered on. So this hook gained a second event: at
# PostToolUse it binds the writing session to the plan it just created, and at
# PreToolUse it reads the session's own verdict rather than the root's.
#
# THE BIND ARM RUNS AT PostToolUse, NOT PreToolUse, and the reason is a hard one: at
# PreToolUse the plan file does not exist yet, `open_runs` cannot list it, and
# `bind_plan` — which refuses any path that is not a member of the open-run set at the
# instant of the write — would refuse every binding this arm exists to make. The
# invariant "a bound path is a member of the open-run set at write time" is only
# satisfiable after the tool has run.

# A PostToolUse payload. `tool_response` is the field that distinguishes a Write that
# CREATED a file from one that overwrote an existing one: transcript evidence on this
# machine (2026-09-04, 17 Write results joined to their tool_use ids across the six most
# recent session transcripts) shows Write reporting `type: "create"` or `type: "update"`
# and Edit reporting no `type` key at all. NONE drives the field-absent fallback.
HOOK_STDOUT=""
# THE FOURTH ARGUMENT IS THE DEPTH. An agent-context payload carries a top-level `agent_id`
# alongside the DISPATCHING session's `session_id` (hooks/agent-context-guard.sh's partition
# rests on exactly that); a main-thread payload has no such key. Empty means main thread.
# THE FIFTH ARGUMENT IS THE SESSION'S OWN CWD (wave-18-fixit-185, REQ-2). Real PostToolUse
# payloads carry `.cwd`, and since D5 the bind arm resolves the plan against the root the
# SESSION engaged under rather than the root walked up from the artifact — so a fixture that
# posts no cwd is exercising the second rung of that resolution, not the first. Empty (every
# pre-existing call site) posts no `cwd` key at all, which is the shape those rows were
# written against. `GS_POST_HOME` moves HOME for the one row whose project IS $HOME.
GS_POST_HOME=""
run_post() {  # <tool> <file-path> <tool_response.type|NONE> [agent_id] [cwd]
  local tool="$1" file_path="$2" rtype="$3" agent="${4:-}" cwd="${5:-}"
  local input
  input=$(jq -n \
    --arg p "$file_path" \
    --arg s "$GS_SID" \
    --arg t "$tool" \
    --arg r "$rtype" \
    --arg a "$agent" \
    --arg c "$cwd" \
    '{session_id: $s,
      hook_event_name: "PostToolUse",
      tool_name: $t,
      tool_input: {file_path: $p, content: ""},
      tool_response: (if $r == "NONE" then {filePath: $p} else {type: $r, filePath: $p} end)}
     + (if $a == "" then {} else {agent_id: $a} end)
     + (if $c == "" then {} else {cwd: $c} end)')
  local tmp_err tmp_out
  tmp_err=$(mktemp); tmp_out=$(mktemp)
  if HOME="${GS_POST_HOME:-$FAKE_HOME}" CLAUDE_CODE_SESSION_ID="$GS_SID" \
     CLAUDE_PROJECT_DIR="" bash "$HOOK" <<< "$input" >"$tmp_out" 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDOUT=$(cat "$tmp_out")
  HOOK_STDERR=$(cat "$tmp_err")
  # THE SAME CALL AGAIN, WITH THE KNOB (task 13, ruling D-1): the values this suite
  # reads off the refusal are `detail` now. Guarded on the refusal and `|| true` because
  # the suite runs under `set -e` and the hook exits 2 when it refuses.
  HOOK_VSTDERR=""
  if [ "$HOOK_EXIT" -ne 0 ]; then
    HOOK_VSTDERR=$(HOME="${GS_POST_HOME:-$FAKE_HOME}" CLAUDE_CODE_SESSION_ID="$GS_SID" \
      CLAUDE_PROJECT_DIR="" BIONIC_WALL_VERBOSE=1 \
      bash "$HOOK" <<< "$input" 2>&1 >/dev/null) || true
  fi
  rm -f "$tmp_out" "$tmp_err"
}

# THE DURABLE HALF OF EVERY DECLINE (AC-2.1). `log_finding` puts the line on stderr AND
# appends it under $HOME, and the journal is the half that outlives the session — so every
# exit row below reads both, and a line that only ever reached stderr would fail here.
journal_of() {  # <project root> -> the audit file the hook's findings land in
  printf '%s/.claude/logs/%s/sdlc-audit.md' "${GS_POST_HOME:-$FAKE_HOME}" "$(slug_for "$1")"
}
journal_has() {  # <project root> <substring> -> yes|no
  local f; f="$(journal_of "$1")"
  [ -f "$f" ] || { echo no; return 0; }
  if /usr/bin/grep -qF -- "$2" "$f"; then echo yes; else echo no; fi
}

marker_plan() {  # <project> → the marker's `plan=` value; empty when absent or unbound
  local f="$1/.bionic/tmp/engaged-$GS_SID.state"
  [ -f "$f" ] || return 0
  sed -n 's/^plan=//p' "$f" | head -1
}

marker_lines() {  # <project> → the marker's line count; 0 when absent
  local f="$1/.bionic/tmp/engaged-$GS_SID.state"
  [ -f "$f" ] || { echo 0; return 0; }
  wc -l < "$f" | tr -d ' '
}

# An OPEN run: Step 4, nothing delivered. A CLOSED one: Step 9 with the delivery line
# `run_open` reads. Both carry the flush-left `## SDLC State` heading that makes a file a
# plan to the whole fleet.
open_plan_body()   { printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 4\n\n- Step 4: in flight\n'; }
closed_plan_body() { printf -- '---\ncanonical_sdlc_version: 14\n---\n\n## SDLC State\n\ncurrent: 9\n\n- Step 9: close-out delivered: yes\n'; }

# plant_plan <abs-path> <open|closed> — the file the tool would have left behind.
plant_plan() {
  mkdir -p "$(dirname "$1")"
  if [ "$2" = open ]; then open_plan_body > "$1"; else closed_plan_body > "$1"; fi
}

# --- b1: an unbound engaged session's Write of a new open plan binds ---
b_p=$(make_project)
b_plans="$b_p/.bionic/docs/plans/epic-01-demo"
b_a="$b_plans/wave-01-a.plan.md"
plant_plan "$b_a" open
run_post Write "$b_a" create
assert_eq "b1 an unbound session binds to the plan it just wrote" "$b_a" "$(marker_plan "$b_p")"
assert_eq "b1 ...exit 0" 0 "$HOOK_EXIT"
assert_eq "b1 ...no decision JSON on stdout" "" "$HOOK_STDOUT"
assert_contains "b1 ...and says so" "governing-skill: session bound to $b_a" "$HOOK_STDERR"
assert_eq "b1 ...marker keeps its two-line shape" 2 "$(marker_lines "$b_p")"

# --- b2 (T4): a session bound to an OLDER open plan REBINDS to the new one ---
b_b="$b_plans/wave-02-b.plan.md"
plant_plan "$b_b" open
run_post Write "$b_b" create
assert_eq "b2 (T4) a bound session rebinds to a newly written open plan" "$b_b" "$(marker_plan "$b_p")"
assert_contains "b2 ...and names the new path" "session bound to $b_b" "$HOOK_STDERR"

# --- b3: a session bound to a DELIVERED plan binds to the new one ---
# The stale binding is planted by hand: `bind_plan` refuses a closed plan, so this state
# is only reachable the way it happens in the field — a plan that was open when the
# session bound to it and has since been delivered.
b_done="$b_plans/wave-00-done.plan.md"
plant_plan "$b_done" closed
bound_marker "$b_p" "$GS_SID" "$b_done"
b_c="$b_plans/wave-03-c.plan.md"
plant_plan "$b_c" open
run_post Write "$b_c" create
assert_eq "b3 a session bound to a delivered plan binds to the new open one" "$b_c" "$(marker_plan "$b_p")"

# --- b4: a Write of a plan that reads CLOSED leaves the binding alone ---
b_closed="$b_plans/wave-04-closed.plan.md"
plant_plan "$b_closed" closed
run_post Write "$b_closed" create
assert_eq "b4 a plan that reads closed does not become a binding" "$b_c" "$(marker_plan "$b_p")"
# SILENT UNTIL wave-18-fixit-185 (REQ-2 AC-2.1). The decline is the library's word for it,
# not a sentence this hook composes: `bind_plan` refuses a path `open_runs` does not list
# and now says WHICH refusal that was.
assert_contains "b4 ...and the decline names the open-run set" "bind]: not-an-open-run" "$HOOK_STDERR"
assert_contains "b4 ...and names the path it declined" "$b_closed" "$HOOK_STDERR"
assert_eq "b4 ...and the journal keeps it" "yes" "$(journal_has "$b_p" "bind: not-an-open-run")"
assert_eq "b4 ...exit 0" 0 "$HOOK_EXIT"

# --- b5: an Edit is never a bind trigger ---
run_post Edit "$b_a" NONE
assert_eq "b5 an Edit of an open plan leaves the binding alone" "$b_c" "$(marker_plan "$b_p")"
assert_eq "b5 ...exit 0" 0 "$HOOK_EXIT"

# --- b6: only plans/ and incidents/ bind; record/ and specs/ do not ---
b_rec="$b_p/.bionic/docs/record/wave-01/notes.md"
plant_plan "$b_rec" open
run_post Write "$b_rec" create
assert_eq "b6 a record/ file carrying ## SDLC State does not bind" "$b_c" "$(marker_plan "$b_p")"
b_spec="$b_p/.bionic/docs/specs/epic-01-demo/wave-01.spec.md"
plant_plan "$b_spec" open
run_post Write "$b_spec" create
assert_eq "b6 a specs/ file carrying ## SDLC State does not bind" "$b_c" "$(marker_plan "$b_p")"
# …and since wave-18-fixit-185 it says which half of the docs tree it wanted (AC-2.1).
assert_contains "b6 ...and names the two directories that bind" \
  "bind]: not under plans/ or incidents/ of $b_p/.bionic/docs" "$HOOK_STDERR"
assert_eq "b6 ...and the journal keeps it" "yes" \
  "$(journal_has "$b_p" "bind: not under plans/ or incidents/")"

# --- b6b: incidents/ binds, on the same footing as plans/ ---
b_inc="$b_p/.bionic/docs/incidents/0002-thing/incident.plan.md"
plant_plan "$b_inc" open
run_post Write "$b_inc" create
assert_eq "b6b an incidents/ plan binds" "$b_inc" "$(marker_plan "$b_p")"

# --- b7: an UNENGAGED session neither binds nor leaves a marker behind ---
b_u=$(make_project)
b_u_plan="$b_u/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md"
plant_plan "$b_u_plan" open
unengage "$b_u"
run_post Write "$b_u_plan" create
assert_eq "b7 an unengaged session does not bind" "" "$(marker_plan "$b_u")"
assert_eq "b7 ...and no marker is created" 0 "$(marker_lines "$b_u")"
assert_eq "b7 ...exit 0" 0 "$HOOK_EXIT"
assert_contains "b7 ...and says the engagement is what is missing" \
  "bind]: engagement absent under $b_u" "$HOOK_STDERR"
assert_eq "b7 ...and the journal keeps it" "yes" "$(journal_has "$b_u" "bind: engagement absent")"

# --- b8: PostToolUse NEVER blocks, not even on a plan this hook would refuse ---
# The same content at PreToolUse is exit 2 (invalid `intent:`), which is the control
# below. PostToolUse cannot block — the tool has already run — so the arm reports by
# binding and nothing else.
b_bad=$(make_project)
b_bad_plan="$b_bad/.bionic/docs/plans/epic-01-demo/wave-01-bad.plan.md"
# A plan the PreToolUse wall refuses (invalid `intent:`) that is nonetheless a real open
# run — the `## SDLC State` block is what `open_runs` reads, and the frontmatter is what
# the wall reads. The two questions are independent, and this case is where that shows.
b_bad_body="$(build_plan intent=definitely-not-an-intent)
## SDLC State

current: 4

- Step 4: in flight"
mkdir -p "$(dirname "$b_bad_plan")"
printf '%s\n' "$b_bad_body" > "$b_bad_plan"
run_post Write "$b_bad_plan" create
assert_eq "b8 PostToolUse never blocks, even on a plan the wall would refuse" 0 "$HOOK_EXIT"
assert_eq "b8 ...no decision JSON on stdout" "" "$HOOK_STDOUT"
assert_eq "b8 ...and it still binds" "$b_bad_plan" "$(marker_plan "$b_bad")"
run_write "$b_bad_plan" "$b_bad_body"
assert_eq "b8 control: the same content at PreToolUse is still refused" 2 "$HOOK_EXIT"

# --- b9: an OVERWRITE (tool_response.type = update) is not a new run ---
b_ov=$(make_project)
b_ov_plan="$b_ov/.bionic/docs/plans/epic-01-demo/wave-01-ov.plan.md"
plant_plan "$b_ov_plan" open
run_post Write "$b_ov_plan" update
assert_eq "b9 a Write that overwrote an existing file does not bind" "" "$(marker_plan "$b_ov")"
assert_contains "b9 ...and names the result type it read" \
  "bind]: the write updated an existing file (tool_response.type=update)" "$HOOK_STDERR"
assert_eq "b9 ...and the journal keeps it" "yes" "$(journal_has "$b_ov" "bind: the write updated")"

# --- b10: a payload with no `type` at all still binds (the documented fallback) ---
run_post Write "$b_ov_plan" NONE
assert_eq "b10 a tool_response with no type field binds" "$b_ov_plan" "$(marker_plan "$b_ov")"

# --- b11: a path under plans/ that is NOT a plan (no ## SDLC State) does not bind ---
b_np="$b_ov/.bionic/docs/plans/epic-01-demo/notes.md"
printf '# just notes\n\ncurrent: 4\n' > "$b_np"
run_post Write "$b_np" create
assert_eq "b11 a plans/ file with no ## SDLC State does not bind" "$b_ov_plan" "$(marker_plan "$b_ov")"

# --- b13: a DISPATCHED AGENT's Write never moves its dispatcher's binding (S10a, A-2/F5) ---
#
# An agent-context payload carries the ORCHESTRATOR's `session_id`, which is the only key
# this arm ever read — so a subagent drafting the next wave's plan, or a Step-9 close-out
# writer, silently re-pointed the live orchestrator at the file it had just created, and the
# orchestrator's evidence gate then gated its commits on that plan. T4 ratified rebinding for
# the main thread; nothing extended it to depth two, and the roster's own rule is that only
# depth-one dispatches are recorded.
#
# THE TWO CALLS DIFFER BY ONE FIELD. Same project, same plan, same `create` — so a pass here
# cannot come from the fixture failing to be bindable in the first place.
b_ag=$(make_project)
b_ag_plan="$b_ag/.bionic/docs/plans/epic-01-demo/wave-01-agent.plan.md"
plant_plan "$b_ag_plan" open
run_post Write "$b_ag_plan" create "agent_01ABCdefGHIjklMNOpqrs"
assert_eq "b13 a payload carrying agent_id does not bind" "" "$(marker_plan "$b_ag")"
assert_eq "b13 ...and creates no marker at all" 0 "$(marker_lines "$b_ag")"
assert_eq "b13 ...exit 0" 0 "$HOOK_EXIT"
assert_contains "b13 ...and names the partition it declined on" \
  "bind]: a dispatched agent's write never rebinds its dispatcher" "$HOOK_STDERR"
assert_eq "b13 ...and the journal keeps it" "yes" \
  "$(journal_has "$b_ag" "bind: a dispatched agent")"
run_post Write "$b_ag_plan" create
assert_eq "b13 paired: the same Write from the main thread DOES bind" "$b_ag_plan" "$(marker_plan "$b_ag")"
assert_contains "b13 paired: ...and says so" "session bound to $b_ag_plan" "$HOOK_STDERR"
# ...and an agent's Write cannot MOVE a binding that already exists either, which is the
# harmful case: the orchestrator is mid-run and the subagent writes the NEXT wave's plan.
b_ag2="$b_ag/.bionic/docs/plans/epic-01-demo/wave-02-next.plan.md"
plant_plan "$b_ag2" open
run_post Write "$b_ag2" create "agent_01ABCdefGHIjklMNOpqrs"
assert_eq "b13 an agent writing a SECOND plan leaves the live binding where it was" \
  "$b_ag_plan" "$(marker_plan "$b_ag")"

# --- b12: a file the Write did not actually leave on disk does not bind ---
b_gone="$b_ov/.bionic/docs/plans/epic-01-demo/wave-99-gone.plan.md"
run_post Write "$b_gone" create
assert_eq "b12 a target that does not exist on disk does not bind" "$b_ov_plan" "$(marker_plan "$b_ov")"
assert_contains "b12 ...and says the file is not there" \
  "bind]: the written file is not on disk" "$HOOK_STDERR"
assert_eq "b12 ...and the journal keeps it" "yes" "$(journal_has "$b_ov" "bind: the written file is not on disk")"

echo
echo "--- the shapes that used to bind nothing and say nothing (AC-2.1, AC-2.3, AC-2.4) ---"

# WHY THESE SEVEN AND NOT OTHERS (epic-23 wave-18-fixit-185, REQ-2; research R4 §1.3). Every
# bind fixture above this line is `make_project`: one plain root, one git repository, no
# worktree, no symlinked `.bionic`, no `docs-root:` override, no `$HOME` root, and — until
# now — no task-scale plan anywhere in the file (`grep -n 'current: T' ` returned nothing).
# The shapes a consumer reported silence on were precisely the untested ones, and four of
# them reproduce the silence in fifteen scratch fixtures. So they come in here, each one
# asserting THE LINE IT NOW PRINTS, because an instrumentation change nobody asserts is a
# comment: the row is what makes the sentence a wall.
#
# TWO OF THE SEVEN BIND RATHER THAN DECLINE, and that is the D5 fix itself — the arm resolves
# the write against the root the SESSION engaged under, so a project that is `$HOME` and a
# plan written through a linked worktree of the engaged root both reach `bind_plan` now
# instead of being lost to a second root walked up from the artifact.

gs_git_repo() {  # <dir> -> an initialised repo with one commit, so `git worktree add` works
  mkdir -p "$1"
  git -C "$1" init -q .
  git -C "$1" -c user.email=t@example.invalid -c user.name=bionic-test \
    commit -q --allow-empty -m init
}
gs_sandbox() {  # -> a fresh physical directory, cleaned up with the rest
  local d; d=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$d"); printf '%s' "$d"
}

# --- s1: the project IS a linked git worktree ---
#
# `project_root` maps a linked worktree onto its MAIN repository before it walks (root.sh:246),
# so the plan under the worktree's own `.bionic/` resolves to a root that does not contain it.
# The arm cannot bind it — `open_runs` of the engaged root does not list a file in another
# tree — but it can say so, which is the whole of REQ-2.
s1_base=$(gs_sandbox)
s1_main="$s1_base/main"
s1_wt="$s1_base/18-T1"
gs_git_repo "$s1_main"
git -C "$s1_main" worktree add -q -b wt/18-T1 "$s1_wt"
engage "$s1_main"
s1_plan="$s1_wt/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
plant_plan "$s1_plan" open
run_post Write "$s1_plan" create "" "$s1_wt"
assert_contains "s1 a plan under a linked worktree's own .bionic names the engaged root" \
  "bind]: outside the engaged root $s1_main" "$HOOK_STDERR"
assert_eq "s1 ...and binds nothing" "" "$(marker_plan "$s1_main")"
assert_eq "s1 ...and the journal keeps it" "yes" \
  "$(journal_has "$s1_main" "bind: outside the engaged root")"
assert_eq "s1 ...exit 0" 0 "$HOOK_EXIT"

# --- s2: the project is NESTED INSIDE a linked worktree ---
s2_base=$(gs_sandbox)
s2_main="$s2_base/main"
s2_wt="$s2_base/18-T2"
gs_git_repo "$s2_main"
git -C "$s2_main" worktree add -q -b wt/18-T2 "$s2_wt"
engage "$s2_main"
s2_plan="$s2_wt/child/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
mkdir -p "$s2_wt/child/.bionic/docs/plans/epic-01-demo"
plant_plan "$s2_plan" open
run_post Write "$s2_plan" create "" "$s2_wt/child"
assert_contains "s2 a project nested inside a worktree names the engaged root too" \
  "bind]: outside the engaged root $s2_main" "$HOOK_STDERR"
assert_eq "s2 ...and binds nothing" "" "$(marker_plan "$s2_main")"

# --- s3: the project's `.bionic` is a SYMLINK ---
#
# The walk refuses to choose a root whose `.bionic` is a link (root.sh:276), and `bind_plan`
# refuses to write a marker under one (binding.sh, the marker-path guard). The session is
# engaged through the link, so the arm gets all the way to the writer and reports the
# writer's own word for the refusal — which is what AC-2.2 is for.
s3_base=$(gs_sandbox)
s3_proj="$s3_base/proj"
s3_store="$s3_base/store"
mkdir -p "$s3_store/docs/plans/epic-01-demo" "$s3_store/tmp"
gs_git_repo "$s3_proj"
ln -s "$s3_store" "$s3_proj/.bionic"
: > "$s3_proj/.bionic/tmp/engaged-$GS_SID.state"
s3_plan="$s3_proj/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
plant_plan "$s3_plan" open
run_post Write "$s3_plan" create "" "$s3_proj"
assert_contains "s3 a symlinked .bionic reports the marker-directory refusal by name" \
  "bind]: marker-dir-symlink" "$HOOK_STDERR"
assert_eq "s3 ...and binds nothing" "" "$(marker_plan "$s3_proj")"
assert_eq "s3 ...and the journal keeps it" "yes" "$(journal_has "$s3_proj" "bind: marker-dir-symlink")"

# --- s4: a `docs-root:` override, with the plan written to the DEFAULT path ---
s4_p=$(make_project)
printf 'docs-root: alt\n' > "$s4_p/.bionic/config.yaml"
mkdir -p "$s4_p/alt/plans/epic-01-demo"
s4_plan="$s4_p/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
plant_plan "$s4_plan" open
run_post Write "$s4_plan" create "" "$s4_p"
assert_contains "s4 an override names both roots, so the misplacement is readable" \
  "bind]: the engaged root's docs root is $s4_p/alt, not $s4_p/.bionic/docs" "$HOOK_STDERR"
assert_eq "s4 ...and binds nothing" "" "$(marker_plan "$s4_p")"
assert_eq "s4 ...and the journal keeps it" "yes" "$(journal_has "$s4_p" "bind: the engaged root's docs root")"
# the pair, one argument apart: the same plan written UNDER the configured root binds.
s4_right="$s4_p/alt/plans/epic-01-demo/wave-01.plan.md"
plant_plan "$s4_right" open
run_post Write "$s4_right" create "" "$s4_p"
assert_eq "s4 paired: the same plan under the configured root binds" "$s4_right" "$(marker_plan "$s4_p")"

# --- s5: the project root IS `$HOME` (D5: it binds now) ---
#
# `project_root` never CHOOSES a root at or above `$HOME` (root.sh:274), so the walk from the
# artifact ended in a fallback that was not a bionic root at all and the write was lost. The
# session's own root is the marker's, and the marker is right there.
# NOT A GIT REPOSITORY, which is what makes the row reproduce the reported silence. With a
# repo the walk's `git-toplevel-fallback` lands back on the project by luck; without one it
# falls through to `cwd-fallback`, and the cwd it falls back to is the ARTIFACT's directory —
# a "root" three levels inside the docs tree, where no marker has ever been written. That is
# research R4's fixture L, and the session's own root is the answer to it.
s5_base=$(gs_sandbox)
s5_home="$s5_base/home"
mkdir -p "$s5_home/.bionic/docs/plans/epic-01-demo" "$s5_home/.bionic/tmp"
: > "$s5_home/.bionic/tmp/engaged-$GS_SID.state"
s5_plan="$s5_home/.bionic/docs/plans/epic-01-demo/wave-01.plan.md"
plant_plan "$s5_plan" open
GS_POST_HOME="$s5_home"
run_post Write "$s5_plan" create "" "$s5_home"
GS_POST_HOME=""
assert_eq "s5 a project that IS \$HOME binds its own plan" "$s5_plan" "$(marker_plan "$s5_home")"
assert_contains "s5 ...and says so" "governing-skill: session bound to $s5_plan" "$HOOK_STDERR"

# --- s6: a task-scale plan in a root with twelve other open runs BINDS ---
#
# The charter named both conditions as suspects and research R4 refuted both; this row is
# what keeps them refuted. `current: T<n>` is an open run (run.sh's task-scale arm) and
# twelve siblings cost the walk 0.46 s against a 10 s budget.
s6_p=$(make_project)
for s6_i in 01 02 03 04 05 06 07 08 09 10 11 12; do
  plant_plan "$s6_p/.bionic/docs/plans/epic-01-demo/wave-$s6_i-open.plan.md" open
done
s6_plan="$s6_p/.bionic/docs/plans/epic-51-exam-cache/task-07-thing.plan.md"
mkdir -p "$(dirname "$s6_plan")"
printf -- '---\ncanonical_sdlc_version: 14\nscale: task\n---\n\n## SDLC State\n\ncurrent: T3\n\n- T3: in flight\n' \
  > "$s6_plan"
run_post Write "$s6_plan" create "" "$s6_p"
assert_eq "s6 a task-scale plan among twelve open runs BINDS" "$s6_plan" "$(marker_plan "$s6_p")"
assert_contains "s6 ...and says so" "governing-skill: session bound to $s6_plan" "$HOOK_STDERR"
assert_eq "s6 ...exit 0" 0 "$HOOK_EXIT"

# --- s7 (AC-2.4): a Write through a LINKED WORKTREE of the engaged root binds the run ---
#
# The D5 case, and the one this arm rewrites a path for: the session engaged under R, and the
# plan it wrote is R's plan reached through R's worktree, whose `.bionic/` is a tree of its own
# because `.bionic/` is gitignored and never checked out. The marker's `plan=` must be R's.
s7_base=$(gs_sandbox)
s7_main="$s7_base/main"
s7_wt="$s7_base/18-T3"
s7_rel=".bionic/docs/plans/epic-01-demo/wave-01.plan.md"
gs_git_repo "$s7_main"
engage "$s7_main"
plant_plan "$s7_main/$s7_rel" open
git -C "$s7_main" worktree add -q -b wt/18-T3 "$s7_wt"
plant_plan "$s7_wt/$s7_rel" open
run_post Write "$s7_wt/$s7_rel" create "" "$s7_wt"
assert_eq "s7 (AC-2.4) a Write from a linked worktree binds the ENGAGED ROOT's plan" \
  "$s7_main/$s7_rel" "$(marker_plan "$s7_main")"
assert_contains "s7 ...and names the engaged root's spelling, not the worktree's" \
  "governing-skill: session bound to $s7_main/$s7_rel" "$HOOK_STDERR"
assert_eq "s7 ...and the worktree grew no marker of its own" 0 "$(marker_lines "$s7_wt")"

echo
echo "--- the PreToolUse verdict: fallback, bound, and bound-closed ---"

# AC-3: an unbound session still resolves by newest plan, and SAYS which resolution it
# used. Two open plans, distinct mtimes, so the newest is not a coin toss.
v_p=$(make_project)
v_plans="$v_p/.bionic/docs/plans/epic-01-demo"
plant_plan "$v_plans/wave-01-old.plan.md" open
plant_plan "$v_plans/wave-02-new.plan.md" open
touch -t 202601010000 "$v_plans/wave-01-old.plan.md"
touch -t 202602010000 "$v_plans/wave-02-new.plan.md"
v_probe="$v_p/.bionic/docs/record/probe.md"
run_write "$v_probe" '# operational note'
assert_contains "v1 an unbound session announces the newest-plan fallback" \
  "governing-skill: run resolved by newest-plan fallback (session unbound) — $v_plans/wave-02-new.plan.md" \
  "$HOOK_STDERR"
assert_eq "v1 ...and passes" 0 "$HOOK_EXIT"

bound_marker "$v_p" "$GS_SID" "$v_plans/wave-01-old.plan.md"
run_write "$v_probe" '# operational note'
expect_absent "v2 a BOUND session never announces a fallback" "fallback" "$HOOK_STDERR"

# AC-6: a binding is a commitment. The bound plan is delivered and the OTHER plan in this
# root is wide open — the session still has no run, and is told why rather than being
# handed somebody else's.
plant_plan "$v_plans/wave-01-old.plan.md" closed
run_write "$v_probe" '# operational note'
assert_contains "v3 a session bound to a closed plan is told, and never falls through" \
  "governing-skill: bound plan closed — $v_plans/wave-01-old.plan.md; this session has no open run" \
  "$HOOK_STDERR"
assert_eq "v3 ...and still passes" 0 "$HOOK_EXIT"

# v4 (epic-23 wave-14 T17): THE VERDICT FOLLOWS THE ARTIFACT'S ROOT, NEVER THE SESSION'S.
#
# WHAT THIS REFUSES, AND WHY IT IS WORTH A ROW OF ITS OWN. `bionic_context` can compute a
# run verdict for a caller that asks (`BIONIC_CONTEXT_WANT_RUN=1`), and three hooks do —
# hooks/stop.sh, hooks/dispatch-preflight.sh, hooks/session-start.sh. It resolves against
# `BIONIC_ROOT`, which is the SESSION's cwd. This hook resolves against
# `PROJECT_ROOT_FROM_PATH`, which is the ARTIFACT's own root, and its header says why in
# as many words: "a hook that scoped itself by the session's cwd and enforced against the
# artifact's root would go quiet exactly where it was added to bind." The two look
# interchangeable in every fixture where the session sits in the project it is writing to,
# which is most of them — so the swap is a plausible-looking latency cut that would pass
# this whole suite except here. Two projects, one plan each, the write aimed at one and
# the session sitting in the other: only the artifact's plan may be named.
v_art=$(make_project)
v_cwd=$(make_project)
plant_plan "$v_art/.bionic/docs/plans/epic-01-demo/wave-11-artifact.plan.md" open
plant_plan "$v_cwd/.bionic/docs/plans/epic-01-demo/wave-22-cwd.plan.md" open
run_write_from "$v_art/.bionic/docs/record/probe.md" '# operational note' "$v_cwd"
assert_contains "v4 the run verdict names the ARTIFACT's plan"   "$v_art/.bionic/docs/plans/epic-01-demo/wave-11-artifact.plan.md" "$HOOK_STDERR"
expect_absent "v4 ...and never the plan of the project the session happens to sit in"   "wave-22-cwd.plan.md" "$HOOK_STDERR"
assert_eq "v4 ...and passes" 0 "$HOOK_EXIT"

section "K5/AC-K5.1: *.requirements.md gets the frontmatter contract, minus the design rule"

# K5: requirements.md is the Step-1 artifact (design ledger K5; ADR-001), living beside the
# spec under specs/epic-NN-<slug>/. It gets the SAME frontmatter contract *.spec.md gets —
# but never the three-way design rule (that arm's own case statement keys on *.spec.md only).
k5_p=$(make_project)
k5_req="$k5_p/.bionic/docs/specs/epic-01-demo/wave-01-x.requirements.md"

echo "k5a: requirements.md with no frontmatter → block"
run_write "$k5_req" '# Requirements body, no frontmatter'
assert_eq "k5a exit 2" 2 "$HOOK_EXIT"
assert_contains "k5a names the missing frontmatter block" "missing a YAML frontmatter block" "$HOOK_VSTDERR"

echo "k5b: requirements.md with the full valid contract → allow"
run_write "$k5_req" "$VALID_FRONTMATTER"
assert_eq "k5b exit 0" 0 "$HOOK_EXIT"
assert_eq "k5b silent" "" "$HOOK_STDERR"

echo "k5c: the SAME frontmatter (no '## Design', no 'design:' pointer, no waiver) written to a" \
     ".spec.md path would block on the design wall (proven in the design-wall section above)" \
     "— written to .requirements.md instead it is allowed: the design rule never fires here"
run_write "$k5_req" "$(build_plan)"
assert_eq "k5c exit 0 (design rule not applied to a requirements file)" 0 "$HOOK_EXIT"
assert_eq "k5c silent" "" "$HOOK_STDERR"

# k5d: this wave's own requirements.md is the exemplar shape (design ledger K5; the brief
# says "copy it into a fixture and assert that"). Frontmatter copied byte-for-byte from
# .bionic/docs/specs/epic-22-plugin-only/wave-01-plugin-only.requirements.md (gitignored,
# machine-local — not a path this hermetic suite can read live, so the fixture is a literal
# copy rather than a dynamic read). K5.4 (mid-wave, landed after k5d was first written):
# the real file's own opening picked up a '## Goal' section between the title and
# "## Requirements and acceptance criteria" — this fixture is updated to match, so k5d
# keeps proving "the real artifact passes the arm as-is" against the ARM'S CURRENT SHAPE,
# K5.4's included, rather than a shape the real file no longer has.
K5_EXEMPLAR_FRONTMATTER='---
governing-skill: agent-skills:idea-refine
sdlc-step: 1
intent: build
rigor: audited
scale: wave
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-medium; auditor=opus-high; critic=opus-high
created: 2026-09-07
---

# bionic 1.6.0 — plugin-only · requirements (epic-22 wave-01)

## Goal

Ship bionic 1.6.0 as a plugin a stranger can install and trust: one source renders every skill
and canon passage, the version lives in one place, dependent plugins stop falling out of the
registry, known doctor and setup bugs are fixed, walls print one line, and the lifecycle shows the
user settings at Step 0, the contract at Step 3, and the premise before the build.

## Requirements and acceptance criteria

**REQ-K5 — Three artifacts, three steps.**
- AC-K5.1 The governing-skill hook validates '"'"'*.requirements.md'"'"' frontmatter under '"'"'specs/'"'"'.'
echo "k5d: this wave's own requirements.md is the exemplar shape and must pass the arm as-is"
k5_real_target="$k5_p/.bionic/docs/specs/epic-01-demo/real.requirements.md"
run_write "$k5_real_target" "$K5_EXEMPLAR_FRONTMATTER"
assert_eq "k5d exit 0 on the real wave-01 requirements doc's frontmatter" 0 "$HOOK_EXIT"
assert_eq "k5d silent" "" "$HOOK_STDERR"

# ============================================================
# K5.4/AC-K5.4: the goal-paragraph rule (design ledger K5.4)
# ============================================================
#
# Chris 2026-09-07 ~14:45 PT, "Option 2 - but make it: opens with a CONCISE goal
# description in one paragraph": each of requirements.md, spec.md and plan.md opens with
# a '## Goal' section — one concise paragraph — first after the title.
#
# SCALE DECISION (recorded here and in the hook's own comment): the arm is wave|epic
# only, matching the design wall and the Verification Matrix wall in this same hook —
# at `scale: task` there is no three-artifact shape to hold open (Step 1-3 collapse into
# ONE session plan with a '## Tasks' ledger), so a task-scale plan is untouched (k54-4).
echo
section "K5.4/AC-K5.4: the goal-paragraph rule"

k54_p=$(make_project)

echo "k54-1: plan.md, wave scale, no '## Goal' at all → block, naming Goal and the file"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/w1.plan.md" "$(build_plan goal=no)"
assert_eq "k54_plan_no_goal exit 2" 2 "$HOOK_EXIT"
assert_contains "k54_plan_no_goal names Goal" "'## Goal'" "$HOOK_STDERR"
assert_contains "k54_plan_no_goal names the file" "w1.plan.md" "$HOOK_VSTDERR"

echo "k54-2: plan.md, wave scale, '## Goal' present with a real paragraph → allow"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/w2.plan.md" "$(build_plan goal=yes)"
assert_eq "k54_plan_with_goal exit 0" 0 "$HOOK_EXIT"
assert_eq "k54_plan_with_goal silent" "" "$HOOK_STDERR"

echo "k54-3: plan.md, wave scale, '## Goal' present but EMPTY (heading, no paragraph) → block"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/w3.plan.md" "$(build_plan goal=empty)"
assert_eq "k54_plan_empty_goal exit 2" 2 "$HOOK_EXIT"
assert_contains "k54_plan_empty_goal names the empty section" "'Goal' section is empty" "$HOOK_VSTDERR"

echo "k54-4: plan.md, TASK scale, no Goal at all → allow (arm inert — no three-artifact shape at task scale)"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/w4.plan.md" "$(build_plan goal=no scale=task matrix=no)"
assert_eq "k54_plan_task_untouched exit 0" 0 "$HOOK_EXIT"
assert_eq "k54_plan_task_untouched silent" "" "$HOOK_STDERR"

echo "k54-5: plan.md, EPIC scale, no Goal → block (epic gets the arm too, not just wave)"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/w5.plan.md" "$(build_plan goal=no scale=epic)"
assert_eq "k54_plan_epic_scoped exit 2" 2 "$HOOK_EXIT"

echo "k54-6: spec.md, wave scale, no Goal (Design present) → block on Goal — proven independent of the design wall"
run_write "$k54_p/.bionic/docs/specs/epic-01-demo/w6.spec.md" "$(build_spec goal=no section=yes)"
assert_eq "k54_spec_no_goal exit 2" 2 "$HOOK_EXIT"
assert_contains "k54_spec_no_goal names Goal" "'## Goal'" "$HOOK_STDERR"

echo "k54-7: spec.md, wave scale, Goal present + Design present → allow (both walls satisfied)"
run_write "$k54_p/.bionic/docs/specs/epic-01-demo/w7.spec.md" "$(build_spec goal=yes section=yes)"
assert_eq "k54_spec_with_goal exit 0" 0 "$HOOK_EXIT"
assert_eq "k54_spec_with_goal silent" "" "$HOOK_STDERR"

echo "k54-8: spec.md, wave scale, Goal EMPTY + Design present → block on the empty Goal, not the design wall"
run_write "$k54_p/.bionic/docs/specs/epic-01-demo/w8.spec.md" "$(build_spec goal=empty section=yes)"
assert_eq "k54_spec_empty_goal exit 2" 2 "$HOOK_EXIT"
assert_contains "k54_spec_empty_goal names the empty section" "'Goal' section is empty" "$HOOK_VSTDERR"

echo "k54-9: requirements.md, wave scale, no Goal → block (requirements gets the arm too)"
run_write "$k54_p/.bionic/docs/specs/epic-01-demo/w9.requirements.md" "$(build_plan goal=no)"
assert_eq "k54_req_no_goal exit 2" 2 "$HOOK_EXIT"

echo "k54-10: requirements.md, wave scale, Goal present → allow"
run_write "$k54_p/.bionic/docs/specs/epic-01-demo/w10.requirements.md" "$(build_plan goal=yes)"
assert_eq "k54_req_with_goal exit 0" 0 "$HOOK_EXIT"

echo "k54-11: continuation.md, no Goal → allow (untouched — never one of the three artifacts)"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/continuation.md" "$(build_plan goal=no)"
assert_eq "k54_continuation_untouched exit 0" 0 "$HOOK_EXIT"

echo "k54-12: adr-*.md, no Goal → allow (untouched — an ADR has no three-artifact shape)"
run_write "$k54_p/.bionic/docs/adrs/epic-01-demo/adr-099-x.md" "$(build_plan goal=no)"
assert_eq "k54_adr_untouched exit 0" 0 "$HOOK_EXIT"

echo "k54-13: a write to record/ (operational, never enforced), no Goal, no frontmatter at all → allow untouched"
run_write "$k54_p/.bionic/docs/record/k54-note.md" '# an operational note, no canonical-sdlc frontmatter at all'
assert_eq "k54_record_untouched exit 0" 0 "$HOOK_EXIT"

# --- exemplar fixtures: this wave's own three artifacts, as-shipped ---
#
# The brief: "This wave's three artifacts already comply — each opens with `## Goal` —
# and are your exemplar fixtures ... copy each into a fixture and assert the arm accepts
# them." k5d above already covers requirements.md (K5_EXEMPLAR_FRONTMATTER, updated for
# K5.4). The two below cover spec.md and plan.md. All three real files open with the
# SAME Goal paragraph, word for word — copied here once and reused, rather than retyped
# three times where a copy-paste slip could quietly diverge.
K54_GOAL_PARA='Ship bionic 1.6.0 as a plugin a stranger can install and trust: one source renders every skill
and canon passage, the version lives in one place, dependent plugins stop falling out of the
registry, known doctor and setup bugs are fixed, walls print one line, and the lifecycle shows the
user settings at Step 0, the contract at Step 3, and the premise before the build.'

# spec.md exemplar: frontmatter + title + Goal copied from
# .bionic/docs/specs/epic-22-plugin-only/wave-01-plugin-only.spec.md (gitignored,
# machine-local, same reason k5d's copy is literal). The real file's design wall is
# satisfied by an in-place '## Design' section (not reproduced here — this fixture is
# about the Goal arm, not the design wall, which tasks 16/17/18 already cover in depth);
# a waiver substitutes, the same pattern SPEC_DESIGN_WAIVER already uses above for
# fixtures that are not about design.
K54_SPEC_EXEMPLAR='---
governing-skill: agent-skills:spec-driven-development
sdlc-step: 2
intent: build
rigor: audited
scale: wave
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-medium; auditor=opus-high; critic=opus-high
requirements: specs/epic-22-plugin-only/wave-01-plugin-only.requirements.md
'"$SPEC_DESIGN_WAIVER"'
created: 2026-09-07
---

# bionic 1.6.0 — plugin-only · specification (epic-22 wave-01)

## Goal

'"$K54_GOAL_PARA"'

## Context and Problem

As ratified in the requirements document (§Context, §Problem); they travel into the PR body at Step 8.
'

echo "k54-14: this wave's own spec.md opening (title + '## Goal' + the shared paragraph) → allow"
run_write "$k54_p/.bionic/docs/specs/epic-01-demo/real.spec.md" "$K54_SPEC_EXEMPLAR"
assert_eq "k54_spec_exemplar exit 0" 0 "$HOOK_EXIT"
assert_eq "k54_spec_exemplar silent" "" "$HOOK_STDERR"

# plan.md exemplar: frontmatter + title + Goal copied from
# .bionic/docs/plans/epic-22-plugin-only/wave-01-plugin-only.plan.md (same gitignored-copy
# reasoning). sdlc-step 3 needs a '## Verification Matrix' section (the wall above this
# one) — a minimal stub stands in for the real 60-row matrix, which is not this fixture's
# subject.
K54_PLAN_EXEMPLAR='---
governing-skill: superpowers:writing-plans
sdlc-step: 3
intent: build
rigor: audited
scale: wave
canonical_sdlc_version: 14
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-1; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-medium; auditor=opus-high; critic=opus-high
requirements: specs/epic-22-plugin-only/wave-01-plugin-only.requirements.md
spec: specs/epic-22-plugin-only/wave-01-plugin-only.spec.md
created: 2026-09-07
---

# bionic 1.6.0 — plugin-only · implementation plan (epic-22 wave-01)

## Goal

'"$K54_GOAL_PARA"'

## Verification Matrix

stack-health: n/a: no long-running serve observed

| AC | tier | status | evidence | auditor |
|---|---|---|---|---|
| AC-1 | T1 | discharged | see AC-1 | CONFIRMED |
'

echo "k54-15: this wave's own plan.md opening (title + '## Goal' + the shared paragraph) → allow"
run_write "$k54_p/.bionic/docs/plans/epic-01-demo/real.plan.md" "$K54_PLAN_EXEMPLAR"
assert_eq "k54_plan_exemplar exit 0" 0 "$HOOK_EXIT"
assert_eq "k54_plan_exemplar silent" "" "$HOOK_STDERR"

echo "AC-E1.3/E1.5: every refusal is one line, in the criterion's shape"

# fails-when: a refusal reaches the user as more than one line, or in any shape but
# `bionic: <verb> refused — <fact> (<fix ≤ 40 cols>)`. The counters below were filled by
# every refusal the sections above produced, through the two main drivers.
assert_eq "E1.3 the wall refused many times in this run (not counting over air)" "yes" \
  "$([ "$GS_E1_SEEN" -ge 30 ] && echo yes || echo no)"
assert_eq "E1.3 every refusal matched the criterion's shape" "" "$GS_E1_BAD_SHAPE"
assert_eq "E1.3 every refusal was exactly one line" "" "$GS_E1_BAD_LINES"
assert_eq "E1.3 every refusal fitted the 100-column budget" "" "$GS_E1_BAD_COLS"

# THE TABLE'S EXACT WORDING at two sites, one direct and one through the `block` frame.
gs_e1_project=$(make_project)
run_write "$gs_e1_project/.bionic/docs/plans/epic-01-demo/badver.plan.md" "$(build_plan version=99)"
assert_eq "E1.3 row 89 (an unsupported version) is the table's line" \
  "bionic: write refused — this artifact declares an unsupported version (set the supported version)" \
  "$(printf '%s\n' "$HOOK_STDERR" | /usr/bin/grep '^bionic: ')"
assert_contains "E1.5 …and the value found is in the detail, behind the knob" \
  "canonical_sdlc_version: '99'" "$HOOK_VSTDERR"
assert_eq "E1.5 …with the one line still first" \
  "bionic: write refused — this artifact declares an unsupported version (set the supported version)" \
  "$(printf '%s\n' "$HOOK_VSTDERR" | /usr/bin/grep -m1 '^bionic: ')"

# ============================================================
section "REQ-1e AC-1e.5: the Step-3 wall on the '## Tasks' table"
# ============================================================
#
# fails-when: a plan whose Tasks table has an unknown status, a dangling dep, or a
# missing column is written at sdlc-step >= 3.
#
# THE WALL IS THE PLAN SIDE OF WHAT units.sh OWNS. The evidence gate catches a broken
# table at COMMIT time, which is one round trip and a refused commit too late: the
# orchestrator has already briefed writers off it. This arm runs `units_validate` on the
# content being written, at the same step boundary and the same scale carve-out as the
# Verification Matrix arm above — the table is a Step-3 artifact, and a task-scale plan
# carries the five-column registration ledger instead, which this schema does not widen.
#
# AN ABSENT TABLE IS NOT A VIOLATION HERE. A plan mid-authoring may not have written its
# table yet, and the D7 PRESENCE rule already lives in the evidence gate at commit time
# (validate_dispatch_ledger). This arm judges a table that is there.

gs_1e_project=$(make_project)
gs_1e_plan="$gs_1e_project/.bionic/docs/plans/epic-01-demo/tasks.plan.md"

# A valid ten-column table, and the three fixtures AC-1e.5 names, each one cell away
# from it. Appended to build_plan's body, which already satisfies every other arm.
gs_tasks_good='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 5 | verify | the verify | auditor | T1 | 30m | REQ-x | b.sh | pending |
'
gs_tasks_bad_status="${gs_tasks_good/| b.sh | pending |/| b.sh | doing |}"
gs_tasks_dangling="${gs_tasks_good/| auditor | T1 |/| auditor | T99 |}"
gs_tasks_missing_col='
## Tasks

| id | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|
| T1 | build | the build | implementor | — | 30m | REQ-x | a.sh | landed |
'

echo "1e.5a: a valid Tasks table at sdlc-step 3 → allow"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_good"
assert_eq "1e.5a exit 0" 0 "$HOOK_EXIT"
assert_eq "1e.5a silent" "" "$HOOK_STDERR"

echo "1e.5b: a status nobody defines → refused, naming the id and the rule"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_bad_status"
assert_eq "1e.5b exit 2" 2 "$HOOK_EXIT"
assert_contains "1e.5b the detail names the offending id" "T2" "$HOOK_VSTDERR"
assert_contains "1e.5b …and the rule it broke" "status doing is not one of" "$HOOK_VSTDERR"

echo "1e.5c: a dep naming no row → refused, naming the dep"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_dangling"
assert_eq "1e.5c exit 2" 2 "$HOOK_EXIT"
assert_contains "1e.5c the detail names the dangling dep" "T99" "$HOOK_VSTDERR"

echo "1e.5d: a header short of the ten columns → refused, naming the column"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_missing_col"
assert_eq "1e.5d exit 2" 2 "$HOOK_EXIT"
assert_contains "1e.5d the detail names the absent column" "missing column step" "$HOOK_VSTDERR"

echo "1e.5e: the same broken table at sdlc-step 2 → allow (the wall opens at 3)"
run_write "$gs_1e_plan" "$(build_plan step=2 matrix=no)$gs_tasks_bad_status"
assert_eq "1e.5e exit 0" 0 "$HOOK_EXIT"

echo "1e.5f: a task-scale plan is out of scope (its ledger is the five-column one)"
run_write "$gs_1e_plan" "$(build_plan scale=task matrix=no)$gs_tasks_bad_status"
assert_eq "1e.5f exit 0" 0 "$HOOK_EXIT"

# 1e.5h/1e.5i — THE `worktree` COLUMN (wave-14 REQ-2, ADR-027). The dispatcher writes the
# tree it created into the row, so the Step-3 write-time wall has to accept a plan that
# carries the cell. It is OPTIONAL: this wall must neither refuse a plan for carrying it nor
# refuse the far larger set of plans that do not.
gs_tasks_worktree='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30m | REQ-x | a.sh | 14-T1 | landed |
| T2 | 5 | verify | the verify | auditor | T1 | 30m | REQ-x | b.sh | — | pending |
'
gs_tasks_worktree_bad="${gs_tasks_worktree/| b.sh | — | pending |/| b.sh | — | doing |}"

echo "1e.5h: an eleven-column table carrying worktree at sdlc-step 3 → allow"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_worktree"
assert_eq "1e.5h exit 0" 0 "$HOOK_EXIT"
assert_eq "1e.5h silent" "" "$HOOK_STDERR"

echo "1e.5i: …and the wall still reads the status cell past the new column (not shifted)"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_worktree_bad"
assert_eq "1e.5i exit 2" 2 "$HOOK_EXIT"
assert_contains "1e.5i the detail names the offending id" "T2" "$HOOK_VSTDERR"
assert_contains "1e.5i …and the rule it broke" "status doing is not one of" "$HOOK_VSTDERR"

# 1e.5j/1e.5k — AN ACTIVE ROW NAMES ITS TREE (wave-17 REQ-1, AC-1.2, ADR-032). The register
# the evidence gate reads is written HERE, at the Step-3 write, and through wave-16 every row
# of every plan this repo shipped left the cell at `—` — so the gate's row arm was never
# reached and a writer's commit was judged at the run's step (research R1). The fault belongs
# at the write, not at the writer's commit a round trip later, and this is the same
# `units_validate` call the evidence gate makes: one rule, two doors.
gs_tasks_wt_active="${gs_tasks_worktree/| b.sh | — | pending |/| b.sh | — | active |}"

echo "1e.5j: an ACTIVE row with no tree in its cell → refused, naming the id and the rule"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_wt_active"
assert_eq "1e.5j exit 2" 2 "$HOOK_EXIT"
assert_contains "1e.5j the detail names the offending id and the rule" \
  "T2: active row names no worktree" "$HOOK_VSTDERR"

echo "1e.5k: …and the SAME empty cell on a pending row is still allowed (1e.5h is the control)"
run_write "$gs_1e_plan" "$(build_plan)$gs_tasks_worktree"
assert_eq "1e.5k exit 0" 0 "$HOOK_EXIT"
assert_eq "1e.5k silent" "" "$HOOK_STDERR"

echo "1e.5g: a plan with no Tasks table at all → allow (presence is the gate's rule)"
run_write "$gs_1e_plan" "$(build_plan)"
assert_eq "1e.5g exit 0" 0 "$HOOK_EXIT"
assert_eq "1e.5g silent" "" "$HOOK_STDERR"

# ============================================================
section "REQ-8 AC-8.1/AC-8.4: on an Edit the Tasks arm judges the POST-EDIT body"
# ============================================================
#
# fails-when: an Edit REPAIRING a broken Tasks table is refused, an Edit BREAKING a valid one
# is admitted, or an Edit the tool itself cannot apply is refused by this arm.
#
# THE DEADLOCK THIS REPLACES (wave-14 A-T21.4). `$CONTENT` on an Edit used to be the file AS
# IT STANDS, so the arm judged the PRE-edit text. Two consequences, both wrong and in
# opposite directions: the Edit that repaired a broken table was refused by the very fault it
# repaired — leaving a whole-file Write as the only way out of a one-character typo — and the
# Edit that broke a valid table passed, to be caught a round trip later at commit.
#
# THE BROKEN TABLE IS THE RAW-PIPE ONE, so this section, tests/units.test.sh §9b and the
# evidence gate's 22e5 are pinned to one fault, one repair and one message.
#
# THE ARM IS NOT SIMPLY OFF FOR EDITS — that would pass every repair case here by doing
# nothing. 8.1b, 8.1c and 8.1e are the discriminators: each is an Edit whose POST-edit body is
# the only thing that could refuse it.

gs_8_project=$(make_project)
gs_8_plan="$gs_8_project/.bionic/docs/plans/epic-01-demo/edit.plan.md"

# A raw `|` in T2's agent cell opens a field the header does not have. The repair is the one
# escape a GFM cell defines.
gs_tasks_raw='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 5 | verify | do b | a raw | pipe | T1 | S | REQ-x | b.sh | pending |
'
gs_tasks_repaired="${gs_tasks_raw/| a raw | pipe |/| a raw \\| pipe |}"

echo "8.1a: an Edit that REPAIRS a broken Tasks table → allow (the deadlock is gone)"
printf '%s\n' "$(build_plan)$gs_tasks_raw" > "$gs_8_plan"
run_edit "$gs_8_plan" 'a raw | pipe' 'a raw \| pipe'
assert_eq "8.1a exit 0" 0 "$HOOK_EXIT"
assert_eq "8.1a silent" "" "$HOOK_STDERR"

echo "8.1b: an Edit that BREAKS a valid Tasks table → refused, naming the pipe"
printf '%s\n' "$(build_plan)$gs_tasks_repaired" > "$gs_8_plan"
run_edit "$gs_8_plan" 'a raw \| pipe' 'a raw | pipe'
assert_eq "8.1b exit 2" 2 "$HOOK_EXIT"
assert_contains "8.1b the detail names the row and both counts" \
  "T2: 12 cells for 11 columns" "$HOOK_VSTDERR"
assert_contains "8.1b …and the repair" "escape it as" "$HOOK_VSTDERR"

echo "8.1c: the post-edit read is general, not raw-pipe-shaped — a status an Edit invents"
printf '%s\n' "$(build_plan)$gs_tasks_repaired" > "$gs_8_plan"
run_edit "$gs_8_plan" '| b.sh | pending |' '| b.sh | doing |'
assert_eq "8.1c exit 2" 2 "$HOOK_EXIT"
assert_contains "8.1c the detail names the status the edit would have written" \
  "status doing is not one of" "$HOOK_VSTDERR"

echo "8.1d: the control — the same broken table by Write is refused as it always was"
run_write "$gs_8_plan" "$(build_plan)$gs_tasks_raw"
assert_eq "8.1d exit 2" 2 "$HOOK_EXIT"
assert_contains "8.1d …naming the same fault" "T2: 12 cells for 11 columns" "$HOOK_VSTDERR"

echo "8.1e: replace_all applies to EVERY occurrence — two broken rows, one Edit → allow"
gs_tasks_raw2='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 4 | build | do b | a raw | pipe | T1 | S | REQ-x | b.sh | landed |
| T3 | 5 | verify | do c | a raw | pipe | T1, T2 | S | REQ-x | c.sh | pending |
'
printf '%s\n' "$(build_plan)$gs_tasks_raw2" > "$gs_8_plan"
run_edit "$gs_8_plan" 'a raw | pipe' 'a raw \| pipe' true
assert_eq "8.1e exit 0" 0 "$HOOK_EXIT"
assert_eq "8.1e silent — a hook that replaced only the first would still see a broken row" \
  "" "$HOOK_STDERR"

echo "8.1f: …and replace_all in the other direction breaks both rows → refused, naming both"
gs_tasks_repaired2="${gs_tasks_raw2//| a raw | pipe |/| a raw \\| pipe |}"
printf '%s\n' "$(build_plan)$gs_tasks_repaired2" > "$gs_8_plan"
run_edit "$gs_8_plan" 'a raw \| pipe' 'a raw | pipe' true
assert_eq "8.1f exit 2" 2 "$HOOK_EXIT"
assert_contains "8.1f the detail names the first shifted row" "T2: 12 cells" "$HOOK_VSTDERR"
assert_contains "8.1f …and the second" "T3: 12 cells" "$HOOK_VSTDERR"

# ---------- 8.1g/8.1h: the post-edit substitution keeps `&` byte-exact (review R1 fold-in) ----
#
# `old_string` here IS the raw pipe from `gs_tasks_raw` ('a raw | pipe'), so an unquoted
# replacement that mishandles a `&` in `new_string` does not just misspell the cell — under
# bash's `patsub_replacement` (5.2+) an unquoted `&` expands to the WHOLE matched text, i.e.
# `old_string` itself, which reintroduces the very raw pipe this Edit is repairing. That makes
# the substitution bug and the table's validity the SAME observable: correct behaviour repairs
# the table (exit 0, silent) and the bug leaves it broken (exit 2, "12 cells for 11 columns"),
# with no need to read $CONTENT directly.
#
# gs_r1_new deliberately contains a literal `&` and no `|` of its own, so the row it produces is
# valid ONLY when `&` survives untouched.
gs_r1_new='no pipe & safe'

echo "8.1g: bash 3.2.57 — & in new_string survives; positive pair, correct before and after R1"
printf '%s\n' "$(build_plan)$gs_tasks_raw" > "$gs_8_plan"
run_edit "$gs_8_plan" 'a raw | pipe' "$gs_r1_new" false /bin/bash
assert_eq "8.1g exit 0" 0 "$HOOK_EXIT"
assert_eq "8.1g silent — the repair lands, & untouched on 3.2.57" "" "$HOOK_STDERR"

GS_BASH52=""
if GS_BASH52=$(gs_find_bash52); then
  echo "8.1h: bash >= 5.2 ($GS_BASH52) — & in new_string must survive byte-exact (patsub_replacement)"
  printf '%s\n' "$(build_plan)$gs_tasks_raw" > "$gs_8_plan"
  run_edit "$gs_8_plan" 'a raw | pipe' "$gs_r1_new" false "$GS_BASH52"
  assert_eq "8.1h exit 0" 0 "$HOOK_EXIT"
  assert_eq "8.1h silent — an unquoted replacement would splice the old pipe back in and refuse this" \
    "" "$HOOK_STDERR"
else
  # A-T20.1: this harness has no skip idiom (grep -n 'skip\|SKIP' tests/lib/assert.sh finds
  # none), so the row is recorded `ok` with the reason in its own label rather than silently
  # omitted — a suite with fewer TOTAL rows on one machine than another is exactly the drift
  # the roster-is-the-directory rule (test-harness.md) exists to prevent.
  ok "8.1h: skip: no bash >= 5.2 on this machine"
fi

# ---------- AC-8.4: an Edit this hook cannot apply is not this hook's to refuse ----------
#
# The Edit tool fails on its own for an `old_string` that is absent or not unique. A wall that
# refused first would be asserting a fault nobody committed (ADR-028) and would re-open the
# deadlock through the back door: every one of these files is BROKEN, and refusing here would
# again be refusing an edit for a fault it is not making.

echo "8.4a: an Edit whose old_string is absent → the arm is skipped, allow"
printf '%s\n' "$(build_plan)$gs_tasks_raw" > "$gs_8_plan"
run_edit "$gs_8_plan" 'no such text anywhere in this plan' 'whatever'
assert_eq "8.4a exit 0" 0 "$HOOK_EXIT"
assert_eq "8.4a silent" "" "$HOOK_STDERR"

echo "8.4b: an Edit whose old_string is not unique and carries no replace_all → skipped, allow"
printf '%s\n' "$(build_plan)$gs_tasks_raw2" > "$gs_8_plan"
run_edit "$gs_8_plan" 'a raw | pipe' 'a raw \| pipe'
assert_eq "8.4b exit 0" 0 "$HOOK_EXIT"
assert_eq "8.4b silent" "" "$HOOK_STDERR"

# The live wave plan's own table is pinned hermetically by fixture 22e1 in
# tests/canonical-sdlc-evidence-gate.test.sh, not read off disk here: `.bionic/` is
# machine-local and absent from a fresh clone, so a fixture reading it would degrade to a
# vacuous pass on exactly the machines this arm protects (Section 38f's rule).

# ============================================================
section "R2 — AC-2.1: the invalid-Tasks Write refusal carries the offending row, knob UNSET (ADR-030)"
# ============================================================
#
# WHAT THIS SECTION EXISTS FOR (seed A §8a, carry-over 8, research R2 row 4). The
# AC-1e.5 section above drives this same wall and reads the offending id — out of
# `$HOOK_VSTDERR`, the second drive, taken with `BIONIC_WALL_VERBOSE=1`. Under ruling D-1
# the drive a real Write gets printed one sentence, so an orchestrator repairing its own
# plan learned that the table was invalid and not which row, and this suite could not see
# that because every one of its detail assertions reads the verbose stream (research R2's
# seam-blindness row). ADR-030 flips the `exit2` channel's field 9; the runner below reads
# the stream the CLI actually delivers.
#
# ITS OWN RUNNER, ON PURPOSE: `run_write` sets `$HOOK_VSTDERR` from a second drive with the
# knob, which is the seam this section is about. One drive, the knob removed from the
# environment rather than merely unset in it, and the whole stream kept.
#
# fails-when: the refusal prints one line with the knob unset, or the violation list names
# no row.
# [REQ-2 AC-2.3 KNOB-UNSET SECTION: BEGIN]
GS_R2_EXIT=0; GS_R2_ERR=""
r2_write_knob_unset() {  # <path> <content> -> GS_R2_EXIT + GS_R2_ERR
  local file_path="$1" content="$2" input tmp_err
  input=$(jq -n --arg p "$file_path" --arg c "$content" --arg s "$GS_SID" \
    '{session_id: $s, tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  tmp_err=$(mktemp)
  if env -u BIONIC_WALL_VERBOSE HOME="$FAKE_HOME" CLAUDE_CODE_SESSION_ID="$GS_SID" \
       bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    GS_R2_EXIT=0
  else
    GS_R2_EXIT=$?
  fi
  GS_R2_ERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}
require_helpers r2_write_knob_unset

gs_r2_project=$(make_project)
gs_r2_plan="$gs_r2_project/.bionic/docs/plans/epic-01-demo/r2.plan.md"
gs_r2_tasks='
## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the build | implementor | — | 30m | REQ-x | a.sh | landed |
| T2 | 5 | verify | the verify | auditor | T1 | 30m | REQ-x | b.sh | doing |
'
r2_write_knob_unset "$gs_r2_plan" "$(build_plan)$gs_r2_tasks"

expect_status "R2a an invalid Tasks table is still refused at Write, fail-closed" "2" "$GS_R2_EXIT"
expect_eq "R2b …and the verdict is the first rendered line, unchanged" \
  "bionic: write refused — this plan's Tasks table is invalid (fix the row the detail names)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R2c …with the offending row named behind it (AC-2.1)" \
  "T2: status doing is not one of pending active landed dropped" "$GS_R2_ERR"
expect_contains "R2d …and the Fix prose that names the columns" \
  "repair each row named above" "$GS_R2_ERR"
expect_eq "R2e …so the stream is no longer the one line the defect shipped" "no" \
  "$([ "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -c .)" = "1" ] && echo yes || echo no)"
expect_eq "R2f …and still exactly one rendered refusal line, not two" "1" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -c '^bionic: ')"

# THE OTHER DIRECTION: the same plan with the status repaired is written in silence, so
# R2c read a refusal rather than a hook that talks on every Write.
r2_write_knob_unset "$gs_r2_plan" "$(build_plan)${gs_r2_tasks/| b.sh | doing |/| b.sh | pending |}"
expect_status "R2g the repaired table is allowed" "0" "$GS_R2_EXIT"
expect_empty "R2h …and prints nothing" "$GS_R2_ERR"
# [REQ-2 AC-2.3 KNOB-UNSET SECTION: END]


# ============================================================
section "R3 — AC-3.1: the Write wall names every version-14 fault at once"
# ============================================================
#
# ONE ROUND TRIP EARLIER THAN THE GATE (research R2 open question 4). This wall sees the
# plan being EDITED, so it is where a bring-forward can be priced before a commit is ever
# attempted. Under 1.8.2 it asked one question — is the `## Tasks` table valid — and the
# other five version-14 faults waited for the evidence gate to meet them one at a time.
#
# THE SAME PREDICATE, THE SAME LIST. `plan_bring_forward` is one function in
# `payload/scripts/lib/walls.sh` and both callers print what it returns, so this section
# and the evidence-gate suite's `[REQ-3 BRING-FORWARD SECTION]` assert the same six
# strings. A list that differed between the two would mean a writer repaired what the Write
# wall named and then met a fault the gate had kept to itself.
#
# KNOB UNSET, for research R2's seam-blindness reason: the list rides `detail`, and under
# `BIONIC_WALL_VERBOSE=1` it would ride it either way (A-T4.2).
#
# fails-when: the pre-14 Write prints fewer than six classes, or more than one refusal line.
# [REQ-3 BRING-FORWARD SECTION: BEGIN]
gs_r3_body='
## SDLC State

current: 5
Step 1: opened 2026-09-19T22:00Z; research record/w16/r.md
Step 5: cmd bash tests/run.sh; pass 9; total 9

## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | audited | the dispatched unit | done |
'
gs_r3_plan="$(build_plan step=5 goal=no)"
gs_r3_plan="${gs_r3_plan/multi_agent: false/multi_agent: true}"
gs_r3_project=$(make_project)
gs_r3_path="$gs_r3_project/.bionic/docs/plans/epic-01-demo/r3.plan.md"
r2_write_knob_unset "$gs_r3_path" "${gs_r3_plan}${gs_r3_body}"

expect_status "R3a the pre-14 plan Write is refused, fail-closed" "2" "$GS_R2_EXIT"
expect_eq "R3b …once: exactly one rendered refusal line" "1" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -c '^bionic: ')"
expect_eq "R3c …and the verdict names the contract version, not one arm" \
  "bionic: write refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3d(1) …the Tasks table's absent columns, named together on one line" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$GS_R2_ERR"
expect_contains "R3d(2) …the wave-scale status vocabulary" \
  "T1: status done is not one of pending active landed dropped" "$GS_R2_ERR"
expect_contains "R3d(3) …the Step-1 requirements pointer" \
  "## SDLC State: the Step 1 evidence names no 'requirements:' pointer" "$GS_R2_ERR"
expect_contains "R3d(4) …the approval line" \
  "## SDLC State: no 'approved-by:' line" "$GS_R2_ERR"
expect_contains "R3d(5) …the matrix's fails-when" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$GS_R2_ERR"
expect_contains "R3d(6) …and the missing Goal section" \
  "## Goal: the first section is not '## Goal'" "$GS_R2_ERR"

# THE OTHER DIRECTION, and the pin that keeps the arm narrow: a plan whose table is at the
# ten-column contract but carries ONE broken row still gets 1.8.2's own refusal, verbatim.
# The bring-forward arm is for a body that is pre-14, not for an ordinary fault.
gs_r3_ok_body='
## SDLC State

current: 5
Step 1: opened 2026-09-19T22:00Z; requirements: specs/epic-01-demo/w.requirements.md
approved-by: fixture 2026-09-19T00:00Z "approved"

## Tasks

| id | step | kind | task | agent | deps | size | serves | Files | status |
|---|---|---|---|---|---|---|---|---|---|
| T1 | 4 | build | the dispatched unit | implementor | — | 30m | REQ-x | a.sh | doing |
'
r2_write_knob_unset "$gs_r3_path" "${gs_r3_plan}${gs_r3_ok_body}"
expect_eq "R3e a ten-column table with one broken row keeps 1.8.2's own verdict" \
  "bionic: write refused — this plan's Tasks table is invalid (fix the row the detail names)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"

# THE STAMP AND THE BODY DISAGREE, and only ONE of them is a fact about this plan (wave-16
# T25, Step-6 critic §C1). `plan_bring_forward` used to be HANDED the step, and its two
# callers handed it different things: the evidence gate passed the body's `current:`, this
# hook passed the frontmatter's `sdlc-step:`. A frontmatter stamp is written once at Step 0
# and almost never moved again — this repo's own archive carries `sdlc-step: 3` beside
# `current: 9` — so the Write-side arm computed against step 3 for the whole life of the
# plan and the two `>= 4` classes could never reach it. AC-3.1's "identical lists from both
# callers" was unreachable past Step 3, and silently so: the author was refused for the
# TABLE ALONE and never told about `approved-by:` or `fails-when:`.
#
# THE FIXTURE IS THAT DISAGREEMENT AND NOTHING ELSE: `sdlc-step: 3` in the frontmatter,
# `current: 5` in the body, a Step-1 `requirements:` pointer PRESENT and a `## Goal`
# PRESENT — so the classes left are the pre-14 table that arms the predicate and exactly
# the two the stamp used to hide.
#
# fails-when: the verdict names the table rather than the contract version, either `>= 4`
# class is absent from the detail, or a class the body satisfies is named anyway.
gs_r3_stamp_body='
## SDLC State

current: 5
Step 1: opened 2026-09-19T22:00Z; requirements: specs/epic-01-demo/w.requirements.md

## Tasks

| id | intent | rigor | description | status |
|---|---|---|---|---|
| T1 | build | audited | the dispatched unit | pending |
'
gs_r3_stamp_plan="$(build_plan step=3)"
gs_r3_stamp_plan="${gs_r3_stamp_plan/multi_agent: false/multi_agent: true}"

# META, so no row below can pass over a fixture that lost its own disagreement.
expect_eq "R3s0 meta: the fixture's frontmatter stamp and its body really do disagree" \
  "sdlc-step=3 current=5" \
  "sdlc-step=$(printf '%s' "$gs_r3_stamp_plan" | /usr/bin/grep -m1 '^sdlc-step:' | tr -cd '0-9') current=$(printf '%s' "$gs_r3_stamp_body" | /usr/bin/grep -m1 '^current:' | tr -cd '0-9')"

r2_write_knob_unset "$gs_r3_path" "${gs_r3_stamp_plan}${gs_r3_stamp_body}"

expect_status "R3s1 the stamp-mismatched pre-14 Write is refused, fail-closed" "2" "$GS_R2_EXIT"
expect_eq "R3s2 …and the verdict is the contract version, not the table alone" \
  "bionic: write refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3s3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$GS_R2_ERR"
expect_contains "R3s3(2) …the approval line, a class the frontmatter stamp used to hide" \
  "## SDLC State: no 'approved-by:' line" "$GS_R2_ERR"
expect_contains "R3s3(3) …and the matrix's fails-when, the other hidden class" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$GS_R2_ERR"
# THE LIST IS DERIVED, NOT BLANKET: the two classes this body SATISFIES are absent from it.
# Paired with R3s3(1)-(3) over the same refusal, so neither reads a producer that never ran.
expect_absent "R3s4(1) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$GS_R2_ERR"
expect_absent "R3s4(2) …nor the '## Goal' section this body carries" \
  "## Goal:" "$GS_R2_ERR"

# THE TWIN OF THIS FIXTURE IS THE EVIDENCE-GATE SUITE'S OWN R3s BLOCK, driving the OTHER
# caller over the same five classes; the five strings below are the five it asserts.
#
# ONE SOURCE, ASSERTED AT THE FUNCTION ITSELF. The same plan text through the same
# predicate the evidence gate calls, invoked the way BOTH callers now invoke it — with NO
# step argument — must yield the list this hook just rendered. A caller that reintroduced a
# step argument, or a predicate that went back to trusting one, moves one of these rows.
gs_r3_stamp_file="$(mktemp "${TMPDIR:-/tmp}/gs-r3-stamp.XXXXXX")"
printf '%s' "${gs_r3_stamp_plan}${gs_r3_stamp_body}" > "$gs_r3_stamp_file"
gs_r3_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" "$gs_r3_stamp_file" 2>/dev/null || true)"
rm -f "$gs_r3_stamp_file"
expect_contains "R3s5 the predicate, called with NO step argument, derives step 5 from the body" \
  "## SDLC State: no 'approved-by:' line" "$gs_r3_direct"
# EVERY line it returned, against the refusal this hook rendered — the identical-lists half
# of AC-3.1, read one line at a time so a list that agreed on three of five cannot pass.
gs_r3_n=0
while IFS= read -r gs_r3_line; do
  [ -n "$gs_r3_line" ] || continue
  gs_r3_n=$((gs_r3_n + 1))
  expect_contains "R3s6.${gs_r3_n} …predicate line ${gs_r3_n} reached the rendered refusal" \
    "$gs_r3_line" "$GS_R2_ERR"
done <<< "$gs_r3_direct"
# FIVE: the missing-column line, this row's two `units_validate` faults, `approved-by:` and
# `fails-when:`. A count, so a predicate that returned one line could not satisfy the loop.
expect_eq "R3s7 …and the predicate returned every line, not a prefix of them" "5" "$gs_r3_n"

# THE CRLF TWIN (wave-16 T27, critic C7). Byte-for-byte the R3s fixture above — same
# frontmatter-stamp/body disagreement, same pre-14 table — translated to CRLF line endings
# with `perl -pe 's/\n/\r\n/'`, the critic's own repro technique. Before the fix,
# `_bf_section` and the `first_heading` awk inside `plan_bring_forward` read the plan RAW:
# a CRLF `## SDLC State` heading matched nothing, the derived step fell through to 0, and
# the predicate returned silently — the Write-side arm ADMITTED a pre-14 CRLF plan the SAME
# body's LF twin refuses six lines for (this is the RED; see T27-crlf-one-source.md).
#
# fails-when: the CRLF Write is admitted, or its refusal names a different list than the
# LF twin's (R3s3(1)-(3) above).
gs_r3t_lf="${gs_r3_stamp_plan}${gs_r3_stamp_body}"
gs_r3t_crlf="$(printf '%s' "$gs_r3t_lf" | perl -pe 's/\n/\r\n/')"
gs_r3t_file="$(mktemp "${TMPDIR:-/tmp}/gs-r3t-crlf.XXXXXX")"
printf '%s' "$gs_r3t_crlf" > "$gs_r3t_file"

# META FIRST, so no row below can pass over a fixture that lost its own CRLF-ness.
expect_contains "R3t0 meta: the twin fixture really is CRLF-terminated" \
  "CRLF" "$(file "$gs_r3t_file")"

r2_write_knob_unset "$gs_r3_path" "$gs_r3t_crlf"

expect_status "R3t1 the CRLF pre-14 Write is refused, fail-closed — same as its LF twin" "2" "$GS_R2_EXIT"
expect_eq "R3t2 …with the contract-version verdict, not admitted silently" \
  "bionic: write refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3t3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$GS_R2_ERR"
expect_contains "R3t3(2) …the approval line, a class the frontmatter stamp used to hide" \
  "## SDLC State: no 'approved-by:' line" "$GS_R2_ERR"
expect_contains "R3t3(3) …and the matrix's fails-when, the other hidden class" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$GS_R2_ERR"
expect_absent "R3t3(4) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$GS_R2_ERR"
expect_absent "R3t3(5) …nor the '## Goal' section this body carries" \
  "## Goal:" "$GS_R2_ERR"

# THE FUNCTION-LEVEL ROW, no hook in the loop: `plan_bring_forward` on the CRLF fixture
# must return rc=1 with the SAME lines as `plan_bring_forward` on the LF fixture (R3s5-7's
# `$gs_r3_direct`, still in scope) — a diff of the two outputs must be empty. Sourced the
# same minimal way R3s5 sources it (units.sh + walls.sh, NOT run.sh), which is also why the
# fix normalizes line endings inline inside `plan_bring_forward` itself rather than by
# calling `normalize_newlines` (run.sh) — this row would break if it depended on that.
gs_r3t_rc=0
gs_r3t_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" "$gs_r3t_file" 2>/dev/null)" || gs_r3t_rc=$?
rm -f "$gs_r3t_file"
expect_status "R3t4 the predicate returns rc=1 on the CRLF fixture, same as its LF twin" "1" "$gs_r3t_rc"
expect_eq "R3t5 …and the SAME lines as the LF twin, byte for byte (diff empty)" \
  "" "$(diff <(printf '%s\n' "$gs_r3_direct") <(printf '%s\n' "$gs_r3t_direct") 2>&1 || true)"

# THE BOM TWIN (T8; REQ-11; wave-16 critic-b77d5aa C10; research R4 §D3). Byte-for-byte the
# gs_r3t_lf fixture above, prefixed with a UTF-8 byte-order mark on its very first byte.
# `plan_bring_forward`'s normalization awk compares the whole first record to "---" with
# `==`, which is BOM-insensitive, but every reader downstream (`_bf_fm_get`, `first_heading`)
# matches an ANCHORED regex, which the BOM defeats the same way the CRLF twin's line endings
# did before its own fix (research R4 D3.3-D3.4: octal and `\x` escapes in an awk REGEX do
# not strip a BOM on awk 20200816; only a STRING compare against "\357\273\277" does).
#
# fails-when: the BOM Write is admitted, or its refusal names a different list than the LF
# twin's (R3s3(1)-(3) above); or a direct call to `plan_bring_forward` on the BOM twin
# differs from the LF twin's own direct-call output.
gs_r3u_bom="$(printf '\357\273\277%s' "$gs_r3t_lf")"
gs_r3u_file="$(mktemp "${TMPDIR:-/tmp}/gs-r3u-bom.XXXXXX")"
printf '%s' "$gs_r3u_bom" > "$gs_r3u_file"

# META FIRST, so no row below can pass over a fixture that lost its own BOM.
expect_eq "R3u0 meta: the twin fixture really opens with a UTF-8 BOM" "efbbbf" \
  "$(head -c3 "$gs_r3u_file" | xxd -p)"

r2_write_knob_unset "$gs_r3_path" "$gs_r3u_bom"

expect_status "R3u1 the BOM pre-14 Write is refused, fail-closed — same as its LF twin" "2" "$GS_R2_EXIT"
expect_eq "R3u2 …with the contract-version verdict, not admitted silently" \
  "bionic: write refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3u3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$GS_R2_ERR"
expect_contains "R3u3(2) …the approval line, a class the frontmatter stamp used to hide" \
  "## SDLC State: no 'approved-by:' line" "$GS_R2_ERR"
expect_contains "R3u3(3) …and the matrix's fails-when, the other hidden class" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$GS_R2_ERR"
expect_absent "R3u3(4) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$GS_R2_ERR"
expect_absent "R3u3(5) …nor the '## Goal' section this body carries" \
  "## Goal:" "$GS_R2_ERR"

gs_r3u_rc=0
gs_r3u_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" "$gs_r3u_file" 2>/dev/null)" || gs_r3u_rc=$?
rm -f "$gs_r3u_file"
expect_status "R3u4 the predicate returns rc=1 on the BOM fixture, same as its LF twin" "1" "$gs_r3u_rc"
expect_eq "R3u5 …and the SAME lines as the LF twin, byte for byte (diff empty)" \
  "" "$(diff <(printf '%s\n' "$gs_r3_direct") <(printf '%s\n' "$gs_r3u_direct") 2>&1 || true)"

# THE BOM+CRLF TWIN — a Windows editor emits both at once (research R4 D3.6 row-27 note).
# Same shape as the BOM twin above, over the combined fixture.
gs_r3v_bomcrlf="$(printf '\357\273\277%s' "$gs_r3t_crlf")"
gs_r3v_file="$(mktemp "${TMPDIR:-/tmp}/gs-r3v-bomcrlf.XXXXXX")"
printf '%s' "$gs_r3v_bomcrlf" > "$gs_r3v_file"

expect_eq "R3v0 meta: the BOM+CRLF twin opens with the BOM and is CRLF-terminated" "efbbbf CRLF" \
  "$(head -c3 "$gs_r3v_file" | xxd -p) $(file "$gs_r3v_file" | /usr/bin/grep -o CRLF)"

r2_write_knob_unset "$gs_r3_path" "$gs_r3v_bomcrlf"

expect_status "R3v1 the BOM+CRLF pre-14 Write is refused, fail-closed" "2" "$GS_R2_EXIT"
expect_eq "R3v2 …with the contract-version verdict, not admitted silently" \
  "bionic: write refused — this plan's body is not at contract version 14 (bring the plan forward)" \
  "$(printf '%s\n' "$GS_R2_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_contains "R3v3(1) …the pre-14 table that arms the predicate" \
  "## Tasks: the table is missing columns: step task agent deps size serves Files" "$GS_R2_ERR"
expect_contains "R3v3(2) …the approval line, a class the frontmatter stamp used to hide" \
  "## SDLC State: no 'approved-by:' line" "$GS_R2_ERR"
expect_contains "R3v3(3) …and the matrix's fails-when, the other hidden class" \
  "## Verification Matrix: no AC block names a 'fails-when:'" "$GS_R2_ERR"
expect_absent "R3v3(4) …the requirements pointer this body carries is not named" \
  "the Step 1 evidence names no 'requirements:' pointer" "$GS_R2_ERR"
expect_absent "R3v3(5) …nor the '## Goal' section this body carries" \
  "## Goal:" "$GS_R2_ERR"

gs_r3v_rc=0
gs_r3v_direct="$(bash -c '. "$1"; . "$2"; plan_bring_forward "$3"' _ \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/units.sh" \
  "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh" "$gs_r3v_file" 2>/dev/null)" || gs_r3v_rc=$?
rm -f "$gs_r3v_file"
expect_status "R3v4 the predicate returns rc=1 on the BOM+CRLF fixture, same as its LF twin" "1" "$gs_r3v_rc"
expect_eq "R3v5 …and the SAME lines as the LF twin, byte for byte (diff empty)" \
  "" "$(diff <(printf '%s\n' "$gs_r3_direct") <(printf '%s\n' "$gs_r3v_direct") 2>&1 || true)"
# [REQ-3 BRING-FORWARD SECTION: END]


# ============================================================
section "R4 — walls.sh's prose-record reader cannot shadow observe.sh's roster reader (wave-16 T21, walk-2c882be.md §3)"
# ============================================================
#
# THE COLLISION THE WALK FOUND. payload/scripts/lib/observe.sh (and its byte-identical
# copies in session-poker.sh, stop-orders.sh, session-sweeper.sh, execution-recorder.sh)
# define `line_field <line> <key>` as the PIPE-DELIMITED ROSTER-ROW reader. This wall's own
# `requirements:`/`approved-by:`/`walk-artifact` reads need a different contract — a key
# ANYWHERE on a semicolon-separated PROSE line — and until this task walls.sh defined a
# SECOND function under the SAME name. No process sources both libraries today, so nothing
# collided yet; a future `BIONIC_LIB_WANT` line naming both would have had the second
# source silently win, misreading every roster row the caller touched afterwards.
#
# fails-when: walls.sh still defines a function literally named `line_field`, its
# prose-record reader is not reachable under its own name, or a real call through that
# name misreads the mid-record pointer shape the docblock documents.
WALLS_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/walls.sh"

r4_has_fn() {  # <file> <fn-name> -> exit 0/1, real source in a subshell, no side effects
  ( . "$1" >/dev/null 2>&1; declare -F "$2" >/dev/null 2>&1 )
}

expect_false "R4a walls.sh no longer defines a function literally named 'line_field'" \
  r4_has_fn "$WALLS_LIB" line_field
expect_true "R4b …and the renamed reader is reachable as 'evidence_line_field'" \
  r4_has_fn "$WALLS_LIB" evidence_line_field

# EXERCISED, not only declared: the exact mid-record shape line_field's docblock
# documents, read by the real function under its new name — a real source, a real call.
R4_REC="- Step 1: opened 2026-09-19T22:00Z; requirements: specs/epic-01-demo/w.requirements.md; card approved"
R4_GOT="$(bash -c '. "$1"; evidence_line_field "$2" requirements' _ "$WALLS_LIB" "$R4_REC" 2>/dev/null)"
expect_eq "R4c …exercised: it reads a mid-record pointer by key, real call, real source" \
  "specs/epic-01-demo/w.requirements.md" "$R4_GOT"

# AND EXERCISED THROUGH THE LIVE W6 ARM. R3 above already drives THIS HOOK end to end
# through `plan_bring_forward`, which is the caller this rename had to keep working:
# R3d(3)/R3d(4) name the same `requirements:`/`approved-by:` reads this section isolates.
# A rename that broke the caller rather than only the name would already have reddened R3;
# nothing further needs to run here.

finish
