#!/bin/bash
# GOVERNING-SKILL GATE: Blocks Write and Edit to canonical-sdlc artifact
# files that lack the required governing-skill frontmatter.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
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
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
#   ---
#   governing-skill: superpowers:writing-plans
#   sdlc-step: 3
#   epic: epic-02-checkout
#   wave: wave-01-checkout-refactor
#   canonical_sdlc_version: 13
#   intent: build
#   rigor: audited
#   scale: wave
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
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
# Match files under the project's docs root (default <project>/.bionic/
# docs/, configurable via <project>/.bionic/config.yaml `docs-root:`).
#
# Strategy: the project root is COMPUTED from git, never DISCOVERED by
# walking for an existing `.bionic/`. From that root, resolve docs-root and
# check whether FILE_PATH lives under <docs-root>/{specs,plans,adrs,incidents}/.
#
# `git rev-parse --git-common-dir` names the MAIN repository's .git even from
# inside a linked worktree (`--git-dir` would name the worktree's private
# dir), so every worktree of one repo resolves to ONE root and therefore one
# `.bionic/` tree.
#
# `--path-format=absolute` is load-bearing, not cosmetic: the bare form
# returns a RELATIVE path (`.git` at the root, `../.git` one level down),
# whose dirname is `.` or `..` — a cwd-dependent string, not a root. It landed
# in git 2.31.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# OLD-GIT FALLBACK (Step-6 finding K2). On git < 2.31 `--path-format` is an
# unknown option and rev-parse exits 129 — which the single-branch predecessor
# could not tell apart from "not a repository", so the root silently became the
# session's cwd and EVERY canonical-sdlc artifact write on such a machine
# blocked as misplaced, pointing the author at whatever directory the session
# started in. Fail-closed in the wrong direction, and wave-introduced: the
# walk-up predecessor worked on every git version. Plan assumption 6 claimed a
# `cd`-and-`pwd` fallback already covered this; it did not exist. A documented
# mitigation that was never built is worse than an unlogged one — it reads as
# retired, and a reviewer who checks the local git version moves on.
#
# So: retry the BARE form, which every git has, and absolutize its answer here.
# It answers RELATIVE inside the main repo and ABSOLUTE from a linked worktree,
# hence the `case`. Only when BOTH forms fail is this genuinely not a
# repository, and the supplied fallback wins as before.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# `git -C` needs a directory that EXISTS, and this is a PreToolUse gate: on
# the first artifact write into a project the target's parent directories have
# not been created yet. Climbing to the nearest existing ancestor supplies git
# a valid cwd — it is not a search for `.bionic/`; the loop's condition never
# mentions it, and the answer still comes from git.
#
# The walk-up-for-`.bionic/` predecessor could not resolve a root in a project
# where `.bionic/` did not already exist, and resolved a linked worktree to
# the worktree instead of its parent repo.
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
  # NO-GIT FALLBACK: the pin follows the TARGET, never the shell. Outside any
  # repository, walk up from the nearest existing ancestor of the target for
  # the nearest directory already carrying a `.bionic/` tree and answer there;
  # only when none exists does the supplied fallback (default pwd) win — which
  # preserves the first-write-into-a-fresh-project path and changes nothing
  # inside a git repository, where the arms above always answer first.
  root="$d"
  while [ -n "$root" ] && [ "$root" != "/" ] && [ "$root" != "." ]; do
    if [ -d "$root/.bionic" ]; then
      printf '%s\n' "$root"
      return
    fi
    root=$(dirname "$root")
  done
  printf '%s\n' "${2:-$(pwd)}"
}

