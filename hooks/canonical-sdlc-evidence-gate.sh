#!/bin/bash
# EVIDENCE GATE: Blocks git commits during a canonical-sdlc run when the
# plan file's ## SDLC State section is missing the current step's evidence.
#
# Convention: the plan file contains a section like:
#
#   ## SDLC State
#   mode: overnight
#   integration-branch: main
#   current: 5
#   Step 1: /path/or/link
#   Step 2: /path/to/spec.md
#   Step 3: docs/bionic/plans/epic-NN-<slug>/wave-NN-<slug>.plan.md
#   Step 4: git worktree at /path, base SHA abc123
#   Step 5: tests passing, commit abc123
#
# The hook also accepts `Phase N:` lines for backward compatibility with
# in-flight plans written under the prior "phase" vocabulary. Both forms
# are parsed; new plans should use `Step N:`.
#
# If the current step's line is empty or a placeholder (TODO, pending,
# in progress, XXX, TBD, placeholder), block the commit. The rule is:
# the evidence artifact must be recorded in the plan file *before* the
# commit that closes the step.
#
# Plans without ## SDLC State pass through unblocked — this hook only
# enforces against canonical-sdlc runs.
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Not a Bash tool call or empty command — nothing to gate.
if [ -z "$COMMAND" ]; then
  exit 0
fi

