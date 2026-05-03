#!/bin/bash
# DISPATCH GATE: PreToolUse|Agent hook for canonical-sdlc autonomous-mode
# plans. Reads .bionic/sdlc-dispatch-rules.json and the active plan's
# frontmatter, then either:
#   - allows (subagent matches the rule, or rule is permissive),
#   - logs a mismatch / ambiguity to .bionic/memory/dispatch-audit.md
#     (when dispatch_enforce: false — Wave 2 default),
#   - blocks the call with exit 2 (when dispatch_enforce: true and the
#     subagent doesn't match the rule).
#
# Pass-through when:
#   - tool_name != Agent
#   - no active plan or plan has no canonical-sdlc frontmatter
#   - governing-skill != canonical-sdlc
#   - mode != autonomous (other modes have their own rule sets, deferred)
#   - canonical_sdlc_version: 1 (legacy plans grandfathered out)
#   - rules JSON missing (project not opted in)
#   - rules JSON malformed (fail-open with stderr warning — never break
#     the workflow on a bad config; the user can fix and retry)
#   - active rule resolves to agent: null (no specialist required)
#   - rule has no `when` match and no `default` for the phase
#   - dispatch_override:"<reason>" detected in prompt → log + allow
#
# See: docs/bionic/plans/canonical-sdlc-autonomous-redesign.md §1.3.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -uo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL_NAME" != "Agent" ] && exit 0

# ---------- locate plan + parse frontmatter ----------

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(echo "$INPUT" | jq -r '.cwd // empty')
fi
[ -z "$PROJECT_ROOT" ] && PROJECT_ROOT=$(pwd)

# Newest *.plan.md / continuation*.md under docs/bionic/plans/ at depth
# up to 3 (the bionic directory-per-epic layout is depth 2; flat plans
# at depth 1).
find_active_plan() {
  local plan_dir="$1/docs/bionic/plans"
  [ ! -d "$plan_dir" ] && return
  local newest="" newest_mtime=0
  while IFS= read -r -d '' f; do
    local m
    m=$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)
    if [ -n "$m" ] && [ "$m" -gt "$newest_mtime" ]; then
      newest_mtime="$m"
      newest="$f"
    fi
  done < <(find "$plan_dir" -maxdepth 3 -type f \
    \( -name '*.plan.md' -o -name 'continuation*.md' -o -name '*.md' \) \
    -print0 2>/dev/null)
  echo "$newest"
}

PLAN_FILE=$(find_active_plan "$PROJECT_ROOT")
[ -z "$PLAN_FILE" ] && exit 0
[ ! -f "$PLAN_FILE" ] && exit 0

extract_frontmatter() {
  awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$1"
}

FRONTMATTER=$(extract_frontmatter "$PLAN_FILE")
[ -z "$FRONTMATTER" ] && exit 0

yaml_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' \
    | sed -E "s/^['\"]//;s/['\"]\$//"
}

GOVERNING=$(yaml_get governing-skill)
[ "$GOVERNING" != "canonical-sdlc" ] && exit 0

MODE=$(yaml_get mode)
[ "$MODE" != "autonomous" ] && exit 0

SDLC_VERSION=$(yaml_get canonical_sdlc_version)
[ "$SDLC_VERSION" = "1" ] && exit 0

STEP=$(yaml_get sdlc-step)

# Map step number → phase key in rules JSON.
map_step_to_phase_key() {
  case "$1" in
    0)  echo "phase_0_prereqs" ;;
    1)  echo "phase_1_ideate" ;;
    2)  echo "phase_2_spec" ;;
    3)  echo "phase_3_plan" ;;
    4)  echo "phase_4_isolate" ;;
    5)  echo "phase_5_implement" ;;
    6)  echo "phase_6_browser_verify" ;;
    7)  echo "phase_7_verify_done" ;;
    8)  echo "phase_8_review" ;;
    8b|8B) echo "phase_8b_adversarial" ;;
    9)  echo "phase_9_document" ;;
    10) echo "phase_10_commit" ;;
    11) echo "phase_11_external_review" ;;
    12) echo "phase_12_finish" ;;
    13) echo "phase_13_ship" ;;
    *)  echo "" ;;
  esac
}

