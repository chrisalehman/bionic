#!/bin/bash
# SETUP — epic-17 wave-03 slice S6 (spec AC-2, AC-6; design boundaries:
# "all machine mutation behind consent lives in scripts").
#
# WHAT THIS SUITE OWNS. payload/scripts/setup.sh — the whole of `/bionic:setup`:
# the native plugin install wrapper, core enable-verify, the bionic-installed
# loop, the shell-rc export, the two ported bootstrap obligations (legacy alias
# block, legacy-channel managed-hook entries), the consented permission-profile apply,
# and the end summary. It also owns payload/commands/setup.md's existence and
# its one structural rule that command-format.test.sh cannot state (the wrapper
# adds no logic — it invokes the script and nothing else).
#
# WHAT IT DOES NOT OWN. The libraries setup consumes. deps.sh's table, its
# per-dep install functions and their consent gate are pinned by
# tests/plugin-lib.test.sh; profile.sh's render/apply/strip/diff by
# tests/profile.test.sh. This suite asserts that setup CALLS them and that the
# call carries consent — never that they work, which is already proven.
#
# HERMETIC, AND WHAT THAT COSTS. No network, no live `claude`, no live
# ~/.claude, no brew/npm/uv. Every root setup reads is handed over by env var
# and points into a per-arm fixture tree; PATH is REPLACED (not prefixed) by a
# bin dir this suite builds, so a real brew on this machine can never be
# reached by accident. The `claude` shim is a STATEFUL fake — `plugin install`
# writes a state file that `plugin list --json` reads back — because a
# stateless stub would make the idempotence arm vacuous: setup would re-install
# forever and the arm would still pass.
#
# The shims are not a seam that substitutes the value under test. setup calls
# the real `command -v`, the real `claude`, the real `install_dep`; what
# changes is which directory PATH resolves them in. The evidence considered is
# the recorder file the shims append to and the bytes of the fixture tree —
# never a dry-run flag the production path would never set.
#
# FIXTURE FIDELITY. The legacy alias-block fixtures used to be DERIVED at run
# time from claude-bootstrap.sh's own ALIAS_START/ALIAS_END/ALIAS_CONTENT
# assignments. That installer retired at epic-17 W5 (4/6), and the only
# remaining copies of those markers are the ones under test — deriving from
# them would be a fixture that changes whenever the thing it checks changes.
# So Group 6 now STATES the markers and pins all three production copies
# (setup.sh, detect.sh, remove.sh) against that statement. The
# legacy-channel-hook settings fixture keeps the settings.json shape the
# retired installer used to write (matcher + hooks[].command + timeout) —
# that shape is Claude Code's, not the installer's, and did not retire with
# it.
#
# BOTH ARMS, ALWAYS. Every mutating step is asserted in its consented AND its
# declined form, and the declined form is proven by bytes (the fixture tree is
# fingerprinted before and after), not by an absent log line.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh): containment is bash `[[ == * ]]`
# in-process, and grep runs against FILE arguments only.
#
# Usage: bash tests/setup.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SETUP_SH="${REPO}/payload/scripts/setup.sh"
SETUP_MD="${REPO}/payload/commands/setup.md"
LIB_DIR="${REPO}/payload/scripts/lib"
TEMPLATE="${REPO}/payload/permissions/profile.template.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq()    { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "no match for '$pattern' in: $(printf '%.400s' "$actual")"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "unexpected match for '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# The bin dir: real tools setup legitimately needs, plus recording shims.
# ---------------------------------------------------------------------------

BIN="$TMP/bin"; mkdir -p "$BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod stat ls tr head tail sort uniq wc \
            jq mktemp find xargs shasum uname date touch diff printf true false; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BIN}/${real}" 2>/dev/null
done

# A bin dir with everything above EXCEPT jq — the honest-unknown arms.
NOJQ_BIN="$TMP/bin-nojq"; mkdir -p "$NOJQ_BIN"
for f in "$BIN"/*; do
  case "${f##*/}" in jq) continue ;; esac
  ln -sf "$(readlink "$f" 2>/dev/null || echo "$f")" "${NOJQ_BIN}/${f##*/}" 2>/dev/null
done

CALLS="$TMP/calls.log"; : > "$CALLS"
STATE="$TMP/cli-state"; mkdir -p "$STATE"   # OUTSIDE any fixture tree: not fingerprinted
TMPDIR_FIX="$TMP/tmpdir"; mkdir -p "$TMPDIR_FIX"

# A plain recorder: appends its argv and exits 0.
make_stub() {  # <name> [exit-code]
  local name="$1" rc="${2:-0}"
  cat > "${BIN}/${name}" <<STUB
#!/bin/bash
echo "${name} \$*" >> "\$BIONIC_TEST_CALLS"
exit ${rc}
STUB
  chmod +x "${BIN}/${name}"
  ln -sf "${BIN}/${name}" "${NOJQ_BIN}/${name}" 2>/dev/null
}

# The stateful `claude` fake. \$BIONIC_TEST_STATE/plugins holds one
# `<id> <enabled>` line per installed plugin; install appends, enable flips the
# flag, and `plugin list --json` renders the file. That is what makes "run it
# twice and the second run is a no-op" a real assertion rather than a tautology.
cat > "${BIN}/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$BIONIC_TEST_CALLS"
STATE_FILE="${BIONIC_TEST_STATE}/plugins"
[ -f "$STATE_FILE" ] || : > "$STATE_FILE"
case "${1:-}" in
  plugin|plugins)
    case "${2:-}" in
      list)
        # TWO SHAPES, ONE STATE FILE. `--json` is what setup's own
        # `_setup_cli_plugin` asks for; the BARE listing is what the CLI prints
        # to a human and what the load-state probe parses (plan A-4.S2.1: one
        # indented BLOCK per plugin, measured on this machine 2026-08-20, not
        # the one-line reflow W5's report shows). Rendering both from the same
        # state file is what keeps "installed" and "loaded" the same fixture's
        # answer rather than two independent fictions.
        case " $* " in
          *" --json "*)
            sep=""; printf '['
            while read -r id en; do
              [ -n "$id" ] || continue
              printf '%s{"id":"%s","version":"0.1.0","scope":"user","enabled":%s}' "$sep" "$id" "$en"
              sep=","
            done < "$STATE_FILE"
            printf ']\n'
            ;;
          *)
            printf 'Installed plugins:\n\n'
            while read -r id en; do
              [ -n "$id" ] || continue
              if [ "$en" = "true" ]; then st='✔ enabled'; else st='✘ not enabled'; fi
              printf '  ❯ %s\n    Version: 0.1.0\n    Scope: user\n    Status: %s\n\n' "$id" "$st"
            done < "$STATE_FILE"
            ;;
        esac
        exit 0 ;;
      install)
        id=""
        for a in "$@"; do case "$a" in *@*) id="$a"; break ;; esac; done
        [ -n "$id" ] || exit 1
        grep -q "^${id} " "$STATE_FILE" 2>/dev/null || echo "${id} true" >> "$STATE_FILE"
        exit 0 ;;
      enable)
        id=""
        for a in "$@"; do case "$a" in *@*) id="$a"; break ;; esac; done
        [ -n "$id" ] || exit 1
        awk -v id="$id" '{ if ($1 == id) print $1, "true"; else print }' "$STATE_FILE" > "${STATE_FILE}.tmp" \
          && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        exit 0 ;;
    esac
    exit 1 ;;
  mcp)
    case "${2:-}" in get) exit 1 ;; esac
    exit 0 ;;
