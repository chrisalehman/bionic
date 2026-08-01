#!/bin/bash
# EVIDENCE GATE: Blocks git commits during a canonical-sdlc run when the
# plan file's ## SDLC State section is missing the current step's evidence.
#
# Convention: the plan file contains a section like:
#
#   ## SDLC State
#   integration-branch: main
#   current: 5
#   Step 1: /path/or/link
#   Step 2: /path/to/spec.md
#   Step 3: .bionic/docs/plans/epic-NN-<slug>/wave-NN-<slug>.plan.md
#   Step 4: git worktree at /path, base SHA abc123
#   Step 5: tests passing, commit abc123
#
# If the current step's line is empty or a placeholder (TODO, pending,
# in progress, XXX, TBD, placeholder), block the commit. The rule is:
# the evidence artifact must be recorded in the plan file *before* the
# commit that closes the step.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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

# Locate the newest plan file across THIS PROJECT's plan directories:
#   - <docs-root>/plans/      (bionic canonical-sdlc convention)
#   - <docs-root>/incidents/  (incident-response runs)
#
# Picks the newest .md across those that exist. If none exist, this isn't a
# canonical-sdlc session — let the commit through (see ABSENT vs MISPLACED
# below).
#
# NOT searched, deliberately: `~/.claude/plans/` and
# `<project>/docs/superpowers/plans/`. Both were in the search set until
# 2026-07-28; bionic gates bionic's plans, full stop (user ruling). The global
# directory is the harness's own, project-AGNOSTIC one — Claude Code's plan mode
# drops unrelated notes there routinely, and selection takes the newest .md
# across the whole set. One such note therefore won selection, carried no
# `## SDLC State`, and this hook exited 0: every commit in that project ran
# ungated. The superpowers directory was the same pre-`.bionic/docs` vestige
# (the root `docs/` tree was deleted 2026-07-16); nothing writes canonical plans
# to either.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# Project resolution mirrors memory-update.sh: CLAUDE_PROJECT_DIR first,
# then the hook input's cwd field, then pwd. Consistent with existing hooks.
# That value NAMES the invoking directory; the ROOT is computed from it below.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(echo "$INPUT" | jq -r '.cwd // empty')
fi
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR=$(pwd)
fi

