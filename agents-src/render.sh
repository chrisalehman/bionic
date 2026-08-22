#!/usr/bin/env bash
# agents-src/render.sh — renders the repo's GENERATED markdown from the templates and shared
# blocks in this directory. Epic-17 W4 S2, spec AC-2; design ledger D1. Generalized to a
# second render unit at W6 S1 (spec AC-6; ratified D-C).
#
# WHY THIS EXISTS. Text that must be word-identical across several files was previously held
# in agreement by pairwise byte-diff arms in the suite — identity by ENFORCEMENT, which is
# green right up until someone edits five of the six. Here there is one copy of each block
# and the finals are generated, so they cannot disagree: identity by CONSTRUCTION.
#
# TWO RENDER UNITS, ONE PIPELINE:
#
#   agents-src/templates/          -> agents/              the six agent role files. Shared
#                                                          duty text: the reporting contract
#                                                          (all six), the implementor core
#                                                          (both implementors), the survival
#                                                          rules (all six).
#   agents-src/templates/commands/ -> payload/commands/    the four shipped slash-command
#                                                          files. Shared text: the
#                                                          presentation contract, one block,
#                                                          in all four (W6 spec AC-6).
#
# THE SHIPPING BOUNDARY. agents/ and payload/commands/ are product — the plugin installs
# those files. THIS directory is build-time apparatus and never ships;
# tests/plugin-payload.test.sh §G is the wall that keeps it repo-side.
#
#   agents-src/blocks/<name>.md               one shared block, body text only
#   agents-src/templates/<role>.md.tmpl       one role skeleton with directives
#   agents-src/templates/commands/<cmd>.md.tmpl  one command skeleton with directives
#   agents/<role>.md, payload/commands/<cmd>.md  the committed, shipped, generated finals
#
# TEMPLATE DIRECTIVES, each on a line of its own:
#
#   <!-- GENERATED-HEADER -->    expands to the do-not-edit header. Exactly one per
#                                template, and it belongs AFTER the closing frontmatter
#                                fence — Claude Code reads name/model/effort from a role's
#                                fence and `description` from a command's, and a fence has
#                                to start on line 1, so nothing may precede it.
#   <!-- INJECT: <name> -->      expands to blocks/<name>.md wrapped in <!-- NAME-BEGIN -->
#                                / <!-- NAME-END --> markers, the marker name being the
#                                block's own filename upper-cased. Marker and source can
#                                therefore never drift apart.
#
# ONE PLACEHOLDER, substituted INLINE wherever it appears in a template line:
#
#   @@PLUGIN_VERSION@@           the `.version` field of payload/.claude-plugin/plugin.json.
#                                Unlike the two directives above it is not a line of its own:
#                                the SENTENCE belongs to the template (help.md's opening line
#                                reads `bionic @@PLUGIN_VERSION@@ (installed)`) and only the
#                                VALUE comes from here.
#
# WHY THE VERSION IS BAKED AT RENDER TIME (epic-17 W6 S9a, walk finding W-2). help.md used to
# read plugin.json at RUNTIME, from ${CLAUDE_PLUGIN_ROOT}, so that the page and the manifest
# could not disagree. The Step-5 walk measured what that costs a user: run /bionic:help from
# any session whose working directory is not this repo and the read is REFUSED — a permission
# notice one time, a working-directory sandbox error the next — printed above the page, in
# different words each time, with no version line either way. Baking it moves plugin.json
# from a file the shipped page reads into a file THIS PIPELINE reads, which is a source like
# any block or template: `--check` goes red when the committed page and the committed
# plugin.json disagree, in both directions, so plugin.json stays the version's single owner
# and help.md is a rendering of it — the same relationship marketplace.json has with the
# dependency list. A missing or version-less plugin.json is a hard failure, for the same
# reason a missing block is: a page rendered with a hole in it would leave --check green.
#
# Section HEADINGS stay in the templates rather than in the blocks: a block owns doctrine,
# a template owns document structure, and a final is free to place a shared block under
# whatever heading reads right for that file.
#
# WHY THE COMMAND HEADER IS WORDED DIFFERENTLY. The role-file header names this script and
# the suite that guards it. A command file may not: three suites pin every `.sh` token in
# payload/commands/*.md to be an invocation rooted at ${CLAUDE_PLUGIN_ROOT}, because a
# command file naming any other script is naming something the machine cannot run. A build
# instruction in a shipped file is not worth reopening that rule, so the command header
# carries the same warning and the same source pointer with no script filenames in it.
#
# USAGE
#   bash agents-src/render.sh            rewrite every final and the checksum manifest
#                                        (payload/integrity/agents.sha256, spec AC-4 — the
#                                        file /bionic:doctor reads to tell a user whether
#                                        their installed role files are stock)
#   bash agents-src/render.sh --check    re-render into memory and diff against the
#                                        committed finals AND the committed manifest;
#                                        exit 1 with the diff if any differ. This is the
#                                        whole staleness class in one command, and
#                                        tests/agent-render.test.sh is where it runs. It
#                                        fails identically whether the OUTPUT was
#                                        hand-edited or a SOURCE was edited without a
#                                        re-render, which is the point: both mean the
#                                        committed file is not the render of the committed
#                                        source.
#
# Every directory is derived from this script's own location, never from $PWD, so a copy of
# the tree in a temp directory renders against ITS OWN outputs — that is what lets the suite
# plant staleness into a fixture without touching the repo.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "$SRC_DIR/.." && pwd -P)"
BLOCK_DIR="$SRC_DIR/blocks"