esac
exit 0
STUB
chmod +x "${BIN}/claude"
ln -sf "${BIN}/claude" "${NOJQ_BIN}/claude" 2>/dev/null

for s in brew npx uv pnpm; do make_stub "$s"; done

# npm needs one behavioural detail the plain recorder cannot fake: real
# `npm list -g --depth=0 <pkg>` exits NON-ZERO when the package is absent, and
# that exit code is what deps.sh reads as "not installed". A recorder that
# exits 0 with empty output would report every npm package as PRESENT and
# quietly skip the arm that proves the npm rows install at all.
cat > "${BIN}/npm" <<'STUB'
#!/bin/bash
echo "npm $*" >> "$BIONIC_TEST_CALLS"
case "${1:-}" in list) exit 1 ;; esac
exit 0
STUB
chmod +x "${BIN}/npm"
ln -sf "${BIN}/npm" "${NOJQ_BIN}/npm" 2>/dev/null

# ---------------------------------------------------------------------------
# Fixture builder. One tree per arm; every root setup reads points into it.
# ---------------------------------------------------------------------------

FIX=""
new_fixture() {  # <name>
  FIX="$TMP/fix-$1"
  rm -rf "$FIX"
  mkdir -p "$FIX/home" "$FIX/ch/plugins" "$FIX/root/.claude-plugin" "$FIX/root/hooks"
  printf '%s\n' '{"version":"0.1.0","name":"bionic"}' > "$FIX/root/.claude-plugin/plugin.json"
  printf '%s' '{}' > "$FIX/ch/settings.json"
  printf '%s\n' '{"version":2,"plugins":{}}' > "$FIX/ch/plugins/installed_plugins.json"
  printf 'export PATH="$HOME/bin:$PATH"\n' > "$FIX/rc"
  : > "$STATE/plugins"
  : > "$CALLS"
}

# `<name>@<marketplace>` rows in the CLI fake's state.
plant_cli_plugin() {  # <id> <enabled>
  grep -q "^$1 " "$STATE/plugins" 2>/dev/null || echo "$1 $2" >> "$STATE/plugins"
}

# A core row in the registry file check_dep reads.
plant_installed() {  # <key> <version>
  local key="$1" ver="$2" tmp="$FIX/ch/plugins/installed_plugins.json.tmp"
  jq --arg k "$key" --arg v "$ver" \
    '.plugins[$k] = [{"scope":"user","installPath":("/fixture/" + $k),"version":$v}]' \
    "$FIX/ch/plugins/installed_plugins.json" > "$tmp" && mv "$tmp" "$FIX/ch/plugins/installed_plugins.json"
}

run_setup() {  # <answers> [extra env assignments...] — stdout+stderr of one setup run
  local answers="$1"; shift
  local script="${SETUP_UNDER_TEST:-$SETUP_SH}"
  printf '%s' "$answers" | env -i \
    HOME="$FIX/home" \
    PATH="${SETUP_PATH:-$BIN}" \
    TMPDIR="$TMPDIR_FIX" \
    BIONIC_TEST_CALLS="$CALLS" \
    BIONIC_TEST_STATE="$STATE" \
    BIONIC_LIB_DIR="$LIB_DIR" \
    BIONIC_PLUGIN_ROOT="$FIX/root" \
    BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
    BIONIC_CLAUDE_HOME="$FIX/ch" \
    BIONIC_SETTINGS_FILE="$FIX/ch/settings.json" \
    BIONIC_INSTALLED_PLUGINS_FILE="$FIX/ch/plugins/installed_plugins.json" \
    BIONIC_SHELL_RC="$FIX/rc" \
    "$@" bash "$script" 2>&1
}

YES="$(for _ in $(seq 1 60); do printf 'y\n'; done)"
NO="$(for _ in $(seq 1 60); do printf 'n\n'; done)"

# Byte fingerprint of a whole fixture tree — the only evidence a "declined"
# or "idempotent" claim is allowed to rest on.
fingerprint() {  # <dir>
  find "$1" -type f | sort | xargs shasum -a 256 2>/dev/null | sed "s|$1||"
}

