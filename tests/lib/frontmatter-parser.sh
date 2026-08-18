# tests/lib/frontmatter-parser.sh — the shared SKILL.md `hooks:` frontmatter walker
# (epic-17 wave-04, AC-12). Before this file, the same 4-line block entry/exit state
# machine was hand-copied into four call sites across three test files — this file's
# own L.1 row-extractor, a dead `skill_block_count` left over from a retired pairing
# arm, installer-behavior.test.sh's `_skill_frontmatter_has`, and scripts.test.sh's
# two inline checks — with no agreement between them (t6-review.md F-5, W2 review
# DO-NOW 7). One shared implementation removes the plurality instead of pinning it.
#
#     . "$(dirname "$0")/lib/frontmatter-parser.sh"      # from tests/*.test.sh
#
# skill_hooks_rows <file>
#   Prints one "event|matcher|command|timeout" row per entry inside the file's
#   top-level `hooks:` frontmatter block. A row is only emitted once its `timeout:`
#   line is seen, so a stripped bound drops the whole row rather than rendering a
#   partial one — callers that count rows get this for free.
skill_hooks_rows() {
  awk '
    /^hooks:$/ { active=1; next }
    active && /^---$/ { active=0 }
    active && /^[A-Za-z]/ { active=0 }
    !active { next }
    /^  [A-Za-z]+:$/ { event=$0; sub(/^  /,"",event); sub(/:$/,"",event); matcher=""; next }
    /^    - matcher: "/ { matcher=$0; sub(/^    - matcher: "/,"",matcher); sub(/"$/,"",matcher); next }
    /^    - hooks:$/ { matcher=""; next }
    /^          command: / { cmd=$0; sub(/^          command: /,"",cmd); next }
    /^          timeout: / { t=$0; sub(/^          timeout: /,"",t); print event "|" matcher "|" cmd "|" t }
  ' "$1"
}

# skill_hooks_has <file> <event> <matcher> <command>
#   Exit 0 iff a row with exactly this event/matcher/command exists (any timeout).
skill_hooks_has() {
  skill_hooks_rows "$1" | awk -F'|' -v e="$2" -v m="$3" -v c="$4" \
    '$1 == e && $2 == m && $3 == c { found=1 } END { exit !found }'
}