PHASE_KEY=$(map_step_to_phase_key "$STEP")
[ -z "$PHASE_KEY" ] && exit 0

DISPATCH_ENFORCE=$(yaml_get dispatch_enforce)
ENFORCE_MODE="${DISPATCH_ENFORCE:-false}"

SUBAGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // "fork"')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')

# ---------- audit log helpers ----------

AUDIT_LOG="$PROJECT_ROOT/.bionic/memory/dispatch-audit.md"

ensure_audit_header() {
  if [ ! -f "$AUDIT_LOG" ]; then
    mkdir -p "$(dirname "$AUDIT_LOG")"
    cat > "$AUDIT_LOG" <<'EOF'
# Dispatch Audit

Append-only. Each entry = one Agent dispatch event flagged by
canonical-sdlc-dispatch-gate.sh.

Entry kinds:
- `override`         — agent included `dispatch_override:"<reason>"` in the prompt; bypass logged.
- `log-only-single`  — single-agent rule mismatch with `dispatch_enforce: false`; not blocked.
- `log-only-parallel` — parallel-rule mismatch with `dispatch_enforce: false`; not blocked.

Review monthly: recurring overrides or log-only mismatches are signals to update
`.bionic/sdlc-dispatch-rules.json`.

EOF
  fi
}

# Append a structured entry to the audit log.
#   $1 kind: "override" | "log-only-single" | "log-only-parallel"
#   $2 expected (single agent or "[a, b]")
#   $3 got (subagent_type passed to Agent)
#   $4 reason (free text)
log_audit() {
  local kind="$1" expected="$2" got="$3" reason="$4"
  ensure_audit_header
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)
  local plan_rel="$PLAN_FILE"
  case "$plan_rel" in
    "$PROJECT_ROOT"/*) plan_rel="${plan_rel#"$PROJECT_ROOT/"}" ;;
  esac
  {
    echo "---"
    echo ""
    echo "## ${ts} — plan: ${plan_rel}"
    echo ""
    echo "- mode: ${kind}"
    echo "- step: ${STEP}"
    echo "- expected: ${expected}"
    echo "- got: ${got}"
    echo "- reason: ${reason}"
    echo ""
  } >> "$AUDIT_LOG"
}

# ---------- override detection (skill-level escape hatch) ----------

if echo "$PROMPT" | grep -qE 'dispatch_override:[[:space:]]*"[^"]+"'; then
  REASON=$(echo "$PROMPT" \
    | grep -oE 'dispatch_override:[[:space:]]*"[^"]+"' \
    | head -1 \
    | sed -E 's/^dispatch_override:[[:space:]]*"//;s/"$//')
  log_audit "override" "(any required)" "$SUBAGENT" "$REASON"
  exit 0
fi

# ---------- load rules ----------

RULES_FILE="$PROJECT_ROOT/.bionic/sdlc-dispatch-rules.json"
[ ! -f "$RULES_FILE" ] && exit 0

if ! jq empty "$RULES_FILE" 2>/dev/null; then
  echo "WARN: dispatch-gate: $RULES_FILE is malformed JSON; allowing dispatch (fail-open)." >&2
  exit 0
fi

PHASE_RULES=$(jq -c ".phases.${PHASE_KEY} // empty" "$RULES_FILE" 2>/dev/null)
[ -z "$PHASE_RULES" ] || [ "$PHASE_RULES" = "null" ] && exit 0

# ---------- predicate evaluator ----------
# Grammar (subset of design §1.1.2 — only what §1.1.3 actually uses):
#   <flag> == 'value'    — string equality (single-quoted RHS)
#   <flag> == true|false — boolean equality (bare RHS)
#   <atom1> && <atom2>   — conjunction of any two atoms above

eval_atom() {
  local atom
  atom=$(echo "$1" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  [ -z "$atom" ] && return 0  # empty atom is vacuously true

  local lhs rhs
  lhs=$(echo "$atom" | sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*==[[:space:]]*.*$/\1/p')
  rhs=$(echo "$atom" | sed -nE 's/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*==[[:space:]]*(.+)$/\1/p')
  if [ -z "$lhs" ] || [ -z "$rhs" ]; then
    return 1  # malformed — treat as no-match
  fi
  rhs=$(echo "$rhs" | sed -E "s/^'(.*)'\$/\1/")
  rhs=$(echo "$rhs" | sed -E 's/[[:space:]]+$//')

  local actual
  actual=$(yaml_get "$lhs")
  [ "$actual" = "$rhs" ]
}

eval_predicate() {
  local pred="$1" atom
  # Split on "&&" into atoms; each atom must hold for the predicate to.
  while IFS= read -r atom; do
    eval_atom "$atom" || return 1
  done < <(echo "$pred" | awk -v RS='&&' '{print}')
  return 0
}

# ---------- walk the rule list ----------
#
# First pass: find the first `when` rule that matches, or any `always`
# rule. If none match, fall through to the first `default` rule.

n_rules=$(echo "$PHASE_RULES" | jq 'length')
matched_rule=""

for i in $(seq 0 $((n_rules - 1))); do
  rule=$(echo "$PHASE_RULES" | jq -c ".[$i]")
  always=$(echo "$rule" | jq -r '.always // false')
  when=$(echo "$rule" | jq -r '.when // empty')
  if [ "$always" = "true" ]; then
    matched_rule="$rule"
    break
  fi
  if [ -n "$when" ] && eval_predicate "$when"; then
    matched_rule="$rule"
    break
  fi
done

if [ -z "$matched_rule" ]; then
  for i in $(seq 0 $((n_rules - 1))); do
    rule=$(echo "$PHASE_RULES" | jq -c ".[$i]")
    is_default=$(echo "$rule" | jq -r '.default // false')
    if [ "$is_default" = "true" ]; then
      matched_rule="$rule"
      break
    fi
  done
fi

# No rule applied at all → not opted in for this phase.
[ -z "$matched_rule" ] && exit 0

# ---------- enforce the matched rule ----------

is_parallel=$(echo "$matched_rule" | jq -r '.parallel // false')
single_agent=$(echo "$matched_rule" | jq -r '.agent // empty')

# agent: null (literal JSON null serializes via -r as "null" string;
# missing key yields empty). Both mean "no specialist required".
if [ "$is_parallel" != "true" ]; then
  if [ -z "$single_agent" ] || [ "$single_agent" = "null" ]; then
    exit 0
  fi
  if [ "$SUBAGENT" = "$single_agent" ]; then
    exit 0
  fi
  if [ "$ENFORCE_MODE" = "true" ]; then
    echo "BLOCKED: dispatch-gate: Step ${STEP} requires subagent_type='${single_agent}', got '${SUBAGENT}'." >&2
    echo "Path: $PLAN_FILE" >&2
    echo "Fix: dispatch with subagent_type='${single_agent}', or add 'dispatch_override:\"<one-line reason>\"' to the prompt to override (logged for review)." >&2
    exit 2
  else
    log_audit "log-only-single" "$single_agent" "$SUBAGENT" "rules-mismatch (dispatch_enforce=false)"
    exit 0
  fi
fi

# Parallel rule: SUBAGENT must be one of .agents[]. The companion
# "did the agent dispatch ALL required" check is deferred (design §1.4).
required_list=$(echo "$matched_rule" | jq -r '.agents[]' 2>/dev/null)
if [ -z "$required_list" ]; then
  exit 0
fi

if echo "$required_list" | grep -qx "$SUBAGENT"; then
  exit 0
fi

# Build a comma-joined list for messages / audit.
required_csv=$(echo "$required_list" | paste -sd, -)
required_pretty=$(echo "$required_list" | paste -sd, - | sed 's/,/, /g')

if [ "$ENFORCE_MODE" = "true" ]; then
  echo "BLOCKED: dispatch-gate: Step ${STEP} requires parallel dispatch to one of [${required_pretty}]; got '${SUBAGENT}'." >&2
  echo "Path: $PLAN_FILE" >&2
  echo "Fix: use multiple Agent tool calls in one message — one per required agent. To override (logged), include 'dispatch_override:\"<reason>\"' in the prompt." >&2
  exit 2
else
  log_audit "log-only-parallel" "[${required_csv}]" "$SUBAGENT" "rules-mismatch (dispatch_enforce=false)"
  exit 0
fi
