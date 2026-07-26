#!/bin/bash
# Tests for canonical-sdlc-governing-skill.sh
#
# Strategy: build synthetic Write/Edit tool_input payloads that target
# files in a temp project dir. No HOME override needed — the hook only
# inspects the posted JSON and, for Edit, reads the file at the given
# path.
#
# Usage: bash hooks/canonical-sdlc-governing-skill.test.sh

set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/canonical-sdlc-governing-skill.sh"
PASS=0
FAIL=0
TOTAL=0

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

make_project() {
  local dir
  dir=$(mktemp -d)
  mkdir -p "$dir/.bionic/docs/plans/epic-01-demo"
  mkdir -p "$dir/.bionic/docs/specs/epic-01-demo"
  mkdir -p "$dir/.bionic/docs/adrs/epic-01-demo"
  cleanup_dirs+=("$dir")
  echo "$dir"
}

# Runs hook with a synthetic Write payload for $FILE with $CONTENT.
run_write() {
  local file_path="$1" content="$2"
  local input
  input=$(jq -n \
    --arg p "$file_path" \
    --arg c "$content" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  local tmp_err
  tmp_err=$(mktemp)
  if HOME="$FAKE_HOME" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

run_edit() {
  local file_path="$1" old_str="$2" new_str="$3"
  local input
  input=$(jq -n \
    --arg p "$file_path" \
    --arg o "$old_str" \
    --arg n "$new_str" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}')
  local tmp_err
  tmp_err=$(mktemp)
  if HOME="$FAKE_HOME" bash "$HOOK" <<< "$input" >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s (expected=%q actual=%q)\n' "$label" "$expected" "$actual"
  fi
}

# Asserts $3 (haystack, typically $HOOK_STDERR) contains substring $2.
# Same PASS/FAIL accounting + output shape as the inline `case` idiom
# used throughout this file, hoisted to a helper for the many
# stderr-substring checks.
assert_contains() {
  local label="$1" needle="$2" hay="$3"
  TOTAL=$((TOTAL + 1))
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)); printf '  PASS  %s\n' "$label" ;;
    *) FAIL=$((FAIL + 1)); printf '  FAIL  %s (missing %q in %q)\n' "$label" "$needle" "$hay" ;;
  esac
}