lib_query() {  # <lib> <function> [args] — read one fact back out of the fixture
  local lib="$1"; shift
  env -i HOME="$FIX/home" PATH="$BIN" \
    BIONIC_PLUGIN_ROOT="$FIX/root" BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
    BIONIC_CLAUDE_HOME="$FIX/ch" BIONIC_SETTINGS_FILE="$FIX/ch/settings.json" \
    BIONIC_INSTALLED_PLUGINS_FILE="$FIX/ch/plugins/installed_plugins.json" \
    BIONIC_SHELL_RC="$FIX/rc" \
    bash -c '. "$1"; shift; "$@"' _ "$lib" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Group 1 — the artifacts exist and are well formed.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 1: artifacts ==="

expect_true "payload/scripts/setup.sh exists" test -f "$SETUP_SH"
expect_true "setup.sh parses (bash -n)" bash -n "$SETUP_SH"
expect_true "payload/commands/setup.md exists" test -f "$SETUP_MD"

if [ -f "$SETUP_MD" ]; then
  SETUP_MD_TEXT="$(cat "$SETUP_MD")"
  expect_match "setup.md invokes the script via the literal \${CLAUDE_PLUGIN_ROOT}" \
    '*${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh*' "$SETUP_MD_TEXT"
  expect_match "setup.md carries a frontmatter description" '*description:*' "$SETUP_MD_TEXT"
  # The wrapper adds no logic: the only shell it names is the one invocation.
  wrapper_cmds="$(grep -cE '^[[:space:]]*(bash|sh|claude|jq|npm|brew) ' "$SETUP_MD" 2>/dev/null | tr -d ' ')"
  expect_eq "setup.md is a wrapper — exactly one command line, no second mechanism" "1" "$wrapper_cmds"
fi

# ---------------------------------------------------------------------------
# Group 2 — (a) the native plugin install wrapper, tier 2 ⊃ tier 1.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 2: native plugin install wrapper (AC-2, tier 2 wraps tier 1) ==="

new_fixture install-fresh
OUT="$(run_setup "$YES")"
expect_match "fresh machine: setup names the install it would run before asking" \
  '*claude plugin install bionic@bionic*' "$OUT"
expect_match "fresh machine: consented install reaches the CLI" \
  '*plugin install bionic@bionic*' "$(cat "$CALLS")"

new_fixture install-already
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
expect_match "already installed: setup says so" '*already installed*' "$OUT"
expect_no_match "already installed: no second install call" '*plugin install bionic@bionic*' "$(cat "$CALLS")"

new_fixture install-declined
OUT="$(run_setup "$NO")"
expect_no_match "declined install: nothing reached the CLI" '*plugin install bionic@bionic*' "$(cat "$CALLS")"
expect_match "declined install: named in the end summary as an action" '*claude plugin install bionic@bionic*' "$OUT"

new_fixture install-nojq
OUT="$(SETUP_PATH="$NOJQ_BIN" run_setup "$YES")"
expect_match "no jq: install state is reported unknown, never a confident answer" '*unknown*' "$OUT"
expect_match "no jq: the summary names jq as the fix" '*jq*' "$OUT"

# ---------------------------------------------------------------------------
# Group 2b — AC-13's setup half: is the CLI actually LOADING us?
#
# THE FAILURE THIS EXISTS FOR (epic-17 W5, F12). `claude plugin install` exits 0,
# prints a success line, writes the registry — and if a dependency is missing the
# plugin loads NOTHING. Every registry-reading fact stays green. The only surface
# that says so is the CLI's own listing, which is why setup reports it right after
# the install step rather than trusting the step's own exit code.
#
# The healthy arm is driven through the stateful `claude` fake (installed by
# setup's own step 1, then read back), so "loaded" is the fixture's answer to a
# real question. The dep-broken arm cannot be made on a live machine mid-wave
# (plan A-0.3), so it is driven through `BIONIC_PLUGIN_LIST_CMD` at the seam
# detect.sh publishes for exactly this, pointed at the captured listing S2
# fixtured — the Error line in it is verbatim from the W5 measurement.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 2b: load state reported after the install step (AC-13, setup half) ==="

LIST_DEP_BROKEN="${REPO}/tests/fixtures/plugin-list-dep-broken.txt"
expect_true "the dep-broken listing fixture exists" test -f "$LIST_DEP_BROKEN"

new_fixture loadstate-healthy
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_match "healthy machine: setup says bionic is loaded" '*bionic: loaded*' "$OUT"
expect_no_match "healthy machine: no error text about loading" '*did not load*' "$OUT"

# The load-state line belongs to the install step, not to the dependencies step:
# it is a fact about the install that just happened. Asserted by ORDER against
# the next step's header, which is the only delimiter the user can see.
LOAD_BEFORE_DEPS="$(awk '/bionic: loaded/ { seen = 1 } /^2\. Dependencies/ { print (seen ? "before" : "after"); exit }' <<< "$OUT")"
expect_eq "the load-state line is printed before the dependencies step" "before" "$LOAD_BEFORE_DEPS"

new_fixture loadstate-broken
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO" BIONIC_PLUGIN_LIST_CMD="cat $LIST_DEP_BROKEN")"
expect_match "dep-broken machine: the CLI's Error text is printed verbatim" \
  '*Dependency "superpowers@bionic" is not installed*' "$OUT"
expect_match "dep-broken machine: setup says the plugin did not load" '*did not load*' "$OUT"
expect_match "dep-broken machine: a fix is named on its own line" '*Fix:*' "$OUT"
expect_match "dep-broken machine: the summary carries the load failure as an action" \
  '*Summary*' "$OUT"
BROKEN_SUMMARY="$(awk '/^Summary/ { f = 1 } f' <<< "$OUT")"
expect_match "dep-broken machine: the action line names the load failure" \
  '*did not load*' "$BROKEN_SUMMARY"

# An unreadable listing is `unknown` and says WHY — never a confident "loaded".
# The cause is the third field S2 added (A-4.S2.4) and setup must render it,
# because "unknown" with no reason is a shrug the user cannot act on.
new_fixture loadstate-unknown
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO" BIONIC_PLUGIN_LIST_CMD="printf nonsense")"
expect_match "unreadable listing: setup reports the load state as unknown" '*unknown*' "$OUT"
expect_match "unreadable listing: the cause is rendered, not swallowed" \
  '*is not a plugin listing*' "$OUT"
expect_no_match "unreadable listing: never claims the plugin is loaded" '*bionic: loaded*' "$OUT"

# ---------------------------------------------------------------------------
# Group 2c — AC-8: no silent duplicates, and no noise when there are none.
#
# BOTH DIRECTIONS, because either alone is satisfiable by a broken step: a step
# that never speaks passes "clean machine says nothing", and a step that always
# speaks passes "planted duplicate is reported". The clean arm is asserted as
# ZERO TEXT — not merely "no question" — because a header printed on every
# machine is the noise the wave's principle is against.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 2c: duplicates are asked about, and only when they exist (AC-8) ==="

# The duplicate is planted in the registry file `detect_plugin_duplicates` reads:
# two catalogs, one bare name. That is the collision — the registry KEYS are
# unique by construction, so nothing that compares keys can see it.
new_fixture dup-planted
plant_cli_plugin "bionic@bionic" true
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "superpowers@claude-plugins-official" "6.2.0"
plant_installed "agent-skills@bionic" "0.6.7"
OUT="$(run_setup "$NO")"
expect_match "planted duplicate: the duplicates step appears" '*Duplicates*' "$OUT"
expect_match "planted duplicate: the colliding name is named" '*superpowers*' "$OUT"
expect_match "planted duplicate: both catalog copies are named" \
  '*superpowers@claude-plugins-official*' "$OUT"
expect_match "planted duplicate: the consolidation command is named" \
  '*claude plugin uninstall superpowers@claude-plugins-official*' "$OUT"
# All three answers Chris named are visible at the moment of asking; the
# question itself is deps.sh's one prompt shape, whose capital N is the default.
expect_match "planted duplicate: consolidating is offered" '*onsolidat*' "$OUT"
expect_match "planted duplicate: coexisting is offered as a legitimate answer" '*coexist*' "$OUT"
expect_match "planted duplicate: the question is asked with a default-No prompt" '*\[y/N\]*' "$OUT"
expect_no_match "declined duplicate: nothing was uninstalled" '*plugin uninstall*' "$(cat "$CALLS")"

new_fixture dup-consented
plant_cli_plugin "bionic@bionic" true
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "superpowers@claude-plugins-official" "6.2.0"
OUT="$(run_setup "$YES")"
expect_match "consented duplicate: the loser's uninstall reaches the CLI" \
  '*plugin uninstall superpowers@claude-plugins-official*' "$(cat "$CALLS")"
expect_no_match "consented duplicate: bionic's own copy is never the one removed" \
  '*plugin uninstall superpowers@bionic*' "$(cat "$CALLS")"

new_fixture dup-clean
plant_cli_plugin "bionic@bionic" true
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "agent-skills@bionic" "0.6.7"
OUT="$(run_setup "$NO")"
expect_no_match "clean machine: not one word about duplicates" '*uplicat*' "$OUT"
expect_no_match "clean machine: no consolidation command offered" '*plugin uninstall*' "$OUT"

# `dup=unknown` is a FAILURE TO LOOK, not a duplicate (plan A-4.S2.8). Setup
# must not ask about it — there is nothing to consolidate — and must not stay
# silent either, because silence is the claim "no duplicates" that an unreadable
# registry has not earned.
new_fixture dup-unknown
plant_cli_plugin "bionic@bionic" true
printf '%s\n' 'not json at all' > "$FIX/ch/plugins/installed_plugins.json"
OUT="$(run_setup "$NO")"
expect_match "unreadable registry: setup renders the cause rather than claiming none" \
  '*could not be parsed*' "$OUT"
expect_no_match "unreadable registry: no consolidation is offered for a non-duplicate" \
  '*plugin uninstall*' "$OUT"

# ---------------------------------------------------------------------------
# Group 3 — (b) core enable-verify, repair by explicit enable (P2).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 3: core enable-verify ==="

new_fixture enable-ok
plant_cli_plugin "bionic@bionic" true
plant_cli_plugin "superpowers@bionic" true
plant_cli_plugin "agent-skills@bionic" true
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "agent-skills@bionic" "0.6.7"
OUT="$(run_setup "$YES")"
expect_match "both deps present and enabled: superpowers reported enabled" '*superpowers*enabled*' "$OUT"
expect_match "both deps present and enabled: agent-skills reported enabled" '*agent-skills*enabled*' "$OUT"
expect_no_match "both deps enabled: no repair call" '*plugin enable*' "$(cat "$CALLS")"

new_fixture enable-disabled
plant_cli_plugin "bionic@bionic" true
plant_cli_plugin "superpowers@bionic" false
plant_cli_plugin "agent-skills@bionic" true
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "agent-skills@bionic" "0.6.7"
OUT="$(run_setup "$YES")"
expect_match "disabled dep: consented repair is an explicit enable" \
  '*plugin enable superpowers@bionic*' "$(cat "$CALLS")"

new_fixture enable-disabled-declined
plant_cli_plugin "bionic@bionic" true
plant_cli_plugin "superpowers@bionic" false
plant_installed "superpowers@bionic" "6.3.0"
OUT="$(run_setup "$NO")"
expect_no_match "declined repair: no enable call" '*plugin enable*' "$(cat "$CALLS")"
expect_match "declined repair: named in the summary" '*superpowers*' "$OUT"

new_fixture enable-absent
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_no_match "absent dep is not 'enabled'" '*enable agent-skills*' "$(cat "$CALLS")"
expect_match "absent dep: summary names it" '*agent-skills*' "$OUT"

# ---------------------------------------------------------------------------
# Group 4 — (c) the install loops, through the ONE install_dep function (AC-5).
#
# WAVE-06 S4 SPLIT ONE LOOP INTO TWO, and the split is the requirement. D-B
# ratified four dependency CLASSES answering *when* bionic installs a tool, and
# AC-11 states the consequence: setup asks about the basics and the optional
# extras, and about no `when-needed` row at all. The pre-S4 loop walked every
# row whose kind was not native, which is the basics, the extras AND the
# when-needed rows together — so a user setting up a machine was asked to
# install a headless browser and an MCP server for routes they might never
# take. Step 3 now walks `dep_names_class basic` and step 4 walks
# `dep_names_class extra`; nothing walks `when-needed`, whose install offer
# belongs to the route that needs it (lib/jit.sh).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 4: the install loops (basics, then extras) ==="

new_fixture deps-consent
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
CALLTEXT="$(cat "$CALLS")"
expect_match "a basic row installs through install_dep's own argv" '*brew install ripgrep*' "$CALLTEXT"
expect_match "an extra npm row installs through install_dep's own argv" '*npm install -g @pencil.dev/cli*' "$CALLTEXT"
expect_match "an extra mcp row registers through install_dep's own argv" '*mcp add context7*' "$CALLTEXT"
expect_no_match "native-kind rows never reach install_dep (the harness owns them)" \
  '*brew install superpowers*' "$CALLTEXT"
# The list must be read on its own descriptor. A `while read ... done < <(list)`
# loop hands the BODY the same stdin, so the consent prompt inside it eats the
# next dependency NAME as the answer — declining every item and silently
# skipping the rest of the table. Reaching the LAST row of BOTH loops is the
# catch, so each loop is asserted on its own final row.
expect_match "the basics loop reaches its last row (the list is never eaten by the prompts)" \
  '*aws*' "$OUT"
expect_match "the extras loop reaches its last row" '*@pencil.dev/cli*' "$OUT"
expect_match "a consented row actually mutates (statusline recorded in settings)" \
  '*ccstatusline*' "$(cat "$FIX/ch/settings.json")"

new_fixture deps-declined
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
CALLTEXT="$(cat "$CALLS")"
expect_no_match "declined: no brew install ran" '*brew install*' "$CALLTEXT"
expect_no_match "declined: no npm install ran" '*npm install*' "$CALLTEXT"
expect_match "declined: the dependency is named in the summary" '*ripgrep*' "$OUT"

# `ccstatusline` is the extras row whose presence probe needs jq (the statusline
# lives in settings.json). Without jq its presence is unreadable, and the loop
# must say so and OFFER rather than assume either way — the same honest-unknown
# rule the rest of the script follows. This arm replaces the pre-S4 one, which
# read `motion`: motion is `when-needed` now and setup never mentions it.
new_fixture deps-unknown
plant_cli_plugin "bionic@bionic" true
OUT="$(SETUP_PATH="$NOJQ_BIN" run_setup "$NO")"
expect_match "a presence the probe cannot read reports unknown, never a confident no" \
  '*ccstatusline*unknown*' "$OUT"

# ---------------------------------------------------------------------------
# Group 4b — AC-11 by name: WHICH rows setup is allowed to ask about.
#
# Both directions, because either alone is satisfiable by a broken loop: a loop
# that asks about nothing passes "no when-needed row appears", and the pre-S4
# loop passes "every basic appears". The four extras additionally carry the
# shape D-B ratified for them — one line of why, and a question that defaults to
# No — and the why-line is asserted per row rather than in aggregate, since one
# shared sentence would satisfy a count.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 4b: setup asks about basics and extras only (AC-11) ==="

new_fixture classes
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"

# The step blocks, so a name found in one step is not credited to another. The
# transcript's step headers are the only delimiters available and they are what
# the user reads, which makes them the right ones to key on.
step_block() {  # <this-step-header-prefix> <next-step-header-prefix>
  awk -v a="$1" -v b="$2" 'index($0, a) == 1 { f = 1 } f && index($0, b) == 1 { f = 0 } f' <<< "$OUT"
}
TOOLS="$(step_block "3. Tools" "4. ")"
EXTRAS="$(step_block "4. Optional extras" "5. ")"

expect_match "the tools step has its own header" '*3. Tools*' "$OUT"
expect_match "the extras step has its own header" '*4. Optional extras*' "$OUT"

for basic in git node pnpm gh jq rg uv docker aws; do
  expect_match "basic offered at setup: ${basic}" "*${basic}*" "$TOOLS"
done

# The when-needed rows, checked against the WHOLE transcript: "setup asks about
# no when-needed tool" is a claim about the run, not about one step.
# `impeccable` is the one that is also native-kind, so a loop keyed on class
# rather than kind would hand it to install_dep, which is required to refuse it
# — the failure would surface as an error message, not as an offer.
for jit in impeccable "@playwright/cli" playwright-chromium chrome-devtools motion; do
  expect_no_match "when-needed row is NOT offered at setup: ${jit}" "*${jit}*" "$OUT"
done

for extra in ccstatusline notebooklm context7 "@pencil.dev/cli"; do
  expect_match "extra offered at setup: ${extra}" "*${extra}*" "$EXTRAS"
  expect_match "extra carries its own line of why: ${extra}" "*   ${extra} — *" "$EXTRAS"
done

# `[y/N]` is deps.sh's own prompt shape and the capital N IS the default, so
# asserting it here asserts that an extra goes through the one consent gate
# rather than through a second prompt written for this step.
expect_match "extras are asked with a default-No prompt" '*\[y/N\]*' "$EXTRAS"

# One why line per extra and no more: a single shared sentence at the top of the
# step would satisfy every per-row assertion above while telling the user
# nothing about three of the four tools.
WHY_LINES="$(awk '/^   [a-z@][^ ]* — ./ { n++ } END { print n + 0 }' <<< "$EXTRAS")"
expect_eq "exactly one why line per extra, no shared sentence standing in" "4" "$WHY_LINES"

# Declining every extra mutates nothing — the default really is No.
expect_no_match "declined extras: nothing was installed" '*npm install -g @pencil.dev/cli*' "$(cat "$CALLS")"
expect_no_match "declined extras: no statusline recorded" '*statusLine*' "$(cat "$FIX/ch/settings.json")"

# ---------------------------------------------------------------------------
# Group 5 — (d) the CLAUDE_CODE_ENABLE_TODO_TOOLS export, marker-scoped.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 5: shell-rc export ==="

new_fixture rc-write
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
expect_match "consented: the export lands in the rc" \
  "env:todo-tools present=yes" "$(lib_query "$LIB_DIR/detect.sh" detect_env_todo_tools)"
expect_match "the export is written inside a bionic marker block" '*bionic:env:start*' "$(cat "$FIX/rc")"
expect_match "the rc the user already had is preserved" '*export PATH=*' "$(cat "$FIX/rc")"

RC_AFTER_FIRST="$(cat "$FIX/rc")"
OUT="$(run_setup "$YES")"
expect_eq "second run does not append a second block (byte-identical rc)" \
  "$RC_AFTER_FIRST" "$(cat "$FIX/rc")"
expect_match "second run says the export is already there" '*already*' "$OUT"

new_fixture rc-declined
plant_cli_plugin "bionic@bionic" true
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$NO")"
expect_eq "declined: the rc is untouched, byte for byte" "$RC_BEFORE" "$(cat "$FIX/rc")"
expect_match "declined: the export is named as an action line" '*CLAUDE_CODE_ENABLE_TODO_TOOLS*' "$OUT"

# A machine that already exports it OUTSIDE bionic's markers is already correct.
new_fixture rc-preexisting
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\nexport CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n' > "$FIX/rc"
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$YES")"
expect_eq "pre-existing export outside the markers: no block added" "$RC_BEFORE" "$(cat "$FIX/rc")"

# ---------------------------------------------------------------------------
# Group 6 — (e) the ported legacy .zshrc alias removal, BOTH variants.
#
# Fixture markers are STATED below and every production copy is pinned to them.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 6: legacy alias-block removal (ported from the installer) ==="

# The installer these literals used to be read out of (claude-bootstrap.sh) was
# deleted at epic-17 W5 (4/6). Deriving them from payload/scripts/setup.sh
# instead would be deriving the fixture from the script under test: change the
# markers there and the fixture would change with them and keep passing, which
# is the discrimination this block exists to have. So the literals are STATED
# here — the suite is now the independent statement of what the markers are —
# and every production copy is pinned against that statement below.
ALIAS_START='# ─── bionic:start ───'
ALIAS_END='# ─── bionic:end ───'
ALIAS_CONTENT="alias claude='claude --dangerously-skip-permissions'"

read_script_literal() {  # <file> <VARNAME> — the RHS of `VARNAME='...'` in <file>
  local file="$1" var="$2" line
  line="$(grep -m1 "^${var}=" "$file" 2>/dev/null)"
  line="${line#*=}"
  line="${line#\"}"; line="${line%\"}"
  line="${line#\'}"; line="${line%\'}"
  printf '%s' "$line"
}

# Pin 1 — the script under test agrees with the stated markers.
expect_eq "marker pin: setup.sh SETUP_ALIAS_START is the stated start marker" \
  "$ALIAS_START" "$(read_script_literal "$SETUP_SH" SETUP_ALIAS_START)"
expect_eq "marker pin: setup.sh SETUP_ALIAS_END is the stated end marker" \
  "$ALIAS_END" "$(read_script_literal "$SETUP_SH" SETUP_ALIAS_END)"

# Pin 2 — the other two surfaces that must address the same block agree too.
# detect.sh decides whether the block is PRESENT and remove.sh's standalone
# door strips it on a machine where these libraries are already gone; a marker
# that drifts in any one of the three makes the block unaddressable from that
# surface alone, which is exactly the failure no single-file check would see.
expect_true "marker pin: detect.sh addresses the same start marker" \
  grep -qF "$ALIAS_START" "${REPO}/payload/scripts/lib/detect.sh"
expect_eq "marker pin: remove.sh RM_RC_START is the stated start marker" \
  "$ALIAS_START" "$(read_script_literal "${REPO}/payload/scripts/remove.sh" RM_RC_START)"
expect_eq "marker pin: remove.sh RM_RC_END is the stated end marker" \
  "$ALIAS_END" "$(read_script_literal "${REPO}/payload/scripts/remove.sh" RM_RC_END)"

# Pin 3 — the unmarked (pre-marker) spelling setup.sh migrates still matches
# the alias line this fixture writes, or the UNMARKED variant below is inert.
expect_true "marker pin: setup.sh's unmarked pattern matches the fixture alias line" \
  bash -c 'printf "%s\n" "$1" | grep -qE "$(grep -m1 "^SETUP_ALIAS_PATTERN=" "$2" | sed "s/^[^=]*=//; s/^.//; s/.$//")"' _ "$ALIAS_CONTENT" "$SETUP_SH"

new_fixture alias-marked
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
OUT="$(run_setup "$YES")"
RC_TEXT="$(cat "$FIX/rc")"
expect_no_match "marked variant: the start marker is gone" "*${ALIAS_START}*" "$RC_TEXT"
expect_no_match "marked variant: the end marker is gone" "*${ALIAS_END}*" "$RC_TEXT"
expect_no_match "marked variant: the alias itself is gone" '*dangerously-skip-permissions*' "$RC_TEXT"
expect_match "marked variant: the user's own rc lines survive" '*export PATH=*' "$RC_TEXT"
expect_match "marked variant: detect agrees the legacy block is gone" \
  "env:zshrc-legacy present=no" "$(lib_query "$LIB_DIR/detect.sh" detect_zshrc_legacy_block)"

new_fixture alias-unmarked
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n%s\n' "$ALIAS_CONTENT" > "$FIX/rc"
OUT="$(run_setup "$YES")"
RC_TEXT="$(cat "$FIX/rc")"
expect_no_match "legacy UNMARKED variant: the bare alias is removed too" \
  '*dangerously-skip-permissions*' "$RC_TEXT"
expect_match "legacy unmarked variant: the user's own rc lines survive" '*export PATH=*' "$RC_TEXT"

new_fixture alias-declined
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$NO")"
expect_eq "declined removal: the rc is untouched, byte for byte" "$RC_BEFORE" "$(cat "$FIX/rc")"

new_fixture alias-absent
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
expect_match "no legacy block: setup says there is nothing to remove" '*legacy*' "$OUT"

# ---------------------------------------------------------------------------
# Group 7 — (f) legacy-channel settings.json managed-hook cleanup, jq-gated.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 7: legacy-channel managed-hook cleanup ==="

# Shape of a settings.json managed-hook entry (matcher + hooks[].command +
# timeout) — Claude Code's schema, formerly written by the retired installer.
plant_legacy_channel_settings() {
  cat > "$FIX/ch/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/protect-main.sh", "timeout": 10}] },
      { "matcher": "Write", "hooks": [{"type": "command", "command": "~/.claude/hooks/agent-context-guard.sh ~/.claude/hooks/canonical-sdlc-governing-skill.sh", "timeout": 10}] },
      { "matcher": "Edit", "hooks": [{"type": "command", "command": "/opt/other-tool/hook.sh", "timeout": 10}] }
    ]
  }
}
JSON
}

