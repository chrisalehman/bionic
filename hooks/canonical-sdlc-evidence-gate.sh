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
#
# CRLF plans (\r\n line endings) would otherwise defeat the exact-match
# `$0=="---"` comparison ("---\r" != "---"), so \r is stripped from the
# file before either awk pass — normalizing once here means every
# downstream parse (frontmatter values, SECTION lines, CURRENT, evidence
# blocks) sees plain \n text.
FRONTMATTER=$(tr -d '\r' < "$PLAN" | awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f')

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
SCALE=$(frontmatter_get scale)

# Whole-value placeholder test: trim leading/trailing whitespace, lowercase,
# then require whole-value EQUALITY against the known token set. A token that
# merely appears as a substring of a longer value ("resolved TODOs",
# "*.example placeholders", "status pending → done") is legal evidence.
# "in progress" and its whitespace-free "inprogress" are both listed so
# either spelling of the value matches. Defined here (ahead of the Step-line
# checks) so the v11 task-ledger validator, which runs before them, can reuse it.
is_placeholder_value() {
  local v
  v=$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')
  case "$v" in
    todo|pending|"in progress"|inprogress|xxx|tbd|placeholder) return 0 ;;
    *) return 1 ;;
  esac
}

# v11 log-only finding channel (D14): append one line to the durable audit file
# AND echo to stderr, then return 0 — floor/ledger/merge-target findings never
# block this wave. Twin of the governing-skill hook's helper (hook name differs:
# `evidence-gate`). mkdir + append are fail-open; the audit file lives in the
# durable .bionic/memory/ (not .bionic/tmp/, which is wiped at Integrate).
log_finding() {  # $1=check-id  $2=detail
  local audit_dir="$PROJECT_DIR/.bionic/memory"
  local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) evidence-gate $1: $2 ($PLAN)"
  mkdir -p "$audit_dir" 2>/dev/null && printf '%s\n' "$line" >> "$audit_dir/sdlc-v11-audit.md" 2>/dev/null
  echo "canonical-sdlc v11 [$1]: $2" >&2
  return 0
}

# v11 task-scale ledger validation (D12) — LOG-ONLY (D14, check-id
# `task-ledger`). Reads the `## Tasks` registration table (fence-aware, the
# matrix_section idiom) and the per-task `- T<n>:` evidence lines in the
# ## SDLC State section (SECTION, already \r-stripped). Every deviation appends
# one finding; the function ALWAYS returns 0 — a ledger defect never blocks this
# wave. Checks: missing `## Tasks`; status outside {pending,active,done,dropped};
# an active/done task with no `- T<n>:` line or a placeholder/empty value.
validate_task_ledger() {
  local tasks rows line id status ev
  tasks=$(tr -d '\r' < "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Tasks/ { f=1; next }
    /^## / { f=0 }
    f')
  if [ -z "$tasks" ]; then
    log_finding task-ledger "v11 task-scale plan has no '## Tasks' registration section"
    return 0
  fi
  rows=$(echo "$tasks" | grep -E '^[[:space:]]*\|[[:space:]]*T[0-9]+')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')
    case "$status" in
      pending|active|done|dropped) : ;;
      *) log_finding task-ledger "task ${id} has invalid status '${status:-empty}' (want pending|active|done|dropped)" ;;
    esac
    # Evidence line for this task in ## SDLC State (anchored so T2 never matches T20).
    ev=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:" | head -1 \
         | sed -E "s/^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    case "$status" in
      active|done)
        if [ -z "$ev" ]; then
          log_finding task-ledger "task ${id} is ${status} but has no evidence on a '- ${id}:' line in ## SDLC State"
        elif is_placeholder_value "$ev"; then
          log_finding task-ledger "task ${id} is ${status} but its evidence is a placeholder ('${ev}')"
        fi
        ;;
    esac
  done <<< "$rows"
  return 0
}

# Extract the ## SDLC State section (from its header up to the next ##
# header or EOF). \r stripped here too, for the same CRLF reason as
# FRONTMATTER above.
SECTION=$(tr -d '\r' < "$PLAN" | awk '/^## SDLC State/{flag=1; next} /^## /{flag=0} flag')

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