# Is any segment of the command a `git commit`? Parse segments split on
# &&, ||, ; like protect-main.sh. Ignore content inside quotes (commit
# messages often contain "git commit" as prose).
IS_COMMIT=0
while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"
  stripped=$(echo "$segment" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
  if echo "$stripped" | grep -qE '(^|[[:space:]])git[[:space:]]+commit([[:space:]]|$)'; then
    IS_COMMIT=1
    break
  fi
done <<< "$(echo "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g')"

if [ "$IS_COMMIT" -eq 0 ]; then
  exit 0
fi

# Locate the newest plan file across the supported plan-directory
# conventions:
#   - ~/.claude/plans/            (Claude Code global convention)
#   - <project>/docs/bionic/plans/ (bionic canonical-sdlc convention)
#   - <project>/docs/superpowers/plans/ (superpowers convention)
#
# Picks the newest .md across all that exist. If none exist, this isn't a
# canonical-sdlc session — let the commit through.
#
# Project resolution mirrors memory-update.sh: CLAUDE_PROJECT_DIR first,
# then the hook input's cwd field, then pwd. Consistent with existing hooks.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty')
fi
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(pwd)
fi

# Resolve the per-project docs root: <project>/.bionic/config.yaml's
# `docs-root:` if set, else default <project>/.bionic/docs. See
# canonical-sdlc-dispatch-gate.sh for the same helper.
resolve_docs_root() {
  local proj="$1"
  local config="$proj/.bionic/config.yaml"
  if [ -f "$config" ]; then
    local override
    override=$(grep -E '^[[:space:]]*docs-root[[:space:]]*:' "$config" 2>/dev/null \
      | head -1 \
      | sed -E 's/^[[:space:]]*docs-root[[:space:]]*:[[:space:]]*//' \
      | sed -E "s/^['\"]//;s/['\"]\$//" \
      | sed -E 's/[[:space:]]+$//')
    if [ -n "$override" ]; then
      case "$override" in
        /*) echo "$override" ;;
        *)  echo "$proj/$override" ;;
      esac
      return
    fi
  fi
  echo "$proj/.bionic/docs"
}

PLAN_DIRS=( "${HOME}/.claude/plans" )
if [ -n "$PROJECT_DIR" ]; then
  DOCS_ROOT=$(resolve_docs_root "$PROJECT_DIR")
  PLAN_DIRS+=(
    "${DOCS_ROOT}/plans"
    "${DOCS_ROOT}/incidents"
    "${PROJECT_DIR}/docs/superpowers/plans"
  )
fi

PLAN=""
for d in "${PLAN_DIRS[@]}"; do
  [ -d "$d" ] || continue
  # Descend up to 2 levels deep to support the bionic directory-per-epic
  # layout: docs/bionic/plans/epic-NN-<slug>/wave-NN-<slug>.plan.md.
  # Flat conventions (~/.claude/plans/<name>.md) are still covered at
  # depth 1.
  while IFS= read -r -d '' f; do
    if [ -z "$PLAN" ] || [ "$f" -nt "$PLAN" ]; then
      PLAN="$f"
    fi
  done < <(find "$d" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
done

if [ -z "$PLAN" ] || [ ! -f "$PLAN" ]; then
  exit 0
fi

# The newest plan has no ## SDLC State section → not a canonical-sdlc run.
if ! grep -q '^## SDLC State' "$PLAN"; then
  exit 0
fi

# Extract YAML frontmatter (between first two `---` lines at column 0)
# if the plan has any. Used to read `evidence_schema` and `deploy_target`
# for v2 shape enforcement; absent on legacy plans, in which case the
# hook reverts to presence-only behavior.
FRONTMATTER=$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$PLAN")

frontmatter_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' \
    | sed -E "s/^['\"]//;s/['\"]\$//"
}

EVIDENCE_SCHEMA=$(frontmatter_get evidence_schema)
DEPLOY_TARGET=$(frontmatter_get deploy_target)
SDLC_VERSION=$(frontmatter_get canonical_sdlc_version)
USE_WORKTREE=$(frontmatter_get use_worktree)

# Extract the ## SDLC State section (from its header up to the next ##
# header or EOF).
SECTION=$(awk '/^## SDLC State/{flag=1; next} /^## /{flag=0} flag' "$PLAN")

if [ -z "$SECTION" ]; then
  echo "BLOCKED: canonical-sdlc plan file has an empty '## SDLC State' section." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: populate the section with 'current: N' and per-step evidence lines." >&2
  exit 2
fi

# Parse current step. Accepts integers (1-13) and the 8b adversarial
# critic step.
CURRENT=$(echo "$SECTION" \
          | grep -E '^[[:space:]]*current[[:space:]]*:' \
          | head -1 \
          | sed -E 's/^[[:space:]]*current[[:space:]]*:[[:space:]]*//' \
          | tr -d '[:space:]')

if [ -z "$CURRENT" ] || ! echo "$CURRENT" | grep -qE '^[0-9]+[ab]?$'; then
  echo "BLOCKED: canonical-sdlc plan file's '## SDLC State' section is missing a valid 'current: N' line." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: add a line like 'current: 5' (or 'current: 8b') before committing." >&2
  exit 2
fi

# Find the evidence line for the current step. Accepts both "Step N:"
# (current vocabulary) and "Phase N:" (legacy plans), with or without a
# leading list marker. New plans should use "Step"; "Phase" is retained
# for backward compatibility.
LINE=$(echo "$SECTION" \
       | grep -E "^[[:space:]]*-?[[:space:]]*(Step|Phase)[[:space:]]+${CURRENT}[[:space:]]*:" \
       | head -1)

if [ -z "$LINE" ]; then
  echo "BLOCKED: canonical-sdlc plan file has no 'Step ${CURRENT}:' line in '## SDLC State'." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: add the evidence artifact for step ${CURRENT} before committing." >&2
  exit 2
fi

RAW_VALUE=$(echo "$LINE" | sed -E "s/^[[:space:]]*-?[[:space:]]*(Step|Phase)[[:space:]]+${CURRENT}[[:space:]]*:[[:space:]]*//")

# v2 multi-line form: when the Step line has no inline content, evidence
# may live on indented continuation lines below. Collect them so the
# rest of the hook treats `Step N:\n  field: value\n  ...` as non-empty
# evidence.
extract_continuation() {
  local section="$1" step="$2"
  local sline
  sline=$(echo "$section" | grep -nE "^[[:space:]]*-?[[:space:]]*(Step|Phase)[[:space:]]+${step}[[:space:]]*:" | head -1 | cut -d: -f1)
  [ -z "$sline" ] && return
  echo "$section" | awk -v start="$sline" '
    NR > start {
      if ($0 ~ /^[[:space:]]*-?[[:space:]]*(Step|Phase)[[:space:]]+[0-9]+[ab]?[[:space:]]*:/) exit
      if ($0 ~ /^[^[:space:]]/) exit
      if ($0 ~ /^[[:space:]]*$/) next
      print $0
    }
  '
}

CONTINUATION=$(extract_continuation "$SECTION" "$CURRENT")

# Combined block used for empty/placeholder/shape checks.
BLOCK=$RAW_VALUE
if [ -n "$CONTINUATION" ]; then
  BLOCK="${BLOCK}
${CONTINUATION}"
fi
BLOCK_STRIPPED=$(echo "$BLOCK" | tr -d '[:space:]')

if [ -z "$BLOCK_STRIPPED" ]; then
  echo "BLOCKED: canonical-sdlc step ${CURRENT} evidence line is empty in '## SDLC State'." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: record the evidence artifact (commit SHA, path, link) for step ${CURRENT} before committing." >&2
  exit 2
fi

# Placeholder detection. Compare lowercase, whitespace-stripped value
# against a set of known placeholder tokens.
NORM=$(echo "$BLOCK_STRIPPED" | tr '[:upper:]' '[:lower:]')
case "$NORM" in
  *todo*|*pending*|*inprogress*|*xxx*|*tbd*|*placeholder*)
    echo "BLOCKED: canonical-sdlc step ${CURRENT} evidence line is a placeholder (\"${BLOCK}\")." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: replace with the actual evidence artifact before committing." >&2
    exit 2
    ;;
esac

# ---------- shape validation (v2 evidence_schema or v3 plans) ----------
# Legacy plans (no evidence_schema, no v3 marker) stop here — presence
# + placeholder check is the full contract.
#
# v3 plans (canonical_sdlc_version: 3) use a renumbered shape switch:
#   - Step 4 (Implement) — pointer step, optionally worktree fields when use_worktree=true
#   - Step 5 (Browser verify) — devtools-trace OR n/a
#   - Step 6 (Verify done) — cmd/pass/total/output
#   - Step 7 (Self-review) — pointer step
#   - Step 8 (Adversarial critic) — pointer step
#   - Step 9 (Document) — adr OR rca OR n/a
#   - Step 10 (Commit) — commit/subject/files
#   - Step 11 (External review) — pr OR n/a
#   - Step 12 (Finish branch) — merge/worktree-removed
#   - Step 13 (Post-merge cleanup) — cleanup/tmp-wiped/tasks-completed OR n/a
#   - Step 14 (Ship) — deploy/verified-at/monitor OR n/a
#
# v2 plans (canonical_sdlc_version: 2 or evidence_schema: v2) use the
# original shape switch with old step numbers including Step 4
# (worktree) and Step 8b (adversarial critic).

# v4 uses the same per-step evidence shape table as v3 — the v4 bump added
# a required `model_plan` frontmatter field (enforced by the governing-skill
# hook), which changes no per-step evidence shape.
#
# v5 (gate-collapse) renumbers and merges steps, so it has its own shape
# switch:
#   - Step 5 (Verify gate) — cmd/pass/total/output (tests modality, pass==total)
#     AND devtools-trace OR n/a (browser modality)
#   - Step 6 (Review gate) — pointer step
#   - Step 7 (Document) — adr OR rca OR n/a   (was v3 Step 9)
#   - Step 8 (External review) — pr OR n/a    (was v3 Step 11)
#   - Step 9 (Integrate & close) — merge/worktree-removed AND cleanup triple
#     OR cleanup: n/a   (merge of v3 Steps 12 + 13)
#   - Step 10 (Ship) — deploy/verified-at/monitor OR n/a   (was v3 Step 14)
#   Commit is a cross-cutting rhythm, not a numbered step (no Step 10 commit shape).
if [ "$SDLC_VERSION" = "5" ]; then
  SHAPE_MODE="v5"
elif [ "$SDLC_VERSION" = "3" ] || [ "$SDLC_VERSION" = "4" ]; then
  SHAPE_MODE="v3"
elif [ "$EVIDENCE_SCHEMA" = "v2" ]; then
  SHAPE_MODE="v2"
else
  exit 0
fi

# Pointer steps differ between schema versions due to renumbering.
if [ "$SHAPE_MODE" = "v5" ]; then
  case "$CURRENT" in
    1|2|3|4|6)
      # Step 4 is a pointer step in v5 BUT may include worktree fields when
      # use_worktree=true; Step 6 (Review) is always a pointer step.
      if [ "$CURRENT" = "4" ] && [ "$USE_WORKTREE" = "true" ]; then
        : # fall through to shape check below
      else
        exit 0
      fi
      ;;
  esac