# THE UNIT TABLE: one row per (templates dir -> output dir), both repo-relative. Adding a
# third rendered surface is a row here and nothing else; every loop below is driven from it,
# so a new unit cannot be half-wired — rendered by the write path and invisible to --check.
RENDER_UNITS="
agents-src/templates|agents
agents-src/templates/commands|payload/commands
"

ROLES="auditor critic implementor researcher senior-implementor test-runner"

# THE CHECKSUM MANIFEST (epic-17 W4 S5, spec AC-4). /bionic:doctor compares a user's
# installed role files against this file and reports one line: stock, or modified locally.
# It is written HERE, by the same command that writes the finals, for one reason — a
# manifest maintained separately is a manifest that ships stale, and a stale manifest
# accuses a user who edited nothing. The paths inside it are PLUGIN-ROOT-relative
# (`agents/<role>.md`), which is what they resolve to on the installed machine and, through
# payload/agents -> ../agents, here as well.
#
# IT COVERS THE ROLE FILES ONLY. The command files are the second render unit, not a second
# integrity subject: doctor's stock-or-modified line is about the six role files it was
# written for, and widening it is a doctor change with its own acceptance criterion, not a
# side effect of generalizing this script.
MANIFEST_REL="payload/integrity/agents.sha256"
MANIFEST="$REPO_DIR/$MANIFEST_REL"

PLUGIN_JSON_REL="payload/.claude-plugin/plugin.json"
PLUGIN_JSON="$REPO_DIR/$PLUGIN_JSON_REL"
VERSION_PLACEHOLDER='@@PLUGIN_VERSION@@'

die() { echo "render.sh: $1" >&2; exit 1; }

# The plugin version, read once and cached. Read LAZILY — only a template that actually
# carries the placeholder needs it — so a render unit that has nothing to do with the plugin
# manifest does not acquire a dependency on it, and the error, when there is one, names the
# template that asked.
#
# `jq` when it is here, a field read when it is not: this script runs from the suite on
# machines where jq is a bionic dependency rather than a given, and a renderer that silently
# skipped the substitution on such a machine would commit a page with the placeholder still
# in it. Both paths return the same bytes for a manifest of this shape, and an empty result
# from either is a failure, never a default.
PLUGIN_VERSION=""
plugin_version() {
  [ -n "$PLUGIN_VERSION" ] && { printf '%s' "$PLUGIN_VERSION"; return 0; }
  [ -f "$PLUGIN_JSON" ] || { echo "render.sh: $PLUGIN_JSON_REL does not exist, and a template needs the plugin version from it" >&2; return 1; }
  local v=""
  if command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
  else
    v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PLUGIN_JSON" 2>/dev/null | head -1)"
  fi
  [ -n "$v" ] || { echo "render.sh: $PLUGIN_JSON_REL declares no non-empty .version" >&2; return 1; }
  PLUGIN_VERSION="$v"
  printf '%s' "$PLUGIN_VERSION"
}

# Digest one file. shasum is present on macOS and on any box with perl; sha256sum is the
# GNU spelling. Nothing else is tried: a manifest written by an unknown tool would be a
# manifest doctor cannot reproduce.
sha256_of() {  # <file>
  local out
  if command -v shasum >/dev/null 2>&1; then
    out="$(shasum -a 256 "$1")" || return 1
  elif command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum "$1")" || return 1
  else
    return 1
  fi
  echo "${out%% *}"
}