# v11 task-scale plans address a ledger TASK, not a numbered step:
# `current: T<n>` with evidence on `- T<n>:` lines (no `Step N:` line). Validate
# the ledger (log-only, D12/D14) and allow the commit — the task pointer is
# structurally valid, so a false block here would be a defect (R4.3). A
# `current: T<n>` on a v≤10 plan or a non-task v11 plan is NOT accepted here; it
# falls through to the numeric check below and blocks (T-format is v11 + scale:task
# only, never retrofitted).
if echo "$CURRENT" | grep -qE '^T[0-9]+$' && [ "$SDLC_VERSION" = "11" ] && [ "$SCALE" = "task" ]; then
  validate_task_ledger
  exit 0
fi

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

# Placeholder detection. Each line of the block is checked as a whole value:
# the text after the first ':' on a "key: value" continuation line, or the
# whole line when it has no colon (the single-line "Step N: <value>" case,
# which arrives here as RAW_VALUE). ${_bline#*:} yields the after-colon text
# on colon lines and the unchanged line otherwise.
while IFS= read -r _bline; do
  if is_placeholder_value "${_bline#*:}"; then
    echo "BLOCKED: canonical-sdlc step ${CURRENT} evidence line is a placeholder (\"${BLOCK}\")." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: replace with the actual evidence artifact before committing." >&2
    exit 2
  fi
done <<< "$BLOCK"

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
#
# v6 removes the external-review step entirely, so it has its own shape
# switch — identical to v5 except Step 8 (External review) is gone and
# the tail renumbers:
#   - Steps 5, 6, 7 — same shapes as v5
#   - Step 8 (Integrate & close) — merge/worktree-removed AND cleanup triple
#     OR cleanup: n/a   (was v5 Step 9)
#   - Step 9 (Ship) — deploy/verified-at/monitor OR n/a   (was v5 Step 10)
#   Commit remains a cross-cutting rhythm, not a numbered step.
#
# v7 is the v6 shape table plus ONE addition: Step 5 (Verify)
# additionally requires a `bundle-fresh:` key — the pasted output of the
# project's bundle-freshness proof (proves the served artifact reflects
# the working tree before any live observation is used as evidence), or
# `bundle-fresh: n/a: <reason>`. Universal with an n/a escape, exactly
# like `devtools-trace:` — "not applicable" is an explicit recorded
# decision, never a silent omission. The proof format is
# project-specific by design; the hook validates presence, non-empty
# value / non-empty n/a reason, and the existing placeholder ban only.
#
# v8 is the v7 shape table plus ONE addition: Step 5 (Verify)
# additionally requires a `drive-check:` key — proof that one trusted
# interaction changed app state, read back semantically (not via pixels),
# before browser-modality evidence counts. Forms: an observed state delta,
# `drive-check: suite: <named test — what it asserts>` (suite-credit only via a named test
# making the same real contact), or `drive-check: n/a: <reason>`. Universal
# with an n/a escape, grandfathered like every prior key — the hook
# validates presence, non-empty value / non-empty n/a reason, and the
# existing placeholder ban only; the suite-credit semantics live in
# SKILL.md prose. v7 and earlier plans are never retrofitted.
#
# v9 (current) = v8 + Step-5 stack-health: ONE more universal key,
# `stack-health: <before/after snapshot, no delta>` or
# `stack-health: n/a: <reason>` — a runtime-integrity sibling of
# bundle-fresh (artifact) and drive-check (contact): a crash-restart
# mid-walk can swallow the bug being probed while the app returns
# looking healthy. Same contract as its siblings: presence, non-empty
# value / non-empty n/a reason, existing placeholder ban. v8 and earlier
# plans are never retrofitted.
if [ "$SDLC_VERSION" = "11" ]; then
  # v11 wave/epic-scale plans carry the v10 shape (task-scale plans exited
  # above via validate_task_ledger). The v11 arm reuses v10's validators.
  SHAPE_MODE="v11"
elif [ "$SDLC_VERSION" = "10" ]; then
  SHAPE_MODE="v10"
elif [ "$SDLC_VERSION" = "9" ]; then
  SHAPE_MODE="v9"
elif [ "$SDLC_VERSION" = "8" ]; then
  SHAPE_MODE="v8"
elif [ "$SDLC_VERSION" = "7" ]; then
  SHAPE_MODE="v7"
elif [ "$SDLC_VERSION" = "6" ]; then
  SHAPE_MODE="v6"
elif [ "$SDLC_VERSION" = "5" ]; then
  SHAPE_MODE="v5"