elif [ "$SHAPE_MODE" = "v3" ]; then
  case "$CURRENT" in
    1|2|3|4|7|8)
      # Step 4 is a pointer step in v3 BUT may include worktree fields
      # when use_worktree=true. We let the pointer-step exit happen
      # only when use_worktree is not true.
      if [ "$CURRENT" = "4" ] && [ "$USE_WORKTREE" = "true" ]; then
        : # fall through to shape check below
      else
        exit 0
      fi
      ;;
  esac
else
  case "$CURRENT" in
    1|2|3|5|8|8b)
      exit 0
      ;;
  esac
fi

# Extract a value for a key from the BLOCK ("key: value" lines or
# "key: value" appearing on the Step line directly). Returns empty if
# not found.
block_get() {
  local key="$1"
  echo "$BLOCK" \
    | grep -E "^[[:space:]]*${key}[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

block_has() {
  echo "$BLOCK" | grep -qE "^[[:space:]]*$1[[:space:]]*:"
}

block_has_na() {
  block_has "n/a"
}

shape_block() {
  local missing=()
  for f in "$@"; do
    if ! block_has "$f"; then
      missing+=("$f")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "BLOCKED: canonical-sdlc step ${CURRENT} evidence missing required field(s): ${missing[*]}" >&2
    echo "Plan: $PLAN" >&2
    echo "Required for step ${CURRENT} (evidence_schema: v2): $*" >&2
    echo "Fix: rewrite the Step ${CURRENT} block as multi-line YAML-style fields. See canonical-sdlc/SKILL.md \"Evidence (three-tier)\" → verification shape table." >&2
    exit 2
  fi
}

if [ "$SHAPE_MODE" = "v5" ]; then
  # v5 shape switch — gate-collapsed steps.
  case "$CURRENT" in
    4)
      # use_worktree=true case: require worktree/base-sha/branch fields.
      # (When use_worktree=false we exited above as a pointer step.)
      shape_block worktree base-sha branch
      ;;
    5)
      # Verify gate: tests modality (cmd/pass/total/output, pass==total) is
      # always required; browser modality is devtools-trace OR n/a.
      shape_block cmd pass total output
      pass=$(block_get pass)
      total=$(block_get total)
      if ! echo "$pass" | grep -qE '^[0-9]+$' || ! echo "$total" | grep -qE '^[0-9]+$'; then
        echo "BLOCKED: canonical-sdlc v5 step 5 'pass:' and 'total:' must be integers (got pass='${pass}', total='${total}')." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      if [ "$pass" -ne "$total" ]; then
        echo "BLOCKED: canonical-sdlc v5 step 5 evidence has pass=${pass} but total=${total}; the suite is not fully green." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: do not commit step 5 until pass equals total." >&2
        exit 2
      fi
      if ! block_has devtools-trace && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc v5 step 5 (Verify) browser modality requires 'devtools-trace: <path>' or 'n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: add the browser-evidence path, or 'n/a:' with a reason. See SKILL.md verification shape table." >&2
        exit 2
      fi
      ;;
    7)
      if ! block_has adr && ! block_has rca && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc v5 step 7 evidence requires 'adr: <path>', 'rca: <path>' (incident-response mode), or 'n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      ;;
    8)
      if ! block_has pr && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc v5 step 8 evidence requires either 'pr: <url>' or 'n/a: <reason>' (e.g. 'n/a: PR-less workflow')." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      ;;
    9)
      # Integrate & close: merge is always required; cleanup is the triple
      # (cleanup/tmp-wiped/tasks-completed) OR the explicit `cleanup: n/a`
      # marker (cleanup_on_finish=false case).
      shape_block merge worktree-removed
      cleanup_val=$(block_get cleanup)
      case "$cleanup_val" in
        n/a|n/a:*)
          : # cleanup_on_finish=false / already-cleaned case (reason optional)
          ;;
        *)
          shape_block cleanup tmp-wiped tasks-completed
          ;;
      esac
      ;;
    10)
      if block_has_na; then
        if [ -n "$DEPLOY_TARGET" ] && [ "$DEPLOY_TARGET" != "none" ]; then
          echo "BLOCKED: canonical-sdlc v5 step 10 'n/a:' is only valid when deploy_target=none in frontmatter (got deploy_target=${DEPLOY_TARGET})." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: provide 'deploy:', 'verified-at:', and 'monitor:' fields, or change deploy_target to none." >&2
          exit 2
        fi
      else
        shape_block deploy verified-at monitor
      fi
      ;;
  esac