# Resolve a path's ancestors to their physical form, keeping any tail that does
# not exist yet. `git` answers with the PHYSICAL root, while FILE_PATH arrives
# from the tool as whatever path the session used — if the project is reached
# through a symlink the two disagree on prefix and every path comparison below
# misfires. This function is the fix, and the severity is why it could not be
# deferred: under the old pass-through the mismatch was a silent bypass
# (artifacts quietly stopped being gated), but once misplacement BLOCKS, the
# same mismatch inverts into the worse failure — a correctly placed artifact
# false-BLOCKED. Fail-closed turns a hole into a wall in front of legitimate
# work, so closing the hole and resolving symlinks had to land together.
#
# Not exotic on macOS, where /tmp and /var are themselves symlinks.
#
# `pwd -P` needs a directory that EXISTS, and this is a PreToolUse gate, so the
# climb mirrors resolve_project_root's: walk up to the nearest existing
# ancestor, physicalize that, re-attach the tail. Fail-open — an unresolvable
# path is returned unchanged.
# FOLD `.` AND `..` LEXICALLY FIRST, before the filesystem is consulted at all — cs review
# S-2, epic-16 w2 Step-6 remediation R4. The climb below resolves only the EXISTING ancestor
# prefix, so a component that does not exist yet strands everything after it, `..` segments
# included, as an unresolved literal: `<pinned>/.bionic/nonexistent/../../../other/.bionic/
# docs/record/x.md` kept its climb un-folded, the pinned-root comparison found the harmless
# `.bionic` at the front of that string, and the write landed OUTSIDE the repository. The
# Write tool creates parent directories, so the non-existent segment was never an obstacle
# to the write — only to the wall seeing where it was going.
#
# The loop is hooks/dispatch-preflight.sh resolve_in_repo()'s, which already folds this way
# before comparing a deliverable path against the repo, and whose `set -f` guard is
# load-bearing here too: a `*` inside a tool-supplied path is a character, never a glob.
# Two walls in one wave had disagreed about how to resolve a path, and this is the weaker
# one adopting the stronger one.
#
# A LEXICAL fold, deliberately, not realpath: `<symlink>/..` folds to the symlink's parent
# rather than to its target's parent. Same reading resolve_in_repo takes, and for a wall
# whose question is "which tree does this path NAME" it is the right one.
fold_dots() {  # $1=path → `.` and `..` folded lexically, absolute
  local p="$1" abs out part had_f
  case "$p" in
    /*) abs="$p" ;;
    *)  abs="$(pwd)/$p" ;;
  esac
  case "$-" in *f*) had_f=1 ;; *) had_f=0 ;; esac
  set -f
  out=""
  local IFS=/
  for part in $abs; do
    case "$part" in
      ''|.) ;;
      ..)   out="${out%/*}" ;;
      *)    out="$out/$part" ;;
    esac
  done
  unset IFS
  [ "$had_f" -eq 1 ] || set +f
  printf '%s\n' "${out:-/}"
}

physicalize() {  # $1=absolute path (need not exist) → folded, ancestors resolved
  local d rest p folded
  folded=$(fold_dots "$1")
  d=$(dirname "$folded")
  rest=$(basename "$folded")
  while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ] && [ -n "$d" ]; do
    rest="$(basename "$d")/$rest"
    d=$(dirname "$d")
  done
  if p=$(cd "$d" 2>/dev/null && pwd -P); then
    printf '%s/%s\n' "${p%/}" "$rest"
  else
    # Fail-open on an unresolvable path, but never back to the UNFOLDED spelling: the fold
    # is what the comparisons below are entitled to, and handing back the raw climb is the
    # bypass this function just closed.
    printf '%s\n' "$folded"
  fi
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

PROJECT_ROOT_FROM_PATH=$(resolve_project_root "$FILE_PATH" || true)
if [ -z "$PROJECT_ROOT_FROM_PATH" ]; then
  # No root at all — resolve_project_root falls back to pwd, so this is
  # reachable only if pwd itself is empty. Kept as a defensive guard against a
  # future resolver change; it is not the misplacement fail-open, which is
  # closed below by the UNDER_DOCS_ROOT verdict.
  exit 0
fi
DOCS_ROOT=$(resolve_docs_root "$PROJECT_ROOT_FROM_PATH")

# Incident 0001: the audit stream must live where a consuming project cannot
# commit it, regardless of that project's .gitignore. $HOME-rooted, per-project,
# durable — the same $HOME/.claude/ audit path the archived epic-10 poker used
# (that work is recoverable at tag archive/epic-10-never-die).
# Slug = <basename>-<cksum of the absolute path>: readable, deterministic, and
# collision-resistant across same-named projects under different parents.
# cksum and basename are POSIX — no new dependency.
# Byte-identical to the copies in farm-out-reminder.sh,
# canonical-sdlc-evidence-gate.sh and context-spend.sh — divergence would give
# one project two audit files. Deliberate per-hook duplication (no shared lib).
# [INSTRUMENT]
audit_path() {  # $1=project root → absolute audit-file path; rc 1 if no $HOME
  [ -n "${HOME:-}" ] || return 1
  local base sum
  base=$(basename "$1" | sed 's/[^A-Za-z0-9._-]/-/g')
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s/.claude/logs/%s-%s/sdlc-audit.md' "$HOME" "$base" "$sum"
}

BASENAME=$(basename "$FILE_PATH")
ENFORCE=0
case "$BASENAME" in
  *.plan.md|*.spec.md|continuation*.md) ENFORCE=1 ;;
  adr-*.md) ENFORCE=1 ;;
esac

# ---------- AC-13: misplacement blocks; absence never does ----------
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# Two facts about the target path, kept separate because they answer different
# questions:
#   IN_SCOPE        — inside one of the four enforced subdirectories, so the
#                     full frontmatter contract applies.
#   UNDER_DOCS_ROOT — inside the docs root at all, so the file is PLACED.
#
# The fail-open this closes: an artifact declaring canonical-sdlc frontmatter
# but living outside the docs root used to fall straight out of the scope check
# and exit 0 — written, ungated, in the wrong place. Slice 1's
# resolve_project_root() always answers, so the historical no-root `exit 0` is
# unreachable; the scope check is the fail-open that survived.
#
# ABSENCE is not misplacement. DOCS_ROOT is COMPUTED, so a brand-new project
# with no `.bionic/` still has one, and its first artifact write targets it and
# passes. Nothing here blocks on `.bionic/` being missing — only on a file that
# names itself a canonical-sdlc artifact while sitting somewhere else.
#
# "Placed" means the whole docs root, not just the four subdirectories:
# `<docs-root>/spikes/` and `<docs-root>/record/` hold real files carrying this
# frontmatter. They pass through unenforced, exactly as they did before.
# Both sides physicalized before comparing, or a symlinked project path makes
# every verdict below wrong. FILE_PATH itself is left alone — it is what the
# messages quote back, and quoting a path the user never typed is its own
# confusion.
FILE_PATH_MATCH=$(physicalize "$FILE_PATH")
DOCS_ROOT_MATCH=$(physicalize "$DOCS_ROOT")

# ---------- R9/AC-13: pinned-root wall ----------
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# The `.bionic` tree is pinned to ONE physical location per project:
# PROJECT_ROOT_FROM_PATH already resolves there via --git-common-dir,
# unaffected by which worktree or subdirectory the write's own path happens
# to sit under (AC-10). What that resolution does NOT already guarantee is
# that the WRITE ITSELF lands there: the target path can carry its own
# `.bionic` path segment that names a different tree entirely — a linked
# worktree's phantom copy, or a stray `.bionic` created a level down inside a
# subdirectory of the main repo — even though the computed root is correct.
# PINNED_BIONIC is the one true tree; TARGET_BIONIC is whichever `.bionic`
# segment (if any) the write's own path names. Scope: this project's single
# pinned root (spec assumption 4) — a multi-project session is out of scope
# by design, not by omission.
#
# THE DEEPEST `.bionic` SEGMENT IS THE TARGET, not the first one (`%` and not `%%` —
# shortest suffix removed, so the prefix kept is the longest). cs review S-2, case C: a
# path naming a second `.bionic` INSIDE the pinned tree —
# `<pinned>/.bionic/tmp/scratch/.bionic/docs/record/x.md` — compared equal to the pinned
# root under the first-match reading and passed. R4 rules that in scope: it is the same
# phantom tree this wall already refuses one directory over (a stray `.bionic` a level
# down inside `subdir/`), and the tree the write actually lands in is the deepest one its
# own path names. The cost of the stricter reading is that a genuinely intended nested
# `.bionic` is blocked with a message naming where to write instead.
PINNED_BIONIC="$PROJECT_ROOT_FROM_PATH/.bionic"
case "$FILE_PATH_MATCH" in
  */.bionic/*) TARGET_BIONIC="${FILE_PATH_MATCH%/.bionic/*}/.bionic" ;;
  */.bionic)   TARGET_BIONIC="$FILE_PATH_MATCH" ;;
  *)           TARGET_BIONIC="" ;;
