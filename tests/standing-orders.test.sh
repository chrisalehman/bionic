#!/bin/bash
# tests/standing-orders.test.sh — standing orders live in one place the tool reads and the walls
# enforce (wave-38 T18; REQ-7 AC-7.1, AC-7.2; design-ledger Δ10 D17).
#
# WHAT A STANDING ORDER IS. An item of the `standing-orders:` list in `.bionic/config.yaml`: the
# user's standing answer, one of the two exception classes to the four human stops (D17). So the
# surfaces that print one are telling the model what has already been decided, and an item that
# carries a `| refuse: <cmd-class>` tail is a wall, not a reminder.
#
# §PRINT (AC-7.1, spec eval row 218). A two-order fixture: `config_section <root> standing-orders`
# (lib/roots.sh, the one list reader of config.yaml) returns both items, in order, quotes stripped,
# the `| refuse:` tail kept verbatim; session-start's engaged block prints each as
# `bionic: standing order — <item>` at startup, clear, resume and compact; the resume recap
# (`session-poker.sh resume`, T13's door) repeats each as `standing-order: <item>` after its
# owned-by-user: lines. fails-when: an order in config is absent from either surface.
#
# §THREE (the spec's ownership row): ONE config fixture, and the three surfaces print the same
# items — the reader's list is the block's list is the recap's list.
#
# §REFUSE (AC-7.2, spec eval row 219). `- hand test in progress | refuse: suite`: the Bash wall
# refuses `tests/run.sh --only x.test.sh` naming the order; `git status` passes; an item without a
# tail refuses nothing; an unknown class is enforced never. THE FACT ARRIVES FROM THE PREAMBLE (the
# freeze, .claude/rules/hook-authoring.md): `wall_standing_orders <command> <section>` in lib/walls.sh
# is a pure predicate over the section hooks/bash-walls.sh reads and hands in, so handed an empty
# section beside a config that holds a lock it refuses nothing. THE MUTANT: a copy of walls.sh whose
# wall reads config.yaml itself flips that pin, and the suite builds it and shows it flip.
# fails-when: a heavy run passes under a lock.
#
# FIXTURE FIDELITY (HERMETIC). The session-poker prelude's sandbox, session id and plan builder
# (`s42_plan`: a gate-admitted plan, the session bound, committed); the handoff file is written by the
# real `handoff` verb while bound, then the session is made new (engaged, unbound, unarmed) exactly as
# tests/handoff-file.test.sh §RESUME does before it resumes. Both hooks are driven from this checkout
# with payloads in the CLI's shape; nothing reads this machine's ~/.claude.
#
# ANTI-VACUITY. Every absence sits beside a positive read through the same extractor on the same
# output: the order-line extractors are proved non-empty by P3/P4 before any row reads their absence.
#
# Usage: bash tests/standing-orders.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"

POKER="${BIONIC_HOOKS_DIR}/session-poker.sh"
. "$(dirname "$0")/session-poker.prelude.sh"
POKE_BOUND=180
export TZ=America/Los_Angeles

SO_LIB="$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)"
SO_START="${BIONIC_HOOKS_DIR}/session-start.sh"
SO_WALLS_HOOK="${BIONIC_HOOKS_DIR}/bash-walls.sh"
SO_WALLS="${STANDING_WALLS_UNDER_TEST:-$SO_LIB/walls.sh}"
SO_HOME="$TMPROOT/claude-home"; mkdir -p "$SO_HOME"
SO_DOOR=".bionic/docs/record/wave-01-fixture/handoff.md"
SO_ITEM1="hand test in progress | refuse: suite"
SO_ITEM2="no force-push while the user reviews"
SO_SUITE_CMD="tests/run.sh --only x.test.sh"