# Compute the project root that owns $1 — never discover it by walking for an
# existing `.bionic/`. Byte-identical twin of the copy in
# canonical-sdlc-governing-skill.sh (deliberate per-hook duplication, no shared
# lib — same convention as audit_path below).
#
# `git rev-parse --git-common-dir` names the MAIN repository's .git even from
# inside a linked worktree (`--git-dir` would name the worktree's private dir),
# so every worktree of one repo resolves to ONE root and therefore one audit
# file.
#
# `--path-format=absolute` is load-bearing, not cosmetic: the bare form returns
# a RELATIVE path (`.git` at the root, `../.git` one level down), whose dirname
# is `.` or `..` — a cwd-dependent string, not a root. It landed in git 2.31.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# OLD-GIT FALLBACK (Step-6 finding K2). On git < 2.31 `--path-format` is an
# unknown option and rev-parse exits 129 — which the single-branch predecessor
# could not tell apart from "not a repository", so the root silently became the
# caller's cwd. Plan assumption 6 claimed a `cd`-and-`pwd` fallback already
# covered this; it did not exist. A documented mitigation that was never built
# is worse than an unlogged one — it reads as retired, and a reviewer who checks
# the local git version moves on.
#
# So: retry the BARE form, which every git has, and absolutize its answer here.
# It answers RELATIVE inside the main repo and ABSOLUTE from a linked worktree,
# hence the `case`. Only when BOTH forms fail is this genuinely not a
# repository, and the supplied fallback wins as before. The governing-skill
# hook feels this hardest (its call passes no fallback, so it lands on `pwd`);
# the twin is kept byte-identical regardless.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# `git -C` needs a directory that EXISTS; climbing to the nearest existing
# ancestor supplies git a valid cwd. That climb is not a search for `.bionic/`
# — the loop's condition never mentions it, and the answer still comes from git.
resolve_project_root() {  # $1=a path whose repo we want; $2=fallback (default pwd)
  local d common root
  d=$(dirname "$1")
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ] && [ -n "$d" ]; do
    d=$(dirname "$d")
  done
  if common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    dirname "$common"
    return
  fi
  if common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null); then
    case "$common" in
      /*) root=$(dirname "$common") ;;
      *)  root=$(cd "$d" 2>/dev/null && cd "$(dirname "$common")" 2>/dev/null && pwd -P) ;;
    esac
    if [ -n "$root" ]; then
      printf '%s\n' "$root"
      return
    fi
  fi
  printf '%s\n' "${2:-$(pwd)}"
}

# ONE root per repo, across BOTH hooks (Step-6 finding C2/S1).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# The governing-skill hook resolves an artifact's project with the twin above,
# so a Write from inside a linked worktree is placed against the MAIN repo's
# docs root. This gate used to keep PROJECT_DIR — and therefore DOCS_ROOT,
# PLAN_DIRS, and the AC-13 misplacement sweep's root — at the raw invoking
# directory, i.e. the worktree. Slice 1 migrated only audit_root().
#
# The consequence was that in a linked worktree NO artifact placement satisfied
# both hooks: obey the governing hook and put the plan in the main repo, and
# every commit made from the worktree ran ungated; put it in the worktree so
# this gate finds it, and every artifact write was blocked. canonical-sdlc ships
# a `use_worktree` flag, so that is the lifecycle's own normal mode.
#
# `$PROJECT_DIR/.` hands the helper a path whose dirname is PROJECT_DIR itself
# (it is written for a FILE path). Fail-open: when git cannot answer — an
# invoking directory outside any repository — the fallback is the unresolved
# value, so a non-repo caller keeps exactly its previous meaning.
PROJECT_DIR=$(resolve_project_root "$PROJECT_DIR/." "$PROJECT_DIR")

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

# Read unconditionally, next to the other globals: this hook runs `set -u`, and
# a variable bound on only some code paths crashes the others. See
# `.claude/rules/hook-authoring.md` (machine-local, gitignored, authored in
# place — no script recreates it, so it is absent from a fresh clone) § "`set -u` and
# conditionally-bound variables" — the recorded recurrence of exactly this.
DOCS_ROOT=$(resolve_docs_root "$PROJECT_DIR")

# Both directories belong to THIS project. No `if [ -n "$PROJECT_DIR" ]` guard:
# PROJECT_DIR is unconditionally non-empty (it falls back to pwd above), and an
# empty array would be worse than useless here — `"${arr[@]}"` on an empty array
# is an unbound-variable error under `set -u` on bash 3.2.
PLAN_DIRS=( "${DOCS_ROOT}/plans" "${DOCS_ROOT}/incidents" )

# PLAN — the newest .md across them; the plan this gate validates, and the same
# value the misplacement sweep below keys off.
#
# This was two variables until 2026-07-28 (PLAN + PROJECT_PLAN). The split
# existed for exactly one reason: the search set then included the
# project-AGNOSTIC `~/.claude/plans/`, so the newest file overall might belong to
# no project at all, and the sweep needed a project-only selection to key on.
# With every searched directory now this project's, the two selections are the
# same file by construction.
PLAN=""
for d in "${PLAN_DIRS[@]}"; do
  [ -d "$d" ] || continue
  # Descend up to 2 levels deep to support the bionic directory-per-epic
  # layout: <docs-root>/plans/epic-NN-<slug>/wave-NN-<slug>.plan.md. Flat
  # conventions (<docs-root>/plans/<name>.md) are covered at depth 1.
  while IFS= read -r -d '' f; do
    if [ -z "$PLAN" ] || [ "$f" -nt "$PLAN" ]; then
      PLAN="$f"
    fi
  done < <(find "$d" -maxdepth 2 -type f -name '*.md' -print0 2>/dev/null)
done

# ---------- AC-13: misplacement blocks; absence never does ----------
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# No plan file was found in this project's plan directories. That used to be an
# unconditional `exit 0`, and it is this hook's fail-open — a structurally
# different one from the governing-skill hook's, which is why the two are fixed
# and tested independently. This one never tests `.bionic/` at all: every
# candidate directory is skipped by `[ -d "$d" ] || continue`, PLAN comes back
# empty, and the commit passes ungated.
#
# The guard was PROJECT_PLAN from the Step-6 C1/S2 repair until 2026-07-28,
# because PLAN then meant "no plan in ANY searched directory" and the first
# directory searched was the project-agnostic `~/.claude/plans/`: one unrelated
# `.md` there made PLAN non-empty and this whole block dead. Deleting that
# directory from the search set fixes the same hole at its root, so the guard is
# back on PLAN — which now means what C1/S2 needed it to mean.
#
# ABSENT is not an error and must never block. No plan anywhere is every commit
# in every project that does not use this lifecycle, plus the normal first-run
# state of one that does.
#
# MISPLACED is: a plan carrying the run-state marker exists inside the project
# but outside every directory this gate searches. The gate is then silently
# disabled — precisely the failure the AC exists to convert into a block.
#
# Scoping, deliberately narrow, because a false positive here walls off every
# commit in the project:
#   - `*.plan.md` only. The gate consumes plans. A misplaced file under the
#     flat `~/.claude/plans/<name>.md` convention is not covered — that whole
#     directory is already searched.
#   - The LEADING frontmatter must declare `canonical_sdlc_version`, the
#     run-state marker (never `governing-skill`, the artifact-author field —
#     see `.claude/rules/hook-authoring.md` — machine-local, gitignored,
#     authored in place; no script recreates it). Reading only the leading block is
#     what keeps a fenced example in a documentation page from counting.
#   - The whole docs root is "placed", not just plans/ and incidents/:
#     <docs-root>/spikes/ and <docs-root>/record/ hold real artifacts carrying
#     this frontmatter, and the governing-skill hook treats them as placed too.
#   - Bounded walk: `.git` and `node_modules` pruned, depth 5, filename match
#     first. It runs only when no plan was found, so a project in an active
#     canonical-sdlc run never pays for it.
if [ -z "$PLAN" ] || [ ! -f "$PLAN" ]; then
  MISPLACED_PLAN=""
  if [ -d "$PROJECT_DIR" ]; then
    while IFS= read -r -d '' f; do
      case "$f" in "$DOCS_ROOT"/*) continue ;; esac
      if head -c 8192 "$f" \
         | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' \
         | awk 'NR == 1 && $0 == "---" { inside = 1; next }
                inside && $0 == "---" { exit }
                inside { print }' \
         | grep -qE '^[[:space:]]*canonical_sdlc_version[[:space:]]*:'; then
        MISPLACED_PLAN="$f"
        break
      fi
    done < <(find "$PROJECT_DIR" -maxdepth 5 \
               \( -name .git -o -name node_modules \) -prune -o \
               -type f -name '*.plan.md' -print0 2>/dev/null)
  fi

  if [ -n "$MISPLACED_PLAN" ]; then
    echo "BLOCKED: a canonical-sdlc plan is misplaced — this commit would pass ungated." >&2
    echo "Misplaced plan: $MISPLACED_PLAN" >&2
    echo "Docs root:      $DOCS_ROOT" >&2
    echo "The evidence gate searches only the plan directories for this project, so a plan" >&2
    echo "outside them silently disables it — no step evidence is checked at all." >&2
    echo "Fix: move it under $DOCS_ROOT/plans/ (or $DOCS_ROOT/incidents/ for an incident run)." >&2
    exit 2
  fi

  # ABSENCE: nothing misplaced and nothing to validate. Never blocks — this is
  # every commit in every project that does not use the lifecycle, plus the
  # normal first-run state of one that does. This exit lived in a second `if`
  # on its own until 2026-07-28, when the sweep's guard was the narrower
  # PROJECT_PLAN and the two conditions could differ; on one guard they cannot,
  # so the sweep and its fall-through are one block.
  exit 0
fi

# Normalize a plan file's line endings to plain \n on stdout. Strips a trailing
# \r from each record (CRLF: \r\n → \n) and converts any remaining lone \r
# (classic-Mac CR-only: \r without \n) into a real newline. Every parse below is
# line-anchored, so it must see real newlines.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# `tr -d '\r'` (the prior normalization) merely DELETED every \r. On a CRLF file
# that happened to work, but on a CR-only file it removed every line break,
# collapsing the whole plan to ONE line beginning with the frontmatter `---`.
# The line-anchored `/^## SDLC State/` presence check then never matched, the
# hook exited 0 as "not a canonical-sdlc plan", and every commit passed ungated.
# awk splits on \n by default, so a CR-only file arrives as a single record that
# gsub re-splits into real lines; LF and CRLF files are unaffected.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
normalize_newlines() {
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1"
}

# The newest plan has no ## SDLC State section → not a canonical-sdlc run.
# Fence-aware (matches the SECTION extraction below): a `## SDLC State` heading
# that appears ONLY inside a ``` fenced example is documentation, not state, so
# the file passes through as non-canonical rather than being parsed and then
# false-blocked on the empty extraction. Line endings normalized (CRLF and
# CR-only) to real newlines first — see normalize_newlines.
if [ -z "$(normalize_newlines "$PLAN" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { print "yes"; exit }
')" ]; then
  exit 0
fi

# Extract YAML frontmatter (between first two `---` lines at column 0)
# if the plan has any. Used to read the version marker, the triple, and the
# discriminator flags the checks below key off.
#
# CRLF/CR-only plans would otherwise defeat the exact-match `$0=="---"`
# comparison ("---\r" != "---"), so line endings are normalized to \n before
# every awk pass (normalize_newlines) — meaning every downstream parse
# (frontmatter values, SECTION lines, CURRENT, evidence blocks) sees plain
# \n text regardless of the file's original line-ending style.
FRONTMATTER=$(normalize_newlines "$PLAN" | awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f')

frontmatter_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*$1[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*$1[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//' \
    | sed -E "s/^['\"]//;s/['\"]\$//"
}

DEPLOY_TARGET=$(frontmatter_get deploy_target)
SDLC_VERSION=$(frontmatter_get canonical_sdlc_version)
USE_WORKTREE=$(frontmatter_get use_worktree)
SCALE=$(frontmatter_get scale)
INTENT=$(frontmatter_get intent)
RIGOR=$(frontmatter_get rigor)
MULTI_AGENT=$(frontmatter_get multi_agent)

# ONE supported version. Anything else — an older number, a typo, an empty
# value, garbage — blocks. Symmetric with the governing-skill hook. There is
# no version dispatch anywhere below this line, so there is also no path that
# reaches `exit 0` by matching no arm.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
SUPPORTED_SDLC_VERSION=12

if [ "$SDLC_VERSION" != "$SUPPORTED_SDLC_VERSION" ]; then
  echo "BLOCKED: canonical-sdlc evidence-gate: plan declares canonical_sdlc_version: '$SDLC_VERSION'." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: set 'canonical_sdlc_version: ${SUPPORTED_SDLC_VERSION}' — the only supported version." >&2
  exit 2
fi

# Whole-value placeholder test: trim leading/trailing whitespace, lowercase,
# then require whole-value EQUALITY against the known token set. A token that
# merely appears as a substring of a longer value ("resolved TODOs",
# "*.example placeholders", "status pending → done") is legal evidence.
# "in progress" and its whitespace-free "inprogress" are both listed so
# either spelling of the value matches. Defined here (ahead of the Step-line
# checks) so the task-ledger validator, which runs before them, can reuse it.
is_placeholder_value() {
  local v
  v=$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | tr '[:upper:]' '[:lower:]')
  case "$v" in
    todo|pending|"in progress"|inprogress|xxx|tbd|placeholder) return 0 ;;
    *) return 1 ;;
  esac
}

# Audit dir follows the plan's own project, COMPUTED from $PLAN's own repo
# rather than discovered by walking for a `.bionic/` ancestor — matching the
# governing-skill hook's resolve_project_root strategy. Findings live with the
# project that owns the artifact, not necessarily the invoking PROJECT_DIR, and
# every worktree of one repo shares one audit file. PROJECT_DIR remains the
# fallback when $PLAN resolves outside any repository — the same value the
# exhausted walk-up used to return. Fail-open: git failure never crashes the hook.
# [INSTRUMENT]
audit_root() {
  resolve_project_root "$PLAN" "$PROJECT_DIR"
}

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# Byte-identical to the copies in farm-out-reminder.sh,
# canonical-sdlc-governing-skill.sh and context-spend.sh — divergence would give
# one project two audit files. Deliberate per-hook duplication (no shared lib).
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

# Log-only finding channel (D14): append one line to the durable audit file
# AND echo to stderr, then return 0 — floor/ledger/merge-target findings never
# block this wave. Twin of the governing-skill hook's helper (hook name differs:
# `evidence-gate`). mkdir + append are fail-open. audit_root() still selects
# WHICH project the finding belongs to; incident 0001 moved WHERE the file for
# that project lives — $HOME/.claude/logs/<project-slug>/, outside every
# consuming project tree, never .bionic/memory/ again. An unwritable
# destination drops the line; there is deliberately no fallback branch.
# [INSTRUMENT]
log_finding() {  # $1=check-id  $2=detail
  local f
  if f=$(audit_path "$(audit_root)"); then
    local line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) evidence-gate $1: $2 ($PLAN)"
    mkdir -p "$(dirname "$f")" 2>/dev/null && printf '%s\n' "$line" >> "$f" 2>/dev/null
  fi
  echo "canonical-sdlc [$1]: $2" >&2
  return 0
}

# Normalize a task row's rigor cell to its effective rigor lane. Whole-value
# `case` equality against the rigor enum (bash-3.2 safe — no associative arrays,
# same idiom as is_r7_key below): a cell already naming a lane passes through; a
# non-empty cell outside the enum is INVALID; an empty cell inherits the
# plan-level RIGOR when that itself names a lane, else defaults to `tested` (the
# floor — see plan Assumption A3). Defined ahead of validate_task_ledger (which
# runs at the `current: T<n>` branch, before is_r7_key is defined below) so the
# validator can call it — same placement rationale as is_placeholder_value.
effective_row_rigor() {  # $1 = row's rigor cell
  local cell
  cell=$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$cell" in
    tested|peer-reviewed|audited) echo "$cell"; return ;;
    "") : ;;
    *) echo "INVALID"; return ;;
  esac
  case "$RIGOR" in
    tested|peer-reviewed|audited) echo "$RIGOR" ;;
    *) echo "tested" ;;
  esac
}

# Total order over the rigor enum, for the per-row FLOOR check (slice 4/8).
# tested < peer-reviewed < audited. An empty/unknown value maps to 0 (the tested
# floor) so an unset frontmatter rigor never manufactures a phantom downgrade.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
# Mirrors the governing-skill hook's ord map at its rigor check (kept in sync by
# hand, not imported — the two hooks share no source). bash-3.2 safe whole-value
# `case`, same idiom as effective_row_rigor above.
rigor_ord() {  # $1 = a rigor lane name (or empty)
  case "$1" in
    peer-reviewed) echo 1 ;;
    audited)       echo 2 ;;
    *)             echo 0 ;;  # tested, empty, or unknown → the floor
  esac
}

# Proof-shape test (D-slice 4/2): an evidence value counts as "proof-shaped"
# — a command invocation + result counts, not prose — iff it contains BOTH
# at least one digit AND at least one command token. A command token is any
# of: a backtick; a literal '/' anywhere (a path, e.g. 'hooks/foo.sh'); or a
# whole-word match against the fixed runner list (bash-3.2 safe — no
# associative arrays, `grep -Ew` for the bounded whole-word match so `test`
# matches in "bash test.sh 12/12" but `testing` never triggers on a `test`
# substring). Returns 0 (proof-shaped) / 1 (not) — never blocks itself; the
# caller (apply_rigor_lanes) decides what a failure means.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
is_proof_shaped() {  # $1 = evidence value
  local v="$1"
  echo "$v" | grep -qE '[0-9]' || return 1
  if echo "$v" | grep -q '`'; then
    return 0
  fi
  if echo "$v" | grep -qF '/'; then
    return 0
  fi
  if echo "$v" | grep -Ewq 'bash|sh|npm|pnpm|yarn|make|pytest|go|cargo|git|test'; then
    return 0
  fi
  return 1
}

# Rigor-keyed evidence lanes (D-slice 4/2, TASK SCALE ONLY). Applies to
# the addressed row (any status) and to every OTHER row with status `done`
# that has a non-empty, non-placeholder evidence line — the caller only
# invokes this once those upstream 4/1 presence/placeholder checks (and, for
# the addressed row, the rigor-enum check) have already passed. BLOCKS
# (exit 2) on any lane breach:
#   - effective rigor peer-reviewed or audited: evidence must be proof-shaped.
#   - status done AND effective rigor >= peer-reviewed: evidence must name
#     an `auditor` verdict.
#   - status done AND effective rigor audited: evidence must ALSO name a
#     `critic` verdict.
# The `tested` floor carries none of these demands — 4/1's presence +
# placeholder checks are its entire contract (plan Assumption A4: the literal
# substrings are sufficient tokens, no pointer-format sub-schema).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
apply_rigor_lanes() {  # $1=id $2=status $3=effective-rigor $4=evidence-value
  local id="$1" status="$2" eff="$3" ev="$4"
  case "$eff" in
    peer-reviewed|audited)
      if ! is_proof_shaped "$ev"; then
        echo "BLOCKED: canonical-sdlc task ${id} evidence must show a command + counts, not prose, at rigor '${eff}' ('${ev}')." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: replace the '- ${id}:' evidence with the actual command invocation and result counts (e.g. 'bash test.sh 12/12 green')." >&2
        exit 2
      fi
      ;;
  esac
  if [ "$status" = "done" ]; then
    case "$eff" in
      peer-reviewed|audited)
        if ! echo "$ev" | grep -Ewq 'auditor'; then
          echo "BLOCKED: canonical-sdlc task ${id} is done at rigor '${eff}' but its evidence has no 'auditor' verdict ('${ev}')." >&2
          echo "Plan: $PLAN" >&2
          echo "Fix: record the independent auditor's verdict in the '- ${id}:' evidence line before marking done." >&2
          exit 2
        fi
        ;;
    esac
    if [ "$eff" = "audited" ]; then
      if ! echo "$ev" | grep -Ewq 'critic'; then
        echo "BLOCKED: canonical-sdlc task ${id} is done at rigor 'audited' but its evidence has no 'critic' verdict ('${ev}')." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: record the adversarial critic's verdict in the '- ${id}:' evidence line before marking done." >&2
        exit 2
      fi
    fi
  fi
}

# Per-row rigor FLOOR check (slice 4/8, A15 — user-ratified, momentous). The
# per-row `rigor` cell is a FLOOR unified with the run-rigor floor model: a
# cell RAISING a row above the frontmatter rigor is always allowed (the cell
# drives the heavier lane, 4/4), but a cell LOWERING it below the frontmatter
# rigor is a DOWNGRADE — a recorded decision, never silent. A downgrade BLOCKS
# (exit 2) UNLESS the row's `- T<n>:` evidence line carries a whole-word `waiver`
# marker (Waiver Protocol — same `grep -Ewq` word-boundary idiom as the lane
# token checks), in which case the row proceeds at its (lower) cell lane.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# Called on exactly the rows the rigor lanes cover — the addressed unit (any
# status) and non-addressed `done` rows with real evidence — AFTER their
# presence/placeholder checks and the per-row INVALID guard, and BEFORE
# apply_rigor_lanes. Ordering rationale: a missing/placeholder evidence block
# (addressed unit, or audited non-addressed via ledger_shape_fail) and the
# INVALID-cell block both fire upstream of this, so they still win — a row with
# no evidence line never reaches here (there is no line to hold a waiver, and its
# absence already blocks or logs). `eff` is the RESOLVED effective rigor: an
# empty cell resolves to the frontmatter rigor, so rigor_ord(eff) ==
# rigor_ord(RIGOR) and no phantom downgrade fires — only an explicit lower cell
# trips it. A cell EQUAL to the frontmatter is not a downgrade (strict `<`).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
enforce_rigor_floor() {  # $1=id  $2=effective-rigor  $3=evidence-value
  local id="$1" eff="$2" ev="$3"
  [ "$(rigor_ord "$eff")" -lt "$(rigor_ord "$RIGOR")" ] || return 0
  if echo "$ev" | grep -Ewq 'waiver'; then
    return 0  # recorded downgrade — proceed at the lower cell lane
  fi
  echo "BLOCKED: canonical-sdlc task ${id} lowers rigor from '${RIGOR}' to '${eff}', below the plan's floor." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: raise the cell to at least '${RIGOR}', or record a downgrade: add 'waiver: <user> <date> <reason>' to the '- ${id}:' evidence line (Waiver Protocol)." >&2
  exit 2
}

# Router for the previously-log-only NON-addressed-row ledger-shape checks
# (D-slice 4/3, task scale). On a frontmatter `rigor: audited` plan these
# promote to BLOCKING (exit 2); at any other rigor they stay log-only findings
# (D14, unchanged). The detail string is authored once by the caller and used
# verbatim in whichever channel fires. The addressed-unit floor (4/1) and the
# rigor lanes (4/2) are NOT routed through here — they already block
# unconditionally where they should.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
ledger_shape_fail() {  # $1 = detail
  if [ "$RIGOR" = audited ]; then
    echo "BLOCKED: canonical-sdlc task-ledger: $1" >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: resolve the ledger-shape defect above before committing (audited rigor makes the ledger-shape checks blocking; a non-audited plan would log this as a finding instead)." >&2
    exit 2
  fi
  log_finding task-ledger "$1"
}

# Task-scale ledger validation (D12). Reads the `## Tasks` registration
# table (fence-aware, the matrix_section idiom) and the per-task `- T<n>:`
# evidence lines in the ## SDLC State section (SECTION, already newline-normalized).
#
# Two lanes (slice 4/1), plus rigor-keyed lanes on top (slice 4/2):
#   - THE ADDRESSED UNIT — the `T<n>` named by `current: T<n>` — is BLOCKING at
#     the tested floor: its row must exist in `## Tasks`, carry a non-placeholder
#     `- T<n>:` evidence line, and have a rigor cell that resolves (its cell
#     names a lane, or is empty; a non-empty cell outside the enum is INVALID).
#     Any breach emits a 3-line block message and exit 2. Once past the floor,
#     apply_rigor_lanes (4/2) applies the proof-shape/auditor/critic lanes keyed
#     to its effective rigor.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
#   - EVERY OTHER row stays LOG-ONLY (D14, check-id `task-ledger`) for status
#     and presence/placeholder: status outside {pending,active,done,dropped},
#     or an active/done task with no `- T<n>:` line or a placeholder/empty
#     value, each append one finding and never block. Missing `## Tasks`
#     entirely is also log-only here. A `done` row that DOES have a non-empty,
#     non-placeholder evidence line resolves its effective rigor and is
#     additionally passed through apply_rigor_lanes (4/2) — BLOCKING, since a
#     done claim at peer-reviewed+ rigor without real evidence is a false-done
#     claim, not a bookkeeping gap. A malformed (off-enum) rigor cell on ANY row
#     — addressed or not, at ANY status (done, active, pending, dropped) — is
#     caught earlier by the per-row INVALID guard (4/7), which resolves the cell
#     and BLOCKS unconditionally at any frontmatter rigor before this
#     status-based branching; see that guard for the rationale.
# [INSTRUMENT]
validate_task_ledger() {
  local tasks rows line id status rigor_cell ev eff addressed_found=0
  tasks=$(normalize_newlines "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Tasks/ { f=1; next }
    /^## / { f=0 }
    f')
  if [ -z "$tasks" ]; then
    ledger_shape_fail "task-scale plan has no '## Tasks' registration section"
    return 0
  fi
  rows=$(echo "$tasks" | grep -E '^[[:space:]]*\|[[:space:]]*T[0-9]+')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(echo "$line"         | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    status=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')
    rigor_cell=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')
    # status enum — routed through ledger_shape_fail (4/3): blocking on audited
    # plans, log-only otherwise (was unconditionally log-only in D12).
    case "$status" in
      pending|active|done|dropped) : ;;
      *) ledger_shape_fail "task ${id} has invalid status '${status:-empty}' (want pending|active|done|dropped)" ;;
    esac
    # Per-row INVALID rigor-cell guard (4/7): resolve this row's rigor cell and
    # block if it is off-enum. A malformed rigor cell makes the row's lane
    # indeterminate — a hard STRUCTURAL error, the exact sibling of the
    # status-enum check above (both are whole-value enum equality on a single
    # cell, validated per-row REGARDLESS of the row's status). So it blocks
    # UNIFORMLY: on ANY row (addressed or not; done, active, pending, dropped)
    # and at ANY frontmatter rigor — NOT routed through the audited-only
    # ledger_shape_fail. Placed here, before the evidence extraction and the
    # addressed-vs-other branching, so this ONE guard covers every row —
    # consolidating the former per-branch INVALID checks (4/1 addressed unit,
    # 4/6 non-addressed done) that left non-addressed active/pending rows
    # unchecked. `eff` is reused by both branches below (never INVALID past
    # here). Order vs the status-enum check: status first, then rigor — a row
    # with BOTH defects may block on either; this order is pinned for determinism.
    # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
    eff=$(effective_row_rigor "$rigor_cell")
    if [ "$eff" = "INVALID" ]; then
      echo "BLOCKED: canonical-sdlc task ${id} has an invalid rigor '${rigor_cell}' (want tested|peer-reviewed|audited)." >&2
      echo "Plan: $PLAN" >&2
      echo "Fix: set the '${id}' row's rigor cell to one of tested, peer-reviewed, audited before committing." >&2
      exit 2
    fi
    # Evidence line for this task in ## SDLC State (anchored so T2 never matches T20).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
    ev=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:" | head -1 \
         | sed -E "s/^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    if [ "$id" = "$CURRENT" ]; then
      # THE ADDRESSED UNIT: the tested floor is BLOCKING (slice 4/1).
      addressed_found=1
      if [ -z "$ev" ]; then
        echo "BLOCKED: canonical-sdlc task ${id} has no '- ${id}:' evidence line in '## SDLC State'." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: record the evidence artifact on a '- ${id}:' line before committing." >&2
        exit 2
      fi
      if is_placeholder_value "$ev"; then
        echo "BLOCKED: canonical-sdlc task ${id} evidence line is a placeholder ('${ev}')." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: replace the '- ${id}:' placeholder with the actual evidence artifact before committing." >&2
        exit 2
      fi
      # 4/8: FLOOR check — a cell lowering this row below the frontmatter rigor
      # blocks unless the evidence line records a waiver. Runs after the
      # presence/placeholder blocks above (so those win) and before the lanes.
      enforce_rigor_floor "$id" "$eff" "$ev"
      # 4/2: rigor-keyed proof-shape/auditor/critic lanes on top of the tested
      # floor above. `eff` was resolved and INVALID-guarded at the per-row guard
      # (4/7); it names a valid lane here. Applies regardless of this row's own
      # status — the addressed unit is always in scope.
      # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
      apply_rigor_lanes "$id" "$status" "$eff" "$ev"
    else
      # Every OTHER row's presence/placeholder checks route through
      # ledger_shape_fail (4/3): blocking on audited plans, log-only otherwise.
      case "$status" in
        active|done)
          if [ -z "$ev" ]; then
            ledger_shape_fail "task ${id} is ${status} but has no evidence on a '- ${id}:' line in ## SDLC State"
          elif is_placeholder_value "$ev"; then
            ledger_shape_fail "task ${id} is ${status} but its evidence is a placeholder ('${ev}')"
          elif [ "$status" = "done" ]; then
            # 4/2: a done row WITH real evidence is in scope for the
            # rigor-keyed lanes (BLOCKING) — a false-done claim at
            # peer-reviewed+ rigor, not a bookkeeping gap. A done row with
            # NO evidence line stays log-only above (4/3 territory). `eff` was
            # resolved and INVALID-guarded at the per-row guard (4/7 — was a
            # done-only guard under 4/6; now uniform across statuses), so it
            # names a valid lane here.
            # 4/8: FLOOR check first — a done row whose cell lowers it below the
            # frontmatter rigor blocks unless its evidence line records a waiver.
            enforce_rigor_floor "$id" "$eff" "$ev"
            apply_rigor_lanes "$id" "$status" "$eff" "$ev"
          fi
          ;;
      esac
    fi
  done <<< "$rows"
  # The addressed unit (current: T<n>) must have a row in ## Tasks (BLOCKING).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
  if [ "$addressed_found" -eq 0 ]; then
    echo "BLOCKED: canonical-sdlc task ${CURRENT} has no row in the '## Tasks' registration table." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: add a '| ${CURRENT} | <intent> | <rigor> | <description> | <status> |' row to '## Tasks' before committing." >&2
    exit 2
  fi
  return 0
}

# Extract the ## SDLC State section (from its header up to the next ##
# header or EOF). Line endings normalized here too (normalize_newlines), for
# the same reason as FRONTMATTER above. Fence-aware (same idiom as matrix_section): lines inside
# ``` fenced code blocks are skipped, so a plan documenting the D12 task-scale
# schema in a fenced example — a `## SDLC State` heading with `current: T<n>` —
# does not shadow the REAL section (which would mis-parse `current:` and false-
# block). Fence state is tracked across the whole file so section detection
# stays fence-aware.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
SECTION=$(normalize_newlines "$PLAN" | awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^## SDLC State/ { flag=1; next }
  /^## / { flag=0 }
  flag')

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

# Task-scale plans address a ledger TASK, not a numbered step:
# `current: T<n>` with evidence on `- T<n>:` lines (no `Step N:` line). Validate
# the ledger (log-only, D12/D14) and allow the commit — the task pointer is
# structurally valid, so a false block here would be a defect (R4.3). A
# `current: T<n>` on a non-task plan is NOT accepted here; it falls through to
# the numeric check below and blocks (T-format is scale: task only).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
if echo "$CURRENT" | grep -qE '^T[0-9]+$' && [ "$SCALE" = "task" ]; then
  validate_task_ledger
  exit 0
fi

if [ -z "$CURRENT" ] || ! echo "$CURRENT" | grep -qE '^[0-9]+[ab]?$'; then
  echo "BLOCKED: canonical-sdlc plan file's '## SDLC State' section is missing a valid 'current: N' line." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: add a line like 'current: 5' (or 'current: 8b') before committing." >&2
  exit 2
fi

# Find the evidence line for the current step: a "Step N:" line, with or
# without a leading list marker.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
LINE=$(echo "$SECTION" \
       | grep -E "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+${CURRENT}[[:space:]]*:" \
       | head -1)

if [ -z "$LINE" ]; then
  echo "BLOCKED: canonical-sdlc plan file has no 'Step ${CURRENT}:' line in '## SDLC State'." >&2
  echo "Plan: $PLAN" >&2
  echo "Fix: add the evidence artifact for step ${CURRENT} before committing." >&2
  exit 2
fi

RAW_VALUE=$(echo "$LINE" | sed -E "s/^[[:space:]]*-?[[:space:]]*Step[[:space:]]+${CURRENT}[[:space:]]*:[[:space:]]*//")

