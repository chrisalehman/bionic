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

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — mirroring hooks/sdlc-poker.sh:111's $HOME/.claude/ audit log.
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# Byte-identical to the copies in farm-out-reminder.sh,
# canonical-sdlc-evidence-gate.sh and context-spend.sh — divergence would give
# one project two audit files. Deliberate per-hook duplication (no shared lib).
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-v11-audit.md' "$HOME" "$base" "$sum"
}

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

# Normalize line endings to plain \n before any parsing. Strip a trailing
# \r from each record (CRLF: \r\n → \n) and translate any remaining lone \r
# (classic-Mac CR-only: \r without \n) into a real newline. Every parse below
# is line-anchored (the exact-match `$0 == "---"` frontmatter delimiter,
# yaml_get, the matrix grep), so it must see real newlines.
#
# `tr -d '\r'` (the prior normalization) merely DELETED every \r. On a CRLF
# artifact that happened to work, but on a CR-only artifact it removed every
# line break, collapsing the whole file to ONE line — the frontmatter parser
# then never matched and a VALID artifact was false-BLOCKed as "missing a YAML
# frontmatter block". awk splits on \n by default, so a CR-only file arrives as
# a single record that gsub re-splits into real lines; LF and CRLF files are
# unaffected. Twin of the evidence-gate hook's normalize_newlines.
CONTENT=$(printf '%s' "$CONTENT" | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }')

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