new_fixture hooks-clean
plant_cli_plugin "bionic@bionic" true
plant_legacy_channel_settings
OUT="$(run_setup "$YES")"
expect_eq "consented cleanup: legacy-channel entries are gone" "env:legacy-channel-hooks count=0" \
  "$(lib_query "$LIB_DIR/detect.sh" detect_legacy_channel_hooks)"
expect_match "cleanup keeps a foreign hook that is not bionic's leftover" '*other-tool*' "$(cat "$FIX/ch/settings.json")"
expect_match "cleanup keeps unrelated settings keys" '*"model"*' "$(cat "$FIX/ch/settings.json")"

# D-1/D-2 — the setup-side WALL. Every assertion above uses detect.sh as an
# ORACLE: it proves setup AGREES with the library on this fixture, which a
# second implementation can do right up until the day it drifts. The ownership
# table's row 1 names a wall, and doctor had one while setup did not — setup
# carried its own jq strip program, structurally different from remove.sh's,
# with nothing pinning them together.
#
# setup has no standalone-door excuse for a copy: it refuses to run at all
# without the libraries beside it. So the rewrite lives in hooks.sh and this
# asserts setup does not grow a second one.
expect_true "setup.sh calls the library strip rather than carrying one" \
  bash -c 'grep -qF "hooks_strip_legacy_channel" "$1"' _ "$SETUP_SH"