# Multi-line form: when the Step line has no inline content, evidence lives on
# indented continuation lines below. Collect them so the rest of the hook treats
# `Step N:\n  field: value\n  ...` as non-empty evidence.
extract_continuation() {
  local section="$1" step="$2"
  local sline
  sline=$(echo "$section" | grep -nE "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+${step}[[:space:]]*:" | head -1 | cut -d: -f1)
  [ -z "$sline" ] && return
  echo "$section" | awk -v start="$sline" '
    NR > start {
      if ($0 ~ /^[[:space:]]*-?[[:space:]]*Step[[:space:]]+[0-9]+[ab]?[[:space:]]*:/) exit
      if ($0 ~ /^[^[:space:]]/) exit
      if ($0 ~ /^[[:space:]]*$/) next
      print $0
    }
  '
}

CONTINUATION=$(extract_continuation "$SECTION" "$CURRENT")

# Combined block used for empty/placeholder/shape checks.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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

# R7 intent-scoped Step-5 keys (D14 log-only — see validate_intent_evidence
# below). A whole-value match against this exact key name exempts the line from
# the universal placeholder ban; the R7 contract is enforced instead by
# validate_intent_evidence, which logs a finding but never blocks.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
is_r7_key() {
  case "$1" in
    behavior-preservation|compat-matrix|revert-plan|baseline|target|re-measure) return 0 ;;
    *) return 1 ;;
  esac
}