# ---------- fixture ----------
so_config() {  # <repo> <items, one per line, written as YAML list items verbatim> -> the config file
  local repo="$1" items="$2" it
  mkdir -p "$repo/.bionic"
  {
    printf 'poker-interval: 3600s\n'
    printf 'standing-orders:\n'
    while IFS= read -r it; do [ -n "$it" ] && printf '  - %s\n' "$it"; done <<< "$items"
    printf '  # a comment inside the list is not an order\n'
    printf 'other-list:\n  - not an order\n'
  } > "$repo/.bionic/config.yaml"
}

# ---------- drivers ----------
so_section() {  # <root> [key] -> config_section's answer, through lib/run.sh (which soft-sources roots.sh)
  bash -c '. "$1/run.sh" >/dev/null 2>&1 || exit 127; config_section "$2" "$3"' _ "$SO_LIB" "$1" "${2:-standing-orders}" 2>/dev/null
}
so_start() {  # <repo> <source> -> SO_OUT (session-start's stdout), SO_RC
  SO_OUT="$( cd "$1" && printf '{"session_id":"%s","transcript_path":"%s/t.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"%s"}' \
      "$SID" "$SO_HOME" "$1" "$2" \
    | CLAUDE_CODE_SESSION_ID="$SID" BIONIC_CLAUDE_HOME="$SO_HOME" CLAUDE_PLUGIN_ROOT= bash "$SO_START" 2>/dev/null )"
  SO_RC=$?
}
so_hook() {  # <repo> <command> -> SO_HOUT, SO_HERR, SO_HRC from hooks/bash-walls.sh on the main thread
  local input
  input="$(jq -n --arg s "$SID" --arg cwd "$1" --arg c "$2" '{session_id: $s, cwd: $cwd,
    hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}, tool_use_id: "toolu_t18"}')"
  SO_HOUT="$( cd "$1" && HOME="$SO_HOME" CLAUDE_PROJECT_DIR="" CLAUDE_CODE_SESSION_ID="$SID" \
    bash "$SO_WALLS_HOOK" <<< "$input" 2>"$TMPROOT/so-hook.err" )"
  SO_HRC=$?
  SO_HERR="$(cat "$TMPROOT/so-hook.err")"
}
so_refused() {  # -> yes when the last so_hook refused (exit 2, or a deny on the JSON wire)
  if [ "$SO_HRC" = 2 ] || [ "$(printf '%s' "$SO_HOUT" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)" = deny ]; then
    printf yes; else printf no; fi
}
so_wall() {  # <walls.sh> <command> <section> [root] -> SO_WRC, SO_WFACT, SO_WFIX: the predicate called alone
  local out
  out="$( cd "${4:-$TMPROOT}" && BIONIC_LIB="$SO_LIB" bash -c '
    . "$BIONIC_LIB/refuse.sh" && . "$BIONIC_LIB/fold.sh" && . "$BIONIC_LIB/run.sh" && . "$1" || exit 127
    BIONIC_ROOT="$PWD"
    declare -F wall_standing_orders >/dev/null 2>&1 || exit 126
    wall_standing_orders "$2" "$3"; rc=$?
    printf "rc=%s\nfact=%s\nfix=%s\n" "$rc" "${_BF_PEND_FACT:-}" "${_BF_PEND_FIX:-}"' _ "$1" "$2" "$3" 2>/dev/null )"
  SO_WRC="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"; [ -n "$SO_WRC" ] || SO_WRC="none"
  SO_WFACT="$(printf '%s\n' "$out" | sed -n 's/^fact=//p')"
  SO_WFIX="$(printf '%s\n' "$out" | sed -n 's/^fix=//p')"
}

# ---------- extractors ----------
so_start_items() { printf '%s\n' "$1" | awk 'index($0, "bionic: standing order — ") == 1 { print substr($0, length("bionic: standing order — ") + 1) }'; }
so_recap_items() { printf '%s\n' "$1" | awk 'index($0, "standing-order: ") == 1 { print substr($0, 17) }'; }
so_first() {  # <text> <prefix> -> the first line number starting with <prefix>, or '-'
  local n; n="$(printf '%s\n' "$1" | awk -v p="$2" 'index($0, p) == 1 { print NR; exit }')"; printf '%s' "${n:--}"
}
so_last() {  # <text> <prefix> -> the last line number starting with <prefix>, or '-'
  local n; n="$(printf '%s\n' "$1" | awk -v p="$2" 'index($0, p) == 1 { n = NR } END { if (n) print n }')"; printf '%s' "${n:--}"
}