elif [ "$SHAPE_MODE" = "v3" ]; then
  # v3 shape switch — renumbered steps.
  case "$CURRENT" in
    4)
      # use_worktree=true case: require worktree/base-sha/branch fields.
      # (When use_worktree=false we exited above as a pointer step.)
      shape_block worktree base-sha branch
      ;;
    5)
      if ! block_has devtools-trace && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc v3 step 5 evidence requires either 'devtools-trace: <path>' or 'n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: pick one. See SKILL.md verification shape table." >&2
        exit 2
      fi
      ;;
    6)
      shape_block cmd pass total output
      pass=$(block_get pass)
      total=$(block_get total)
      if ! echo "$pass" | grep -qE '^[0-9]+$' || ! echo "$total" | grep -qE '^[0-9]+$'; then
        echo "BLOCKED: canonical-sdlc v3 step 6 'pass:' and 'total:' must be integers (got pass='${pass}', total='${total}')." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      if [ "$pass" -ne "$total" ]; then
        echo "BLOCKED: canonical-sdlc v3 step 6 evidence has pass=${pass} but total=${total}; the suite is not fully green." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: do not commit step 6 until pass equals total." >&2
        exit 2
      fi
      ;;
    9)
      if ! block_has adr && ! block_has rca && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc v3 step 9 evidence requires 'adr: <path>', 'rca: <path>' (incident-response mode), or 'n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      ;;
    10)
      shape_block commit subject files
      ;;
    11)
      if ! block_has pr && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc v3 step 11 evidence requires either 'pr: <url>' or 'n/a: <reason>' (e.g. 'n/a: PR-less workflow')." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      ;;
    12)
      shape_block merge worktree-removed
      ;;
    13)
      if block_has_na; then
        : # n/a is acceptable for Step 13 (cleanup_on_finish=false case)
      else
        shape_block cleanup tmp-wiped tasks-completed
      fi
      ;;
    14)
      if block_has_na; then
        if [ -n "$DEPLOY_TARGET" ] && [ "$DEPLOY_TARGET" != "none" ]; then
          echo "BLOCKED: canonical-sdlc v3 step 14 'n/a:' is only valid when deploy_target=none in frontmatter (got deploy_target=${DEPLOY_TARGET})." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: provide 'deploy:', 'verified-at:', and 'monitor:' fields, or change deploy_target to none." >&2
          exit 2
        fi
      else
        shape_block deploy verified-at monitor
      fi
      ;;
  esac