# Placeholder detection. Each line of the block is checked as a whole value:
# the text after the first ':' on a "key: value" continuation line, or the
# whole line when it has no colon (the single-line "Step N: <value>" case,
# which arrives here as RAW_VALUE). ${_bline#*:} yields the after-colon text
# on colon lines and the unchanged line otherwise.
while IFS= read -r _bline; do
  _bkey=$(printf '%s' "$_bline" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*:.*$//')
  if is_r7_key "$_bkey"; then
    continue
  fi
  if is_placeholder_value "${_bline#*:}"; then
    echo "BLOCKED: canonical-sdlc step ${CURRENT} evidence line is a placeholder (\"${BLOCK}\")." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: replace with the actual evidence artifact before committing." >&2
    exit 2
  fi
done <<< "$BLOCK"


# A pointer step records a link/path (not shaped fields); having passed the
# presence + placeholder checks above, it needs no shape check, so allow the
# commit. Step 4 is the exception: when use_worktree=true it carries worktree
# fields and must fall through to the shape check below.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
POINTER_STEPS="1 2 3 4"  # Step 6 must reach dispatch for the matrix prefix check

for _ps in $POINTER_STEPS; do
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

# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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
    echo "Required for step ${CURRENT}: $*" >&2
    echo "Fix: rewrite the Step ${CURRENT} block as multi-line YAML-style fields. See canonical-sdlc/SKILL.md \"Evidence (two tiers)\" → verification shape table." >&2
    exit 2
  fi
}