# ============================================================
section "§PRINT: config_section returns both orders; session-start prints them; the recap repeats them (AC-7.1)"
# ============================================================
SO_R="$(make_repo so-print)"; ( cd "$SO_R" && git commit -q --allow-empty -m init )
git -C "$SO_R" config user.name "Dana Fixture"; git -C "$SO_R" config user.email d@example.com
SO_P="$(s42_plan "$SO_R" 4)"
so_config "$SO_R" "$SO_ITEM1
\"$SO_ITEM2\""
SO_WANT="$SO_ITEM1
$SO_ITEM2"
SO_SEC="$(so_section "$SO_R")"
expect_eq "P1 config_section <root> standing-orders returns both items, in config order, quotes stripped, the refuse: tail kept" \
  "$SO_WANT" "$SO_SEC"
expect_eq "P1b …and another list key is its own section (the reader stops at the next flush-left key)" \
  "not an order" "$(so_section "$SO_R" other-list)"
expect_eq "P2 a key the file does not carry: nothing (P1 read the same file)" "" "$(so_section "$SO_R" no-such-list)"
expect_eq "P2b no config at all: nothing" "" "$(so_section "$TMPROOT/nowhere")"

so_start "$SO_R" clear
SO_START_OUT="$SO_OUT"
expect_eq "P3 session-start on a clear, engaged and bound: exit 0" "0" "$SO_RC"
expect_contains "P3b …prints the first order" "bionic: standing order — $SO_ITEM1" "$SO_START_OUT"
expect_contains "P3c …and the second" "bionic: standing order — $SO_ITEM2" "$SO_START_OUT"
expect_eq "P3d …every order, once each, in config order" "$SO_WANT" "$(so_start_items "$SO_START_OUT")"
SO_BOUND_N="$(so_first "$SO_START_OUT" "bionic: bound to ")"
SO_ORDER_N="$(so_first "$SO_START_OUT" "bionic: standing order — ")"
SO_ARM_N="$(so_first "$SO_START_OUT" "re-arm: ")"
expect_nonempty "P3e precondition: the bound line and the arm line are read" "$SO_BOUND_N$SO_ARM_N"
expect_true "P3f the orders print after the bound line and before the arm line" \
  test "$SO_BOUND_N" != - -a "$SO_ORDER_N" != - -a "$SO_ARM_N" != - -a "$SO_BOUND_N" -lt "$SO_ORDER_N" -a "$SO_ORDER_N" -lt "$SO_ARM_N"
for SO_SRC in startup resume compact; do
  so_start "$SO_R" "$SO_SRC"
  expect_eq "P3.$SO_SRC …and on a $SO_SRC start too" "$SO_WANT" "$(so_start_items "$SO_OUT")"
done
unengage "$SO_R"
so_start "$SO_R" clear
expect_contains "P3g precondition: an unengaged session still gets its advice line" "bionic:" "$SO_OUT"
expect_eq "P3h …and no order line: the orders are an engaged session's (P3d read the same extractor)" "" "$(so_start_items "$SO_OUT")"
engage "$SO_R"; bound_marker "$SO_R" "$SID" "$SO_P" >/dev/null 2>&1