esac

IN_SCOPE=0
case "$FILE_PATH_MATCH" in
  "$DOCS_ROOT_MATCH"/specs/*|"$DOCS_ROOT_MATCH"/plans/*|"$DOCS_ROOT_MATCH"/adrs/*|"$DOCS_ROOT_MATCH"/incidents/*) IN_SCOPE=1 ;;
esac
UNDER_DOCS_ROOT=0
case "$FILE_PATH_MATCH" in
  "$DOCS_ROOT_MATCH"/*) UNDER_DOCS_ROOT=1 ;;
esac

# Placed, and either not in an enforced subdirectory or not an enforced name:
# nothing to check and no content to read.
if [ "$UNDER_DOCS_ROOT" -eq 1 ] && { [ "$IN_SCOPE" -eq 0 ] || [ "$ENFORCE" -eq 0 ]; }; then
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
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
CONTENT=""
if [ "$TOOL" = "Write" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
else
  if [ -f "$FILE_PATH" ]; then
    if [ "$IN_SCOPE" -eq 1 ]; then
      CONTENT=$(cat "$FILE_PATH")
    else
      # Misplacement probe only. This path is reached on EVERY Edit anywhere
      # in the project, and all it inspects is the leading frontmatter block —
      # so read a head, not the whole file. 8 KB is two orders of magnitude
      # more than any frontmatter block; a truncated read can only fail to
      # find the closing `---`, which makes the probe print more, never less.
      CONTENT=$(head -c 8192 "$FILE_PATH")
    fi
  fi
fi

# Normalize line endings to plain \n before any parsing. Strip a trailing
# \r from each record (CRLF: \r\n → \n) and translate any remaining lone \r
# (classic-Mac CR-only: \r without \n) into a real newline. Every parse below
# is line-anchored (the exact-match `$0 == "---"` frontmatter delimiter,
# yaml_get, the matrix grep), so it must see real newlines.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# `tr -d '\r'` (the prior normalization) merely DELETED every \r. On a CRLF
# artifact that happened to work, but on a CR-only artifact it removed every
# line break, collapsing the whole file to ONE line — the frontmatter parser
# then never matched and a VALID artifact was false-BLOCKed as "missing a YAML
# frontmatter block". awk splits on \n by default, so a CR-only file arrives as
# a single record that gsub re-splits into real lines; LF and CRLF files are
# unaffected. Twin of the evidence-gate hook's normalize_newlines.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
CONTENT=$(printf '%s' "$CONTENT" | awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }')

# Extract the leading YAML frontmatter block (between the first two `---`
# lines at column 0). If absent, block.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
FRONTMATTER=$(echo "$CONTENT" | awk '
  NR == 1 && $0 == "---" { inside = 1; next }
  inside && $0 == "---" { exit }
  inside { print }
')

# The misplacement verdict, now that the frontmatter is in hand.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# Reading the LEADING block (and only the leading block) is what keeps a
# documentation page that shows the frontmatter inside a fence from being
# mistaken for an artifact — the fenced example is never at line 1. That trap
# is a recorded recurrence in this repo, not a hypothetical.
#
# Either self-declaration identifies the artifact: `canonical_sdlc_version` is
# the run-state marker the lifecycle stamps, and `governing-skill:
# canonical-sdlc` is what the skill's own Step-0 artifact carries. A file
# carrying neither is not a canonical-sdlc artifact and is none of this hook's
# business, wherever it lives — which is why an ordinary file in an ordinary
# project, in a project with no `.bionic/` at all, passes untouched.
if [ "$UNDER_DOCS_ROOT" -eq 0 ]; then
  if echo "$FRONTMATTER" | grep -qE '^[[:space:]]*(canonical_sdlc_version[[:space:]]*:|governing-skill[[:space:]]*:[[:space:]]*canonical-sdlc[[:space:]]*$)'; then
    case "$BASENAME" in
      *.spec.md) MISPLACED_SUBDIR=specs ;;
      adr-*.md)  MISPLACED_SUBDIR=adrs ;;
      *)         MISPLACED_SUBDIR=plans ;;
    esac
    echo "BLOCKED: canonical-sdlc artifact '$BASENAME' is misplaced." >&2
    echo "Path: $FILE_PATH" >&2
    echo "It declares canonical-sdlc frontmatter but does not live under this project's docs root." >&2
    echo "Docs root: $DOCS_ROOT" >&2
    echo "Fix: write it under $DOCS_ROOT/$MISPLACED_SUBDIR/ instead." >&2
    echo "     (the docs root is <project>/.bionic/docs by default; override with 'docs-root:' in $PROJECT_ROOT_FROM_PATH/.bionic/config.yaml)" >&2
    exit 2
  fi
  # R9/AC-13: the frontmatter arm above only catches artifacts that
  # self-declare canonical-sdlc frontmatter. An operational artifact (a
  # record/ note, a progress file, anything without that frontmatter)
  # written under a NON-pinned `.bionic` tree would otherwise fall straight
  # through here unblocked — the exact gap this wall closes. A write whose
  # own path carries no `.bionic` segment at all (an ordinary project file)
  # is untouched: TARGET_BIONIC is empty and this arm is silent.
  # [WALL: tests/canonical-sdlc-governing-skill.test.sh]
  if [ -n "$TARGET_BIONIC" ] && [ "$TARGET_BIONIC" != "$PINNED_BIONIC" ]; then
    echo "BLOCKED: artifact write targets '$TARGET_BIONIC', not this project's pinned .bionic root." >&2
    echo "Path: $FILE_PATH" >&2
    echo "Pinned root: $PINNED_BIONIC" >&2
    echo "Fix: write under $PINNED_BIONIC instead — the .bionic tree is pinned to the main repository root at Step 0 and is never re-derived from a worktree or subdirectory copy." >&2
    exit 2
  fi
  exit 0
fi

if [ -z "$CONTENT" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' has no content to validate." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: use Write to create the artifact with governing-skill frontmatter." >&2
  exit 2
fi

if [ -z "$FRONTMATTER" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' is missing a YAML frontmatter block." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: prepend:" >&2
  echo "  ---" >&2
  echo "  governing-skill: <skill-id for the step that produced this artifact>" >&2
  echo "  sdlc-step: <step number>" >&2
  echo "  epic: epic-NN-<slug>" >&2
  echo "  wave: wave-NN-<slug>   # omit for epic-level and continuation" >&2
  echo "  canonical_sdlc_version: 13" >&2
  echo "  intent: <build|bugfix|refactor|tune|spike|incident-response>" >&2
  echo "  rigor: <tested|peer-reviewed|audited>" >&2
  echo "  scale: <task|wave|epic>" >&2
  echo "  ---" >&2
  exit 2
fi

# Enforce presence of the governing-skill field with a non-empty value.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
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

# ---------- canonical-sdlc schema enforcement ----------
#
# Discriminator: `canonical_sdlc_version`, NOT `governing-skill`.
# `governing-skill:` records the per-step skill that wrote a given
# artifact — plans correctly declare `superpowers:writing-plans` because
# Step 3 delegates to that skill. We instead read
# `canonical_sdlc_version`, which Step 0 stamps on every canonical-sdlc
# artifact and is therefore the correct run marker.

yaml_get() {
  echo "$FRONTMATTER" \
    | grep -E "^[[:space:]]*${1}[[:space:]]*:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${1}[[:space:]]*:[[:space:]]*//" \
    | sed -E 's/[[:space:]]+$//'
}