# ---------- shared per-step validators ----------

# Compose the "canonical-sdlc step <N>" message prefix.
step_prefix() {
  echo "canonical-sdlc step $1"
}

# Tests modality: cmd/pass/total/output present, pass and total integers,
# pass==total. Used by the Step-5 verify gate.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
validate_tests_block() {
  local step="$1" pass total prefix
  shape_block cmd pass total output
  pass=$(block_get pass)
  total=$(block_get total)
  prefix=$(step_prefix "$step")
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

# Document step: adr OR rca OR n/a.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
validate_document_step() {
  local step="$1" prefix
  if ! block_has adr && ! block_has rca && ! block_has_na; then
    prefix=$(step_prefix "$step")
    echo "BLOCKED: ${prefix} evidence requires 'adr: <path>', 'rca: <path>' (incident-response mode), or 'n/a: <reason>'." >&2
    echo "Plan: $PLAN" >&2
    exit 2
  fi
}

# Integrate & close: merge/worktree-removed always; then the cleanup triple,
# OR an explicit `cleanup: n/a` marker (cleanup_on_finish=false).
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
validate_ship_step() {
  local step="$1" prefix
  if block_has_na; then
    if [ -n "$DEPLOY_TARGET" ] && [ "$DEPLOY_TARGET" != "none" ]; then
      prefix=$(step_prefix "$step")
      echo "BLOCKED: ${prefix} 'n/a:' is only valid when deploy_target=none in frontmatter (got deploy_target=${DEPLOY_TARGET})." >&2
      echo "Plan: $PLAN" >&2
      echo "Fix: provide 'deploy:', 'verified-at:', and 'monitor:' fields, or change deploy_target to none." >&2
      exit 2
    fi
  else
    shape_block deploy verified-at monitor
  fi
}

# ---------- pre-registered Verification Matrix ----------
# The Verify gate discharges a Verification Matrix stored in a top-level
# `## Verification Matrix` section of the plan (separate from ## SDLC State).
# validate_matrix parses that section — a per-session stack-health line, a
# tier table (one row per AC), and one indented per-AC evidence block per
# non-waived row — and fires at current: 5 (via the Step-5 validator) and as a
# prefix check for current: 6..9 (via the dispatcher).
#
# Mid-discharge commits: at current: 5, rows with status
# pending/blocked skip the per-tier key check, and the Step-5 `auditor:`
# pointer is required only when no such row remains. The full contract —
# per-tier keys + CONFIRMED on every non-waived row — bites on the 5→6
# advance via the 6..9 prefix check. The status cell is enum-checked
# (pending|blocked|discharged|waived) since the relaxation makes it
# load-bearing.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]

# Per-tier required evidence keys — MIRROR of the canonical table in
# skills/canonical-sdlc/SKILL.md Step 5 ("Per-tier required evidence keys").
# Change THAT table first; this function follows it. (R27)
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
keys_for_tier() {
  case "$1" in
    T0|T1) echo "tier-run readback" ;;
    T2)    echo "tier-run readback fixture-fidelity" ;;
    T3)    echo "tier-run fresh cold-client contact readback" ;;
    T4)    echo "user-confirmed" ;;
  esac
}