else
  # v2 shape switch — original step numbers (preserved for backwards compat).
  case "$CURRENT" in
    4)
      shape_block worktree base-sha branch
      ;;
    6)
      if ! block_has devtools-trace && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc step 6 evidence requires either 'devtools-trace: <path>' or 'n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: pick one. See SKILL.md verification shape table." >&2
        exit 2
      fi
      ;;
    7)
      shape_block cmd pass total output
      pass=$(block_get pass)
      total=$(block_get total)
      if ! echo "$pass" | grep -qE '^[0-9]+$' || ! echo "$total" | grep -qE '^[0-9]+$'; then
        echo "BLOCKED: canonical-sdlc step 7 'pass:' and 'total:' must be integers (got pass='${pass}', total='${total}')." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      if [ "$pass" -ne "$total" ]; then
        echo "BLOCKED: canonical-sdlc step 7 evidence has pass=${pass} but total=${total}; the suite is not fully green." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: do not commit step 7 until pass equals total." >&2
        exit 2
      fi
      ;;
    9)
      if ! block_has adr && ! block_has rca && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc step 9 evidence requires 'adr: <path>', 'rca: <path>' (incident-response mode), or 'n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      ;;
    10)
      shape_block commit subject files
      ;;
    11)
      if ! block_has pr && ! block_has_na; then
        echo "BLOCKED: canonical-sdlc step 11 evidence requires either 'pr: <url>' or 'n/a: <reason>' (e.g. 'n/a: PR-less workflow')." >&2
        echo "Plan: $PLAN" >&2
        exit 2
      fi
      ;;
    12)
      shape_block merge worktree-removed
      ;;
    13)
      if block_has_na; then
        if [ -n "$DEPLOY_TARGET" ] && [ "$DEPLOY_TARGET" != "none" ]; then
          echo "BLOCKED: canonical-sdlc step 13 'n/a:' is only valid when deploy_target=none in frontmatter (got deploy_target=${DEPLOY_TARGET})." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: provide 'deploy:', 'verified-at:', and 'monitor:' fields, or change deploy_target to none." >&2
          exit 2
        fi
      else
        shape_block deploy verified-at monitor
      fi
      ;;
  esac
fi

exit 0
