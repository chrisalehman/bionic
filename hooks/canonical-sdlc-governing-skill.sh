#!/bin/bash
# GOVERNING-SKILL GATE: Blocks Write and Edit to canonical-sdlc artifact
# files that lack the required governing-skill frontmatter.
#
# Scope: files under <project>/docs/bionic/{specs,plans,adrs}/ matching
#   *.plan.md | *.spec.md | adr-*.md | continuation*.md
# (epic.plan.md and epic.spec.md are covered by *.plan.md / *.spec.md)
#
# Other files under those paths — README.md, images, supporting notes —
# pass through unblocked. Rename-to-bypass is discoverable: the skill's
# own naming gates catch artifacts that aren't named correctly.
#
# Required frontmatter block at the top of the file:
#
#   ---
#   governing-skill: superpowers:writing-plans
#   sdlc-step: 3
#   epic: epic-02-v2-product-pass
#   wave: wave-01-checkout-refactor
#   mode: full
#   ---
#
# This hook enforces the presence of `governing-skill:` only. Other
# fields are documented in the skill but not hook-enforced — the skill's
# content rubric catches malformed values before they ship.
#
# Exit code 2 = block the tool call entirely in Claude Code hooks.
#
# Installed globally by claude-bootstrap.sh to ~/.claude/hooks/

set -u

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only Write and Edit need checking. Other tools pass through.
case "$TOOL" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Is the path under a canonical-sdlc artifact directory AND does the
# basename match an enforced extension? Both must be true.
# Match files under the project's docs root (default <project>/.bionic/
# docs/, configurable via <project>/.bionic/config.yaml `docs-root:`).
#
# Strategy: walk up from FILE_PATH to find the nearest `.bionic/`
# parent — that directory's parent is the project root. From there,
# resolve docs-root and check whether FILE_PATH lives under
# <docs-root>/{specs,plans,adrs,incidents}/.
find_project_root_from_path() {
  local d
  d=$(dirname "$1")
  while [ "$d" != "/" ] && [ "$d" != "." ] && [ -n "$d" ]; do
    if [ -d "$d/.bionic" ]; then
      echo "$d"
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}

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

PROJECT_ROOT_FROM_PATH=$(find_project_root_from_path "$FILE_PATH" || true)
if [ -z "$PROJECT_ROOT_FROM_PATH" ]; then
  # File is not under any .bionic/ project tree → not a canonical artifact.
  exit 0
fi
DOCS_ROOT=$(resolve_docs_root "$PROJECT_ROOT_FROM_PATH")

case "$FILE_PATH" in
  "$DOCS_ROOT"/specs/*|"$DOCS_ROOT"/plans/*|"$DOCS_ROOT"/adrs/*|"$DOCS_ROOT"/incidents/*) ;;
  *) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH")
ENFORCE=0
case "$BASENAME" in
  *.plan.md|*.spec.md|continuation*.md) ENFORCE=1 ;;
  adr-*.md) ENFORCE=1 ;;
esac

if [ "$ENFORCE" -eq 0 ]; then
  exit 0
fi

# Determine the content that will exist after the tool runs.
# - Write: the posted `content` is the new file body in full.
# - Edit: the file exists; the hook cannot cheaply simulate the edit, so
#   it enforces a weaker invariant: the file already contains the
#   frontmatter field. If a Write established valid frontmatter, any
#   subsequent Edit inherits it. If an Edit targets a file that never
#   had the frontmatter, the hook blocks and directs the user to Write
#   the artifact from scratch with the required frontmatter block.
CONTENT=""
if [ "$TOOL" = "Write" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
else
  if [ -f "$FILE_PATH" ]; then
    CONTENT=$(cat "$FILE_PATH")
  fi
fi

if [ -z "$CONTENT" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' has no content to validate." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: use Write to create the artifact with governing-skill frontmatter." >&2
  exit 2
fi

# Extract the leading YAML frontmatter block (between the first two `---`
# lines at column 0). If absent, block.
FRONTMATTER=$(echo "$CONTENT" | awk '
  NR == 1 && $0 == "---" { inside = 1; next }
  inside && $0 == "---" { exit }
  inside { print }
')

if [ -z "$FRONTMATTER" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' is missing a YAML frontmatter block." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: prepend:" >&2
  echo "  ---" >&2
  echo "  governing-skill: <skill-id for the step that produced this artifact>" >&2
  echo "  sdlc-step: <step number>" >&2
  echo "  epic: epic-NN-<slug>" >&2
  echo "  wave: wave-NN-<slug>   # omit for epic-level and continuation" >&2
  echo "  mode: <mode>" >&2
  echo "  ---" >&2
  exit 2
fi

# Enforce presence of the governing-skill field with a non-empty value.
GOVERNING=$(echo "$FRONTMATTER" \
            | grep -E '^[[:space:]]*governing-skill[[:space:]]*:' \
            | head -1 \
            | sed -E 's/^[[:space:]]*governing-skill[[:space:]]*:[[:space:]]*//' \
            | sed -E 's/[[:space:]]+$//')