# The recap: the real handoff verb while bound, then the session made new, then the door.
poke "$SO_R" handoff --mid-flight 'T18 is writing its record'
expect_eq "P4.0 precondition: the handoff is written by the real verb while bound" "0" "$RC"
expect_eq "P4.0b precondition: …its last line is the door" "/bionic:canonical-sdlc $SO_DOOR" "$(tail -1 "$SO_R/$SO_DOOR" 2>/dev/null)"
engage "$SO_R"
rm -f "$(stamp_of "$SO_R")" "$(armed_of "$SO_R")" "$(digest_of "$SO_R")"
poke "$SO_R" resume "$SO_DOOR"
SO_RECAP="$OUT"
expect_eq "P4 resume <handoff.md> exits 0" "0" "$RC"
expect_contains "P4b the recap repeats the first order" "standing-order: $SO_ITEM1" "$SO_RECAP"
expect_contains "P4c …and the second" "standing-order: $SO_ITEM2" "$SO_RECAP"
expect_eq "P4d …every order, once each, in config order" "$SO_WANT" "$(so_recap_items "$SO_RECAP")"
SO_OWN_N="$(so_last "$SO_RECAP" "owned-by-user: ")"
SO_SO_N="$(so_first "$SO_RECAP" "standing-order: ")"
SO_BR_N="$(so_first "$SO_RECAP" "branch: ")"
expect_true "P4e …after the owned-by-user: lines and before branch:" \
  test "$SO_OWN_N" != - -a "$SO_SO_N" != - -a "$SO_BR_N" != - -a "$SO_OWN_N" -lt "$SO_SO_N" -a "$SO_SO_N" -lt "$SO_BR_N"

# An order naming a class no command has: session-start says so, once, beside the order.
SO_RB="$(make_repo so-badclass)"
so_config "$SO_RB" "the release is frozen | refuse: bogus"
so_start "$SO_RB" startup
expect_contains "P5 an order naming an unknown class still prints as an order" \
  "bionic: standing order — the release is frozen | refuse: bogus" "$SO_OUT"
expect_contains "P5b …followed by the config error line naming the class" \
  "bionic: standing order config error — refuse: bogus is not a command class" "$SO_OUT"
expect_eq "P5c …one error line" "1" "$(printf '%s\n' "$SO_OUT" | grep -c 'standing order config error')"
expect_eq "P5d a fixture of known classes prints no error line (P5b read the same extractor)" "0" \
  "$(printf '%s\n' "$SO_START_OUT" | grep -c 'standing order config error')"

# ============================================================
section "§THREE: one config fixture; the three surfaces print the same items"
# ============================================================
expect_nonempty "T1 precondition: the reader's list is non-empty" "$SO_SEC"
expect_eq "T2 session-start's block is the reader's list" "$SO_SEC" "$(so_start_items "$SO_START_OUT")"
expect_eq "T3 the recap is the reader's list" "$SO_SEC" "$(so_recap_items "$SO_RECAP")"

# ============================================================
section "§REFUSE: a refuse: suite order — the Bash wall refuses a suite run naming the order; the fact arrives from the preamble (AC-7.2)"
# ============================================================
SO_RF="$(make_repo so-refuse)"
so_config "$SO_RF" "$SO_ITEM1
$SO_ITEM2"
SO_RF_SEC="$(so_section "$SO_RF")"
expect_eq "R0 precondition: the lock's section reads" "$SO_WANT" "$SO_RF_SEC"

# The predicate alone, handed the section.
so_wall "$SO_WALLS" "$SO_SUITE_CMD" "$SO_RF_SEC" "$SO_RF"
expect_eq "R1 wall_standing_orders refuses tests/run.sh --only x.test.sh under the lock (rc 2)" "2" "$SO_WRC"
expect_eq "R1b …naming the order's text (the words before the |)" "standing order: hand test in progress" "$SO_WFACT"
expect_eq "R1c …and where it is lifted" "lift it in config.yaml" "$SO_WFIX"
so_wall "$SO_WALLS" "git status" "$SO_RF_SEC" "$SO_RF"
expect_eq "R2 git status passes under the same lock (rc 0)" "0" "$SO_WRC"
so_wall "$SO_WALLS" "$SO_SUITE_CMD" "$SO_ITEM2" "$SO_RF"
expect_eq "R3 an order without a refuse: tail refuses nothing" "0" "$SO_WRC"
so_wall "$SO_WALLS" "$SO_SUITE_CMD" "the release is frozen | refuse: bogus" "$SO_RF"
expect_eq "R4 an order naming an unknown class is enforced never" "0" "$SO_WRC"
so_wall "$SO_WALLS" "$SO_SUITE_CMD" "no installs today | refuse: install" "$SO_RF"
expect_eq "R4b an order refuses its own class only: a suite run passes a refuse: install lock" "0" "$SO_WRC"