elif [ "$SDLC_VERSION" = "3" ] || [ "$SDLC_VERSION" = "4" ]; then
  SHAPE_MODE="v3"
elif [ "$EVIDENCE_SCHEMA" = "v2" ]; then
  SHAPE_MODE="v2"
else
  exit 0
fi

# Pointer steps differ between schema versions due to renumbering. A pointer
# step records a link/path (not shaped fields); having passed the presence +
# placeholder checks above, it needs no shape check, so allow the commit.
# Step 4 is the exception: when use_worktree=true it carries worktree fields
# and must fall through to the shape check below. v2 lists Step 4 nowhere
# here, so v2 always shape-checks Step 4 (unchanged from before).
pointer_steps_for_mode() {
  case "$1" in
    v10|v11)     echo "1 2 3 4" ;;  # Step 6 must reach dispatch for the matrix prefix check
    v5|v6|v7|v8|v9) echo "1 2 3 4 6" ;;
    v3)          echo "1 2 3 4 7 8" ;;
    *)           echo "1 2 3 5 8 8b" ;;  # v2
  esac
}

for _ps in $(pointer_steps_for_mode "$SHAPE_MODE"); do
  [ "$CURRENT" = "$_ps" ] || continue
  if [ "$_ps" = "4" ] && [ "$USE_WORKTREE" = "true" ]; then
    break  # fall through to the Step-4 worktree shape check below
  fi
  exit 0
done

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

# ---------- shared per-step validators ----------
# The v5–v8 branches below collapse into one dispatcher (dispatch_modern)
# driven by a role→step map; v3/v2 keep thin `case` arms that call the same
# validators where byte-identical and keep their own arms where they differ.
# Every stderr line is byte-identical to the pre-refactor per-version code
# (the 140-assertion harness is the contract) — the version label and step
# number are the only interpolated parts.

# Compose the "canonical-sdlc <label> step <N>" message prefix. An empty
# label (v2) yields "canonical-sdlc step <N>" with no stray double space.
step_prefix() {
  if [ -n "$1" ]; then
    echo "canonical-sdlc $1 step $2"
  else
    echo "canonical-sdlc step $2"
  fi
}

# Universal Step-5 keys a version layers on the shared verify body, in
# enforcement order. v7 added bundle-fresh; v8 added drive-check; v9 added
# stack-health. A future version appends ONE case arm here (and one
# require_na_key arm).
step5_keys_for_version() {
  case "$1" in
    v9) echo "bundle-fresh drive-check stack-health" ;;
    v8) echo "bundle-fresh drive-check" ;;
    v7) echo "bundle-fresh" ;;
    *)  echo "" ;;  # v5, v6: no universal Step-5 keys
  esac
}

# Presence + non-empty-value / `n/a: <reason>`-with-reason check for one
# universal Step-5 key. Per-key wording lives in the case arms (tests assert
# it byte-for-byte); the whole-block placeholder ban already ran upstream.
# These keys are Step-5 only, so the prefix is fixed at step 5.
require_na_key() {
  local label="$1" key="$2" prefix val
  prefix=$(step_prefix "$label" 5)
  if ! block_has "$key"; then
    case "$key" in
      bundle-fresh)
        echo "BLOCKED: ${prefix} requires 'bundle-fresh: <proof>' or 'bundle-fresh: n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: run the project's bundle-freshness proof and paste its output line as 'bundle-fresh: <proof>', or record 'bundle-fresh: n/a: <reason>' for non-served targets." >&2
        ;;
      drive-check)
        echo "BLOCKED: ${prefix} requires 'drive-check: <observed delta>' or 'drive-check: n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: prove one trusted interaction changed app state (read the delta back semantically, not via pixels) and record the observed delta — or 'drive-check: suite: <named test — what it asserts>' when a suite test makes the same real contact, or 'drive-check: n/a: <reason>' when no browser modality applies." >&2
        ;;
      stack-health)
        echo "BLOCKED: ${prefix} requires 'stack-health: <before/after snapshot>' or 'stack-health: n/a: <reason>'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: snapshot the serving stack's runtime-integrity indicators before and after the walk and paste the no-delta result as 'stack-health: <snapshot>', or record 'stack-health: n/a: <reason>' when no long-running serve is observed." >&2
        ;;
    esac
    exit 2
  fi
  val=$(block_get "$key")
  case "$val" in
    ""|n/a|n/a:)
      case "$key" in
        bundle-fresh)
          echo "BLOCKED: ${prefix} 'bundle-fresh:' needs a non-empty proof, or 'n/a: <reason>' with a non-empty reason." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: paste the freshness tool's output line, or give the reason freshness does not apply." >&2
          ;;
        drive-check)
          echo "BLOCKED: ${prefix} 'drive-check:' needs a non-empty observation, or 'n/a: <reason>' with a non-empty reason." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: record the observed state delta, the qualifying suite test, or the reason a drive-check does not apply." >&2
          ;;
        stack-health)
          echo "BLOCKED: ${prefix} 'stack-health:' needs a non-empty snapshot, or 'n/a: <reason>' with a non-empty reason." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: paste the before/after snapshot showing no delta, or give the reason stack-health does not apply." >&2
          ;;
      esac
      exit 2
      ;;
  esac
}

