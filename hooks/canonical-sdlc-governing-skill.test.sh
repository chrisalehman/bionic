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
#   version — canonical_sdlc_version (default 13); OMIT drops the line.
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
  local intent=build rigor=audited scale=wave step=3 version=13 mode="OMIT" omit=" " matrix=yes
  local skill="superpowers:writing-plans"
  local walk="OMIT" override="OMIT" waived="OMIT"
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
assert_eq "exit 0" 0 "$HOOK_EXIT"

echo "Write: plan file missing frontmatter → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$MISSING_FM"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: plan file with empty governing-skill → block"
run_write "$project/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$EMPTY_GOVERNING"
assert_eq "exit 2" 2 "$HOOK_EXIT"

echo "Write: spec file with valid frontmatter → allow"
run_write "$project/.bionic/docs/specs/epic-01-demo/wave-01-x.spec.md" "$VALID_SPEC_FRONTMATTER"
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
# The hook supports canonical_sdlc_version: 13 and nothing else. Every other
# value blocks with exit 2 and a message naming the value found. One
# table-driven case over representative bad values — an older number, a much
# older number, a legacy single digit, a far-future number, an empty value,
# and non-numeric garbage — because there is one behavior here, not one per
# value.

project=$(make_project)

for bad_version in 11 12 9 2 99 "" "banana" "12.0" "v12"; do
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
assert_contains "absent version names 13 as the supported value" \
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
echo "=== walk: enum (epic-14 AC-3) ==="

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
canonical_sdlc_version: 13
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
canonical_sdlc_version: 13
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
echo "=== rigor-override: marker (epic-14 AC-10, AC-11) ==="

RIGOR_OVERRIDE_LINE='rigor-override: chris 2026-08-01 derived=audited chosen=tested'

echo "project-floor violated + rigor-override marker → writes cleanly, logs user-overridden, not the violation"
project=$(make_project)
printf 'rigor-floor: audited\n' > "$project/.bionic/config.yaml"
run_write "$project/.bionic/docs/plans/epic-01-demo/override-present.plan.md" \
  "$(build_plan intent=build rigor=tested override="$RIGOR_OVERRIDE_LINE")"
assert_eq "rigor_override_present exit 0" 0 "$HOOK_EXIT"
assert_contains "rigor_override_present stderr says user-overridden" "user-overridden" "$HOOK_STDERR"
assert_contains "rigor_override_present audit says user-overridden" "user-overridden" "$(read_audit "$project")"
TOTAL=$((TOTAL + 1))
case "$HOOK_STDERR" in
  *"project floor"*) FAIL=$((FAIL + 1)); printf '  FAIL  rigor_override_present stderr still names the violation text\n' ;;
  *) PASS=$((PASS + 1)); printf '  PASS  rigor_override_present stderr does not name the violation text\n' ;;
esac
TOTAL=$((TOTAL + 1))
case "$(read_audit "$project")" in
  *"project floor"*) FAIL=$((FAIL + 1)); printf '  FAIL  rigor_override_present audit still names the violation text\n' ;;
  *) PASS=$((PASS + 1)); printf '  PASS  rigor_override_present audit does not name the violation text\n' ;;
esac

echo "project-floor violated, NO marker → existing violation log unchanged"
project2=$(make_project)
printf 'rigor-floor: audited\n' > "$project2/.bionic/config.yaml"
run_write "$project2/.bionic/docs/plans/epic-01-demo/override-absent.plan.md" \
  "$(build_plan intent=build rigor=tested)"
assert_eq "rigor_override_absent exit 0" 0 "$HOOK_EXIT"
assert_contains "rigor_override_absent stderr names project-floor violation text" \
  "project floor audited, declared tested" "$HOOK_STDERR"
assert_contains "rigor_override_absent audit line matches pre-slice wording" \
  "project-floor: project floor audited, declared tested" "$(read_audit "$project2")"
TOTAL=$((TOTAL + 1))
case "$HOOK_STDERR" in
  *"user-overridden"*) FAIL=$((FAIL + 1)); printf '  FAIL  rigor_override_absent stderr wrongly says user-overridden\n' ;;
  *) PASS=$((PASS + 1)); printf '  PASS  rigor_override_absent stderr does not say user-overridden\n' ;;
esac
TOTAL=$((TOTAL + 1))
case "$(read_audit "$project2")" in
  *"user-overridden"*) FAIL=$((FAIL + 1)); printf '  FAIL  rigor_override_absent audit wrongly says user-overridden\n' ;;
  *) PASS=$((PASS + 1)); printf '  PASS  rigor_override_absent audit does not say user-overridden\n' ;;
esac

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
echo "=== AC-10: computed root resolution ==="