SDLC_VERSION=$(yaml_get canonical_sdlc_version)

# ONE supported version. Anything else — an older number, a typo, an empty
# value, garbage — blocks. There is no version dispatch below this line and
# no path that reaches `exit 0` without passing the whole contract.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
SUPPORTED_SDLC_VERSION=13

if [ "$SDLC_VERSION" != "$SUPPORTED_SDLC_VERSION" ]; then
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME' declares canonical_sdlc_version: '$SDLC_VERSION'." >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: set 'canonical_sdlc_version: ${SUPPORTED_SDLC_VERSION}' — the only supported version." >&2
  exit 2
fi

# ---------- intent × rigor × scale triple + universal contract ----------
#
# Governance keys off the triple (intent × rigor × scale). Presence +
# whole-value enum validation is blocking; CONTENT is already CR-stripped
# (line 143), so whole-line yaml_get reads compare cleanly under CRLF too.
# The triple's presence is the gate — there is no separate mode axis.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
block() {
  echo "BLOCKED: canonical-sdlc artifact '$BASENAME': $1" >&2
  echo "Path: $FILE_PATH" >&2
  exit 2
}

# Split-brain guard: an artifact declares the triple, never mode.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
[ -z "$(yaml_get mode)" ] || block "artifacts declare intent:/rigor:/scale:, never mode:"
INTENT=$(yaml_get intent); RIGOR=$(yaml_get rigor); SCALE=$(yaml_get scale)
[ -n "$INTENT" ] || block "requires intent: (build|bugfix|refactor|tune|spike|incident-response)"
[ -n "$RIGOR" ]  || block "requires rigor: (tested|peer-reviewed|audited)"
[ -n "$SCALE" ]  || block "requires scale: (task|wave|epic)"
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