# Tests modality: cmd/pass/total/output present, pass and total integers,
# pass==total. Shared by the verify gate (v5–v8 Step 5) and the standalone
# "Verify done" step (v3 Step 6, v2 Step 7).
validate_tests_block() {
  local label="$1" step="$2" pass total prefix
  shape_block cmd pass total output
  pass=$(block_get pass)
  total=$(block_get total)
  prefix=$(step_prefix "$label" "$step")
  if ! echo "$pass" | grep -qE '^[0-9]+$' || ! echo "$total" | grep -qE '^[0-9]+$'; then
    echo "BLOCKED: ${prefix} 'pass:' and 'total:' must be integers (got pass='${pass}', total='${total}')." >&2
    echo "Plan: $PLAN" >&2
    exit 2
  fi
  if [ "$pass" -ne "$total" ]; then
    echo "BLOCKED: ${prefix} evidence has pass=${pass} but total=${total}; the suite is not fully green." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: do not commit step ${step} until pass equals total." >&2
    exit 2
  fi
}

# Verify gate (v5–v8 Step 5): tests modality, then browser modality
# (devtools-trace OR n/a), then each universal key the version requires.
validate_verify_step() {
  local label="$1" k
  validate_tests_block "$label" 5
  if ! block_has devtools-trace && ! block_has_na; then
    echo "BLOCKED: canonical-sdlc ${label} step 5 (Verify) browser modality requires 'devtools-trace: <path>' or 'n/a: <reason>'." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: add the browser-evidence path, or 'n/a:' with a reason. See SKILL.md verification shape table." >&2
    exit 2
  fi
  for k in $(step5_keys_for_version "$label"); do
    require_na_key "$label" "$k"
  done
}

# Standalone browser-verify step (v3 Step 5, v2 Step 6): devtools-trace OR
# n/a. Distinct wording from the verify gate's browser modality above.
validate_browser_verify_step() {
  local label="$1" step="$2" prefix
  if ! block_has devtools-trace && ! block_has_na; then
    prefix=$(step_prefix "$label" "$step")
    echo "BLOCKED: ${prefix} evidence requires either 'devtools-trace: <path>' or 'n/a: <reason>'." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: pick one. See SKILL.md verification shape table." >&2
    exit 2
  fi
}

# Document step: adr OR rca OR n/a.
validate_document_step() {
  local label="$1" step="$2" prefix
  if ! block_has adr && ! block_has rca && ! block_has_na; then
    prefix=$(step_prefix "$label" "$step")
    echo "BLOCKED: ${prefix} evidence requires 'adr: <path>', 'rca: <path>' (incident-response mode), or 'n/a: <reason>'." >&2
    echo "Plan: $PLAN" >&2
    exit 2
  fi
}

# External review step: pr OR n/a.
validate_external_review_step() {
  local label="$1" step="$2" prefix
  if ! block_has pr && ! block_has_na; then
    prefix=$(step_prefix "$label" "$step")
    echo "BLOCKED: ${prefix} evidence requires either 'pr: <url>' or 'n/a: <reason>' (e.g. 'n/a: PR-less workflow')." >&2
    echo "Plan: $PLAN" >&2
    exit 2
  fi
}

# Integrate & close (v5–v8): merge/worktree-removed always; then the cleanup
# triple, OR an explicit `cleanup: n/a` marker (cleanup_on_finish=false).
validate_integrate_step() {
  local cleanup_val
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
}