expect_eq "setup.sh contains no jq rewrite program of its own" "" \
  "$(grep -n 'with_entries' "$SETUP_SH" || true)"

new_fixture hooks-declined
plant_cli_plugin "bionic@bionic" true
plant_legacy_channel_settings
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
OUT="$(run_setup "$NO")"
expect_eq "declined cleanup: settings.json untouched, byte for byte" \
  "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"
expect_match "declined cleanup: the count is named in the summary" '*2 legacy-channel managed-hook*' "$OUT"

new_fixture hooks-none
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_match "no legacy-channel entries: setup says so rather than prompting" '*no legacy-channel managed-hook entries*' "$OUT"

# C-2 — WHAT THE PROMPT PROMISES, in both machine states.
#
# The prompt used to say, unconditionally, that the plugin registers its own
# copy of each hook through the payload's hooks.json. That is a safety claim —
# "delete these, something already covers them" — and it is false on every
# machine where the plugin is not registered with the CLI, which is every
# machine before the W5 cutover. A user who answered `y` severed their hook
# enforcement outright on the strength of it.
#
# The registration is a machine fact (detect_plugin_registered), so the sentence
# is conditional on it. Both branches are asserted, and each asserts the ABSENCE
# of the other's claim — otherwise a prompt that printed both would pass both.