# The `## Verification Matrix` section body (newline-normalized, like SECTION at
# the top of the hook — a separate awk pass over the whole plan). Lines inside
# ``` fenced code blocks are dropped so a jq/shell pipeline written in
# leading-pipe continuation style is never mistaken for a table row; every
# downstream matrix parse (rows, stack-health, false-green, AC blocks) reads
# this body, so scoping the fence-skip here covers all of them. Fence state
# is tracked across the whole file so section detection stays fence-aware.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
matrix_section() {
  normalize_newlines "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Verification Matrix/ { f=1; next }
    /^## / { f=0 }
    f'
}

# The indented evidence block under "<AC-id>:" within MATRIX (up to the next
# non-indented line). index()==1 anchors at line start without regex-escaping
# the AC id, so AC-1 never matches the AC-11 block.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
matrix_block() {
  echo "$MATRIX" | awk -v ac="$1:" '
    index($0, ac)==1 {f=1; next}
    /^[^[:space:]]/ {f=0}
    f'
}

# 3-line BLOCKED/Plan/Fix emit for the matrix arm (mirrors the pattern
# every other validator uses). $1 = message tail, $2 = fix line.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
block_matrix() {
  echo "BLOCKED: canonical-sdlc step ${CURRENT} — $1" >&2
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

validate_matrix() {
  local sh rows line ncols ac tier status ev aud block_txt key val

  # Set while any row is still pending/blocked at current: 5. The
  # Step-5 validator reads it to keep the `auditor:` pointer optional
  # mid-walk (the auditor is the exit gate — it has not run yet).
  UNDISCHARGED=0
  MATRIX=$(matrix_section)
  if [ -z "$MATRIX" ]; then
    block_matrix "the Verify gate requires a '## Verification Matrix' section." \
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
  # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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
    # status enum — the status cell is load-bearing (pending/blocked
    # relax the Verify gate; waived relaxes everything), so a typo must
    # block, not silently read as discharged-like.
    # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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
      # A row still being discharged carries no evidence contract at
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
        # matrix_is_placeholder's lowercasing). The tier CELL is not checked
        # here: retyping T3 to T2 is a downgrade this hook does not see.
        # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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
    # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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

# ---------- walk-first artifact arm (epic-14 W1) ----------
# Verification opens with a walk: an agent narrates the real running surface
# without having read the acceptance criteria, and its narration lands in
# <docs-root>/record/ BEFORE any matrix row discharges. Existence is the wall;
# temporal order stays discipline, since no hook can see when the walk happened.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
#
# FAIL-CLOSED (plan assumption A1, user-ratified): frontmatter `walk: exempt`
# makes the arm inert; `walk: required` OR AN ABSENT KEY arms it. An exemption
# is a Step-0 ratification, never something inferred from an omission — so a
# plan that simply never mentions the key meets this arm at its next Step-5
# commit. A value outside the enum also arms it; validating that enum belongs to
# the governing-skill hook (it gates artifact writes), and treating an
# unrecognized value as "exempt" here would hand every typo a bypass.
walk_mode() {
  case "$(frontmatter_get walk)" in
    exempt) echo exempt ;;
    *)      echo required ;;
  esac
}