if [ -z "$GOVERNING" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' is missing a 'governing-skill:' frontmatter field." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: add a non-empty 'governing-skill: <skill-id>' line to the frontmatter block." >&2
  exit 2
fi

# ---------- canonical-sdlc v1/v2/v3 schema enforcement ----------
#
# Discriminator: `canonical_sdlc_version`, NOT `governing-skill`.
# `governing-skill:` records the per-step skill that wrote a given
# artifact — plans correctly declare `superpowers:writing-plans` because
# Step 3 delegates to that skill. We instead read
# `canonical_sdlc_version`, which Step 0 stamps on every canonical-sdlc
# plan and is therefore the correct run marker.
#
# v1 — legacy; grandfathered, no flag enforcement.
# v2 — legacy; grandfathered, no flag enforcement.
# v3 — current; requires 5 discriminator flags + 2 opt-in flags.

yaml_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*${1}[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${1}[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

SDLC_VERSION=$(yaml_get canonical_sdlc_version)

# No version marker → not a canonical-sdlc plan. Plans authored under
# other governing skills pass through with only the
# governing-skill-field-presence check above.
if [ -z "$SDLC_VERSION" ]; then
  exit 0
fi

# Legacy v1 and v2: grandfathered out of flag enforcement entirely.
if [ "$SDLC_VERSION" = "1" ] || [ "$SDLC_VERSION" = "2" ]; then
  exit 0
fi

# v3 through v8 are all enforced. v4 added a required `model_plan` (the
# Step-0 model-tier decision); v5 collapses the step set (gate model); v6
# removes the external-review step (0–9 shape); v7 adds the universal
# Step-5 `bundle-fresh:` evidence key (enforced by the evidence-gate
# hook — no flag change here); v8 adds the universal Step-5
# `drive-check:` evidence key (also enforced by the evidence-gate hook,
# not here). v4/v5/v6/v7/v8 share v4's flag contract unchanged. v3 plans
# keep the prior contract so in-flight plans authored before v4 are not
# retroactively broken.
if [ "$SDLC_VERSION" != "3" ] && [ "$SDLC_VERSION" != "4" ] && [ "$SDLC_VERSION" != "5" ] && [ "$SDLC_VERSION" != "6" ] && [ "$SDLC_VERSION" != "7" ] && [ "$SDLC_VERSION" != "8" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' has unsupported canonical_sdlc_version: '$SDLC_VERSION'." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: set 'canonical_sdlc_version: 8' (current), '7'/'6'/'5'/'4'/'3' (prior, still enforced), or '1'/'2' for legacy plans." >&2
  exit 2
fi

# v3/v4 schema: require all opt-in flags + discriminators only for autonomous
# mode. Other modes (epic-scope, incident-response, design-refresh, spike)
# have different rule sets and are out of scope for enforcement.
MODE=$(yaml_get mode)
if [ "$MODE" != "autonomous" ]; then
  exit 0
fi

REQUIRED_V3_OPT_IN=("cleanup_on_finish" "use_worktree")
REQUIRED_DISCRIMINATORS=("surface_type" "language" "has_ui" "multi_agent" "deploy_target")

MISSING=()
for flag in "${REQUIRED_V3_OPT_IN[@]}" "${REQUIRED_DISCRIMINATORS[@]}"; do
  if ! echo "$FRONTMATTER" | grep -qE "^[[:space:]]*${flag}[[:space:]]*:"; then
    MISSING+=("$flag")
  fi
done

# v4 and later additionally require the confirmed `model_plan` field (the
# Step-0 model-tier decision). Checked as a separate conditional grep — NOT
# an array element — to stay safe under `set -u` with bash 3.2's empty-array
# expansion behaviour. v3 plans skip this and keep the prior contract.
if [ "$SDLC_VERSION" = "4" ] || [ "$SDLC_VERSION" = "5" ] || [ "$SDLC_VERSION" = "6" ] || [ "$SDLC_VERSION" = "7" ] || [ "$SDLC_VERSION" = "8" ]; then
  if ! echo "$FRONTMATTER" | grep -qE "^[[:space:]]*model_plan[[:space:]]*:"; then
    MISSING+=("model_plan")
  fi
fi

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "BLOCKED: canonical-sdlc autonomous-mode v${SDLC_VERSION} plan '$BASENAME' is missing required frontmatter flags: ${MISSING[*]}" >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: run Step 0 (Configure) to set these explicitly. See SKILL.md §Step 0." >&2
  echo "Required opt-in flags:        ${REQUIRED_V3_OPT_IN[*]}" >&2
  echo "Required discriminator flags: ${REQUIRED_DISCRIMINATORS[*]}" >&2
  if [ "$SDLC_VERSION" = "4" ] || [ "$SDLC_VERSION" = "5" ] || [ "$SDLC_VERSION" = "6" ] || [ "$SDLC_VERSION" = "7" ] || [ "$SDLC_VERSION" = "8" ]; then
    echo "Required for v${SDLC_VERSION} (added):      model_plan" >&2
  fi
  exit 2
fi

exit 0
