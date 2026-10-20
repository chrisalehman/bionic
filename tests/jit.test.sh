#!/bin/bash
# JIT / DEGRADATION — epic-17 wave-03 task S10 (spec AC-5).
#
# WHAT THIS SUITE OWNS. payload/scripts/lib/jit.sh: the route-facing
# degradation contract — jit_check (presence + named fix) and jit_offer
# (states the offer, asks ONE consented question via deps.sh's install_dep,
# degrades cleanly on decline).
#
# THE OWNERSHIP-TABLE AGREEMENT (wave-03 spec §Design, "per-dep install" row):
# jit_offer must not grow a private second installer. It has to call install_dep
# BY NAME so the setup loop and a route's JIT offer always reach the identical
# function. Group 3 below proves that dynamically: it OVERRIDES install_dep
# with a recorder stub AFTER sourcing jit.sh and BEFORE calling jit_offer —
# bash resolves a function call by name at call time, so if jit_offer's "yes"
# path lands in the override, jit_offer contains no private copy of the
# install logic.
#
# HERMETIC, same regime tests/plugin-lib.test.sh used to run (deleted at
# 8582861, epic-18 wave-03): no network, no live
# ~/.claude, PATH replaced outright with a controlled bin dir (real coreutils
# symlinked in, everything else a recorder stub).
#
# Usage: bash tests/jit.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
JIT_SH="${REPO}/payload/scripts/lib/jit.sh"
DEPS_SH="${REPO}/payload/scripts/lib/deps.sh"

# expect_eq, expect_true, expect_false, expect_match, expect_empty are the
# framework's (tests/lib/assert.sh) — identical semantics to the private
# definitions this suite carried (same argument order, same glob match for
# expect_match, same silencing for expect_true/expect_false) (S7, AC-12).

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders (mirrored tests/plugin-lib.test.sh, deleted at 8582861, epic-18 wave-03)
# ---------------------------------------------------------------------------

make_stub() {  # <bindir> <name> [exit-code]
  local bindir="$1" name="$2" rc="${3:-0}"
  mkdir -p "$bindir"
  cat > "${bindir}/${name}" <<STUB
#!/bin/bash
echo "${name} \$*" >> "\$BIONIC_TEST_CALLS"
exit ${rc}
STUB
  chmod +x "${bindir}/${name}"
}

BASE_BIN="$TMP/base-bin"
mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls dirname basename tr head tail sort uniq wc jq python3; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

mkdir -p "$TMP/home"
CALLS="$TMP/calls.log"; : > "$CALLS"

# jit_run <env-assignments...> -- <function> [args]   — sources jit.sh (which
# sources deps.sh itself), then runs one function in a fresh bash.
jit_run() {
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift  # drop --
  env -i \
    HOME="$TMP/home" \
    PATH="$BASE_BIN" \
    BIONIC_TEST_CALLS="$CALLS" \
    "${envs[@]}" \
    bash -c '. "$1"; shift; "$@"' _ "$JIT_SH" "$@" 2>&1
}

PRESENT_BIN="$TMP/present-bin"
cp -R "$BASE_BIN/." "$PRESENT_BIN/" 2>/dev/null || { mkdir -p "$PRESENT_BIN"; cp -R "$BASE_BIN/." "$PRESENT_BIN/"; }
make_stub "$PRESENT_BIN" rg
make_stub "$PRESENT_BIN" npm
make_stub "$PRESENT_BIN" brew

section "Group 1: jit.sh exists, sources cleanly, passes bash -n"

# (file-exists fixture check removed epic-18 W3 4/6: no production subject -- see ledger-jit.md)
expect_true "jit.sh sources without error" bash -c '. "$1"' _ "$JIT_SH"
expect_true "jit.sh passes bash -n" bash -n "$JIT_SH"
expect_true "jit.sh sourcing defines jit_check" \
  bash -c '. "$1"; declare -F jit_check' _ "$JIT_SH"
expect_true "jit.sh sourcing defines jit_offer" \
  bash -c '. "$1"; declare -F jit_offer' _ "$JIT_SH"