# The Step-5 evidence block, read at ANY current step. The module-level BLOCK
# holds the CURRENT step's evidence, so at current: 6..9 it is the Step-6..9
# block and cannot answer for the walk; this extractor re-reads Step 5 out of
# SECTION with the same line + continuation grammar the top of the hook uses.
# Empty when the plan carries no Step-5 line at all — which, post-Verify, is
# itself a missing walk artifact.
step5_evidence_block() {
  local line raw cont
  line=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*Step[[:space:]]+5[[:space:]]*:" | head -1)
  [ -n "$line" ] || return 0
  raw=$(echo "$line" | sed -E "s/^[[:space:]]*-?[[:space:]]*Step[[:space:]]+5[[:space:]]*:[[:space:]]*//")
  cont=$(extract_continuation "$SECTION" "5")
  printf '%s\n%s\n' "$raw" "$cont"
}

# Resolve a `walk-artifact:` value to an absolute path. Absolute passes through;
# a `record/...` value is docs-root-relative (the form the Step-5 contract
# names); anything else is project-relative, so the fully-spelled
# `.bionic/docs/record/<file>.md` a plan author is likely to paste also lands in
# the right place. Containment is checked by the caller — this only resolves.
resolve_walk_path() {  # $1 = raw walk-artifact value
  case "$1" in
    /*)       printf '%s\n' "$1" ;;
    record/*) printf '%s/%s\n' "$DOCS_ROOT" "$1" ;;
    *)        printf '%s/%s\n' "$PROJECT_DIR" "$1" ;;
  esac
}

# The arm itself. Fires at current: 5..9 (the Verify gate and, as a durable
# prefix condition — plan assumption A5 — every step after it, so the artifact
# cannot be deleted once Verify is behind you). Trigger: at least one matrix row
# with status `discharged`. Rows that are only pending/blocked leave it silent,
# which is what keeps a mid-discharge corrective commit legal. `waived` is NOT a
# trigger: the spec arms this on discharge, and a wave whose every row is waived
# has verified nothing to narrate.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
validate_walk_artifact() {
  local discharged b5 raw abs
  case "$CURRENT" in 5|6|7|8|9) : ;; *) return 0 ;; esac
  [ "$(walk_mode)" = required ] || return 0
  discharged=$(matrix_section | grep -E '^[[:space:]]*\|' \
    | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}' \
    | grep -cx 'discharged')
  [ "$discharged" -gt 0 ] || return 0

  b5=$(step5_evidence_block)
  raw=$(echo "$b5" | grep -E '^[[:space:]]*walk-artifact[[:space:]]*:' | head -1 \
        | sed -E 's/^[[:space:]]*walk-artifact[[:space:]]*:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
  if [ -z "$raw" ]; then
    block_matrix "the walk gate: matrix rows are discharged but the Step 5 evidence has no 'walk-artifact:' line." \
      "run the walk first and record 'walk-artifact: record/<file>.md' in the Step 5 block. Frontmatter 'walk: exempt' is the only way past this arm, and it is a Step-0 decision."
  fi

  # Containment. A `..` component is refused outright rather than normalized:
  # the artifact belongs in record/, and a path that climbs out of it is a
  # placement error whatever it lands on.
  if echo "$raw" | grep -qE '(^|/)\.\.(/|$)'; then
    block_matrix "the walk gate: walk-artifact '${raw}' climbs out of the record directory and so does not resolve under ${DOCS_ROOT}/record/." \
      "name the walk narration relative to the docs root, e.g. 'walk-artifact: record/<file>.md'."
  fi
  abs=$(resolve_walk_path "$raw")
  case "$abs" in
    "$DOCS_ROOT"/record/*) : ;;
    *)
      block_matrix "the walk gate: walk-artifact '${raw}' does not resolve under ${DOCS_ROOT}/record/ (resolved to ${abs})." \
        "move the walk narration into <docs-root>/record/ and name it there, e.g. 'walk-artifact: record/<file>.md'." ;;
  esac
  if [ ! -f "$abs" ]; then
    block_matrix "the walk gate: walk-artifact '${raw}' is named in the Step 5 evidence but no file exists at ${abs}." \
      "write the walk narration to that path before discharging any matrix row (and do not delete it afterwards — the arm re-checks at every later step)."
  fi

  # The walk narrates a running surface; it never checklists acceptance
  # criteria. An AC identifier in the artifact is the tell that it was written
  # with the criteria in hand, which is exactly the power the walk is meant to
  # have. This grep is the whole enforcement.
  # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
  if grep -qE 'AC-[0-9]' "$abs" 2>/dev/null; then
    block_matrix "the walk gate: walk artifact ${abs} names acceptance criteria (matched 'AC-<n>')." \
      "rewrite the walk as narration of what was driven and what came back, with no AC identifiers — the walk is written without reading the criteria."
  fi
  return 0
}

# Verify gate: tests floor, a required non-empty auditor pointer,
# then the Verification Matrix.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
validate_verify_step() {
  local aud
  validate_tests_block 5
  validate_matrix
  # Walk-first: the narration must already exist once anything has discharged.
  validate_walk_artifact
  # The auditor is the Step-5 exit gate — it cannot have run while
  # rows are still pending/blocked, so the pointer is required only once
  # every row is discharged or waived.
  # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
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

# Epic merge-target consistency (LOG-ONLY; D14, check-id `merge-target`).
# On a wave-scale plan naming an `epic:`, when the epic plan exists and
# declares an `integration-branch:` in its ## SDLC State, a mismatch with this
# plan's integration-branch logs a finding. Never blocks. First cross-file read
# in this hook — read-only, fail-open (missing epic plan / missing key → no
# finding). Fires at the integrate step.
# [INSTRUMENT]
validate_merge_target() {
  local epic epic_plan epic_branch this_branch
  epic=$(frontmatter_get epic)
  [ -n "$epic" ] || return 0
  epic_plan="$DOCS_ROOT/plans/$epic/epic.plan.md"
  [ -r "$epic_plan" ] || return 0
  # Fence-aware (matches the SECTION extraction): an epic plan documenting a
  # `## SDLC State` example in a ``` fence must not shadow its real section.
  # [INSTRUMENT]
  epic_branch=$(normalize_newlines "$epic_plan" \
    | awk '
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^## SDLC State/ { f=1; next }
      /^## / { f=0 }
      f' \
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

# Intent-scoped Step-5 evidence keys (R7) — LOG-ONLY (D14; check-ids
# `refactor-evidence`, `tune-evidence`). Fires on plans whose
# declared intent carries a conditional key set; never blocks. Reuses the
# Step-5 BLOCK/block_has/block_get accessors already populated for the
# current step's evidence (same accessors validate_verify_step uses),
# so this validator is only meaningful when called at current: 5.
# [INSTRUMENT]
validate_intent_evidence() {
  local key val
  case "$INTENT" in
    refactor)
      if ! block_has behavior-preservation || [ -z "$(block_get behavior-preservation)" ] \
         || is_placeholder_value "$(block_get behavior-preservation)"; then
        log_finding refactor-evidence "refactor plan Step 5 missing 'behavior-preservation:' evidence"
      fi
      for key in compat-matrix revert-plan; do
        if block_has "$key"; then
          val=$(block_get "$key")
          if [ -z "$val" ] || is_placeholder_value "$val"; then
            log_finding refactor-evidence "refactor plan Step 5 '${key}:' present but empty"
          fi
        fi
      done
      ;;
    tune)
      for key in baseline target re-measure; do
        val=$(block_get "$key")
        if ! block_has "$key" || [ -z "$val" ] || is_placeholder_value "$val"; then
          log_finding tune-evidence "tune plan Step 5 missing '${key}:' evidence"
        fi
      done
      ;;
  esac
  return 0
}

# Wave-scale D7 dispatched-task ledger PRESENCE (D-slice 4/3). Guarded to
# scale:wave + frontmatter rigor:audited + multi_agent:true plans; for
# every other plan it is a no-op (return 0). scale:epic is intentionally OUT —
# epic plans legitimately dispatch research, not task-shaped units, so demanding
# a dispatched-task ledger there would false-block scoping runs (plan Assumption
# A8). Called from dispatch_modern, so it runs at EVERY step that reaches the
# dispatcher (plan Assumption A5): the ledger is commit-time bookkeeping (D7:
# ledger before marking complete), demanded from the first gated commit.
#
# TESTED-FLOOR SHAPE ONLY (plan Assumption A2): the wave's own Step-5 auditor /
# Step-6 critic are the assurance roles at wave scale, so per-row auditor/critic
# tokens (task-scale machinery) are NOT demanded here.
#   1. `## Tasks` section ABSENT -> exit 2 (empty is fine, absent is not — the
#      audited multi_agent wave must carry its dispatched-task ledger home).
#   2. ZERO data rows -> SATISFIED (a human `none dispatched` prose line is
#      documentation, not required by the parser). return 0.
#   3. Each data row: status (field 6) in {pending,active,done,dropped} else
#      exit 2; a non-placeholder `- T<n>:` evidence line must exist in the
#      ## SDLC State section (SECTION) else exit 2.
# [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
validate_dispatch_ledger() {
  [ "$SCALE" = "wave" ] || return 0
  [ "$RIGOR" = "audited" ] || return 0
  [ "$MULTI_AGENT" = "true" ] || return 0

  local tasks rows line id status ev
  # Fence-aware `## Tasks` extraction — same awk extractor as validate_task_ledger.
  tasks=$(normalize_newlines "$PLAN" | awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^## Tasks/ { f=1; next }
    /^## / { f=0 }
    f')
  if [ -z "$tasks" ]; then
    echo "BLOCKED: canonical-sdlc audited multi_agent wave plan has no '## Tasks' dispatched-task ledger section." >&2
    echo "Plan: $PLAN" >&2
    echo "Fix: add a '## Tasks' section (a header plus a 'none dispatched' line is fine); the orchestrator appends one row per dispatched task-shaped unit (D7)." >&2
    exit 2
  fi
  rows=$(echo "$tasks" | grep -E '^[[:space:]]*\|[[:space:]]*T[0-9]+')
  [ -n "$rows" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id=$(echo "$line"     | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    status=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$6); print $6}')
    # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
    case "$status" in
      pending|active|done|dropped) : ;;
      *)
        echo "BLOCKED: canonical-sdlc dispatched task ${id} has invalid status '${status:-empty}' (want pending|active|done|dropped)." >&2
        echo "Plan: $PLAN" >&2
        echo "Fix: set the '${id}' row's status cell to one of pending|active|done|dropped before committing." >&2
        exit 2
        ;;
    esac
    # Evidence line in ## SDLC State (anchored, same lookup as task scale).
    # [WALL: hooks/canonical-sdlc-evidence-gate.test.sh]
    ev=$(echo "$SECTION" | grep -E "^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:" | head -1 \
         | sed -E "s/^[[:space:]]*-?[[:space:]]*${id}[[:space:]]*:[[:space:]]*//" | sed -E 's/[[:space:]]+$//')
    if [ -z "$ev" ]; then
      echo "BLOCKED: canonical-sdlc dispatched task ${id} has no '- ${id}:' evidence line in '## SDLC State'." >&2
      echo "Plan: $PLAN" >&2
      echo "Fix: record the dispatched unit's evidence artifact on a '- ${id}:' line before committing." >&2
      exit 2
    fi
    if is_placeholder_value "$ev"; then
      echo "BLOCKED: canonical-sdlc dispatched task ${id} evidence line is a placeholder ('${ev}')." >&2
      echo "Plan: $PLAN" >&2
      echo "Fix: replace the '- ${id}:' placeholder with the actual evidence artifact before committing." >&2
      exit 2
    fi
  done <<< "$rows"
  return 0
}