new_fixture hooks-registered
plant_cli_plugin "bionic@bionic" true
plant_installed "bionic@bionic" "0.1.0"
plant_legacy_channel_settings
OUT="$(run_setup "$NO")"
expect_match "registered: the prompt says the plugin registers its own copy" \
  '*registers its own copy*' "$OUT"
expect_no_match "registered: it does not also warn that nothing takes their place" \
  '*nothing takes their place*' "$OUT"

new_fixture hooks-unregistered
plant_cli_plugin "bionic@bionic" true
plant_legacy_channel_settings
OUT="$(run_setup "$NO")"
expect_match "unregistered: the prompt says plainly that nothing takes their place" \
  '*nothing takes their place*' "$OUT"
expect_no_match "unregistered: the false replacement claim is not printed" \
  '*registers its own copy*' "$OUT"
expect_match "unregistered: the prompt names the plugin's absence as the reason" \
  '*NOT registered with the CLI*' "$OUT"

# The fixture pair really does differ only in the registration fact, so the
# discrimination above is the registration and not some other fixture drift.
expect_eq "the two arms differ in the registration fact, and in that alone" \
  "plugin:registered=no" "$(lib_query "$LIB_DIR/detect.sh" detect_plugin_registered)"

new_fixture hooks-nojq
plant_cli_plugin "bionic@bionic" true
plant_legacy_channel_settings
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
OUT="$(SETUP_PATH="$NOJQ_BIN" run_setup "$YES")"
expect_eq "no jq: settings.json is never edited blind" "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"
expect_match "no jq: the unknown is reported honestly" '*unknown*' "$OUT"

# ---------------------------------------------------------------------------
# Group 8 — (g) the consented permission-profile apply (AC-6).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 8: permission profile apply ==="

new_fixture profile-apply
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
expect_match "consented apply: the marker block is in user settings" \
  'profile: applied=yes*' "$(lib_query "$LIB_DIR/profile.sh" detect_profile_state)"
expect_match "consented apply: rendered against THIS machine's plugin root" \
  "*${FIX}/root/scripts/setup.sh*" "$(cat "$FIX/ch/settings.json")"
expect_no_match "consented apply: the render token never reaches settings" \
  '*__BIONIC_PLUGIN_ROOT__*' "$(cat "$FIX/ch/settings.json")"

SETTINGS_AFTER_FIRST="$(cat "$FIX/ch/settings.json")"
OUT="$(run_setup "$YES")"
expect_eq "second apply is a no-op (byte-identical settings)" \
  "$SETTINGS_AFTER_FIRST" "$(cat "$FIX/ch/settings.json")"
expect_match "second run reports the profile as already current" '*profile*' "$OUT"

new_fixture profile-declined
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_match "declined apply: no block applied" \
  'profile: applied=no*' "$(lib_query "$LIB_DIR/profile.sh" detect_profile_state)"
expect_match "declined apply: named as an action line" '*permission*' "$OUT"

# ---------------------------------------------------------------------------
# Group 8b — AC-12: ONE consented question about the default permission mode.
#
# WHY THE DECLINE ARM NEEDS A SETTLED FIXTURE. "No leaves the settings file
# untouched" is only a real claim if something in that run COULD have written to
# it. So the fixture is a machine that has already been set up — profile applied
# and current, so the profile half of the step has nothing to do — with the mode
# key removed again. The one question left in that step is this one, and the
# file's bytes are the whole evidence either way.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 8b: the default permission mode (AC-12) ==="

MODE_Q='*default permission mode to auto*'

new_fixture defaultmode-yes
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
expect_match "the mode question is asked" "$MODE_Q" "$OUT"
expect_match "the question says what it buys, in one line" '*Recommended*' "$OUT"
expect_match "the question is asked with a default-No prompt" '*\[y/N\]*' "$OUT"
expect_eq "the mode is asked exactly once in a run" "1" \
  "$(awk '/default permission mode to auto/ { n++ } END { print n + 0 }' <<< "$OUT")"
expect_eq "consented: the default mode is written as auto" "auto" \
  "$(jq -r '.permissions.defaultMode // ""' "$FIX/ch/settings.json" 2>/dev/null)"

# Idempotence: a machine already in auto is not interrogated a second time.
OUT2="$(run_setup "$YES")"
expect_eq "a machine already in auto is not asked again" "0" \
  "$(awk '/default permission mode to auto/ { n++ } END { print n + 0 }' <<< "$OUT2")"

new_fixture defaultmode-declined
plant_cli_plugin "bionic@bionic" true
run_setup "$YES" >/dev/null 2>&1
MODE_TMP="$FIX/ch/settings.json.modetmp"
jq 'del(.permissions.defaultMode)' "$FIX/ch/settings.json" > "$MODE_TMP" && mv "$MODE_TMP" "$FIX/ch/settings.json"
SETTINGS_BEFORE_MODE="$(cat "$FIX/ch/settings.json")"
OUT="$(run_setup "$NO")"
expect_match "settled machine: the mode question is still reached and asked" "$MODE_Q" "$OUT"
expect_eq "declined: the settings file is byte-identical afterwards" \
  "$SETTINGS_BEFORE_MODE" "$(cat "$FIX/ch/settings.json")"
expect_match "declined: the summary names the mode as an outstanding action" \
  '*permission mode*' "$(awk '/^Summary/ { f = 1 } f' <<< "$OUT")"
# ---- D-1: the value has ONE owner, and this writer follows it ----
#
# `auto` was a bare literal here and a second bare literal in remove.sh's reset,
# which is defined as "the one value bionic knows it wrote". Nothing made the two
# agree, and both suites stayed green either way. deps.sh owns it now; the arm
# that matters is behavioural — change the owner's value in a COPY of the
# library, point setup at that copy, and the settings file has to follow.
MUT_LIB="$TMP/mutant-lib"; mkdir -p "$MUT_LIB"
cp "$LIB_DIR/"*.sh "$MUT_LIB/"
sed 's/^BIONIC_DEFAULT_PERMISSION_MODE=.*/BIONIC_DEFAULT_PERMISSION_MODE="plan"/' \
  "$LIB_DIR/deps.sh" > "$MUT_LIB/deps.sh"
