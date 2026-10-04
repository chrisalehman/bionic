#!/bin/bash
# lib/land.sh — whether a checkout may land.
. "$(dirname "${BASH_SOURCE[0]}")/tree.sh"

# land_refusal <dir> — prints why <dir> may not land, or nothing.
land_refusal() {
  local dirty
  dirty="$(tree_dirty_count "$1")"
  [ "$dirty" -eq 0 ] || echo "dirty: $dirty paths differ from $(tree_head "$1")"
}