# Step numbering: 4 worktree · 5 Verify gate · 7 Document · 8 Integrate &
# close · 9 Ship. Steps 1/2/3/6 are pointer steps handled upstream, except
# that Step 6 reaches here so the matrix prefix check can fire.
INTEGRATE_STEP=8
SHIP_STEP=9

dispatch() {
  # Audited multi_agent wave: D7 dispatched-task ledger PRESENCE, at every step
  # that reaches this dispatcher (guarded internally; no-op otherwise).
  validate_dispatch_ledger
  # The Verification Matrix is a prefix contract for every step from the Verify
  # gate on — current: 5 validates it inside validate_verify_step; current: 6..9
  # validate it here, so a REFUTED auditor blocks post-Verify commits too.
  # The walk artifact is a durable prefix condition alongside it (A5): deleting
  # the narration after the Verify gate blocks every later commit.
  case "$CURRENT" in
    6|7|8|9) validate_matrix; validate_walk_artifact ;;
  esac
  # Log-only epic merge-target check at the integrate step.
  [ "$CURRENT" = "$INTEGRATE_STEP" ] && validate_merge_target
  case "$CURRENT" in
    4) shape_block worktree base-sha branch ;;
    5)
      validate_verify_step
      validate_intent_evidence
      ;;
    7) validate_document_step 7 ;;
    *)
      if [ "$CURRENT" = "$INTEGRATE_STEP" ]; then
        validate_integrate_step
      elif [ "$CURRENT" = "$SHIP_STEP" ]; then
        validate_ship_step "$SHIP_STEP"
      fi
      ;;
  esac
}

dispatch
exit 0