# Ship step: deploy/verified-at/monitor, OR `n/a` only when
# deploy_target=none.
validate_ship_step() {
  local label="$1" step="$2" prefix
  if block_has_na; then
    if [ -n "$DEPLOY_TARGET" ] && [ "$DEPLOY_TARGET" != "none" ]; then
      prefix=$(step_prefix "$label" "$step")
      echo "BLOCKED: ${prefix} 'n/a:' is only valid when deploy_target=none in frontmatter (got deploy_target=${DEPLOY_TARGET})." >&2
      echo "Plan: $PLAN" >&2
      echo "Fix: provide 'deploy:', 'verified-at:', and 'monitor:' fields, or change deploy_target to none." >&2
      exit 2
    fi
  else
    shape_block deploy verified-at monitor
  fi
}

# ---------- v10: pre-registered Verification Matrix ----------
# The v10 Verify gate discharges a Verification Matrix stored in a top-level
# `## Verification Matrix` section of the plan (separate from ## SDLC State).
# validate_matrix_v10 parses that section — a per-session stack-health line, a
# tier table (one row per AC), and one indented per-AC evidence block per
# non-waived row — and fires at current: 5 (via the Step-5 validator) and as a
# prefix check for current: 6..9 (via dispatch_modern's v10 arm).
#
# v10.1 (mid-discharge commits): at current: 5, rows with status
# pending/blocked skip the per-tier key check, and the Step-5 `auditor:`
# pointer is required only when no such row remains. The full contract —
# per-tier keys + CONFIRMED on every non-waived row — bites on the 5→6
# advance via the 6..9 prefix check. The status cell is enum-checked
# (pending|blocked|discharged|waived) since the relaxation makes it
# load-bearing.

# Per-tier required evidence keys — MIRROR of the canonical table in
# skills/canonical-sdlc/SKILL.md Step 5 ("Per-tier required evidence keys").
# Change THAT table first; this function follows it. (R27)
keys_for_tier() {
  case "$1" in
    T0|T1) echo "tier-run readback" ;;
    T2)    echo "tier-run readback fixture-fidelity" ;;
    T3)    echo "tier-run fresh cold-client contact readback" ;;
    T4)    echo "user-confirmed" ;;
  esac
}

# The `## Verification Matrix` section body (\r stripped, like SECTION at the
# top of the hook — a separate awk pass over the whole plan). Lines inside
# ``` fenced code blocks are dropped so a jq/shell pipeline written in
# leading-pipe continuation style is never mistaken for a table row; every
# downstream matrix parse (rows, stack-health, false-green, AC blocks) reads
# this body, so scoping the fence-skip here covers all of them. Fence state
# is tracked across the whole file so section detection stays fence-aware.
matrix_section() {
  tr -d '\r' < "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Verification Matrix/ { f=1; next }
    /^## / { f=0 }
    f'
}

# The indented evidence block under "<AC-id>:" within MATRIX (up to the next
# non-indented line). index()==1 anchors at line start without regex-escaping
# the AC id, so AC-1 never matches the AC-11 block.
matrix_block() {
  echo "$MATRIX" | awk -v ac="$1:" '
    index($0, ac)==1 {f=1; next}
    /^[^[:space:]]/ {f=0}
    f'
}

# 3-line BLOCKED/Plan/Fix emit for the v10 matrix arm (mirrors the pattern
# every other validator uses). $1 = message tail, $2 = fix line.
block_matrix() {
  echo "BLOCKED: canonical-sdlc v10 step ${CURRENT} — $1" >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: $2" >&2
  exit 2
}

# Placeholder-token test on a single field value. The matrix section lives
# outside ## SDLC State, so the upstream ban does not cover it; this reuses
# the same whole-value equality test (is_placeholder_value, defined above).
matrix_is_placeholder() {
  is_placeholder_value "$1"
}

