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
if ! echo "$FILE_PATH" | grep -qE '/docs/bionic/(specs|plans|adrs)/'; then
  exit 0
fi

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

# ---------- canonical-sdlc v1/v2 schema enforcement (Wave 1b) ----------
# Schema reference: docs/bionic/plans/canonical-sdlc-autonomous-redesign.md §1.2.2 + §6.4.
#
# Only canonical-sdlc-governed plans are subject to this layer. Plans
# with other governing skills (e.g. superpowers:writing-plans) keep the
# basic governing-skill-field-only enforcement above.
if [ "$GOVERNING" != "canonical-sdlc" ]; then
  exit 0
fi

yaml_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*${1}[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${1}[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

SDLC_VERSION=$(yaml_get canonical_sdlc_version)

# Legacy-skip: v1 plans were migrated by Wave 1a's migrate-frontmatter.sh
# and are grandfathered out of v2 enforcement entirely. Existing
# governing-skill: field check above is the only requirement for them.
if [ "$SDLC_VERSION" = "1" ]; then
  exit 0
fi

# Missing version marker on a canonical-sdlc plan: block. The migration
# script and Step 0.5 wizard are the two ways this gets populated;
# editing a canonical-sdlc plan without either is a process bypass.
if [ -z "$SDLC_VERSION" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' is missing the 'canonical_sdlc_version:' frontmatter field." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: add one of:" >&2
  echo "  canonical_sdlc_version: 1   # legacy-grandfathered plan (skips v2 schema enforcement)" >&2
  echo "  canonical_sdlc_version: 2   # current schema (requires v2 opt-in flags + discriminators when mode is autonomous)" >&2
  echo "For pre-existing plans, run: bash ~/.claude/skills/canonical-sdlc/migrate-frontmatter.sh '$FILE_PATH'" >&2
  exit 2
fi

if [ "$SDLC_VERSION" != "2" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' has unsupported canonical_sdlc_version: '$SDLC_VERSION'." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: set 'canonical_sdlc_version: 1' (legacy) or 'canonical_sdlc_version: 2' (current)." >&2
  exit 2
fi

# v2 schema: require all opt-in flags + discriminators only for autonomous
# mode. Other modes (epic-scope, incident-response, design-refresh, spike)
# have different rule sets and are out of scope for Wave 1b enforcement.
MODE=$(yaml_get mode)
if [ "$MODE" != "autonomous" ]; then
  exit 0
fi

REQUIRED_V2_FLAGS=("narrative_verbose" "dispatch_enforce" "cleanup_on_finish" "archived")
REQUIRED_DISCRIMINATORS=("surface_type" "language" "perf_critical" "security_boundary"
                         "distributed" "has_ui" "multi_agent" "deploy_target")

MISSING=()
for flag in "${REQUIRED_V2_FLAGS[@]}" "${REQUIRED_DISCRIMINATORS[@]}"; do
  if ! echo "$FRONTMATTER" | grep -qE "^[[:space:]]*${flag}[[:space:]]*:"; then
    MISSING+=("$flag")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "BLOCKED: canonical-sdlc autonomous-mode plan '$BASENAME' is missing required v2 frontmatter flags: ${MISSING[*]}" >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: run Step 0.5 (Configure) to set these explicitly. See SKILL.md §0.5 for the wizard." >&2
  echo "Required v2 opt-in flags:    ${REQUIRED_V2_FLAGS[*]}" >&2
  echo "Required discriminator flags: ${REQUIRED_DISCRIMINATORS[*]}" >&2
  exit 2
fi

exit 0