# ---------- walk: enum (epic-14 AC-3) ----------
#
# `walk:` is optional at THIS hook — an absent key is not this hook's
# concern; the evidence-gate hook fail-closes on absence at Step 5 (A1/A7,
# epic-14-verification-power wave-01 plan). When present, only the literal
# values `required` and `exempt` are legal — anything else (typo, other
# value) blocks, naming both legal values.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
WALK=$(yaml_get walk)
if [ -n "$WALK" ]; then
  case "$WALK" in
    required|exempt) ;;
    *) block "invalid walk: '$WALK' — allowed: required|exempt" ;;
  esac
fi

# ---------- floor-consistency checks (LOG-ONLY; D14, spec R3) ----------
#
# Past the blocking gates above INTENT/RIGOR/SCALE are valid enums. These
# checks compute derivable rigor floors and record a finding when the
# declared rigor violates one. Findings NEVER block: each appends one line
# to $HOME/.claude/logs/<project-slug>/sdlc-audit.md — outside every
# consuming project tree (incident 0001) — AND echoes to stderr, then
# returns 0. Promotion to blocking is a separate later decision made from
# this data. Every read path (config.yaml, epic plan, audit file) is
# fail-open. The evidence-gate hook carries a twin of log_finding (hook
# name differs); a shared hooks-lib extraction is deliberately deferred.
# [INSTRUMENT]
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
  echo "canonical-sdlc [$1]: $2" >&2
  return 0
}

# rigor-override: <user> <date> derived=<v> chosen=<v> (epic-14 AC-10/AC-11).
# Only PRESENCE of the key is detected — the fields are never validated,
# matching the existing waiver-token precedent. When present, a
# floor-violation finding logs "user-overridden" instead of the violation
# detail; the write still succeeds either way (log-only never blocks). This
# does NOT cover the "invalid rigor-floor value in config.yaml" finding below
# — that is a data-quality problem in the floor itself, not a user choosing a
# rigor below a valid floor, so the marker does not suppress it.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
RIGOR_OVERRIDE=$(yaml_get rigor-override)
log_floor_finding() {  # $1=check-id $2=violation-detail
  if [ -n "$RIGOR_OVERRIDE" ]; then
    log_finding "$1" "user-overridden"
  else
    log_finding "$1" "$2"
  fi
}

RR=$(rigor_rank "$RIGOR")
# Intent floor / spike cap (derivable from intent + rigor).
[ "$INTENT" = "incident-response" ] && [ "$RR" -lt 2 ] \
  && log_floor_finding intent-floor "incident-response floors at audited, declared $RIGOR"
[ "$INTENT" = "spike" ] && [ "$RR" -gt 0 ] \
  && log_floor_finding spike-cap "spike is capped at tested, declared $RIGOR"