validate_matrix_v10() {
  local sh rows line ncols ac tier status ev aud block_txt key val

  # v10.1: set while any row is still pending/blocked at current: 5. The
  # Step-5 validator reads it to keep the `auditor:` pointer optional
  # mid-walk (the auditor is the exit gate — it cannot have run yet).
  UNDISCHARGED=0
  MATRIX=$(matrix_section)
  if [ -z "$MATRIX" ]; then
    block_matrix "the Verify gate requires a '## Verification Matrix' section (v10 contract)." \
      "add the '## Verification Matrix' section: a stack-health line, the AC tier table, and one per-AC evidence block. See canonical-sdlc/SKILL.md Step 5."
  fi

  # stack-health: non-empty proof, or `n/a: <reason>` with a reason.
  if ! echo "$MATRIX" | grep -qE '^[[:space:]]*stack-health[[:space:]]*:'; then
    block_matrix "'## Verification Matrix' is missing the 'stack-health:' line." \
      "add 'stack-health: <before/after snapshot>' or 'stack-health: n/a: <reason>' above the table."
  fi
  sh=$(echo "$MATRIX" | grep -E '^[[:space:]]*stack-health[[:space:]]*:' | head -1 \
       | sed -E 's/^[[:space:]]*stack-health[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  case "$sh" in
    ""|n/a|n/a:)
      block_matrix "'stack-health:' needs a non-empty snapshot, or 'n/a: <reason>' with a non-empty reason." \
        "paste the before/after snapshot showing no delta, or give the reason stack-health does not apply." ;;
  esac

  # false-green two-part rule: any `false-green:` entry must have a paired
  # `rewritten:` entry, or the gate blocks (Assumption 12a).
  if echo "$MATRIX" | grep -qE '^[[:space:]]*false-green[[:space:]]*:'; then
    if ! echo "$MATRIX" | grep -qE '^[[:space:]]*rewritten[[:space:]]*:'; then
      block_matrix "a 'false-green:' entry in the matrix has no paired 'rewritten:' entry." \
        "add 'rewritten: <commit/test ref>' for the false-green test — a logged-but-unfixed false green is a blocking defect."
    fi
  fi

  rows=$(echo "$MATRIX" | grep -E '^[[:space:]]*\|')
  if [ -z "$rows" ]; then
    block_matrix "'## Verification Matrix' has no tier table rows." \
      "add the '| AC | tier | status | evidence | auditor |' table with one row per AC."
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # separator row (only pipes/dashes/colons/spaces) → skip
    echo "$line" | grep -qE '^[[:space:]]*\|[-|:[:space:]]*$' && continue
    ncols=$(echo "$line" | awk -F'|' '{print NF}')
    ac=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    tier=$(echo "$line"   | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')
    ev=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$5); print $5}')
    aud=$(echo "$line"    | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')
    # header row → skip
    [ "$ac" = "AC" ] && continue
    # malformed: a well-formed 5-cell row splits into exactly 7 fields on '|'.
    if [ "$ncols" -ne 7 ]; then
      block_matrix "matrix row for '${ac}' is malformed (wrong cell count — no literal '|' inside cells)." \
        "write the row as '| AC | tier | status | evidence | auditor |' with exactly five cells and no literal pipe inside any cell."
    fi
    # tier enum
    if ! echo "$tier" | grep -qE '^T[0-4]$'; then
      block_matrix "matrix row for '${ac}' has an invalid tier '${tier}' (want T0..T4)." \
        "set the tier cell to one of T0, T1, T2, T3, T4."
    fi
    # status enum (v10.1) — the status cell is load-bearing (pending/blocked
    # relax the Verify gate; waived relaxes everything), so a typo must
    # block, not silently read as discharged-like.
    case "$status" in
      pending|blocked|discharged|waived) : ;;
      *)
        block_matrix "matrix row '${ac}' has an invalid status '${status:-empty}' (want pending|blocked|discharged|waived)." \
          "set the status cell to one of: pending, blocked, discharged, waived." ;;
    esac
    block_txt=$(matrix_block "$ac")
    # waived rows (evidence cell or the AC block carries a `waiver:` entry) are
    # exempt from the per-tier evidence requirement.
    if echo "$ev" | grep -qE 'waiver:' || echo "$block_txt" | grep -qE '^[[:space:]]*waiver[[:space:]]*:'; then
      :
    elif [ "$CURRENT" = "5" ] && { [ "$status" = "pending" ] || [ "$status" = "blocked" ]; }; then
      # v10.1: a row still being discharged carries no evidence contract at
      # the Verify gate itself — its per-tier keys bite on the 5→6 advance
      # (the 6..9 prefix check), mirroring the CONFIRMED rule. This is what
      # gives a mid-walk corrective commit an honest home at current: 5.
      UNDISCHARGED=1
    else
      for key in $(keys_for_tier "$tier"); do
        if ! echo "$block_txt" | grep -qE "^[[:space:]]*${key}[[:space:]]*:"; then
          block_matrix "matrix row '${ac}' (${tier}) is missing evidence key '${key}' in its AC block." \
            "add '${key}: <evidence>' to the '${ac}:' block, or waive the row via the Waiver Protocol."
        fi
        val=$(echo "$block_txt" | grep -E "^[[:space:]]*${key}[[:space:]]*:" | head -1 \
              | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
        if [ -z "$val" ]; then
          block_matrix "matrix row '${ac}' (${tier}) evidence key '${key}' is empty." \
            "record the evidence for '${key}' in the '${ac}:' block, or waive the row."
        fi
        if matrix_is_placeholder "$val"; then
          block_matrix "matrix row '${ac}' (${tier}) evidence key '${key}' is a placeholder (\"${val}\")." \
            "replace '${key}' with the real evidence before committing."
        fi
        # live-tier (T3/T4) fields cannot be self-written n/a — that is a
        # downgrade, which is a user decision via the Waiver Protocol.
        # Case-insensitive: 'N/A' is the same downgrade as 'n/a' (matches
        # matrix_is_placeholder's lowercasing).
        val_lc=$(echo "$val" | tr '[:upper:]' '[:lower:]')
        case "$tier" in
          T3|T4)
            case "$val_lc" in
              n/a|n/a:*)
                block_matrix "matrix row '${ac}' (${tier}) key '${key}' is a self-written 'n/a' on a live tier." \
                  "a live-tier field cannot be n/a — downgrade the row via the Waiver Protocol (record 'waiver: <user> <date> <reason>'), a user decision." ;;
            esac ;;
        esac
      done
    fi
    # Once past the Verify gate, every non-waived row must be CONFIRMED.
    if [ "$CURRENT" -gt 5 ] 2>/dev/null; then
      if [ "$status" = "waived" ] || echo "$ev" | grep -qE 'waiver:' \
         || echo "$block_txt" | grep -qE '^[[:space:]]*waiver[[:space:]]*:'; then
        :
      elif [ "$aud" != "CONFIRMED" ]; then
        block_matrix "matrix row '${ac}' auditor verdict is '${aud:-empty}', not CONFIRMED, at step ${CURRENT}." \
          "the independent auditor must CONFIRM every non-waived row before advancing past the Verify gate, or the row must be waived."
      fi
    fi
  done <<< "$rows"
}

