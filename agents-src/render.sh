#!/usr/bin/env bash
# agents-src/render.sh — renders the six agent role files under agents/ from the templates
# and shared blocks in this directory. Epic-17 W4 S2, spec AC-2; design ledger D1.
#
# WHY THIS EXISTS. The six role files share duty text that must be word-identical across
# them: the reporting contract (all six), the implementor core (both implementors), the
# survival rules (all six). Six hand-maintained copies were previously held in agreement by
# pairwise byte-diff arms in the suite — identity by ENFORCEMENT, which is green right up
# until someone edits five of the six. Here there is one copy of each block and the finals
# are generated, so they cannot disagree: identity by CONSTRUCTION.
#
# THE SHIPPING BOUNDARY. agents/ is product — the plugin installs those files. This
# directory is build-time apparatus and never ships; tests/plugin-payload.test.sh §G is the
# wall that keeps it repo-side.
#
#   agents-src/blocks/<name>.md        one shared block, body text only
#   agents-src/templates/<role>.md.tmpl  one role skeleton with directives
#   agents/<role>.md                   the committed, shipped, generated final
#
# TEMPLATE DIRECTIVES, each on a line of its own:
#
#   <!-- GENERATED-HEADER -->    expands to the do-not-edit header. Exactly one per
#                                template, and it belongs AFTER the closing frontmatter
#                                fence — Claude Code reads name/model/effort from a fence
#                                that has to start on line 1, so nothing may precede it.
#   <!-- INJECT: <name> -->      expands to blocks/<name>.md wrapped in <!-- NAME-BEGIN -->
#                                / <!-- NAME-END --> markers, the marker name being the
#                                block's own filename upper-cased. Marker and source can
#                                therefore never drift apart.
#
# Section HEADINGS stay in the templates rather than in the blocks: a block owns doctrine,
# a template owns document structure, and a role file is free to place a shared block under
# whatever heading reads right for that role.
#
# USAGE
#   bash agents-src/render.sh            rewrite the six finals
#   bash agents-src/render.sh --check    re-render into memory and diff against the
#                                        committed finals; exit 1 with the diff if any
#                                        differ. This is the whole staleness class in one
#                                        command, and tests/agent-render.test.sh is where
#                                        it runs. It fails identically whether the OUTPUT
#                                        was hand-edited or a SOURCE was edited without a
#                                        re-render, which is the point: both mean the
#                                        committed file is not the render of the committed
#                                        source.
#
# The output directory is derived from this script's own location (../agents), never from
# $PWD, so a copy of the tree in a temp directory renders against ITS OWN agents/ — that is
# what lets the suite plant staleness into a fixture without touching the repo.

set -uo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "$SRC_DIR/.." && pwd -P)"
BLOCK_DIR="$SRC_DIR/blocks"
TMPL_DIR="$SRC_DIR/templates"
OUT_DIR="$REPO_DIR/agents"

ROLES="auditor critic implementor researcher senior-implementor test-runner"

die() { echo "render.sh: $1" >&2; exit 1; }

generated_header() {  # $1=role
  cat <<EOF
<!-- GENERATED FILE — DO NOT EDIT.
     Rendered by agents-src/render.sh from agents-src/templates/$1.md.tmpl and the shared
     blocks in agents-src/blocks/. Edit those, then re-run \`bash agents-src/render.sh\`.
     tests/agent-render.test.sh goes red whenever this file and its sources disagree. -->
EOF
}

# render_one <role> → rendered bytes on stdout; nonzero (and a reason on stderr) if the
# template is missing, names a block that does not exist, or carries no header directive.
# A missing block must be loud: a silent skip would emit a role file with a hole in it and
# --check would stay green, because output and source would still agree.
render_one() {
  local role="$1"
  local tmpl="$TMPL_DIR/$role.md.tmpl"
  [ -f "$tmpl" ] || { echo "render.sh: no template for '$role' at $tmpl" >&2; return 1; }

  local line name upper block saw_header=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "<!-- GENERATED-HEADER -->")
        generated_header "$role"
        saw_header=$((saw_header + 1))
        ;;
      "<!-- INJECT: "*" -->")
        name="${line#<!-- INJECT: }"; name="${name% -->}"
        block="$BLOCK_DIR/$name.md"
        [ -f "$block" ] || { echo "render.sh: $role.md.tmpl injects '$name' but $block does not exist" >&2; return 1; }
        upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
        printf '<!-- %s-BEGIN -->\n' "$upper"
        # Command substitution strips trailing newlines; the printf puts exactly one back,
        # so a block source with or without a trailing blank line renders the same bytes.
        printf '%s\n' "$(cat "$block")"
        printf '<!-- %s-END -->\n' "$upper"
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$tmpl"

  case "$saw_header" in
    1) ;;
    0) echo "render.sh: $role.md.tmpl has no <!-- GENERATED-HEADER --> directive" >&2; return 1 ;;
    *) echo "render.sh: $role.md.tmpl has $saw_header GENERATED-HEADER directives (want exactly 1)" >&2; return 1 ;;
  esac
  return 0
}

MODE="write"
case "${1:-}" in
  "")       MODE="write" ;;
  --check)  MODE="check" ;;
  -h|--help)
    sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) die "unknown argument '$1' (want --check, or no argument to write)" ;;
esac

[ -d "$BLOCK_DIR" ] || die "no blocks directory at $BLOCK_DIR"
[ -d "$TMPL_DIR" ]  || die "no templates directory at $TMPL_DIR"
[ -d "$OUT_DIR" ]   || die "no output directory at $OUT_DIR"

WORK="$(mktemp -d)" || die "cannot create a temp directory"
trap 'rm -rf "$WORK"' EXIT

RC=0
STALE=""

for role in $ROLES; do
  if ! render_one "$role" > "$WORK/$role.md"; then
    RC=1
    continue
  fi
  if [ "$MODE" = check ]; then
    if [ ! -f "$OUT_DIR/$role.md" ]; then
      echo "render.sh: agents/$role.md does not exist (template renders, nothing committed)" >&2
      STALE="$STALE $role"; RC=1
    elif ! diff -u "$OUT_DIR/$role.md" "$WORK/$role.md" > "$WORK/$role.diff" 2>&1; then
      echo "── agents/$role.md differs from a fresh render ──"
      sed -e "s|$WORK/|<rendered>/|" -e "s|$OUT_DIR/|agents/|" "$WORK/$role.diff"
      STALE="$STALE $role"; RC=1
    fi
  else
    cp "$WORK/$role.md" "$OUT_DIR/$role.md" || { echo "render.sh: cannot write $OUT_DIR/$role.md" >&2; RC=1; }
  fi
done

if [ "$MODE" = check ]; then
  if [ "$RC" = 0 ]; then
    echo "render.sh --check: all six finals match a fresh render"
  else
    echo "render.sh --check: STALE —${STALE:- (render failure)}" >&2
    echo "  the committed file is not the render of the committed source. Either a final was" >&2
    echo "  edited directly, or a block/template was edited without re-rendering." >&2
    echo "  Repair: bash agents-src/render.sh — then commit the finals with the sources." >&2
  fi
else
  [ "$RC" = 0 ] && echo "render.sh: rendered six role files into agents/"
fi

exit "$RC"