# The five criteria below run against the SHIPPED text of the function,
# extracted from the hook and eval'd here — not against a reimplementation.
# That seam can only observe what the function returns, never that the hook
# calls it, so the two end-to-end cases at the end of this section drive the
# hook through its real stdin contract and pin the call site.
ac10_src=$(awk '/^resolve_project_root\(\)/,/^\}/' "$HOOK")
TOTAL=$((TOTAL + 1))
if [ -n "$ac10_src" ]; then
  PASS=$((PASS + 1)); printf '  PASS  ac10_resolver_extracted\n'
  eval "$ac10_src"
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac10_resolver_extracted (no resolve_project_root() in %s)\n' "$HOOK"
  # Keep the five criteria individually reportable rather than aborting the run.
  resolve_project_root() { :; }
fi

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

# 1 — from the repo root, the repo root.
ac10_r1=$(resolve_project_root "$ac10_main/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c1 repo root → repo root" "$ac10_main" "$ac10_r1"

# 2 — from an arbitrary subdirectory, the same repo root: both when the target
# path lives in the subdirectory, and when the process cwd is the subdirectory.
ac10_r2=$(resolve_project_root "$ac10_main/deep/sub/dir/x.plan.md")
assert_eq "ac10_c2 target in a subdirectory → repo root" "$ac10_main" "$ac10_r2"
ac10_r2b=$(cd "$ac10_main/deep/sub/dir" && resolve_project_root "$ac10_main/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c2 cwd in a subdirectory → repo root (not cwd-relative)" "$ac10_main" "$ac10_r2b"

# 3 — from inside a linked worktree, the PARENT repo root. `--git-common-dir`
# is what makes this true; `--git-dir` would name the worktree's private dir.
ac10_r3=$(resolve_project_root "$ac10_wt/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c3 inside a worktree → parent repo root" "$ac10_main" "$ac10_r3"

# 4 — a repo where .bionic/ has never existed. None of the target's parent
# directories exist either, which is the ordinary case for a PreToolUse gate.
ac10_r4=$(resolve_project_root "$ac10_nb/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c4 .bionic/ never existed → repo root" "$ac10_nb" "$ac10_r4"

# 5 — outside any repository: cwd, and no error.
ac10_r5=$(cd "$ac10_out" && resolve_project_root "$ac10_out/notes/x.plan.md")
assert_eq "ac10_c5 outside any repo → cwd" "$ac10_out" "$ac10_r5"
TOTAL=$((TOTAL + 1))
if (cd "$ac10_out" && resolve_project_root "$ac10_out/notes/x.plan.md" >/dev/null 2>&1); then
  PASS=$((PASS + 1)); printf '  PASS  ac10_c5 outside any repo → rc 0, no error\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac10_c5 outside any repo → rc 0, no error (rc=%d)\n' "$?"
fi

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
ac10_oldgit_resolve() {
  local saved="$PATH" out
  PATH="$ac10_oldgit:$PATH"
  out=$(resolve_project_root "$@")
  PATH="$saved"
  printf '%s\n' "$out"
}

ac10_r6=$(ac10_oldgit_resolve "$ac10_main/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c6 old git: repo root → repo root" "$ac10_main" "$ac10_r6"
ac10_r7=$(ac10_oldgit_resolve "$ac10_main/deep/sub/dir/x.plan.md")
assert_eq "ac10_c7 old git: subdirectory → repo root (relative bare form)" "$ac10_main" "$ac10_r7"
ac10_r8=$(ac10_oldgit_resolve "$ac10_wt/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c8 old git: worktree → parent repo root (absolute bare form)" "$ac10_main" "$ac10_r8"
ac10_r9=$(ac10_oldgit_resolve "$ac10_nb/.bionic/docs/plans/epic-01-demo/x.plan.md")
assert_eq "ac10_c9 old git: .bionic/ never existed → repo root" "$ac10_nb" "$ac10_r9"
# Outside any repository BOTH forms fail, so the supplied fallback still wins —
# the fallback branch must not swallow the genuine no-repo case.
ac10_r10=$(ac10_oldgit_resolve "$ac10_out/notes/x.plan.md" "$ac10_out")
assert_eq "ac10_c10 old git: outside any repo → the supplied fallback" "$ac10_out" "$ac10_r10"

# Every answer is an ABSOLUTE path. The naive `dirname $(git rev-parse
# --git-common-dir)` yields `.` and `..`; a criterion that accepted a relative
# answer would pass the defect it exists to catch. The old-git arms are in
# scope here precisely because the bare form is what returns `.` and `..`.
for ac10_i in 1 2 3 4 5 6 7 8 9 10; do
  eval "ac10_v=\$ac10_r${ac10_i}"
  TOTAL=$((TOTAL + 1))
  case "$ac10_v" in
    /*) PASS=$((PASS + 1)); printf '  PASS  ac10_absolute c%s\n' "$ac10_i" ;;
    *)  FAIL=$((FAIL + 1)); printf '  FAIL  ac10_absolute c%s (relative or empty: %q)\n' "$ac10_i" "$ac10_v" ;;
  esac
done

# --- end-to-end through the hook (no extraction seam) ---

# Criterion 4 at the CALL SITE: a repo where .bionic/ has never existed. The
# predecessor's ancestor walk found no root here and the hook exited 0, so an
# unframed artifact went ungated. Computing the root gates it.
echo "e2e: unframed artifact in a repo where .bionic/ never existed → block"
run_write "$ac10_nb/.bionic/docs/plans/epic-01-demo/never-existed.plan.md" "$MISSING_FM"
assert_eq "ac10_e2e_no_bionic exit 2" 2 "$HOOK_EXIT"

# Criterion 3 at the CALL SITE, observed through the audit file's project key.
# A worktree-local .bionic/ is NOT the project's tree: resolution answers with
# main, so main's docs root does not contain this path.
#
# Slice 1 left this as an exit-0 pass-through and flagged it as the exact
# misplacement class slice 3 was to close. It is now a BLOCK naming main's
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
  "$ac10_main/.bionic/docs/plans/" "$HOOK_STDERR"
TOTAL=$((TOTAL + 1))
if [ ! -f "$(audit_file_for "$ac10_wt")" ]; then
  PASS=$((PASS + 1)); printf '  PASS  ac10_e2e_worktree no audit file keyed on the worktree\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac10_e2e_worktree audit file keyed on the worktree (%s)\n' "$(audit_file_for "$ac10_wt")"
fi
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
  input=$(jq -n --arg p "$file_path" --arg c "$content" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}')
  tmp_err=$(mktemp)
  if (cd "$ac10_out" && HOME="$FAKE_HOME" PATH="$ac10_oldgit:$PATH" bash "$HOOK" <<< "$input") \
       >/dev/null 2>"$tmp_err"; then
    HOOK_EXIT=0
  else
    HOOK_EXIT=$?
  fi
  HOOK_STDERR=$(cat "$tmp_err")
  rm -f "$tmp_err"
}
ac10_og="$ac10_tmp/oldgit"; mkdir -p "$ac10_og"; git -C "$ac10_og" init -q .
run_write_oldgit "$ac10_og/.bionic/docs/plans/epic-01-demo/oldgit.plan.md" "$(build_plan)"
assert_eq "ac10_e2e_oldgit valid artifact allowed" 0 "$HOOK_EXIT"
assert_eq "ac10_e2e_oldgit no stderr" "" "$HOOK_STDERR"
# ...and misplacement still BLOCKS under old git, naming the artifact's OWN
# repo. A fallback that resolved everything to the cwd would pass the arm above
# by turning the hook off; this arm is what makes that impossible.
run_write_oldgit "$ac10_og/notes/rogue.plan.md" "$(build_plan)"
assert_eq "ac10_e2e_oldgit misplaced artifact blocked" 2 "$HOOK_EXIT"
assert_contains "ac10_e2e_oldgit names the artifact's own repo, not the session cwd" \
  "$ac10_og/.bionic/docs/plans/" "$HOOK_STDERR"

# ============================================================
# AC-11 / AC-12: tree creation on first lifecycle use
# ============================================================
#
# Slice 2 (F4): creation hangs off the SAME frontmatter this hook already
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
echo "=== AC-11/AC-12: tree creation on first lifecycle use ==="

make_bare_project() {
  local dir
  dir=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$dir" init -q .
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
TOTAL=$((TOTAL + 1))
if tree_exists "$ac11_p1"; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c1_precondition (.bionic/ tree already exists before the write)\n'
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c1_precondition (.bionic/ absent before the write)\n'
fi
run_write "$ac11_p1/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc)"
assert_eq "ac11_c1 write allowed" 0 "$HOOK_EXIT"
ac11_c1_stderr="$HOOK_STDERR"
TOTAL=$((TOTAL + 1))
if tree_exists "$ac11_p1"; then
  PASS=$((PASS + 1)); printf '  PASS  ac11_c1 full tree created\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c1 full tree created (missing under %s/.bionic)\n' "$ac11_p1"
fi

echo "AC-11 c3: no manual step, no prompt -- one hook invocation, no interactive/setup text on stderr"
assert_eq "ac11_c3 clean stderr on the creating write" "" "$ac11_c1_stderr"

echo "AC-11 c2: running the identical write again -> idempotent, no error, tree unchanged"
ac11_before_listing=$(cd "$ac11_p1/.bionic" && find . | sort)
run_write "$ac11_p1/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc)"
assert_eq "ac11_c2 second write still exits 0" 0 "$HOOK_EXIT"
ac11_after_listing=$(cd "$ac11_p1/.bionic" && find . | sort)
assert_eq "ac11_c2 tree listing unchanged (idempotent)" "$ac11_before_listing" "$ac11_after_listing"

echo "AC-11 c4a: unrelated file written outside the docs-root -> no over-creation, no .bionic/ at all"
ac11_p2=$(make_bare_project)
run_write "$ac11_p2/README.md" "just some notes"
assert_eq "ac11_c4a write allowed (not an enforced artifact)" 0 "$HOOK_EXIT"
TOTAL=$((TOTAL + 1))
if [ -d "$ac11_p2/.bionic" ]; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4a no .bionic/ created (found %s/.bionic)\n' "$ac11_p2"
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4a no .bionic/ created\n'
fi

# A7 REGRESSION. Slice 2 gated creation on `governing-skill: canonical-sdlc` —
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
TOTAL=$((TOTAL + 1))
if tree_exists "$ac11_p3"; then
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4b tree created for a lifecycle artifact authored by another skill\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4b tree created for a lifecycle artifact authored by another skill (missing under %s/.bionic)\n' "$ac11_p3"
fi

# The no-over-creation arm the inverted case above used to carry. An artifact
# with NO `canonical_sdlc_version` is not a canonical-sdlc run artifact: it
# blocks on the version gate AND creates nothing. This is what keeps the fix
# from degenerating into "create on any frontmatter at all".
echo "AC-11 c4c: enforced artifact with NO canonical_sdlc_version -> blocks, and creates no tree"
ac11_p5=$(make_bare_project)
run_write "$ac11_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc version=OMIT)"
assert_eq "ac11_c4c write blocked" 2 "$HOOK_EXIT"
TOTAL=$((TOTAL + 1))
if [ -d "$ac11_p5/.bionic" ]; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4c no .bionic/ created for a versionless artifact (found %s/.bionic)\n' "$ac11_p5"
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4c no .bionic/ created for a versionless artifact\n'
fi

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
# [WALL: hooks/canonical-sdlc-governing-skill.sh]
echo "AC-11 c4d: blocked on the VERSION gate (wrong number) -> no tree"
ac11_p6=$(make_bare_project)
run_write "$ac11_p6/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan version=3)"
assert_eq "ac11_c4d write blocked" 2 "$HOOK_EXIT"
TOTAL=$((TOTAL + 1))
if [ -d "$ac11_p6/.bionic" ]; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4d no .bionic/ created for a wrong-version artifact (found %s/.bionic)\n' "$ac11_p6"
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4d no .bionic/ created for a wrong-version artifact\n'
fi

echo "AC-11 c4e: blocked on the TRIPLE gate (invalid intent) -> no tree"
ac11_p7=$(make_bare_project)
run_write "$ac11_p7/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan intent=definitely-not-an-intent)"
assert_eq "ac11_c4e write blocked" 2 "$HOOK_EXIT"
TOTAL=$((TOTAL + 1))
if [ -d "$ac11_p7/.bionic" ]; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4e no .bionic/ created for an invalid-triple artifact (found %s/.bionic)\n' "$ac11_p7"
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4e no .bionic/ created for an invalid-triple artifact\n'
fi

echo "AC-11 c4f: blocked on the required-FLAGS gate -> no tree"
ac11_p8=$(make_bare_project)
run_write "$ac11_p8/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan omit=has_ui)"
assert_eq "ac11_c4f write blocked" 2 "$HOOK_EXIT"
TOTAL=$((TOTAL + 1))
if [ -d "$ac11_p8/.bionic" ]; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4f no .bionic/ created for a flag-missing artifact (found %s/.bionic)\n' "$ac11_p8"
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4f no .bionic/ created for a flag-missing artifact\n'
fi

echo "AC-11 c4g: blocked on the MATRIX gate -> no tree"
ac11_p9=$(make_bare_project)
run_write "$ac11_p9/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan matrix=no)"
assert_eq "ac11_c4g write blocked" 2 "$HOOK_EXIT"
TOTAL=$((TOTAL + 1))
if [ -d "$ac11_p9/.bionic" ]; then
  FAIL=$((FAIL + 1)); printf '  FAIL  ac11_c4g no .bionic/ created for a matrix-less step-3 plan (found %s/.bionic)\n' "$ac11_p9"
else
  PASS=$((PASS + 1)); printf '  PASS  ac11_c4g no .bionic/ created for a matrix-less step-3 plan\n'
fi

echo "AC-12 c1: .bionic/.gitignore exists and contains '*'"
TOTAL=$((TOTAL + 1))
if [ -f "$ac11_p1/.bionic/.gitignore" ] && grep -qx '\*' "$ac11_p1/.bionic/.gitignore"; then
  PASS=$((PASS + 1)); printf '  PASS  ac12_c1 .bionic/.gitignore exists and contains *\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac12_c1 .bionic/.gitignore missing or wrong content\n'
fi

echo "AC-12 c2: git check-ignore reports a file inside .bionic/ as ignored (the ignore BINDS)"
: > "$ac11_p1/.bionic/tmp/probe.txt"
TOTAL=$((TOTAL + 1))
if git -C "$ac11_p1" check-ignore -q .bionic/tmp/probe.txt; then
  PASS=$((PASS + 1)); printf '  PASS  ac12_c2 git check-ignore reports the probe file as ignored\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac12_c2 git check-ignore does NOT report the probe file as ignored\n'
fi

echo "AC-12 c3: the project's OWN .gitignore is byte-identical before and after (hash, not eye)"
ac12_p4=$(make_bare_project)
printf 'node_modules/\n*.log\n' > "$ac12_p4/.gitignore"
ac12_before_hash=$(shasum -a 256 "$ac12_p4/.gitignore" | awk '{print $1}')
run_write "$ac12_p4/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan skill=canonical-sdlc)"
assert_eq "ac12_c3 write allowed" 0 "$HOOK_EXIT"
ac12_after_hash=$(shasum -a 256 "$ac12_p4/.gitignore" | awk '{print $1}')
assert_eq "ac12_c3 project .gitignore hash unchanged" "$ac12_before_hash" "$ac12_after_hash"

# AC-12 c4 (Step-6 finding C4): the .gitignore write must be SILENT when it
# cannot succeed. `printf '*\n' > "$f" 2>/dev/null` does not silence anything —
# the shell performs the redirection before printf runs, so the redirect's own
# failure is reported by the shell, not by printf. The paired `mkdir -p ...
# 2>/dev/null` above it IS correctly silenced, which is why the asymmetry reads
# as unintended rather than as a choice.
#
# Fixture: `.bionic` present as a REGULAR FILE at the project root, so the
# redirect fails with ENOTDIR. A hook is a tool-call gate — stderr on an ALLOWED
# call is noise the agent has to interpret.
# [WALL: hooks/canonical-sdlc-governing-skill.sh]
echo "AC-12 c4 (C4): an unwritable .gitignore path leaks nothing on stderr"
ac12_p5=$(make_bare_project)
: > "$ac12_p5/.bionic"
run_write "$ac12_p5/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$(build_plan)"
assert_eq "ac12_c4 write still allowed" 0 "$HOOK_EXIT"
assert_eq "ac12_c4 stderr is empty (no shell redirection error)" "" "$HOOK_STDERR"

# ============================================================
# AC-13: misplacement blocks; absence never does
# ============================================================
#
# The fail-open this closes: an artifact that DECLARES itself a canonical-sdlc
# artifact but lives outside the project's computed docs root used to fall out
# of the `case "$FILE_PATH"` scope check and exit 0 — written, ungated, in the
# wrong place. Slice 1 replaced the ancestor walk with resolve_project_root(),
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
# files carrying canonical-sdlc frontmatter (slice 6 put them there); they are
# placed, and c8 pins that they stay unblocked.
echo
echo "=== AC-13: misplacement blocks; absence never does ==="

ac13_p=$(make_project)
ac13_docs="$ac13_p/.bionic/docs"

echo "AC-13 c1: valid artifact written OUTSIDE the computed docs-root -> block, naming the correct path"
run_write "$ac13_p/docs/bionic/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c1 exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c1 says misplaced" "misplaced" "$HOOK_STDERR"
assert_contains "ac13_c1 names the correct path" "$ac13_docs/plans/" "$HOOK_STDERR"

echo "AC-13 c1b: 'governing-skill: canonical-sdlc' alone is enough to identify the artifact"
run_write "$ac13_p/notes/stray.md" '---
governing-skill: canonical-sdlc
---
body
'
assert_eq "ac13_c1b exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c1b says misplaced" "misplaced" "$HOOK_STDERR"

echo "AC-13 c2: the SAME artifact written INSIDE the computed docs-root -> passes"
run_write "$ac13_docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c2 exit 0" 0 "$HOOK_EXIT"

echo "AC-13 c3: the named path follows the artifact kind (spec -> specs/, adr -> adrs/)"
run_write "$ac13_p/docs/wave-01-x.spec.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c3 spec exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c3 spec names specs/" "$ac13_docs/specs/" "$HOOK_STDERR"
run_write "$ac13_p/docs/adr-001-thing.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c3 adr exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c3 adr names adrs/" "$ac13_docs/adrs/" "$HOOK_STDERR"

echo "AC-13 c4: Edit of an already-misplaced artifact blocks too (not just Write)"
mkdir -p "$ac13_p/legacy"
printf '%s' "$VALID_FRONTMATTER" > "$ac13_p/legacy/wave-02-y.plan.md"
run_edit "$ac13_p/legacy/wave-02-y.plan.md" "old" "new"
assert_eq "ac13_c4 exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c4 says misplaced" "misplaced" "$HOOK_STDERR"

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
canonical_sdlc_version: 13
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
assert_eq "ac13_c7 first artifact write is silent" "" "$HOOK_STDERR"

echo "AC-13 c7b: what blocks is the misplacement, not the absence -- same bare repo"
ac13_bare2=$(make_bare_project)
run_write "$ac13_bare2/docs/plans/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c7b exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c7b names the computed docs-root" "$ac13_bare2/.bionic/docs/plans/" "$HOOK_STDERR"

echo "AC-13 c8: under the docs-root but outside the four enforced subdirs -> placed, unblocked"
mkdir -p "$ac13_docs/spikes" "$ac13_docs/record"
run_write "$ac13_docs/spikes/spike-thing-20260101.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c8 spikes/ exit 0" 0 "$HOOK_EXIT"
run_write "$ac13_docs/record/wave-7-handoff.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c8 record/ exit 0" 0 "$HOOK_EXIT"

echo "AC-13 c9: 'the correct path' follows docs-root: in config.yaml, not a hardcoded .bionic/"
ac13_cfg=$(make_project)
printf 'docs-root: custom/docs\n' > "$ac13_cfg/.bionic/config.yaml"
mkdir -p "$ac13_cfg/custom/docs/plans/epic-01-demo"
run_write "$ac13_cfg/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c9 default location is now the misplaced one" 2 "$HOOK_EXIT"
assert_contains "ac13_c9 names the configured docs-root" "$ac13_cfg/custom/docs/plans/" "$HOOK_STDERR"
run_write "$ac13_cfg/custom/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c9 configured location passes" 0 "$HOOK_EXIT"

echo "AC-13 c10: a project reached through a SYMLINK is the same project"
# Slice 1 flagged this and handed it here: `git` answers with the PHYSICAL
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
ln -s "$ac13_sym/real" "$ac13_sym/link"
run_write "$ac13_sym/link/.bionic/docs/plans/epic-01-demo/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c10 correctly-placed artifact via a symlinked path exit 0" 0 "$HOOK_EXIT"
# The paired arm: resolving the symlink must not resolve away the enforcement.
run_write "$ac13_sym/link/docs/plans/wave-01-x.plan.md" "$VALID_FRONTMATTER"
assert_eq "ac13_c10 misplaced artifact via a symlinked path still exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_c10 misplaced-via-symlink names the real docs root" \
  "$ac13_sym/real/.bionic/docs/plans/" "$HOOK_STDERR"

# ============================================================
# AC-14: no session-state file
# ============================================================
#
# Live state is carried by the active plan's `## Handoff` and by
# `continuation.md`, and nothing else. Two halves:
#   (a) no `context.md`-shaped session-state file exists under the new layout;
#   (b) no shipped surface instructs anything to write one.
#
# `.bionic/docs/record/context.md` is EXEMPT: slice 6 relocated the old file
# there as an operational record of what happened, not as live state. The
# whole point of the AC is that nothing reads or writes it as session state.
#
# This lives in the governing-skill suite because AC-13 and AC-14 are one
# slice and this suite is the slice's surface; the assertion is about the
# repo's shipped text, not about this hook. Homed here rather than in a new
# suite so `tests/run.sh`'s suite count is unchanged.
echo
echo "=== AC-14: no session-state file under the new layout ==="

AC14_REPO="$(cd "$(dirname "$HOOK")/.." && pwd)"

echo "AC-14 a: the only context.md under the new docs layout is the exempt operational record"
TOTAL=$((TOTAL + 1))
ac14_stray=""
if [ -d "$AC14_REPO/.bionic/docs" ]; then
  ac14_stray=$(find "$AC14_REPO/.bionic/docs" -type f -name 'context.md' \
               ! -path "$AC14_REPO/.bionic/docs/record/context.md" 2>/dev/null)
fi
if [ -z "$ac14_stray" ]; then
  PASS=$((PASS + 1)); printf '  PASS  ac14_a no session-state context.md under .bionic/docs/\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac14_a session-state context.md found: %s\n' "$ac14_stray"
fi

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
TOTAL=$((TOTAL + 1))
if [ "${#AC14_SURFACES[@]}" -ge 10 ]; then
  PASS=$((PASS + 1)); printf '  PASS  ac14_b surface set is non-vacuous (%d files)\n' "${#AC14_SURFACES[@]}"
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac14_b surface set is vacuous (%d files) — the grep below proves nothing\n' "${#AC14_SURFACES[@]}"
fi

TOTAL=$((TOTAL + 1))
ac14_hits=$(grep -nEi "$AC14_WRITE_VERB" "${AC14_SURFACES[@]}" 2>/dev/null || true)
if [ -z "$ac14_hits" ]; then
  PASS=$((PASS + 1)); printf '  PASS  ac14_b no shipped surface instructs a context.md write\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac14_b shipped surfaces still instruct a context.md write:\n%s\n' "$ac14_hits"
fi

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
# `design:` line · waived=<full line> injects it verbatim.
build_spec() {
  local scale=wave section=yes design="OMIT" waived="OMIT" step=2
  local arg
  for arg in "$@"; do
    case "$arg" in
      scale=*)   scale="${arg#scale=}" ;;
      section=*) section="${arg#section=}" ;;
      design=*)  design="${arg#design=}" ;;
      waived=*)  waived="${arg#waived=}" ;;
      step=*)    step="${arg#step=}" ;;
    esac
  done

  local out='---
governing-skill: canonical-sdlc
sdlc-step: '"$step"'
epic: epic-01-demo
canonical_sdlc_version: 13
intent: build
rigor: audited
scale: '"$scale"'
'
  [ "$design" = OMIT ] || out+="design: $design"$'\n'
  [ "$waived" = OMIT ] || out+="$waived"$'\n'
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
echo "=== design wall: three-way rule (wave-02 AC-2, AC-3, AC-4) ==="

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
assert_contains "design_none names the pointer" "design:" "$HOOK_STDERR"
assert_contains "design_none names the waiver" "design-waived:" "$HOOK_STDERR"

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
assert_contains "design_pointer_dangling names the raw value" "specs/epic-01-demo/nowhere.spec.md" "$HOOK_STDERR"
assert_contains "design_pointer_dangling still names the three-way rule" "design-waived:" "$HOOK_STDERR"

echo "c5: design: pointer to a real file WITHOUT ## Design → block"
run_write "$DESIGN_SPECS/w5.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/no-design.spec.md)"
assert_eq "design_pointer_no_section exit 2" 2 "$HOOK_EXIT"
assert_contains "design_pointer_no_section names the target" "no-design.spec.md" "$HOOK_STDERR"

echo "c6: design: path with a .. component → block even though it would resolve to a real design"
run_write "$DESIGN_SPECS/w6.spec.md" \
  "$(build_spec section=no design=specs/epic-01-demo/../sibling.spec.md)"
assert_eq "design_pointer_dotdot exit 2" 2 "$HOOK_EXIT"
assert_contains "design_pointer_dotdot says the path climbs out" "climbs" "$HOOK_STDERR"
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
assert_contains "design_epic_scale names the three-way rule" "design-waived:" "$HOOK_STDERR"

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
assert_contains "design_fenced_in_place names the three-way rule" "design-waived:" "$HOOK_STDERR"
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
assert_contains "design_fenced_pointer_target names the target" "fenced-design.spec.md" "$HOOK_STDERR"
assert_contains "design_fenced_pointer_target says the target carries no section" "carries no flush-left" "$HOOK_STDERR"
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
assert_contains "design_pointer_cr_only_no_section says the target carries no section" "carries no flush-left" "$HOOK_STDERR"

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
assert_contains "design_combined_dangling names the raw value" "specs/epic-01-demo/nowhere.spec.md" "$HOOK_STDERR"

echo "c15b: in-place '## Design' + a '..' pointer → block"
run_write "$DESIGN_SPECS/w15b.spec.md" \
  "$(build_spec design=specs/epic-01-demo/../sibling.spec.md)"
assert_eq "design_combined_dotdot exit 2" 2 "$HOOK_EXIT"
assert_contains "design_combined_dotdot says the path climbs out" "climbs" "$HOOK_STDERR"

echo "c15c: in-place '## Design' + a pointer to a target that lacks the section → block"
run_write "$DESIGN_SPECS/w15c.spec.md" \
  "$(build_spec design=specs/epic-01-demo/no-design.spec.md)"
assert_eq "design_combined_no_section exit 2" 2 "$HOOK_EXIT"
assert_contains "design_combined_no_section says the target carries no section" "carries no flush-left" "$HOOK_STDERR"

echo "c15d: in-place '## Design' + a VALID pointer → allow (the documented combined shape)"
run_write "$DESIGN_SPECS/w15d.spec.md" \
  "$(build_spec design=specs/epic-01-demo/with-design.spec.md)"
assert_eq "design_combined_valid exit 0" 0 "$HOOK_EXIT"

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
echo "=== AC-13: pinned-root wall ==="

ac13_tmp=$(cd "$(mktemp -d)" && pwd -P); cleanup_dirs+=("$ac13_tmp")
ac13_main="$ac13_tmp/main"
mkdir -p "$ac13_main/.bionic/docs/record" "$ac13_main/subdir"
git -C "$ac13_main" init -q .
git -C "$ac13_main" commit -q --allow-empty -m init
# Absolute worktree path from the repo root, per .claude/rules/git-worktree-
# docs.md — `git worktree add` resolves relative paths against pwd, not the
# repo root.
git -C "$ac13_main" worktree add -q "$ac13_tmp/wt" -b ac13-wt
ac13_wt="$ac13_tmp/wt"

ac13_record_body='# operational artifact — no canonical-sdlc frontmatter at all'

echo "ac13-1: real worktree — operational write under the worktree's OWN .bionic/ → block, names pinned root"
run_write "$ac13_wt/.bionic/docs/record/w2-s8-ac13.md" "$ac13_record_body"
assert_eq "ac13_wt_write exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_wt_write names the pinned root" "Pinned root: $ac13_main/.bionic" "$HOOK_STDERR"
assert_contains "ac13_wt_write names the wrong tree it refused" "$ac13_wt/.bionic" "$HOOK_STDERR"
TOTAL=$((TOTAL + 1))
if [ ! -f "$ac13_wt/.bionic/docs/record/w2-s8-ac13.md" ]; then
  PASS=$((PASS + 1)); printf '  PASS  ac13_wt_write blocked write left no file behind\n'
else
  FAIL=$((FAIL + 1)); printf '  FAIL  ac13_wt_write blocked write left a file behind\n'
fi

echo "ac13-2: paired positive — the IDENTICAL write to the pinned root passes"
run_write "$ac13_main/.bionic/docs/record/w2-s8-ac13.md" "$ac13_record_body"
assert_eq "ac13_pinned_pair exit 0" 0 "$HOOK_EXIT"

echo "ac13-3: plain cd-into-subdir — a stray .bionic a level down in the SAME repo (no worktree) → block, names pinned root"
# NOT a subshell: run_write sets HOOK_EXIT/HOOK_STDERR as globals the assert
# calls below read, and a `(cd ... && run_write ...)` subshell would strand
# those assignments where the assertions can never see them. cd back
# immediately after, before any other test in this file runs.
ac13_orig_pwd=$(pwd)
cd "$ac13_main/subdir"
run_write "$ac13_main/subdir/.bionic/docs/record/w2-s8-ac13-sub.md" "$ac13_record_body"
cd "$ac13_orig_pwd"
assert_eq "ac13_subdir_write exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_subdir_write names the pinned root" "Pinned root: $ac13_main/.bionic" "$HOOK_STDERR"

echo "ac13-4: paired positive — the IDENTICAL subdir-case write to the pinned root passes"
run_write "$ac13_main/.bionic/docs/record/w2-s8-ac13-sub.md" "$ac13_record_body"
assert_eq "ac13_subdir_pinned_pair exit 0" 0 "$HOOK_EXIT"

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
assert_eq "ac13_traversal_missing exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_traversal_missing names the escaped-to tree" \
  "$ac13_sibling/.bionic" "$HOOK_STDERR"
assert_contains "ac13_traversal_missing names the pinned root" \
  "Pinned root: $ac13_main/.bionic" "$HOOK_STDERR"

echo "ac13-7: the same escape through EXISTING segments (control) still blocks"
# The control the cs review used to prove the first case was about resolution, not about
# escaping: identical destination, every segment on the way there real.
run_write "$ac13_main/.bionic/docs/../../../other/.bionic/docs/record/w2-r4-esc2.md" \
  "$ac13_record_body"
assert_eq "ac13_traversal_existing exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_traversal_existing names the escaped-to tree" \
  "$ac13_sibling/.bionic" "$HOOK_STDERR"

echo 'ac13-8: paired positive — a climbing path that folds back ONTO the pinned root passes'
# The discriminator against a fix that refuses every climb outright: folding is not
# refusing, and a legitimate write spelled with a climb through a segment that does not
# exist yet — the exact shape ac13-6 escapes through — still lands.
run_write "$ac13_main/.bionic/nonexistent/../docs/record/w2-r4-legit.md" \
  "$ac13_record_body"
assert_eq "ac13_traversal_pinned_pair exit 0" 0 "$HOOK_EXIT"

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
assert_eq "ac13_nested exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_nested names the nested tree it refused" \
  "$ac13_main/.bionic/tmp/scratch/.bionic" "$HOOK_STDERR"
assert_contains "ac13_nested names the pinned root" \
  "Pinned root: $ac13_main/.bionic" "$HOOK_STDERR"

echo "ac13-10: paired positive — the pinned tree's own operational path is untouched"
# The nested rule must not catch the ordinary write it sits next to.
run_write "$ac13_main/.bionic/tmp/scratch/notes.md" "$ac13_record_body"
assert_eq "ac13_nested_pair exit 0" 0 "$HOOK_EXIT"

echo "ac13-5: canonical (frontmatter-declaring) misplacement is still the AC-10 arm, unchanged — this wall is additive"
run_write "$ac13_wt/.bionic/docs/plans/epic-01-demo/w2-s8-ac13-canon.plan.md" \
  "$(build_plan intent=spike rigor=audited)"
assert_eq "ac13_canonical_still_ac10_arm exit 2" 2 "$HOOK_EXIT"
assert_contains "ac13_canonical_still_ac10_arm keeps the AC-10 misplacement wording" \
  "is misplaced" "$HOOK_STDERR"
assert_contains "ac13_canonical_still_ac10_arm names the pinned docs root, AC-10's shape" \
  "$ac13_main/.bionic/docs/plans/" "$HOOK_STDERR"

echo
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$TOTAL" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