expect_true "sourcing jit.sh also pulls in deps.sh's check_dep (self-source guard)" \
  bash -c '. "$1"; declare -F check_dep' _ "$JIT_SH"

section "Group 2: jit_check — both arms"

expect_true "jit_check rg: present on PATH -> exit 0" \
  bash -c 'env -i HOME="$1" PATH="$2" bash -c ". \"\$1\"; jit_check rg" _ "$3"' _ "$TMP/home" "$PRESENT_BIN" "$JIT_SH"

ABSENT_OUT="$(jit_run PATH="$BASE_BIN" -- jit_check rg)"; ABSENT_RC=$?
expect_true "jit_check rg: absent from PATH -> exit 1" test "$ABSENT_RC" -ne 0


expect_false "jit_check on an unknown dep exits non-zero" \
  bash -c '. "$1"; jit_check no-such-dep' _ "$JIT_SH"

section "Group 3: the ownership-table agreement — jit_offer calls install_dep BY NAME"
#
# Override install_dep AFTER sourcing jit.sh, BEFORE calling jit_offer. If
# jit_offer's "yes" path reaches the override, it has no private installer —
# it dispatches to whatever function is bound to that name, which in
# production is deps.sh's own single mutating entry point.

TRACE="$TMP/install-dep-trace.log"; : > "$TRACE"
env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_TEST_TRACE="$TRACE" \
  bash -c '
    . "$1"
    install_dep() { echo "install_dep-override $*" >> "$BIONIC_TEST_TRACE"; return 0; }
    echo y | jit_offer rg some-route "a capability" "it degrades"
  ' _ "$JIT_SH" >/dev/null 2>&1
expect_match "jit_offer(yes) reaches the function literally named install_dep" \
  "*install_dep-override rg*" "$(cat "$TRACE")"

section "Group 4: jit_offer — consent path invokes the real install_dep (production behavior)"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; jit_offer rg some-route "fast search" "grep is used instead"; }' \
  _ "$JIT_SH" >/dev/null 2>&1
expect_match "jit_offer(yes) drives the real brew install (via install_dep)" \
  "*brew install ripgrep*" "$(cat "$CALLS")"


section "Group 5: jit_offer — declined path (AC-5's clean-degrade half)"

: > "$CALLS"
DECLINE_ERR="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null' _ "$JIT_SH" 2>&1 1>/dev/null)"
: > "$CALLS"
DECLINE_RC="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null; echo $?' _ "$JIT_SH" 2>/dev/null | tail -1)"

expect_true "jit_offer(decline, no stdin answer) returns non-zero" test "$DECLINE_RC" -ne 0
expect_empty "jit_offer(decline) writes nothing to stderr (no cryptic failure)" "$DECLINE_ERR"
expect_eq "jit_offer(decline) ran nothing (recorder empty — no mutation)" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"

# Explicit "n" — the other spelling of decline.
: > "$CALLS"
DECLINE_N_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo n | { . "$1"; jit_offer rg some-route "fast search" "grep is used instead"; }' _ "$JIT_SH" 2>&1)"
expect_eq "jit_offer(explicit n) ran nothing" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

section "Group 6: no assume-yes knob (S1-8 stands)"
#
# jit.sh must not grow an env-var bypass around consent — the same rule
# tests/plugin-lib.test.sh used to pin for install_dep itself; that suite was
# deleted at 8582861 (epic-18 wave-03) and nothing replaced the pin there.

# Matches an actual env-var-shaped bypass token (BIONIC_..._YES, ASSUME_YES=,
# etc.) — not this file's own prose ("no assume-yes knob"), which is
# lowercase-hyphenated and would false-positive a looser pattern.
expect_true "jit.sh source carries no assume-yes / auto-yes env-var bypass" \
  bash -c '! grep -qE "[A-Z_]*_(ASSUME|AUTO)_?YES|(ASSUME|AUTO)_?YES[A-Z_]*=" "$1"' _ "$JIT_SH"
expect_true "jit.sh reads stdin only through install_dep (no private read of its own)" \
  bash -c '! grep -qE "^[[:space:]]*read " "$1"' _ "$JIT_SH"