# The manifest bytes for a directory of rendered finals, on stdout.
manifest_for() {  # <dir-holding-the-six-finals>
  local dir="$1" role digest
  echo "# GENERATED — sha256 of the rendered agent files, plugin-root-relative."
  echo "# Written by agents-src/render.sh alongside the finals themselves; regenerate with"
  echo "# \`bash agents-src/render.sh\`. /bionic:doctor reads it to report whether an installed"
  echo "# machine's role files are stock or locally modified."
  for role in $ROLES; do
    digest="$(sha256_of "$dir/$role.md")" || return 1
    printf '%s  agents/%s.md\n' "$digest" "$role"
  done
}

# generated_header <template-path-relative-to-the-repo>
#
# The header is chosen by WHERE the template lives, because that is what decides where its
# output ships and therefore which rules the output has to satisfy. See "WHY THE COMMAND
# HEADER IS WORDED DIFFERENTLY" above.
generated_header() {
  case "$1" in
    agents-src/templates/commands/*)
      cat <<EOF
<!-- GENERATED FILE — DO NOT EDIT.
     Rendered from $1 and the shared blocks in
     agents-src/blocks/. Edit those, then re-render; the render check goes red whenever
     this file and its sources disagree. -->
EOF
      ;;
    *)
      cat <<EOF
<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from $1 and the shared
     blocks in agents-src/blocks/. Edit those, then re-run \`bash agents-src/render.sh\`.
     tests/agent-render.test.sh goes red whenever this file and its sources disagree. -->
EOF
      ;;
  esac
}

# render_one <template-path> <template-path-relative-to-the-repo> → rendered bytes on
# stdout; nonzero (and a reason on stderr) if the template is missing, names a block that
# does not exist, or carries no header directive. A missing block must be loud: a silent
# skip would emit a final with a hole in it and --check would stay green, because output and
# source would still agree.
render_one() {
  local tmpl="$1" tmpl_rel="$2"
  [ -f "$tmpl" ] || { echo "render.sh: no template at $tmpl" >&2; return 1; }

  local line name upper block version saw_header=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "<!-- GENERATED-HEADER -->")
        generated_header "$tmpl_rel"
        saw_header=$((saw_header + 1))
        ;;
      "<!-- INJECT: "*" -->")
        name="${line#<!-- INJECT: }"; name="${name% -->}"
        block="$BLOCK_DIR/$name.md"
        [ -f "$block" ] || { echo "render.sh: $tmpl_rel injects '$name' but $block does not exist" >&2; return 1; }
        upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
        printf '<!-- %s-BEGIN -->\n' "$upper"
        # Command substitution strips trailing newlines; the printf puts exactly one back,
        # so a block source with or without a trailing blank line renders the same bytes.
        printf '%s\n' "$(cat "$block")"
        printf '<!-- %s-END -->\n' "$upper"
        ;;
      *)
        # Bash's own replacement rather than sed: a version string is arbitrary text, and
        # `&` or `|` in it would be a sed metacharacter waiting for a release to trip over.
        if [ "${line#*$VERSION_PLACEHOLDER}" != "$line" ]; then
          version="$(plugin_version)" || return 1
          line="${line//$VERSION_PLACEHOLDER/$version}"
        fi
        printf '%s\n' "$line"
        ;;
    esac
  done < "$tmpl"

  case "$saw_header" in
    1) ;;
    0) echo "render.sh: $tmpl_rel has no <!-- GENERATED-HEADER --> directive" >&2; return 1 ;;
    *) echo "render.sh: $tmpl_rel has $saw_header GENERATED-HEADER directives (want exactly 1)" >&2; return 1 ;;
  esac
  return 0
}

MODE="write"
case "${1:-}" in
  "")       MODE="write" ;;
  --check)  MODE="check" ;;
  -h|--help)
    # The leading comment block, verbatim, with its `# ` stripped — no line-number range to
    # fall out of step with the comment it is meant to print.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
    exit 0 ;;
  *) die "unknown argument '$1' (want --check, or no argument to write)" ;;
esac

[ -d "$BLOCK_DIR" ] || die "no blocks directory at $BLOCK_DIR"
for unit in $RENDER_UNITS; do
  [ -d "$REPO_DIR/${unit%%|*}" ] || die "no templates directory at $REPO_DIR/${unit%%|*}"
  [ -d "$REPO_DIR/${unit##*|}" ] || die "no output directory at $REPO_DIR/${unit##*|}"
done

WORK="$(mktemp -d)" || die "cannot create a temp directory"
trap 'rm -rf "$WORK"' EXIT

RC=0
STALE=""

for unit in $RENDER_UNITS; do
  tmpl_dir="${unit%%|*}"
  out_dir="${unit##*|}"
  mkdir -p "$WORK/$out_dir" || { echo "render.sh: cannot stage $out_dir" >&2; RC=1; continue; }

  # maxdepth 1 by construction: the role unit's directory HOLDS the command unit's, and a
  # recursive glob would render the commands twice, into the wrong place the second time.
  for tmpl in "$REPO_DIR/$tmpl_dir"/*.md.tmpl; do
    [ -f "$tmpl" ] || continue
    base="$(basename "$tmpl")"; base="${base%.md.tmpl}"
    rel="$out_dir/$base.md"

    if ! render_one "$tmpl" "$tmpl_dir/$base.md.tmpl" > "$WORK/$rel"; then
      RC=1
      continue
    fi

    if [ "$MODE" = check ]; then
      if [ ! -f "$REPO_DIR/$rel" ]; then
        echo "render.sh: $rel does not exist (the template renders, nothing committed)" >&2
        STALE="$STALE $rel"; RC=1
      elif ! diff -u "$REPO_DIR/$rel" "$WORK/$rel" > "$WORK/$out_dir/$base.diff" 2>&1; then
        echo "── $rel differs from a fresh render ──"
        sed -e "s|$WORK/|<rendered>/|" -e "s|$REPO_DIR/||" "$WORK/$out_dir/$base.diff"
        STALE="$STALE $rel"; RC=1
      fi
    else
      cp "$WORK/$rel" "$REPO_DIR/$rel" || { echo "render.sh: cannot write $rel" >&2; RC=1; }
    fi
  done
done

# The manifest, from the bytes just rendered. Skipped entirely when a render failed: a
# manifest of a partial render is worse than none, because doctor would then report a
# healthy machine as modified.
MANIFEST_STALE=no
if [ "$RC" = 0 ]; then
  if ! manifest_for "$WORK/agents" > "$WORK/agents.sha256"; then
    echo "render.sh: cannot compute checksums (no shasum or sha256sum on PATH)" >&2
    RC=1
  elif [ "$MODE" = check ]; then
    if [ ! -f "$MANIFEST" ]; then
      echo "render.sh: $MANIFEST_REL does not exist (the finals render, no manifest is committed)" >&2
      MANIFEST_STALE=yes; RC=1
    elif ! diff -u "$MANIFEST" "$WORK/agents.sha256" > "$WORK/manifest.diff" 2>&1; then
      echo "── $MANIFEST_REL differs from a fresh render ──"
      sed -e "s|$WORK/|<rendered>/|" -e "s|$MANIFEST|$MANIFEST_REL|" "$WORK/manifest.diff"
      MANIFEST_STALE=yes; RC=1
    fi
  else
    # `mkdir -p` rather than a precondition: unlike agents/, the manifest's directory is an
    # output location, and a copy of the tree that has never been rendered has no reason to
    # carry one already (tests/agent-render.test.sh renders into exactly such a copy).
    if mkdir -p "${MANIFEST%/*}" 2>/dev/null && cp "$WORK/agents.sha256" "$MANIFEST"; then
      :
    else
      echo "render.sh: cannot write $MANIFEST_REL" >&2
      RC=1
    fi
  fi
fi

if [ "$MODE" = check ]; then
  if [ "$RC" = 0 ]; then
    echo "render.sh --check: every rendered final matches a fresh render, and so does the manifest"
  else
    [ "$MANIFEST_STALE" = yes ] && STALE="$STALE $MANIFEST_REL"
    echo "render.sh --check: STALE —${STALE:- (render failure)}" >&2
    echo "  the committed file is not the render of the committed source. Either a final was" >&2
    echo "  edited directly, a block/template was edited without re-rendering, or the manifest" >&2
    echo "  was not refreshed with the finals." >&2
    echo "  Repair: bash agents-src/render.sh — then commit the finals with the sources." >&2
  fi
else
  [ "$RC" = 0 ] && echo "render.sh: rendered every final and refreshed $MANIFEST_REL"
fi

exit "$RC"