expect_true "one owner: the copied library really carries the moved value" \
  bash -c 'grep -qF "BIONIC_DEFAULT_PERMISSION_MODE=\"plan\"" "$1"' _ "$MUT_LIB/deps.sh"

new_fixture defaultmode-mutated-owner
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES" BIONIC_LIB_DIR="$MUT_LIB")"
expect_eq "one owner: setup writes whatever the owner names, not a literal of its own" "plan" \
  "$(jq -r '.permissions.defaultMode // ""' "$FIX/ch/settings.json" 2>/dev/null)"
expect_match "one owner: and the question it asks names that value too" \
  '*default permission mode to plan*' "$OUT"
# The mode is a settings key of the machine's own, NOT a rule inside bionic's
# marker block — the block is a rendering of the template and the template ships
# no defaultMode (tests/profile.test.sh Group 2 walls that). Writing it into the
# block would make /bionic:remove's strip silently revert a preference the user
# was asked for separately.
expect_no_match "the mode is not smuggled into the profile's marker block" \
  '*defaultMode*' "$(jq -c '[.permissions.allow[]?]' "$FIX/ch/settings.json" 2>/dev/null)"


# ---------------------------------------------------------------------------
# Group 9 — idempotence over the WHOLE script, by bytes.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 9: idempotence (run twice, fixture byte-identical) ==="

new_fixture idempotence
plant_cli_plugin "superpowers@bionic" false
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "agent-skills@bionic" "0.6.7"
plant_legacy_channel_settings
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"

RUN1="$(run_setup "$YES")"
FP1="$(fingerprint "$FIX")"
RUN2="$(run_setup "$YES")"
FP2="$(fingerprint "$FIX")"

expect_eq "run 2 leaves the fixture tree byte-identical to run 1" "$FP1" "$FP2"
expect_match "run 2 sees the plugin already installed" '*already installed*' "$RUN2"
expect_match "run 2 sees the export already present" '*already*' "$RUN2"
expect_no_match "run 2 finds no legacy alias block left to remove" "*${ALIAS_START}*" "$(cat "$FIX/rc")"
expect_eq "run 2 finds no legacy-channel hook entries left" "env:legacy-channel-hooks count=0" \
  "$(lib_query "$LIB_DIR/detect.sh" detect_legacy_channel_hooks)"

# ---------------------------------------------------------------------------
# Group 10 — a fully declined run mutates NOTHING.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 10: refusal is total ==="

new_fixture refuse-all
plant_legacy_channel_settings
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
FP_BEFORE="$(fingerprint "$FIX")"
OUT="$(run_setup "")"                 # EOF on the first prompt: no answer at all
FP_AFTER="$(fingerprint "$FIX")"
expect_eq "no answers on stdin: the machine is byte-identical afterwards" "$FP_BEFORE" "$FP_AFTER"
# Read-only probing (`plugin list`, `npm list`, `mcp get`) is expected and is
# how setup knows what to offer; what must be absent is every MUTATION.
MUTATING="$(grep -E 'plugin install|plugin enable|brew install|npm install|uv tool install|mcp add|npx --yes|pnpm store add' "$CALLS" 2>/dev/null)"
expect_eq "no answers on stdin: not one mutating command ran" "" "$MUTATING"
expect_match "no answers on stdin: setup still prints its summary" '*Summary*' "$OUT"

# ---------------------------------------------------------------------------
# Group 11 — the end summary carries named action lines (warn-and-continue).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 11: end summary ==="

new_fixture summary
OUT="$(run_setup "$NO")"
expect_match "summary block is printed" '*Summary*' "$OUT"
expect_match "summary names the declined plugin install" '*claude plugin install bionic@bionic*' "$OUT"
expect_match "summary names the declined permission profile" '*permission*' "$OUT"
new_fixture summary-rc
run_setup "$NO" >/dev/null 2>&1
expect_eq "a fully-declined run still exits 0 (warn-and-continue)" "0" "$?"

new_fixture summary-clean
plant_cli_plugin "bionic@bionic" true
plant_cli_plugin "superpowers@bionic" true
plant_cli_plugin "agent-skills@bionic" true
plant_installed "superpowers@bionic" "6.3.0"
plant_installed "agent-skills@bionic" "0.6.7"
run_setup "$YES" >/dev/null 2>&1
OUT="$(run_setup "$YES")"
expect_match "a settled machine's second run reports no outstanding work" '*Summary*' "$OUT"

# ---------------------------------------------------------------------------
# Group 12 — mutation-and-restore ×3. RED evidence dies at green
# (memory: red-evidence-is-perishable), so the proof that each gate is
# load-bearing is taken here against a DOCTORED COPY of setup.sh. The
# production file is only ever read.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 12: mutation-and-restore ×3 ==="

MUT="$TMP/setup-mutated.sh"

# Mutation 1 — delete the rc-export consent gate. A declined run must now
# mutate the rc; if it does not, the gate was never what stopped it.
grep -v '# consent gate: rc export' "$SETUP_SH" > "$MUT"
expect_true "mutation 1: the consent-gate line exists to delete" \
  bash -c "[ \"\$(wc -l < '$MUT')\" -lt \"\$(wc -l < '$SETUP_SH')\" ]"
new_fixture mut1
plant_cli_plugin "bionic@bionic" true
RC_BEFORE="$(cat "$FIX/rc")"
SETUP_UNDER_TEST="$MUT" run_setup "$NO" >/dev/null 2>&1
expect_no_match "MUTATED (consent gate removed): a declined run now writes the rc" \
  "$RC_BEFORE" "$(cat "$FIX/rc")"

new_fixture mut1-control
plant_cli_plugin "bionic@bionic" true
RC_BEFORE="$(cat "$FIX/rc")"
run_setup "$NO" >/dev/null 2>&1
expect_eq "RESTORED (production setup.sh): a declined run leaves the rc alone" \
  "$RC_BEFORE" "$(cat "$FIX/rc")"

# Mutation 2 — corrupt the legacy marker literal. The block must survive.
sed 's/bionic:start/bionic:STARTX/' "$SETUP_SH" > "$MUT"
new_fixture mut2
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
SETUP_UNDER_TEST="$MUT" run_setup "$YES" >/dev/null 2>&1
expect_match "MUTATED (marker literal corrupted): the legacy block survives removal" \
  "*${ALIAS_START}*" "$(cat "$FIX/rc")"

new_fixture mut2-control
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
run_setup "$YES" >/dev/null 2>&1
expect_no_match "RESTORED (production setup.sh): the legacy block is removed" \
  "*${ALIAS_START}*" "$(cat "$FIX/rc")"

# Mutation 3 — delete the rc-export idempotence guard. A second run must now
# append a second block; if it does not, the guard was not what prevented it.
grep -v '# idempotence guard: rc export' "$SETUP_SH" > "$MUT"
expect_true "mutation 3: the idempotence-guard line exists to delete" \
  bash -c "[ \"\$(wc -l < '$MUT')\" -lt \"\$(wc -l < '$SETUP_SH')\" ]"
new_fixture mut3
plant_cli_plugin "bionic@bionic" true
SETUP_UNDER_TEST="$MUT" run_setup "$YES" >/dev/null 2>&1
RC_ONE="$(cat "$FIX/rc")"
SETUP_UNDER_TEST="$MUT" run_setup "$YES" >/dev/null 2>&1
expect_no_match "MUTATED (idempotence guard removed): the second run appends again" \
  "$RC_ONE" "$(cat "$FIX/rc")"

