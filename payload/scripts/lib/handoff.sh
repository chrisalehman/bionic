#!/bin/bash
# payload/scripts/lib/handoff.sh — where a run's handoff file is, read once (wave-39 T16; D18, REQ-12 AC-12.1).
#
# WHAT IT OWNS. The plan's `## Handoff` pointer, the one line `handoff: <path> written <local time>` that
# session-poker.sh `handoff` and close-out.sh write there (wave-38 T12; D23), and the file it names.
#
#     handoff_pointer_of <plan> [<root>]
#                        the absolute path the pointer names; nothing when the plan carries no pointer (a wave-37
#                        plan's in-place section, or no ## Handoff at all). Always rc 0.
#     handoff_default_of <plan> [<root>]
#                        <docs root>/record/<wave>/handoff.md, the file a handoff is written to when nothing else
#                        is named: the docs root of <root> (lib/roots.sh `docs_root`), the slug the plan's own
#                        (lib/proof.sh `proof_plan_slug`, the one slug reader). rc 1 when the plan's name leaves no slug.
#     handoff_file_of <plan> [<root>]
#                        the run's handoff file: the pointer's path, else the default.
#
#     <root> is the project root the pointer is relative to; absent, the project root of the plan's own directory
#     (lib/root.sh `project_root`), physical.
#
# THE ONE READER OF THE POINTER (burns debt handoff-pointer-reader). Two stood: the poker's `handoff_file_of` found the
# section by `##` and any run of blanks, then `Handoff`; close-out.sh's `co_handoff_where` by `## Handoff` after one
# space, so a tab-led heading was a pointer to one and none to the other, and each resolved the relative path and
# the default by its own hand. D18 rules the poker's heading test, the path project-root relative, the default
# record/<wave>/handoff.md. The poker's readers (adopt's STALE note, launch-sync's mark, the verb's carry) and
# close-out's closed form call these; tests/handoff-file.test.sh §POINTER-AGREE holds them to one answer.
#
# THE SECTION TEST, `_HANDOFF_SEC_AWK` (moved here from session-poker.sh, where it burned debt
# handoff-section-reader): `ho_track(line)` is 1 for a line inside `## Handoff`, the heading, fences and fenced lines
# excluded. Every awk that looks in the section prepends it, the poker's in-place rewrites included.
#
# NEEDS lib/root.sh and lib/roots.sh (both callers source them); loads lib/proof.sh from beside itself when
# `proof_plan_slug` is not yet defined. Sourced, never executed; bash 3.2.

_HANDOFF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"

_HANDOFF_SEC_AWK='
  function ho_track(l) {
    if (l ~ /^[ \t]*```/) { _hf = !_hf; return 0 }
    if (_hf) return 0
    if (l ~ /^##[ \t]/) { _hs = (l ~ /^##[ \t]+Handoff[ \t]*$/); return 0 }
    return _hs
  }'

_handoff_root() {  # <plan> [<root>] -> the root the pointer resolves against
  if [ -n "${2:-}" ]; then printf '%s' "$2"; return 0; fi
  ( cd "$(project_root "$(dirname "$1")")" 2>/dev/null && pwd -P )
}

handoff_pointer_of() {  # <plan> [<root>]
  local rel root
  [ -f "${1:-}" ] || return 0
  rel="$(awk "$_HANDOFF_SEC_AWK"'
    ho_track($0) && index($0, "handoff: ") == 1 && $0 ~ / written / { s = substr($0, 10); sub(/ written .*$/, "", s); print s; exit }' "$1" 2>/dev/null)"
  [ -n "$rel" ] || return 0
  case "$rel" in
    /*) printf '%s\n' "$rel" ;;
    *) root="$(_handoff_root "$1" "${2:-}")"
       [ -n "$root" ] && printf '%s/%s\n' "$root" "$rel" ;;
  esac
  return 0
}

handoff_default_of() {  # <plan> [<root>]
  local root slug
  if ! declare -F proof_plan_slug >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    [ -r "$_HANDOFF_LIB_DIR/proof.sh" ] && . "$_HANDOFF_LIB_DIR/proof.sh" >/dev/null 2>&1
  fi
  slug="$(proof_plan_slug "${1:-}")" || return 1
  root="$(_handoff_root "${1:-}" "${2:-}")"
  [ -n "$root" ] || return 1
  printf '%s/record/%s/handoff.md\n' "$(docs_root "$root")" "$slug"
}

handoff_file_of() {  # <plan> [<root>]
  local f
  f="$(handoff_pointer_of "$@")"
  if [ -n "$f" ]; then printf '%s\n' "$f"; return 0; fi
  handoff_default_of "$@"
}