section "Group 7: mutation-and-restore — decline mutates NOTHING, proven twice, two mechanisms"
#
# Two independent fixture roots, two different install mechanisms (brew-dep
# and npm-global), fingerprinted before/after a decline each. A single proof
# could coincidentally hold for one mechanism's code path and not the other.

fingerprint() { find "$1" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $5, $9}' | sort; }

# Mutation-and-restore #1: rg (brew-dep).
FP1_ROOT="$TMP/fp1"; mkdir -p "$FP1_ROOT"; cp -R "$PRESENT_BIN/." "$FP1_ROOT/bin/" 2>/dev/null || { mkdir -p "$FP1_ROOT/bin"; cp -R "$PRESENT_BIN/." "$FP1_ROOT/bin/"; }
: > "$CALLS"
FP1_BEFORE="$(fingerprint "$FP1_ROOT")"
env -i HOME="$TMP/home" PATH="$FP1_ROOT/bin" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer rg some-route "fast search" "grep is used instead" </dev/null' _ "$JIT_SH" >/dev/null 2>&1
FP1_AFTER="$(fingerprint "$FP1_ROOT")"
expect_eq "mutation-and-restore #1: recorder log still empty" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

# Mutation-and-restore #2: @playwright/cli (npm-global) — the canonical
# environment-class dep this task was scoped around.
FP2_ROOT="$TMP/fp2"; mkdir -p "$FP2_ROOT"; cp -R "$PRESENT_BIN/." "$FP2_ROOT/bin/" 2>/dev/null || { mkdir -p "$FP2_ROOT/bin"; cp -R "$PRESENT_BIN/." "$FP2_ROOT/bin/"; }
: > "$CALLS"
FP2_BEFORE="$(fingerprint "$FP2_ROOT")"
env -i HOME="$TMP/home" PATH="$FP2_ROOT/bin" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer @playwright/cli browser-verify "browser driving" "T2/T3 rows are blocked, not silently skipped" </dev/null' \
  _ "$JIT_SH" >/dev/null 2>&1
FP2_AFTER="$(fingerprint "$FP2_ROOT")"
expect_eq "mutation-and-restore #2: recorder log still empty" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

section "Group 8: jit_check absence-vs-presence, driven against @playwright/cli too"

expect_true "jit_check @playwright/cli: present -> exit 0" \
  bash -c 'env -i HOME="$1" PATH="$2" BIONIC_TEST_CALLS="$3" bash -c ". \"\$1\"; jit_check @playwright/cli" _ "$4"' \
  _ "$TMP/home" "$PRESENT_BIN" "$CALLS" "$JIT_SH"
PW_ABSENT_OUT="$(jit_run PATH="$BASE_BIN" -- jit_check @playwright/cli)"; PW_ABSENT_RC=$?
expect_true "jit_check @playwright/cli: absent -> exit 1" test "$PW_ABSENT_RC" -ne 0
expect_match "jit_check @playwright/cli absent: names a fix (npm install -g)" \
  "*npm install -g @playwright/cli*" "$PW_ABSENT_OUT"

#
# S2's dispatch-paragraph precedent: name the contract, let the script bind —
# no restated mechanics. One sentence each, at the point an environment-class
# dependency is assumed.

# wave-11-lean-spine 1b split canonical-sdlc's SKILL.md into a core plus per-step files;
# jit_check/jit_offer moved with Step 5's prose, so this group reads steps/5.md rather than
# a single whole-skill path. Group 12 below reads a second split surface, steps/0.md.
CANONICAL_SKILL_STEP5="${REPO}/skills/canonical-sdlc/steps/5.md"
BROWSER_SKILL="${REPO}/skills/browser-verify/SKILL.md"
EXCALIDRAW_SKILL="${REPO}/payload/skills/excalidraw-diagram/SKILL.md"