# The hook: the section arrives from the preamble, read from config.yaml.
so_hook "$SO_RF" "$SO_SUITE_CMD"
expect_eq "R5 the Bash wall refuses tests/run.sh --only x.test.sh under the lock" "yes" "$(so_refused)"
expect_contains "R5b …with the order's refusal line" \
  "bionic: command refused — standing order: hand test in progress (lift it in config.yaml)" "$SO_HOUT$SO_HERR"
so_hook "$SO_RF" "git status"
expect_eq "R6 git status passes the hook under the lock (exit 0)" "0" "$SO_HRC"
expect_absent "R6b …and no standing order is named (R5b read the same streams)" "standing order:" "$SO_HOUT$SO_HERR"
so_config "$SO_RF" "$SO_ITEM2"
so_hook "$SO_RF" "$SO_SUITE_CMD"
expect_absent "R7 the lock lifted from config, the same suite run names no standing order" "standing order:" "$SO_HOUT$SO_HERR"
so_config "$SO_RF" "$SO_ITEM1
$SO_ITEM2"
expect_regex "R8 the preamble reads the section once, through config_section, and hands it in" \
  'WALL_STANDING_ORDERS="\$\(config_section "\$BIONIC_ROOT" standing-orders' "$(cat "$SO_WALLS_HOOK")"

# THE FREEZE PIN. The predicate handed an empty section, beside a config that holds the lock, refuses
# nothing: it reads only what it is handed.
so_wall "$SO_WALLS" "$SO_SUITE_CMD" "" "$SO_RF"
expect_eq "F1 the freeze: handed no section, the wall refuses nothing though config.yaml holds a lock" "0" "$SO_WRC"
SO_BODY="$(awk '/^wall_standing_orders\(\)/ { f = 1 } f { print } f && /^}/ { exit }' "$SO_WALLS")"
expect_contains "F2 precondition: the wall's body is read (it stages a refusal)" "fold_block" "$SO_BODY"
expect_no_regex "F2b …and it names no config reader, no root and reads no file by redirect" 'config_section|config_value|BIONIC_ROOT|BIONIC_CWD|(^|[^<])<[[:space:]]*["$/.]' "$SO_BODY"

# THE MUTANT: the same wall made to read config.yaml itself when its section is empty.
SO_MUT="$TMPROOT/walls-mutant.sh"
sed 's/^wall_standing_orders() {.*$/&\
  [ -n "${2:-}" ] || set -- "$1" "$(config_section "$BIONIC_ROOT" standing-orders)"/' "$SO_WALLS" > "$SO_MUT"
expect_eq "M0 precondition: the mutant differs from walls.sh by its one config read" "1" \
  "$(diff "$SO_WALLS" "$SO_MUT" | grep -c '^> .*config_section')"
so_wall "$SO_MUT" "git status" "$SO_RF_SEC" "$SO_RF"
expect_eq "M1 precondition: the mutant runs (git status passes it)" "0" "$SO_WRC"
so_wall "$SO_MUT" "$SO_SUITE_CMD" "$SO_RF_SEC" "$SO_RF"
expect_eq "M1b precondition: …and it refuses under a handed lock" "2" "$SO_WRC"
so_wall "$SO_MUT" "$SO_SUITE_CMD" "" "$SO_RF"
expect_eq "M2 the mutant flips the freeze pin: handed no section, it refuses from config.yaml (F1 reads 0)" "2" "$SO_WRC"

finish