# Builds a valid canonical-sdlc artifact. All config via KEY=VALUE args
# (bash-3.2 arg parse):
#   intent/rigor/scale — triple values (default build/audited/wave);
#     value OMIT drops the line entirely (missing-field cases).
#   step    — sdlc-step (default 3).
#   version — canonical_sdlc_version (default 12); OMIT drops the line.
#   mode    — if set, inject a `mode:` line (split-brain guard case).
#   omit    — space-separated flag names to drop (missing-flag cases).
#   matrix  — yes|no; drop the "## Verification Matrix" section when no.
build_plan() {
  local intent=build rigor=audited scale=wave step=3 version=12 mode="OMIT" omit=" " matrix=yes
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
    esac
  done

  local out='---
governing-skill: superpowers:writing-plans
sdlc-step: '"$step"'
epic: epic-01-demo
wave: wave-01-x
'
  [ "$version" = OMIT ] || out+="canonical_sdlc_version: $version"$'\n'
  [ "$mode" = OMIT ]    || out+="mode: $mode"$'\n'
  [ "$intent" = OMIT ]  || out+="intent: $intent"$'\n'
  [ "$rigor" = OMIT ]   || out+="rigor: $rigor"$'\n'
  [ "$scale" = OMIT ]   || out+="scale: $scale"$'\n'

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
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: plan file missing frontmatter → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: plan file with empty governing-skill → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$EMPTY_GOVERNING"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: spec file with valid frontmatter → allow"
run_write "$project/.bionic/docs/specs/epic-01-demo/wave-01-x.spec.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: adr file with valid frontmatter → allow"
run_write "$project/.bionic/docs/adrs/epic-01-demo/adr-001-x.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: continuation.md with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: continuation-checkpoint.md with valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation-checkpoint.md" "$VALID_FRONTMATTER"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: README.md under plans dir, no frontmatter → allow (not an enforced artifact)"
run_write "$project/.bionic/docs/plans/epic-01-demo/README.md" "# some notes"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: .plan.md OUTSIDE any .bionic/-rooted project → allow (hook scope is path-gated)"
outside=$(mktemp -d)
cleanup_dirs+=("$outside")
run_write "$outside/random.plan.md" "$MISSING_FM"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: adr-named file under adrs/ missing frontmatter → block"
run_write "$project/.bionic/docs/adrs/epic-01-demo/adr-007-x.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit: existing file with valid frontmatter → allow"
existing="$project/.bionic/docs/plans/epic-01-demo/wave-02-y.plan.md"
printf '%s' "$VALID_FRONTMATTER" > "$existing"
run_edit "$existing" "Plan body" "Updated body"
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Edit: existing file missing frontmatter → block"
bad="$project/.bionic/docs/plans/epic-01-demo/wave-03-z.plan.md"
printf '%s' "$MISSING_FM" > "$bad"
run_edit "$bad" "Plan body" "Updated body"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Edit: file doesn't exist (Edit would fail anyway) → block"
run_edit "$project/.bionic/docs/plans/epic-01-demo/does-not-exist.plan.md" "x" "y"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Bash tool (non-Write/Edit) → allow"
input=$(jq -n '{tool_name: "Bash", tool_input: {command: "ls"}}')
HOOK_EXIT=0
if ! HOME="$FAKE_HOME" bash "$HOOK" <<< "$input" >/dev/null 2>&1; then
  HOOK_EXIT=$?
fi
assert_eq "exit 0" 0 "$HOOK_EXIT"

# ============================================================
# canonical_sdlc_version: exactly one supported value
# ============================================================
#
# The hook supports canonical_sdlc_version: 12 and nothing else. Every other
# value blocks with exit 2 and a message naming the value found. One
# table-driven case over representative bad values — an older number, a much
# older number, a legacy single digit, a far-future number, an empty value,
# and non-numeric garbage — because there is one behavior here, not one per
# value.

project=$(make_project)

for bad_version in 11 9 2 99 "" "banana" "12.0" "v12"; do
  label="${bad_version:-<empty>}"
  run_write "$project/.bionic/docs/plans/epic-01-demo/unsupported.plan.md" \
    "$(build_plan version="$bad_version")"
  assert_eq "unsupported version '$label' blocks" 2 "$HOOK_EXIT"
  assert_contains "unsupported version '$label' names the value found" \
    "canonical_sdlc_version: '$bad_version'" "$HOOK_STDERR"
done

echo "canonical_sdlc_version line absent entirely → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-version.plan.md" "$(build_plan version=OMIT)"
assert_eq "absent version blocks" 2 "$HOOK_EXIT"
assert_contains "absent version names 12 as the supported value" \
  "the only supported version" "$HOOK_STDERR"

# ============================================================
# intent × rigor × scale triple + universal structural contract
# ============================================================
#
# Governance keys off the triple: presence + whole-value enum validation,
# the `mode:` split-brain guard, barred intent × scale cells, the 5
# discriminator + 2 opt-in flags, `model_plan`, and a `## Verification
# Matrix` at sdlc-step >= 3 for wave/epic plans.
#
# Enums: intent ∈ {build,bugfix,refactor,tune,spike,incident-response};
#        rigor ∈ {tested,peer-reviewed,audited}; scale ∈ {task,wave,epic}.
# Barred intent × scale cells: bugfix·epic, spike·epic, incident-response·epic.

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
assert_contains "blocks_bad_intent_enum lists allowed" "allowed" "$HOOK_STDERR"

echo "bad rigor enum (rigor: reviewed) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/bad-rigor.plan.md" "$(build_plan rigor=reviewed)"
assert_eq "blocks_bad_rigor_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_bad_rigor_enum lists allowed" "allowed" "$HOOK_STDERR"

echo "bad scale enum (scale: session) → block, lists allowed set"
run_write "$project/.bionic/docs/plans/epic-01-demo/bad-scale.plan.md" "$(build_plan scale=session)"
assert_eq "blocks_bad_scale_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_bad_scale_enum lists allowed" "task|wave|epic" "$HOOK_STDERR"

echo "enum substring (intent: rebuild) → block (whole-value equality, not substring)"
run_write "$project/.bionic/docs/plans/epic-01-demo/substr.plan.md" "$(build_plan intent=rebuild)"
assert_eq "blocks_enum_substring exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_enum_substring lists allowed" "allowed" "$HOOK_STDERR"

echo "mode: present (split-brain) → block, error names mode"
run_write "$project/.bionic/docs/plans/epic-01-demo/mode.plan.md" "$(build_plan mode=autonomous)"
assert_eq "blocks_mode_present exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_mode_present names mode" "mode" "$HOOK_STDERR"

echo "barred cell bugfix × epic → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/bugfix-epic.plan.md" "$(build_plan intent=bugfix scale=epic)"
assert_eq "blocks_barred_bugfix_epic exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_barred_bugfix_epic says barred" "barred" "$HOOK_STDERR"

echo "barred cell spike × epic → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/spike-epic.plan.md" "$(build_plan intent=spike scale=epic)"
assert_eq "blocks_barred_spike_epic exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_barred_spike_epic says barred" "barred" "$HOOK_STDERR"

echo "barred cell incident-response × epic → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/incident-epic.plan.md" "$(build_plan intent=incident-response scale=epic)"
assert_eq "blocks_barred_incident_epic exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_barred_incident_epic says barred" "barred" "$HOOK_STDERR"

echo "allowed cell build × epic → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/build-epic.plan.md" "$(build_plan intent=build scale=epic)"
assert_eq "allows_build_epic exit 0" 0 "$HOOK_EXIT"

echo "missing a discriminator flag (surface_type) → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-flag.plan.md" "$(build_plan omit=surface_type)"
assert_eq "blocks_missing_flag exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_flag names surface_type" "surface_type" "$HOOK_STDERR"

echo "missing an opt-in flag (use_worktree) → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-optin.plan.md" "$(build_plan omit=use_worktree)"
assert_eq "blocks_missing_opt_in exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_opt_in names use_worktree" "use_worktree" "$HOOK_STDERR"

echo "missing model_plan → block, error names model_plan"
run_write "$project/.bionic/docs/plans/epic-01-demo/no-mp.plan.md" "$(build_plan omit=model_plan)"
assert_eq "blocks_missing_model_plan exit 2" 2 "$HOOK_EXIT"
assert_contains "blocks_missing_model_plan names model_plan" "model_plan" "$HOOK_STDERR"

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
run_write "$project/.bionic/docs/specs/epic-01-demo/no-matrix.spec.md" "$(build_plan step=3 matrix=no)"
assert_eq "spec_exempt_from_matrix exit 0" 0 "$HOOK_EXIT"

echo "continuation.md at sdlc-step 3 without matrix → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/continuation.md" "$(build_plan step=3 matrix=no)"
assert_eq "continuation_exempt_from_matrix exit 0" 0 "$HOOK_EXIT"

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
assert_contains "crlf error names model_plan (not 'missing frontmatter')" "model_plan" "$HOOK_STDERR"

echo "CR-only plan with full valid frontmatter → allow"
run_write "$project/.bionic/docs/plans/epic-01-demo/cr-only.plan.md" "$(to_cr_only "$(build_plan)")"
assert_eq "cr_only_full exit 0" 0 "$HOOK_EXIT"

echo "CR-only plan missing model_plan → block for the RIGHT reason"
run_write "$project/.bionic/docs/plans/epic-01-demo/cr-only-no-mp.plan.md" "$(to_cr_only "$(build_plan omit=model_plan)")"
assert_eq "cr_only_no_mp exit 2" 2 "$HOOK_EXIT"
assert_contains "cr-only error names model_plan" "model_plan" "$HOOK_STDERR"

echo "CR-only plan with a bad enum → block on the enum, proving the triple parsed"
run_write "$project/.bionic/docs/plans/epic-01-demo/cr-only-enum.plan.md" "$(to_cr_only "$(build_plan intent=feature)")"
assert_eq "cr_only_enum exit 2" 2 "$HOOK_EXIT"
assert_contains "cr-only enum error lists allowed" "allowed" "$HOOK_STDERR"

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
assert_eq "floor_project_satisfied_silent no audit file" "" "$(read_audit "$project")"
assert_eq "floor_project_satisfied_silent empty stderr" "" "$HOOK_STDERR"

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
canonical_sdlc_version: 12
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
assert_eq "floor_epic_plan_missing_silent no audit file" "" "$(read_audit "$project")"

echo "audit file + parent dir created on first finding"
project=$(make_project)
run_write "$project/.bionic/docs/plans/epic-01-demo/audit-create.plan.md" "$(build_plan intent=spike rigor=audited)"
assert_eq "floor_audit_file_created exit 0" 0 "$HOOK_EXIT"
if [ -f "$(audit_file_for "$project")" ]; then
  PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  floor_audit_file_created (file + dir created)\n'
else
  FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  floor_audit_file_created (file missing)\n'
fi
# Incident 0001 (AC-3): the SAME write that just landed above must leave no
# audit file anywhere under the project tree. Paired with the presence check
# directly above — an absence assertion alone passes when nothing was written
# at all, which is exactly the failure mode it exists to catch.
if [ -z "$(find "$project" -name 'sdlc-audit.md' 2>/dev/null)" ]; then
  PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); printf '  PASS  floor_audit_not_in_project_tree\n'
else
  FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); printf '  FAIL  floor_audit_not_in_project_tree (%s)\n' "$(find "$project" -name 'sdlc-audit.md')"
fi

echo "all-violations fixture (intent + project + epic floors) → still exit 0, all three logged"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
cat > "$project/.bionic/docs/plans/epic-01-demo/epic.plan.md" <<'EOF'
---
governing-skill: canonical-sdlc
canonical_sdlc_version: 12
rigor-floor: audited
---

# Epic
EOF
run_write "$project/.bionic/docs/plans/epic-01-demo/all-violations.plan.md" "$(build_plan intent=incident-response rigor=tested)"
assert_eq "floor_never_blocks exit 0" 0 "$HOOK_EXIT"
assert_contains "floor_never_blocks logs intent-floor" "intent-floor" "$(read_audit "$project")"
assert_contains "floor_never_blocks logs project-floor" "project-floor" "$(read_audit "$project")"
assert_contains "floor_never_blocks logs epic-floor" "epic-floor" "$(read_audit "$project")"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