# Project floor: rigor-floor: in <project>/.bionic/config.yaml (fail-open;
# an unparseable/invalid value is its own finding, never a block).
# [INSTRUMENT]
PF=$(grep -E '^rigor-floor:' "$PROJECT_ROOT_FROM_PATH/.bionic/config.yaml" 2>/dev/null \
  | head -1 | sed 's/^rigor-floor:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
if [ -n "$PF" ]; then
  PR=$(rigor_rank "$PF")
  if [ "$PR" -lt 0 ]; then
    log_finding project-floor "invalid rigor-floor value '$PF' in config.yaml"
  elif [ "$RR" -lt "$PR" ]; then
    log_floor_finding project-floor "project floor $PF, declared $RIGOR"
  fi
fi

# Epic floor: rigor-floor: in the epic plan's frontmatter (read-only,
# fail-open; missing/unreadable epic plan or missing key → no finding,
# floors are opt-in).
EPIC=$(yaml_get epic)
if [ -n "$EPIC" ] && [ -r "$DOCS_ROOT/plans/$EPIC/epic.plan.md" ]; then
  EF=$(awk '/^---$/{n++;next} n==1' "$DOCS_ROOT/plans/$EPIC/epic.plan.md" \
    | grep -E '^rigor-floor:' | head -1 | sed 's/^rigor-floor:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
  if [ -n "$EF" ]; then
    ER=$(rigor_rank "$EF")
    [ "$ER" -ge 0 ] && [ "$RR" -lt "$ER" ] \
      && log_floor_finding epic-floor "epic floor $EF (from $EPIC), declared $RIGOR"
  fi
fi

# ---------- required frontmatter flags + model_plan ----------
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
REQUIRED_OPT_IN=("cleanup_on_finish" "use_worktree")
REQUIRED_DISCRIMINATORS=("surface_type" "language" "has_ui" "multi_agent" "deploy_target")

MISSING=()
for flag in "${REQUIRED_OPT_IN[@]}" "${REQUIRED_DISCRIMINATORS[@]}"; do
  if ! echo "$FRONTMATTER" | grep -qE "^[[:space:]]*${flag}[[:space:]]*:"; then
    MISSING+=("$flag")
  fi
done

# `model_plan` (the Step-0 model-tier decision) is checked as a separate
# conditional grep — NOT an array element — to stay safe under `set -u` with
# bash 3.2's empty-array expansion behaviour.
if ! echo "$FRONTMATTER" | grep -qE "^[[:space:]]*model_plan[[:space:]]*:"; then
  MISSING+=("model_plan")
fi

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "BLOCKED: canonical-sdlc plan '$BASENAME' is missing required frontmatter flags: ${MISSING[*]}" >&2
  echo "Path: $FILE_PATH" >&2
  echo "Fix: run Step 0 (Configure) to set these explicitly. See SKILL.md §Step 0." >&2
  echo "Required opt-in flags:        ${REQUIRED_OPT_IN[*]}" >&2
  echo "Required discriminator flags: ${REQUIRED_DISCRIMINATORS[*]}" >&2
  echo "Required:                     model_plan" >&2
  exit 2
fi

# ---------- pre-registered Verification Matrix required at Step 3+ ----------
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# Step 0 derives a "## Verification Matrix" section (per-AC tier + status +
# evidence, locked at Step 3 approval — see canonical-sdlc SKILL.md's
# "Verification Matrix" sub-step under Step 0). This hook checks section
# PRESENCE only (structure, not substance); the evidence-gate hook validates
# the per-row per-tier fields and the CONFIRMED/waived auditor discipline
# (structure vs substance split mirrors the model_plan / flag checks above).
#
# Scope: basename *.plan.md, sdlc-step >= 3 (numeric). Specs,
# continuation*.md and scale: task plans (they carry a ## Tasks ledger, not a
# matrix) are out of scope — the matrix is a wave/epic plan-body artifact
# that exists starting at Step 3 (Plan) approval.
case "$BASENAME" in
  *.plan.md)
    SDLC_STEP=$(yaml_get sdlc-step)
    case "$SDLC_STEP" in
      ''|*[!0-9]*) ;;  # non-numeric or empty sdlc-step → not in scope
      *)
        if [ "$SDLC_STEP" -ge 3 ] 2>/dev/null && [ "$SCALE" != "task" ]; then
          if ! echo "$CONTENT" | grep -qE '^## Verification Matrix'; then
            echo "BLOCKED: canonical-sdlc plan '$BASENAME' (sdlc-step ${SDLC_STEP}) is missing a '## Verification Matrix' section." >&2
            echo "Path: $FILE_PATH" >&2
            echo "Fix: derive the matrix at Step 0 (see SKILL.md §Step 0 'the Verification Matrix') and lock it at Step 3 approval." >&2
            exit 2
          fi
        fi
        ;;
    esac
    ;;
esac