# v10 Verify gate: tests floor (reused), a required non-empty auditor pointer,
# then the Verification Matrix.
validate_verify_step_v10() {
  local aud
  validate_tests_block v10 5
  validate_matrix_v10
  # v10.1: the auditor is the Step-5 exit gate — it cannot have run while
  # rows are still pending/blocked, so the pointer is required only once
  # every row is discharged or waived.
  if [ "$UNDISCHARGED" -eq 0 ]; then
    if ! block_has auditor; then
      block_matrix "the Verify gate requires 'auditor: <verdict summary + report pointer>' in the Step 5 block." \
        "record the independent auditor's one-line verdict summary and report pointer as 'auditor: ...'."
    fi
    aud=$(block_get auditor)
    if [ -z "$aud" ]; then
      block_matrix "the Step 5 'auditor:' pointer is empty." \
        "record the auditor's verdict summary and report pointer."
    fi
  fi
}

# Per-version dispatch for the modern (gate-collapsed) shape table. v5 keeps
# an external-review step and numbers integrate/ship at 9/10; v6+ dropped
# external review and renumber integrate/ship to 8/9. Step 5 (Verify) and
# Step 7 (Document) are common; Step 4 is the worktree shape check reached
# only when use_worktree=true. A future version is one case arm here plus a
# step5_keys_for_version arm.
# v11 epic merge-target consistency (LOG-ONLY; D14, check-id `merge-target`).
# On a v11 wave-scale plan naming an `epic:`, when the epic plan exists and
# declares an `integration-branch:` in its ## SDLC State, a mismatch with this
# plan's integration-branch logs a finding. Never blocks. First cross-file read
# in this hook — read-only, fail-open (missing epic plan / missing key → no
# finding). Fires at the integrate step.
validate_merge_target() {
  local epic epic_plan epic_branch this_branch
  epic=$(frontmatter_get epic)
  [ -n "$epic" ] || return 0
  epic_plan="$DOCS_ROOT/plans/$epic/epic.plan.md"
  [ -r "$epic_plan" ] || return 0
  epic_branch=$(tr -d '\r' < "$epic_plan" \
    | awk '/^## SDLC State/{f=1; next} /^## /{f=0} f' \
    | grep -E '^[[:space:]]*integration-branch[[:space:]]*:' | head -1 \
    | sed -E 's/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  [ -n "$epic_branch" ] || return 0
  this_branch=$(echo "$SECTION" | grep -E '^[[:space:]]*integration-branch[[:space:]]*:' | head -1 \
    | sed -E 's/^[[:space:]]*integration-branch[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  if [ -n "$this_branch" ] && [ "$this_branch" != "$epic_branch" ]; then
    log_finding merge-target "plan integration-branch '$this_branch' != epic '$epic' integration-branch '$epic_branch'"
  fi
  return 0
}

dispatch_modern() {
  local label="$1" ext_step="" integrate_step ship_step
  case "$label" in
    v5)                  ext_step=8; integrate_step=9; ship_step=10 ;;
    v6|v7|v8|v9|v10|v11) integrate_step=8; ship_step=9 ;;
  esac
  # v10/v11: the Verification Matrix is a prefix contract for every step from
  # the Verify gate on — current: 5 validates it inside validate_verify_step_v10;
  # current: 6..9 validate it here, so a REFUTED auditor blocks post-Verify
  # commits too (Step 6 is not a pointer step, so it reaches this arm). v11
  # wave/epic-scale plans carry the v10 shape unchanged, so they share the arm.
  if [ "$label" = "v10" ] || [ "$label" = "v11" ]; then
    case "$CURRENT" in
      6|7|8|9) validate_matrix_v10 ;;
    esac
  fi
  # v11: log-only epic merge-target check at the integrate step.
  if [ "$label" = "v11" ] && [ "$CURRENT" = "$integrate_step" ]; then
    validate_merge_target
  fi
  case "$CURRENT" in
    4) shape_block worktree base-sha branch ;;
    5)
      if [ "$label" = "v10" ] || [ "$label" = "v11" ]; then
        validate_verify_step_v10
      else
        validate_verify_step "$label"
      fi
      ;;
    7) validate_document_step "$label" 7 ;;
    *)
      if [ -n "$ext_step" ] && [ "$CURRENT" = "$ext_step" ]; then
        validate_external_review_step "$label" "$ext_step"
      elif [ "$CURRENT" = "$integrate_step" ]; then
        validate_integrate_step
      elif [ "$CURRENT" = "$ship_step" ]; then
        validate_ship_step "$label" "$ship_step"
      fi
      ;;
  esac
}

