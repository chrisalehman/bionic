# tests/lib/landing-world.sh — THE LANDING'S MODEL WORLD: a world root the commit gate admits, a row's launch line on
# the session's roster, and the carrier's environment
#
#     . "$(dirname "$0")/lib/landing-world.sh"
#
# The landing-line parts load it through tests/landing-line.prelude.sh; a suite that lands rows in the same world
# loads it itself, so the world has one home.
#
# THE CALLER SETS LL_HERE (the tests folder ll_carrier_env loads roster-row.sh from) and defines ll_plan (a root's
# plan path); WORLD_ROOT, WORLD_SID and the world's builders are tests/lib/world.sh's, loaded here when the caller has
# not loaded it.

declare -F world_repo >/dev/null 2>&1 || { [ -r "${BASH_SOURCE[0]%/*}/world.sh" ] && . "${BASH_SOURCE[0]%/*}/world.sh"; } \
  || { echo "landing-world.sh: cannot load ${BASH_SOURCE[0]%/*}/world.sh" >&2; return 1; }

ll_world() {  # -> a world root; its plan admitted by the real commit gate (the hand landing writes it)
  local r
  r="$(world_repo)" || return 1
  [ -n "$r" ] && [ "$(git -C "$r" rev-parse --show-toplevel 2>/dev/null)" = "$r" ] || return 1
  printf '%s' "$r"
}

ll_launch() {  # <root> <row> <lands_on> [key=value...] — the row's launch line on the session's roster
  local r="$1" t="$2" l="$3"
  shift 3
  printf '%s|row=%s|lands_on=%s\n' \
    "$(roster_row_fixture status=intended session="$WORLD_SID" name="wx-$t" agent_id="b00$t" plan="$(ll_plan "$r")" "$@")" \
    "$t" "$l" >> "$r/.bionic/tmp/roster-$WORLD_SID.state"
}

ll_carrier_env() {  # the carrier's environment, as the carrier section of part 1 sets it (wave-28 T4); the lines are that section's own
  . "${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/roster.sh" || return 1
  . "$LL_HERE/lib/roster-row.sh" || return 1
  export CLAUDE_CONFIG_DIR="$WORLD_ROOT/home"
  mkdir -p "$CLAUDE_CONFIG_DIR/bionic"; printf '80\n' > "$CLAUDE_CONFIG_DIR/bionic/share"
  export CLAUDE_CODE_SESSION_ID="$WORLD_SID" BIONIC_GATE_POLL=0.1 BIONIC_LINE_POLL=0.2
  world_machine 8 8192 40 0.5
  world_clock 1000
  export LL_SIG="$WORLD_ROOT/sig"; mkdir -p "$LL_SIG"
}