# ---------- design wall: the three-way rule (wave-02 AC-2/AC-3/AC-4) ----------
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# A wave-or-epic-scale SPEC blocks unless it carries one of three things: a
# flush-left `## Design` section in place; a frontmatter `design:` pointer that
# resolves to a real file carrying one; or a `design-waived:` token. Design is
# the back half of Step 2, and this is the wall that makes it load-bearing.
# The arms are not interchangeable in the order they are tried — see the
# PRECEDENCE note at the branch chain below.
#
# PRESENCE AND RESOLUTION ONLY. The hook never inspects the section's five
# parts — an empty `## Design` passes here and fails at the Step-3 approval,
# which is where a human ratifies design + plan + matrix together. Quality is
# not a hook's job (spec §Design, assumption 4).
#
# Scope is `*.spec.md` at scale wave|epic. Task scale is deliberately untouched
# (R5: a task gets a design paragraph in its session plan, prose-obliged and
# reviewer-checked, never a wall), and plans are untouched because the design
# lives in the spec. Keying on BASENAME rather than on the `specs/` directory
# follows the matrix gate immediately above: a spec artifact is a spec artifact
# wherever under the docs root it was filed, and the alternative leaves a
# rename-free dodge.
#
# WRITE ONLY. On Edit, CONTENT is the file's PRE-edit body, so an Edit arm
# would answer a question nobody asked — it would pass an edit that strips the
# section and block every edit to the pre-W2 specs that predate the rule. The
# post-edit hole is the hook's existing, documented Edit weakness (see the
# CONTENT block above); this arm does not widen it and does not pretend to
# close it.
case "$BASENAME" in
  *.spec.md)
    if [ "$TOOL" = "Write" ] && { [ "$SCALE" = "wave" ] || [ "$SCALE" = "epic" ]; }; then

      # Resolution follows the evidence-gate hook's walk-artifact template
      # (resolve_walk_path): absolute stands, a docs-root subdirectory leader is
      # docs-root-relative, anything else is project-relative — so the
      # fully-spelled `.bionic/docs/specs/...` an author is likely to paste
      # lands in the same place as the short form. The leader set is widened
      # from the walk arm's single `record/` because a governing design can live
      # in any artifact directory; unlike the walk artifact it is NOT contained
      # to one, since an epic-level design a wave implements may legitimately
      # sit outside this project's docs root entirely.
      resolve_design_path() {  # $1 = raw design: value
        case "$1" in
          /*) printf '%s\n' "$1" ;;
          specs/*|plans/*|adrs/*|incidents/*|record/*) printf '%s/%s\n' "$DOCS_ROOT" "$1" ;;
          *)  printf '%s/%s\n' "$PROJECT_ROOT_FROM_PATH" "$1" ;;
        esac
      }

      # Every block from this arm names all three ways out, whichever arm the
      # author was reaching for — the author who mistyped a pointer may well be
      # the author who should have written the section.
      block_design() {  # $1 = what went wrong
        echo "BLOCKED: canonical-sdlc spec '$BASENAME' (scale: $SCALE): $1" >&2
        echo "Path: $FILE_PATH" >&2
        echo "A wave- or epic-scale spec must satisfy one of three:" >&2
        echo "  (a) a flush-left '## Design' section in this spec;" >&2
        echo "  (b) frontmatter 'design: <path>' naming a file that carries a flush-left '## Design';" >&2
        echo "  (c) frontmatter 'design-waived: <user> <date> <reason>' — a user-only move." >&2
        exit 2
      }

      # `## Design` must be flush left and must be the whole heading word:
      # `## Design — v2` is the section, `## Designer notes` is not. The matrix
      # gate's bare prefix match would accept both; the trailing-boundary
      # requirement costs nothing and is the difference between a wall and a
      # word search. `[[:space:]]` covers a CRLF target's trailing \r.
      DESIGN_HEADING='^## Design([[:space:]]|$)'

      # Fence-aware on BOTH read paths, matching the evidence-gate hook, whose
      # `## SDLC State` reads all skip ``` fenced blocks for the same reason: a
      # spec that EXPLAINS this contract will show `## Design` as an example,
      # and an example is documentation, not a section. Stripping fences before
      # the grep keeps one heading regex for both paths rather than a second
      # rendering of it inside awk.
      strip_fences() {  # a document on stdin → the same document, fences dropped
        awk '
          /^[[:space:]]*```/ { fence = !fence; next }
          fence { next }
          { print }
        '
      }

      # The pointer target is read off disk, so it needs the same normalization
      # `$CONTENT` got at the top of this hook — the stdin twin of the evidence
      # gate's normalize_newlines(). The template this arm follows was copied for
      # its path half and not its read half: CRLF survives a line-anchored grep
      # (`[[:space:]]` eats the trailing \r), but a CR-only document arrives as
      # ONE record, so no `## Design` is ever at a line start and a legitimate
      # target false-BLOCKs. CRLF coverage does not catch this class — see
      # `.claude/rules/hook-authoring.md`, and c14 for the case that does.
      # [WALL: tests/canonical-sdlc-governing-skill.test.sh]
      normalize_newlines() {  # a document on stdin → the same document, LF-split
        awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }'
      }

      DESIGN_POINTER=$(yaml_get design)
      # Presence-only, matching the `rigor-override:` waiver precedent: the
      # fields are recorded for the reader, never validated here. Read by grep
      # rather than yaml_get so that a bare `design-waived:` — a malformed
      # waiver, but unmistakably a user's waiver — still counts as present.
      DESIGN_WAIVED=0
      if echo "$FRONTMATTER" | grep -qE '^[[:space:]]*design-waived[[:space:]]*:'; then
        DESIGN_WAIVED=1
      fi

      # PRECEDENCE: waiver short-circuits everything; below it, a PRESENT
      # `design:` pointer validates unconditionally — resolved, existence-checked
      # and `..`-refused whether or not the spec also carries its own section —
      # and only the absence of a pointer falls through to the in-place read.
      # [WALL: tests/canonical-sdlc-governing-skill.test.sh]
      #
      # The order matters because the pointer is not one of three interchangeable
      # ways to be quiet: it is the path the Step-3 approval display prints for
      # the user to open (R2/AC-1). The combined shape — pointer plus a local
      # delta section — is the one the docs recommend, so an `elif` that let the
      # section satisfy the wall first made the recommended shape the one where a
      # typo, a moved epic design or a rename produced an approval display citing
      # nothing, with the wall silent. A pointer is never decorative (critic C-3).
      #
      # The waived path is deliberately NOT symmetric: `design-waived:` still
      # silences a broken pointer beside it. That contradiction is a separate,
      # known finding, and closing it here would smuggle a second rule into a
      # repair scoped to the unwaived path.
      if [ "$DESIGN_WAIVED" -eq 1 ]; then
        :
      elif [ -n "$DESIGN_POINTER" ]; then
        # A `..` component is refused outright rather than normalized, mirroring
        # the walk arm: a design named by climbing out of the directory it was
        # named relative to is a spelling nobody should have to audit, and the
        # refusal holds even when the climb would land on a real design.
        if echo "$DESIGN_POINTER" | grep -qE '(^|/)\.\.(/|$)'; then
          block_design "design: '$DESIGN_POINTER' climbs out with a '..' component and is refused."
        fi
        DESIGN_ABS=$(resolve_design_path "$DESIGN_POINTER")
        if [ ! -f "$DESIGN_ABS" ]; then
          block_design "design: '$DESIGN_POINTER' names no file (resolved to $DESIGN_ABS)."
        fi
        if ! normalize_newlines < "$DESIGN_ABS" 2>/dev/null | strip_fences | grep -qE "$DESIGN_HEADING"; then
          block_design "design: '$DESIGN_POINTER' resolves to $DESIGN_ABS, which carries no flush-left '## Design' section."
        fi
      elif ! echo "$CONTENT" | strip_fences | grep -qE "$DESIGN_HEADING"; then
        block_design "no design. It carries no '## Design' section, no 'design:' pointer and no waiver."
      fi
    fi
    ;;
esac

# ---------- AC-11 / AC-12: tree creation on first lifecycle use ----------
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
#
# Slice 2 (F4): neither hook has an entry point that fires on true first
# lifecycle use without requiring `.bionic/` to pre-exist — except this one.
# The governing-skill hook already knows the target artifact's path and, as
# of slice 1, computes PROJECT_ROOT_FROM_PATH from git rather than by
# walking for an existing `.bionic/`. Creation hangs off that same
# computation.
#
# The discriminator is `canonical_sdlc_version` — the SAME field the schema
# enforcement above reads, and for the same reason. Slice 2 keyed creation on
# `governing-skill: canonical-sdlc` instead, which is the artifact-AUTHOR
# field; `.claude/rules/hook-authoring.md` (machine-local, gitignored, authored
# in place — no script recreates it, so absent from a fresh clone) § "Discriminators in
# enforcement hooks" names that as a known failure mode, because Step 3 plans legitimately
# declare `governing-skill: superpowers:writing-plans` and would have found no
# tree. Slice 2's stated rationale was avoiding a re-fire on later artifacts,
# and re-firing costs nothing: `mkdir -p` is idempotent and the `.gitignore`
# write is `[ -f ]`-guarded.
#
# Deliberately NOT a SessionStart hook: that would create `.bionic/` in
# every repo the user opens a session in. "First lifecycle use" is the
# first canonical-sdlc artifact write, not the first session — see the
# wave-level Not Doing.
#
# PLACEMENT (Step-6 findings C5 / F3 / S4): this block used to sit immediately
# after SDLC_VERSION was read, i.e. AHEAD of the version, triple, flag and
# matrix gates — so a write this hook then REFUSED still left a full tree and a
# `.gitignore` behind, in a repo named by the tool call's own `file_path`. A
# PreToolUse gate must not mutate the filesystem for a call it denies. It now
# runs at the single `exit 0`, past every gate, so the tree is created only for
# an artifact that satisfies the ENTIRE contract — not merely one carrying a
# version marker. Nothing between the old and new positions reads the tree:
# `log_finding` writes under `$HOME/.claude/logs/`, the config.yaml and epic
# plan reads are `[ -r ]`/`2>/dev/null` fail-open and target files this block
# never creates.
#
# Neither call can block — no new exit path is added here; failure to create is
# left to whatever already handles an unwritable project tree elsewhere. The
# `.gitignore` redirect is braced so that the SHELL's failure message (the
# redirection is performed before `printf` runs, so `printf 2>/dev/null` would
# silence nothing) is suppressed too — matching the `mkdir -p ... 2>/dev/null`
# beside it. An allowed tool call must leave stderr clean.
# [WALL: tests/canonical-sdlc-governing-skill.test.sh]
if [ -n "$SDLC_VERSION" ]; then
  mkdir -p \
    "$PROJECT_ROOT_FROM_PATH/.bionic/tmp" \
    "$PROJECT_ROOT_FROM_PATH/.bionic/docs/specs" \
    "$PROJECT_ROOT_FROM_PATH/.bionic/docs/plans" \
    "$PROJECT_ROOT_FROM_PATH/.bionic/docs/adrs" \
    "$PROJECT_ROOT_FROM_PATH/.bionic/docs/incidents" \
    2>/dev/null
  BIONIC_GITIGNORE="$PROJECT_ROOT_FROM_PATH/.bionic/.gitignore"
  [ -f "$BIONIC_GITIGNORE" ] || { printf '*\n' > "$BIONIC_GITIGNORE"; } 2>/dev/null
fi

exit 0