section "Group 9b: the native when-needed row — ONE question, ONE installer (AC-11)"
#
# THE RULING THIS PINS (plan A-4.S4.4-RULING). `impeccable` is `when-needed` AND
# `native`: the moment to install it is the moment the design route asks, and
# `install_dep` refuses every native row by design. S4 resolved that by printing
# a command and asking nothing, which narrowed AC-11's "one question at the
# moment of need" for exactly one row. The ruling put the fix at the layer it
# lives instead — ONE native-plugin installer in deps.sh, called by BOTH setup's
# first step and this offer — so AC-11 holds literally and jit.sh is still not a
# second installer. This group asserts all three halves: the question is asked,
# the CLI is what installs, and the function reached is deps.sh's by NAME.
#
# The offer still returns NON-ZERO on a successful install, and that is not a
# leftover: a plugin the CLI installed mid-session is not loaded into the
# session that asked for it until the plugins are re-read. Telling the route
# "you have it now" would be the one lie this contract exists to prevent.

NATIVE_BIN="$TMP/native-bin"; mkdir -p "$NATIVE_BIN"
cp -R "$PRESENT_BIN/." "$NATIVE_BIN/"
make_stub "$NATIVE_BIN" claude

: > "$CALLS"
NATIVE_YES_OUT="$(env -i HOME="$TMP/home" PATH="$NATIVE_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; jit_offer impeccable design-route "design work" "the route continues without it"; }' \
  _ "$JIT_SH" 2>&1)"
expect_match "native row (yes): the install reaches the CLI, scoped to the marketplace id" \
  "*plugin install impeccable@bionic*" "$(cat "$CALLS")"

NATIVE_YES_RC="$(env -i HOME="$TMP/home" PATH="$NATIVE_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; jit_offer impeccable design-route "design work" "the route continues without it"; }; echo $?' \
  _ "$JIT_SH" 2>/dev/null | tail -1)"
expect_true "native row (yes): returns non-zero — installed is not loaded in THIS session" \
  test "$NATIVE_YES_RC" -ne 0

: > "$CALLS"
NATIVE_NO_OUT="$(env -i HOME="$TMP/home" PATH="$NATIVE_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; jit_offer impeccable design-route "design work" "the route continues without it" </dev/null' \
  _ "$JIT_SH" 2>&1)"
expect_eq "native row (decline): nothing ran — no install, no CLI call" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"

# The ownership agreement, the same way Group 3 proves it for install_dep:
# override the installer AFTER sourcing and watch the yes path land in it.
NATIVE_TRACE="$TMP/native-installer-trace.log"; : > "$NATIVE_TRACE"
env -i HOME="$TMP/home" PATH="$NATIVE_BIN" BIONIC_TEST_TRACE="$NATIVE_TRACE" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '
    . "$1"
    install_plugin_native() { echo "install_plugin_native-override $*" >> "$BIONIC_TEST_TRACE"; return 0; }
    echo y | jit_offer impeccable design-route "design work" "it degrades"
  ' _ "$JIT_SH" >/dev/null 2>&1
expect_match "jit_offer reaches the function literally named install_plugin_native" \
  "*install_plugin_native-override impeccable*" "$(cat "$NATIVE_TRACE")"

# deps.sh keeps its refusal: the shared installer is a SIBLING of install_dep,
# not a way in through it. If this ever passed, the kludge D1 rejected would be
# back and the refusal would be decoration.

section "Group 12: Step-0 model_plan derivation is mechanical, not invented (epic-19 F1)"
#
# AC-F1: the orchestrator reads agents/*.md frontmatter for the six dispatched-role
# tiers; the confirmation display cites each line's source. Before this fix the whole
# derivation rule was "model_plan from multi_agent and the detected session model" —
# no route to the role files existed anywhere in the skill (grounding:
# .bionic/docs/record/epic-19/step1-fixes-grounding.md §1). wave-11-lean-spine 1b moved
# Step 0's prose, this sentence included, into steps/0.md — this group now reads that file
# rather than a whole-skill path; it remains the one place in the roster already set up to
# pin literal prose spans of the Step-0 card.
CANONICAL_SKILL_STEP0="${REPO}/skills/canonical-sdlc/steps/0.md"