case "$SHAPE_MODE" in
  v5|v6|v7|v8|v9|v10|v11)
    dispatch_modern "$SHAPE_MODE"
    ;;
  v3)
    # v3 shape switch — renumbered steps (0–14). Reuses the shared validators
    # where an arm is byte-identical (browser-verify, tests, document,
    # external-review, ship); keeps its own arms where it differs (Step 10
    # commit, Step 12 merge-only, Step 13 bare-n/a cleanup).
    case "$CURRENT" in
      4)  shape_block worktree base-sha branch ;;
      5)  validate_browser_verify_step v3 5 ;;
      6)  validate_tests_block v3 6 ;;
      9)  validate_document_step v3 9 ;;
      10) shape_block commit subject files ;;
      11) validate_external_review_step v3 11 ;;
      12) shape_block merge worktree-removed ;;
      13)
        if block_has_na; then
          : # n/a is acceptable for Step 13 (cleanup_on_finish=false case)
        else
          shape_block cleanup tmp-wiped tasks-completed
        fi
        ;;
      14) validate_ship_step v3 14 ;;
    esac
    ;;
  *)
    # v2 shape switch — original step numbers (preserved for backwards
    # compat). Reuses the shared validators with an empty version label, so
    # messages read "canonical-sdlc step N ..." (no version token).
    case "$CURRENT" in
      4)  shape_block worktree base-sha branch ;;
      6)  validate_browser_verify_step "" 6 ;;
      7)  validate_tests_block "" 7 ;;
      9)  validate_document_step "" 9 ;;
      10) shape_block commit subject files ;;
      11) validate_external_review_step "" 11 ;;
      12) shape_block merge worktree-removed ;;
      13) validate_ship_step "" 13 ;;
    esac
    ;;
esac

exit 0