new_fixture mut3-control
plant_cli_plugin "bionic@bionic" true
run_setup "$YES" >/dev/null 2>&1
RC_ONE="$(cat "$FIX/rc")"
run_setup "$YES" >/dev/null 2>&1
expect_eq "RESTORED (production setup.sh): the second run appends nothing" \
  "$RC_ONE" "$(cat "$FIX/rc")"

# Mutation 4 — delete the legacy-skill-copy consent gate. A declined run must
# now remove the directory; if it does not, the gate was never what stopped it.
grep -v '# consent gate: legacy skill copy' "$SETUP_SH" > "$MUT"
expect_true "mutation 4: the consent-gate line exists to delete" \
  bash -c "[ \"\$(wc -l < '$MUT')\" -lt \"\$(wc -l < '$SETUP_SH')\" ]"
new_fixture mut4
plant_cli_plugin "bionic@bionic" true
mkdir -p "$FIX/ch/skills/canonical-sdlc"
printf -- '---\nname: canonical-sdlc\n---\nbody\n' > "$FIX/ch/skills/canonical-sdlc/SKILL.md"
SETUP_UNDER_TEST="$MUT" run_setup "$NO" >/dev/null 2>&1
expect_true "MUTATED (consent gate removed): a declined run now removes the skill copy" \
  bash -c '[ ! -e "$1" ]' _ "$FIX/ch/skills/canonical-sdlc"

new_fixture mut4-control
plant_cli_plugin "bionic@bionic" true
mkdir -p "$FIX/ch/skills/canonical-sdlc"
printf -- '---\nname: canonical-sdlc\n---\nbody\n' > "$FIX/ch/skills/canonical-sdlc/SKILL.md"
run_setup "$NO" >/dev/null 2>&1
expect_true "RESTORED (production setup.sh): a declined run leaves the skill copy alone" \
  test -f "$FIX/ch/skills/canonical-sdlc/SKILL.md"

# The production file was never opened for writing above — only read.
expect_true "production setup.sh still parses after the mutation arms" bash -n "$SETUP_SH"


# ---------------------------------------------------------------------------
# Group 13 — (h) the legacy installed skill copy (epic-17 W5, 4/6 concern C-1;
# spec AC-8 names it as part of the shipped migration).
#
# WHY THIS STEP EXISTS AT ALL. The retired installer rendered bionic's skills
# into the CLI's OWN skills directory. The plugin ships the same skill inside
# its payload, so after the cutover that installed copy is a second
# canonical-sdlc — and not an inert one: 4/6 measured eleven hook-registration
# lines in its frontmatter, every one of them spelled for the pre-plugin hooks
# directory. A session loading it arms the same walls twice, once through the
# channel that was supposed to have retired, and nothing in the output says so.
#
# 4/6 removed that copy OUT OF BAND to keep its live-fire attribution clean and
# reported the gap rather than papering over it. This group is the gap closing:
# the removal is the SHIPPED migration's own act, under consent, idempotent.
#
# BOTH ARMS BY BYTES, as everywhere else here — the declined arm fingerprints
# the whole fixture tree, so "left alone" is a measurement rather than the
# absence of a log line.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 13: legacy installed skill copy (C-1 / AC-8) ==="

# The shape the installer left: a skill directory under the CLI's config dir,
# carrying a SKILL.md whose frontmatter registers hooks through the pre-plugin
# channel. The registration lines are what made this copy dangerous rather than
# merely redundant, so the fixture carries them.
plant_legacy_skill_copy() {
  mkdir -p "$FIX/ch/skills/canonical-sdlc"
  cat > "$FIX/ch/skills/canonical-sdlc/SKILL.md" <<'SKILLMD'
---
name: canonical-sdlc
description: bootstrap-era rendered copy
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: ~/.claude/hooks/farm-out-reminder.sh
---
The pre-plugin rendered body.
SKILLMD
  printf 'a reference file the installer also rendered\n' > "$FIX/ch/skills/canonical-sdlc/reference.md"
}

new_fixture skill-copy-consented
plant_cli_plugin "bionic@bionic" true
plant_legacy_skill_copy
_present_of() {  # <fact line> -> the present= field
  local l="$1"; l="${l#*present=}"; printf %s "${l%% *}"
}

expect_eq "fixture: the library sees the planted copy before setup runs" \
  "yes" "$(_present_of "$(lib_query "$LIB_DIR/detect.sh" detect_legacy_skill_copy)")"
OUT="$(run_setup "$YES")"
expect_true "consented: the legacy skill directory is gone" \
  bash -c '[ ! -e "$1" ]' _ "$FIX/ch/skills/canonical-sdlc"
expect_eq "consented: the library agrees the copy is gone" \
  "no" "$(_present_of "$(lib_query "$LIB_DIR/detect.sh" detect_legacy_skill_copy)")"
expect_match "consented: setup names the directory it removed" '*skills/canonical-sdlc*' "$OUT"
expect_match "consented: setup says why the copy mattered (the second registration)" \
  '*twice*' "$OUT"

new_fixture skill-copy-declined
plant_cli_plugin "bionic@bionic" true
plant_legacy_skill_copy
FP_BEFORE="$(fingerprint "$FIX")"
OUT="$(run_setup "$NO")"
expect_eq "declined: the whole fixture tree is byte-identical" "$FP_BEFORE" "$(fingerprint "$FIX")"
expect_true "declined: the SKILL.md is still there" \
  test -f "$FIX/ch/skills/canonical-sdlc/SKILL.md"
expect_match "declined: the end summary carries the action line" \
  '*pre-plugin skill copy*' "$OUT"

# ABSENT IS A NO-OP, and specifically not a prompt. A machine that never ran
# the installer — every machine a cold user brings — must not be asked about a
# directory that does not exist, and must not collect an action line for it.
new_fixture skill-copy-absent
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_no_match "absent: setup does not ask about a copy that is not there" \
  '*Remove *skills/canonical-sdlc*' "$OUT"
expect_match "absent: setup says there is nothing to remove" \
  '*no pre-plugin skill copy*' "$OUT"
expect_true "absent: no skills directory was created" \
  bash -c '[ ! -e "$1" ]' _ "$FIX/ch/skills"

# Idempotence over this step specifically: a second consented run against an
# already-clean machine performs no mutation and asks nothing.
new_fixture skill-copy-idempotent
plant_cli_plugin "bionic@bionic" true
plant_legacy_skill_copy
run_setup "$YES" >/dev/null 2>&1
FP_ONE="$(fingerprint "$FIX")"
OUT="$(run_setup "$YES")"
expect_eq "idempotent: the second consented run mutates nothing" "$FP_ONE" "$(fingerprint "$FIX")"
expect_match "idempotent: the second run reports nothing to remove" \
  '*no pre-plugin skill copy*' "$OUT"

# THE PREDICATE IS NARROW ON PURPOSE. The same installer left copies of
# bionic's other two skills behind. 4/6 measured those as registering nothing,
# and their disposition belongs to the wave's close-out — a consented step that
# removed directories nobody has decided about would be the larger defect. So
# a sibling directory is proof the step reads a NAME, not a wildcard.
new_fixture skill-copy-siblings
plant_cli_plugin "bionic@bionic" true
plant_legacy_skill_copy
mkdir -p "$FIX/ch/skills/browser-verify"
printf -- '---\nname: browser-verify\n---\nbody\n' > "$FIX/ch/skills/browser-verify/SKILL.md"
run_setup "$YES" >/dev/null 2>&1
expect_true "the named copy went" bash -c '[ ! -e "$1" ]' _ "$FIX/ch/skills/canonical-sdlc"
expect_true "a sibling skill directory is untouched" \
  test -f "$FIX/ch/skills/browser-verify/SKILL.md"

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