# v3 through v10 are all enforced. v4 added a required `model_plan` (the
# Step-0 model-tier decision); v5 collapses the step set (gate model); v6
# removes the external-review step (0–9 shape); v7 adds the universal
# Step-5 `bundle-fresh:` evidence key (enforced by the evidence-gate
# hook — no flag change here); v8 adds the universal Step-5
# `drive-check:` evidence key (also enforced by the evidence-gate hook,
# not here); v9 adds the universal Step-5 `stack-health:` evidence key
# (also enforced by the evidence-gate hook, not here — no flag change);
# v10 adds the pre-registered Verification Matrix (flag contract
# unchanged — see the matrix-required-at-step-3 check below; the
# per-tier evidence-key shape is enforced by the evidence-gate hook, not
# here). v4/v5/v6/v7/v8/v9/v10 share v4's flag contract unchanged. v3
# plans keep the prior contract so in-flight plans authored before v4
# are not retroactively broken.
if [ "$SDLC_VERSION" != "3" ] && [ "$SDLC_VERSION" != "4" ] && [ "$SDLC_VERSION" != "5" ] && [ "$SDLC_VERSION" != "6" ] && [ "$SDLC_VERSION" != "7" ] && [ "$SDLC_VERSION" != "8" ] && [ "$SDLC_VERSION" != "9" ] && [ "$SDLC_VERSION" != "10" ] && [ "$SDLC_VERSION" != "11" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' has unsupported canonical_sdlc_version: '$SDLC_VERSION'." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: set 'canonical_sdlc_version: 11' (current), '10'/'9'/'8'/'7'/'6'/'5'/'4'/'3' (prior, still enforced), or '1'/'2' for legacy plans." >&2
  exit 2
fi

# ---------- v11: intent × rigor × scale triple + universal contract ----------
#
# v11 re-keys governance off the legacy `mode:` axis onto the triple
# (intent × rigor × scale). Presence + whole-value enum validation is
# blocking; CONTENT is already CR-stripped (line 143), so whole-line
# yaml_get reads compare cleanly under CRLF too. Being a v11
# artifact — not a `mode: autonomous` gate — is what makes the flag /
# model_plan / matrix contract below apply (D13); the mode-gate short
# circuit further down is bypassed for v11 accordingly.
if [ "$SDLC_VERSION" = "11" ]; then
  # Local block helper for this arm — same BLOCKED:/Path: stderr shape as
  # the inline v≤10 blocks above, hoisted to avoid repeating it eight
  # times. Scoped to the v11 path; v≤10 output is untouched.
  block() {
    echo "BLOCKED: canonical-sdlc v11 artifact '$BASENAME': $1" >&2
    echo "Path: $FILE_PATH" >&2
    exit 2
  }
  # Split-brain guard: a v11 artifact declares the triple, never mode.
  [ -z "$(yaml_get mode)" ] || block "v11 artifacts declare intent:/rigor:/scale:, never mode:"
  INTENT=$(yaml_get intent); RIGOR=$(yaml_get rigor); SCALE=$(yaml_get scale)
  [ -n "$INTENT" ] || block "v11 requires intent: (build|bugfix|refactor|tune|spike|incident-response)"
  [ -n "$RIGOR" ]  || block "v11 requires rigor: (tested|peer-reviewed|audited)"
  [ -n "$SCALE" ]  || block "v11 requires scale: (task|wave|epic)"
  case "$INTENT" in
    build|bugfix|refactor|tune|spike|incident-response) ;;
    *) block "invalid intent: '$INTENT' — allowed: build|bugfix|refactor|tune|spike|incident-response" ;;
  esac
  case "$RIGOR" in
    tested|peer-reviewed|audited) ;;
    *) block "invalid rigor: '$RIGOR' — allowed: tested|peer-reviewed|audited" ;;
  esac
  case "$SCALE" in
    task|wave|epic) ;;
    *) block "invalid scale: '$SCALE' — allowed: task|wave|epic" ;;
  esac
  # Intent × scale validity: barred cells derivable from the two enums.
  if [ "$SCALE" = "epic" ]; then
    case "$INTENT" in
      bugfix|spike|incident-response)
        block "barred cell: $INTENT × epic (§Intent × scale validity)" ;;
    esac
  fi

  # ---------- floor-consistency checks (LOG-ONLY; D14, spec R3) ----------
  #
  # Past the blocking gates above INTENT/RIGOR/SCALE are valid enums. These
  # checks compute derivable rigor floors and record a finding when the
  # declared rigor violates one. Findings NEVER block: each appends one line
  # to $HOME/.claude/logs/<project-slug>/sdlc-v11-audit.md — outside every
  # consuming project tree (incident 0001) — AND echoes to stderr, then
  # returns 0. Promotion to blocking is a separate later decision made from
  # this data. Every new read path (config.yaml, epic plan, audit file) is
  # fail-open. The evidence-gate hook carries a twin of log_finding (hook
  # name differs); a shared hooks-lib extraction is deliberately deferred.
  #
  # Rigor ordering (normative): tested(0) < peer-reviewed(1) < audited(2).
  rigor_rank() {
    case "$1" in
      tested) echo 0 ;;
      peer-reviewed) echo 1 ;;
      audited) echo 2 ;;
      *) echo -1 ;;
    esac
  }
  log_finding() {  # $1=check-id $2=detail — never blocks, always returns 0
    local f
    if f=$(audit_path "$PROJECT_ROOT_FROM_PATH"); then
      local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) governing-skill $1: $2 ($FILE_PATH)"
      mkdir -p "$(dirname "$f")" 2>/dev/null \
        && printf '%s\n' "$line" >> "$f" 2>/dev/null
    fi
    echo "canonical-sdlc v11 [$1]: $2" >&2
    return 0
  }

  RR=$(rigor_rank "$RIGOR")
  # Intent floor / spike cap (derivable from intent + rigor).
  [ "$INTENT" = "incident-response" ] && [ "$RR" -lt 2 ] \
    && log_finding intent-floor "incident-response floors at audited, declared $RIGOR"
  [ "$INTENT" = "spike" ] && [ "$RR" -gt 0 ] \
    && log_finding spike-cap "spike is capped at tested, declared $RIGOR"

  # Project floor: rigor-floor: in <project>/.bionic/config.yaml (fail-open;
  # an unparseable/invalid value is its own finding, never a block).
  PF=$(grep -E '^rigor-floor:' "$PROJECT_ROOT_FROM_PATH/.bionic/config.yaml" 2>/dev/null \
    | head -1 | sed 's/^rigor-floor:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
  if [ -n "$PF" ]; then
    PR=$(rigor_rank "$PF")
    if [ "$PR" -lt 0 ]; then
      log_finding project-floor "invalid rigor-floor value '$PF' in config.yaml"
    elif [ "$RR" -lt "$PR" ]; then
      log_finding project-floor "project floor $PF, declared $RIGOR"
    fi
  fi

  # Epic floor: rigor-floor: in the epic plan's frontmatter (first cross-file
  # read in this hook — read-only, fail-open; missing/unreadable epic plan or
  # missing key → no finding, floors are opt-in).
  EPIC=$(yaml_get epic)
  if [ -n "$EPIC" ] && [ -r "$DOCS_ROOT/plans/$EPIC/epic.plan.md" ]; then
    EF=$(awk '/^---$/{n++;next} n==1' "$DOCS_ROOT/plans/$EPIC/epic.plan.md" \
      | grep -E '^rigor-floor:' | head -1 | sed 's/^rigor-floor:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
    if [ -n "$EF" ]; then
      ER=$(rigor_rank "$EF")
      [ "$ER" -ge 0 ] && [ "$RR" -lt "$ER" ] \
        && log_finding epic-floor "epic floor $EF (from $EPIC), declared $RIGOR"
    fi
  fi
fi

# v3–v10 schema: require all opt-in flags + discriminators only for
# autonomous mode. Other modes (epic-scope, incident-response,
# design-refresh, spike) have different rule sets and are out of scope for
# enforcement. v11 has no mode axis — its triple's presence is the gate
# (D13), so v11 enters the flag/model_plan/matrix contract below WITHOUT
# consulting this short circuit (the `!= 11` clause keeps v≤10 behavior
# byte-identical).
MODE=$(yaml_get mode)
# Read SCALE unconditionally here (mirrors MODE) so it is bound on every path
# under `set -u`. The v11 arm re-reads it for its own triple validation; v10
# plans have no scale: field, so SCALE is "" and the matrix block treats them
# as before. Without this, the matrix block's `[ "$SCALE" != "task" ]` guard
# tripped an unbound-variable error on the v10 autonomous path.
SCALE=$(yaml_get scale)
if [ "$SDLC_VERSION" != "11" ] && [ "$MODE" != "autonomous" ]; then
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
if [ "$SDLC_VERSION" = "4" ] || [ "$SDLC_VERSION" = "5" ] || [ "$SDLC_VERSION" = "6" ] || [ "$SDLC_VERSION" = "7" ] || [ "$SDLC_VERSION" = "8" ] || [ "$SDLC_VERSION" = "9" ] || [ "$SDLC_VERSION" = "10" ] || [ "$SDLC_VERSION" = "11" ]; then
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
  if [ "$SDLC_VERSION" = "4" ] || [ "$SDLC_VERSION" = "5" ] || [ "$SDLC_VERSION" = "6" ] || [ "$SDLC_VERSION" = "7" ] || [ "$SDLC_VERSION" = "8" ] || [ "$SDLC_VERSION" = "9" ] || [ "$SDLC_VERSION" = "10" ] || [ "$SDLC_VERSION" = "11" ]; then
    echo "Required for v${SDLC_VERSION} (added):      model_plan" >&2
  fi
  exit 2
fi

# ---------- v10: pre-registered Verification Matrix required at Step 3+ ----------
#
# v10's Step 0 derives a "## Verification Matrix" section (per-AC tier +
# status + evidence, locked at Step 3 approval — see canonical-sdlc
# SKILL.md's "Verification Matrix" sub-step under Step 0). This hook
# checks section PRESENCE only (structure, not substance); the
# evidence-gate hook validates the per-row per-tier fields and the
# CONFIRMED/waived auditor discipline (structure vs substance split
# mirrors the model_plan / flag checks above).
#
# Scope: v10 mode: autonomous OR any v11 (v11 has no mode gate — its
# triple's presence is the gate, D13), basename *.plan.md, sdlc-step >= 3
# (numeric). Specs, non-autonomous v10 modes, continuation*.md, v11
# scale: task plans (they carry a ## Tasks ledger, not a matrix), and
# earlier schema versions are out of scope — the matrix is a plan-body
# artifact that exists starting at Step 3 (Plan) approval.
if { [ "$SDLC_VERSION" = "10" ] && [ "$MODE" = "autonomous" ]; } || [ "$SDLC_VERSION" = "11" ]; then
  case "$BASENAME" in
    *.plan.md)
      SDLC_STEP=$(yaml_get sdlc-step)
      case "$SDLC_STEP" in
        ''|*[!0-9]*) ;;  # non-numeric or empty sdlc-step → not in scope
        *)
          # scale: task plans carry a ## Tasks ledger, not a ## Verification
          # Matrix (the matrix is a wave/epic artifact) — exempt them. SCALE is
          # set only on the v11 arm above (empty for v10 autonomous), so this
          # guard never changes v10 behavior.
          if [ "$SDLC_STEP" -ge 3 ] 2>/dev/null && [ "$SCALE" != "task" ]; then
            if ! echo "$CONTENT" | grep -qE '^## Verification Matrix'; then
              if [ "$SDLC_VERSION" = "11" ]; then
                echo "BLOCKED: canonical-sdlc v11 plan '$BASENAME' (sdlc-step ${SDLC_STEP}) is missing a '## Verification Matrix' section." >&2
              else
                echo "BLOCKED: canonical-sdlc v10 autonomous plan '$BASENAME' (sdlc-step ${SDLC_STEP}) is missing a '## Verification Matrix' section." >&2
              fi
              echo "Path: $FILE_PATH" >&2
              echo "Fix: derive the matrix at Step 0 (see SKILL.md §Step 0 'the Verification Matrix') and lock it at Step 3 approval, or if this wave is reopened, use the Step 5–9 upgrade path in §Versioning." >&2
              exit 2
            fi
          fi
          ;;
      esac
      ;;
  esac
fi

exit 0