# RE-POINTED (epic-22 K1, plan task 15, A-7). K1's Step-0 settings card drops per-line
# inference rationale — the six "role-file default: agents/<role>.md" annotations that used
# to sit beside each model value are gone; that string no longer appears anywhere in
# SKILL.md, so the old grep -c over the whole file now finds 0 by design, not by defect. The
# provenance sentence stays put (still pinned two assertions above, "rendered role files")
# and is stated ONCE rather than six times; what this assertion re-points to is the fact the
# AC actually cares about — that all six dispatched-role tiers are still named, one per line,
# in the card's Models section (record/wave-01-plugin-only/design-ledger.md §D1).
#
# RE-POINTED (wave-27 T11, D6): was a count of six role lines, which a seventh role turned red
# for no defect. A relation now, naming no count (.claude/rules/test-harness.md): every role
# render.sh renders has its rendered file and its line in the card's Models section.
#
# RE-POINTED (wave-39 T26; D3, AC-20.1): the Step-0 card is its own stop again, rendered by `card.sh
# step0` from the plan's frontmatter (wave 38 had folded it into the Step 1 card), so the Models block is
# read from that rendering, over a plan whose model_plan names the orchestrator alone: each role then has
# its line from its role file, and a role render.sh renders without a line is named.
# models_missing <roles> <card> -> each role with no line of its own in the Step-0 card's Models block.
models_missing() {
  local role block
  block="$(printf '%s\n' "$2" | sed -n '/^  Models$/,/^$/p')"
  for role in $1; do
    printf '%s\n' "$block" | grep -qE "^    ${role}([[:space:]]|\$)" || printf '%s\n' "$role"
  done
  return 0
}
JIT_PLAN="$TMP/wave-1-models.plan.md"
printf '%s\n' '---' 'scale: wave' 'rigor: double' 'model_plan: orchestrator=claude-fable-5-1' '---' '' \
  '## Goal' '' 'Render the Models block.' > "$JIT_PLAN"
JIT_CARD="$(bash "${REPO}/payload/scripts/card.sh" step0 "$JIT_PLAN" 2>/dev/null 0<&-)"
JIT_ROLES="$(sed -n 's/^ROLES="\(.*\)"$/\1/p' "${REPO}/agents-src/render.sh")"
expect_nonempty "canonical-sdlc: render.sh declares its ROLES (the relation below reads a set)" "$JIT_ROLES"
expect_true "card.sh step0: the card carries a Models block (the extractor reads something)" \
  grep -qx '  Models' <<< "$JIT_CARD"
for role in $JIT_ROLES; do
  expect_true "canonical-sdlc: role \`${role}\` has its rendered file agents/${role}.md" \
    test -f "${REPO}/agents/${role}.md"
done
expect_eq "card.sh step0: every role render.sh renders has its line in the Step-0 card's Models block" \
  "" "$(models_missing "$JIT_ROLES" "$JIT_CARD")"
expect_eq "card.sh step0: a planted role with no Models line is named (the relation discriminates)" \
  "planted" "$(models_missing "planted" "$JIT_CARD")"

section "Group 13: README roster table agrees with agents/*.md frontmatter (epic-19 F9)"
#
# AC-F9: README.md's roster table (step1-model-surfaces.md §6) is the one copy render.sh's
# AGENT-ROSTER directive does not reach — it is hand-written and had already drifted
# (researcher/test-runner both wrong). This pin reads the model value FROM each role file's
# own frontmatter and checks README's row for the SAME role names it — never a restated
# literal here — so a future role-file change and a stale README both go red without
# touching this test.

README="${REPO}/README.md"
AGENTS_DIR="${REPO}/agents"

for role in $JIT_ROLES; do
  role_file="${AGENTS_DIR}/${role}.md"
  model_raw="$(awk -F': *' '/^model:/ { print $2; exit }' "$role_file")"
  model_title="$(printf '%s' "$model_raw" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }')"
  readme_row="$(grep "| \`${role}\` " "$README")"
  # Both reads non-empty first: an empty model makes the glob below `**`, which matches anything.
  expect_nonempty "README roster table: agents/${role}.md declares a model" "$model_raw"
done

finish
