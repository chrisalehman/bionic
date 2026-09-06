# tests/lib/swept-marker.sh — extracts the one `landing-swept/v1` writer for fixtures
# (wave-01-verification-cannot-lie S15, spec AC-26; research-code-map §2.c).
#
#     . "$(dirname "$0")/lib/resolve-roots.sh"      # first, so BIONIC_HOOKS_DIR is set
#     . "$(dirname "$0")/lib/swept-marker.sh"
#
# WHAT IT REPLACES. Four hand-written printf spellings of the `landing-swept/v1` marker in
# tests/session-poker.test.sh (`:472`, `:885`, `:909`, and the suite's own local `swept_marker`
# helper at `:3372`) — none of them going through the production writer, so none of them could
# catch a marker shape hooks/landing-gate.sh stopped producing.
#
# WHY EXTRACTED, NOT SOURCED FROM A LIB. `swept_marker_write` is defined directly inside
# hooks/landing-gate.sh, beside the `SWEPT_SCHEMA` it uses — not in a payload/scripts/lib
# file. A hook is free to source root.sh/run.sh/session.sh from the loader's own registry
# fallback for state that changes rarely, but that fallback answers with whatever was last
# LANDED, not this worktree's own tree — so a NEW lib function (or a change to an existing
# one) is invisible to any hook copy the loader resolves out-of-tree until the wave lands.
# tests/cross-gate-agreement.test.sh's own `field1_via`/`field2_via` helpers hit this exact
# problem already and solved it the same way this file does: extract the function's SOURCE
# out of the real file with `awk`, `eval` it into the current shell, and call the real thing
# — never a second printf, never a dependency on the loader resolving anything.
#
# swept_marker_write <roster file> <at> <session> <name> <agent id> <state> -> the function
# extracted from hooks/landing-gate.sh, real source, real call.
#
# swept_marker_field <line> <key> -> the value of one field, by key, off a raw marker line —
# the same by-key idiom every production reader uses (hooks/landing-gate.sh's own `_field`),
# so a suite asserting on a captured or produced marker does not hand-roll the pipeline.

if ! declare -p SWEPT_SCHEMA >/dev/null 2>&1; then
  eval "$(grep -m1 '^SWEPT_SCHEMA=' "${BIONIC_HOOKS_DIR}/landing-gate.sh")"
fi
if ! type -t swept_marker_write >/dev/null 2>&1; then
  eval "$(awk '/^swept_marker_write\(\)/,/^\}/' "${BIONIC_HOOKS_DIR}/landing-gate.sh")"
fi

# THE EXTRACTION IS CHECKED (review-b B-12). Both `eval`s above obtain their subject by
# matching SOURCE TEXT of hooks/landing-gate.sh at column 0 — `^SWEPT_SCHEMA=` and
# `^swept_marker_write()`. Indent the function, move the constant, and both become `eval ""`:
# a silent no-op, after which the builder simply does not exist and the failure surfaces
# as `command not found` under the runner's stderr-strict arm, in a suite whose own tally
# says nothing about it. The framework's derivation cannot cover this one either —
# `swept_marker_write` is not in `_tf_scan`'s token set — so the check is here, beside the
# extraction, and it names the file it failed to read.
if ! declare -p SWEPT_SCHEMA >/dev/null 2>&1; then
  echo "tests/lib/swept-marker.sh: no '^SWEPT_SCHEMA=' line in ${BIONIC_HOOKS_DIR}/landing-gate.sh — the constant could not be extracted (the hook was reformatted, or the name moved)." >&2
  exit 1
fi
require_helpers swept_marker_write

swept_marker_field() {  # <line> <key> -> value
  printf '%s' "$1" | tr '|' '\n' | grep "^$2=" | head -1 | cut -d= -f2-
}
