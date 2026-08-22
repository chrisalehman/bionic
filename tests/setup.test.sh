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
# `sleep` earns its place: it is what the probe bound polls with, and without it
# on PATH `detect_bounded` degrades to an unbounded `wait` by design. A fixture
# PATH missing it would make Group 14 measure the degradation instead of the bound.
# `readlink` earns its place the same way (S15): both rc rewriters resolve a
# symlinked rc to its final target before staging, so the dotfiles file is
# rewritten rather than detached. Absent `readlink` they degrade to writing the
# path as given, so a PATH without it measures the degradation, not the fix.
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail sort uniq wc \
            jq mktemp find xargs shasum uname date touch diff printf true false sleep; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BIN}/${real}" 2>/dev/null
done

# `mv` WITH A WITNESS (critic F2). Every rc rewriter in the payload stages its
# work in a `<file>.bionic.tmp` and renames it into place, so the mode the RENAME
# publishes is the only mode that matters: a writer that publishes 0644 and
# repairs it afterwards would still have exposed the whole file — a shell rc is
# where people keep `export …_API_KEY=` — under a predictable name for the span
# before the rename, and permanently if the process dies in it. This wrapper
# records the mode of what each `mv` is about to publish. Inert unless an arm
# sets BIONIC_TEST_MV_LOG; `exec` hands off to the real binary.
SETUP_MV_REAL="$(command -v mv 2>/dev/null)"
# The loop above left a SYMLINK to the real binary here; `cat >` would follow it
# and try to write /bin/mv. Replace the link, do not write through it.
rm -f "${BIN}/mv"
cat > "${BIN}/mv" <<MVSTUB
#!/bin/bash
if [ -n "\${BIONIC_TEST_MV_LOG:-}" ] && [ -f "\$1" ]; then
  printf '%s %s\n' "\$(stat -f '%Lp' "\$1" 2>/dev/null || stat -c '%a' "\$1" 2>/dev/null)" "\$1" \
    >> "\$BIONIC_TEST_MV_LOG"
fi
exec "$SETUP_MV_REAL" "\$@"
MVSTUB
chmod +x "${BIN}/mv"

# `awk` WITH A DURING-WRITE WITNESS (critic delta 2 N5). The `mv` witness above
# measures the staged copy at the RENAME, which is one instant too late to see
# the window this staging order exists to close: the span in which the tmp file
# already holds the whole rc — tokens included — but has not been published yet.
# `_setup_rc_strip_block` writes that content with `awk … > "$tmp"`, and the
# shell opens the redirect before `awk` is exec'd, so a wrapper on `awk` reads
# the tmp's mode at exactly the moment it starts holding content. Inert unless an
# arm sets both BIONIC_TEST_STAGE_LOG and BIONIC_TEST_STAGE_TMP.
SETUP_AWK_REAL="$(command -v awk 2>/dev/null)"
rm -f "${BIN}/awk"
cat > "${BIN}/awk" <<AWKSTUB
#!/bin/bash
if [ -n "\${BIONIC_TEST_STAGE_LOG:-}" ] && [ -n "\${BIONIC_TEST_STAGE_TMP:-}" ] \
   && [ -e "\$BIONIC_TEST_STAGE_TMP" ]; then
  printf '%s %s\n' \
    "\$(stat -f '%Lp' "\$BIONIC_TEST_STAGE_TMP" 2>/dev/null || stat -c '%a' "\$BIONIC_TEST_STAGE_TMP" 2>/dev/null)" \
    "\$BIONIC_TEST_STAGE_TMP" >> "\$BIONIC_TEST_STAGE_LOG"
fi
exec "$SETUP_AWK_REAL" "\$@"
AWKSTUB
chmod +x "${BIN}/awk"

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
  mkdir -p "$FIX/home" "$FIX/ch/plugins" "$FIX/root/.claude-plugin" "$FIX/root/hooks" "$FIX/root/ccstatusline"
  printf '%s\n' '{"version":"0.1.0","name":"bionic"}' > "$FIX/root/.claude-plugin/plugin.json"
  # The shipped ccstatusline layout (epic-18 T1, AC-1): install_dep now copies
  # this into place beside recording the command, so a fixture payload root
  # with no ccstatusline/settings.json makes the install step fail outright.
  printf '%s' '{"version":3,"lines":[[{"id":"1","type":"model"}]]}' > "$FIX/root/ccstatusline/settings.json"
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

# SETUP_FLAGS carries the script's own arguments — `--list`, `--only <name>` —
# and is deliberately a string, word-split at the call: an empty bash 3.2 array
# under `set -u` is an unbound variable, which is the same trap setup.sh's own
# action accumulator documents. Item names carry no spaces, so splitting is
# exactly the right behaviour here rather than a shortcut.
SETUP_FLAGS=""

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
    "$@" bash "$script" ${SETUP_FLAGS:-} 2>&1
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


# ---------------------------------------------------------------------------
# Group 2 — (a) the native plugin install wrapper, tier 2 ⊃ tier 1.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 2: native plugin install wrapper (AC-2, tier 2 wraps tier 1) ==="

new_fixture install-fresh
OUT="$(run_setup "$YES")"
expect_match "fresh machine: consented install reaches the CLI" \
  '*plugin install bionic@bionic*' "$(cat "$CALLS")"

new_fixture install-already
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$YES")"
expect_no_match "already installed: no second install call" '*plugin install bionic@bionic*' "$(cat "$CALLS")"

new_fixture install-declined
OUT="$(run_setup "$NO")"
expect_no_match "declined install: nothing reached the CLI" '*plugin install bionic@bionic*' "$(cat "$CALLS")"

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

new_fixture enable-absent
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_no_match "absent dep is not 'enabled'" '*enable agent-skills*' "$(cat "$CALLS")"

# ---------------------------------------------------------------------------
# Group 4 — (c) the install loops, through the ONE install_dep function (AC-5).
#
# WAVE-06 S4 SPLIT ONE LOOP INTO TWO, and the split is the requirement. D-B
# ratified four dependency CLASSES answering *when* bionic installs a tool, and
# AC-11 states the consequence: setup asks about the basics and the optional
# extras, and about no `when-needed` row at all. The pre-S4 loop walked every
# row whose kind was not native, which is the basics, the extras AND the
# when-needed rows together. Step 3 now walks `dep_names_class basic` and step 4
# walks `dep_names_class extra`; nothing walks `when-needed`, whose install offer
# belongs to the route that needs it (lib/jit.sh).
#
# WHICH ROWS ARE IN WHICH CLASS CHANGED ON 2026-08-22 and this structure did not.
# S4's own argument here was that a user should not be asked to install a headless
# browser for a route they might never take; Chris ruled the other way after an
# incident — an install that happens inside the run that needs it is an install
# nobody can predict — so the browser driver, the devtools server, the chromium
# build and the pnpm-warmed animation library are `extra` rows now and step 4
# offers them. The loop that reads the class is untouched.
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
# A glob on "*installed.*" would also match "ripgrep is not installed." two
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


for basic in git node pnpm gh jq rg uv docker aws; do
  expect_match "basic offered at setup: ${basic}" "*${basic}*" "$TOOLS"
done

# The when-needed rows, checked against the WHOLE transcript: "setup asks about
# no when-needed tool" is a claim about the run, not about one step.
# `impeccable` is the one that is also native-kind, so a loop keyed on class
# rather than kind would hand it to install_dep, which is required to refuse it
# — the failure would surface as an error message, not as an offer.
#
# THE LIST SHRANK ON 2026-08-22, and both halves of that ruling are asserted:
# these two rows must still be absent from the whole run, and the four rows that
# left the class must now appear in step 4 (the roster below).
for jit in impeccable excalidraw-renderer; do
  expect_no_match "when-needed row is NOT offered at setup: ${jit}" "*${jit}*" "$OUT"
done

# Restated here rather than read from the dependency table on purpose: this suite
# measures a TRANSCRIPT, and a roster read from the table under test would keep
# passing on a table that had silently lost a row.
EXTRA_ROSTER="ccstatusline notebooklm context7 @pencil.dev/cli humanizer document-skills example-skills @playwright/cli chrome-devtools playwright-chromium motion"
for extra in $EXTRA_ROSTER; do
  expect_match "extra offered at setup: ${extra}" "*${extra}*" "$EXTRAS"
done

# A NATIVE ROW IN THE EXTRAS STEP, which is new at epic-18 T4 and is the one
# shape this loop had never carried. `install_dep` refuses every native row by
# design, so a loop that hands `document-skills` to it prints deps.sh's refusal
# — a library error message — at a user who did nothing wrong. The route is the
# CLI's own installer, the same one jit.sh reaches for `impeccable`.
expect_match "a native extra is offered as the CLI's own plugin install" \
  "*claude plugin install document-skills@anthropic-agent-skills*" "$EXTRAS"
expect_no_match "…never as deps.sh's refusal to be a second installer" \
  "*there is no second installer*" "$OUT"




# Declining every extra mutates nothing — the default really is No.
expect_no_match "declined extras: nothing was installed" '*npm install -g @pencil.dev/cli*' "$(cat "$CALLS")"
expect_no_match "declined extras: no statusline recorded" '*statusLine*' "$(cat "$FIX/ch/settings.json")"

# ---------------------------------------------------------------------------
# Group 5 — (d) bionic's environment settings, in the CLI's own settings.json.
#
# THE DEFECT THIS GROUP REPLACES AN ARM FOR. Until W7 this step appended
# `export CLAUDE_CODE_ENABLE_TODO_TOOLS=1` to the user's shell rc inside a
# marker block, and on 2026-08-21 that export was measured NOT REACHING the
# session it was written for: the host that launches the CLI runs its shell with
# rc files disabled. settings.json is read by the CLI itself however the session
# was started, so it is the one home that reaches every session — and the arms
# below assert the shell rc is not written to AT ALL, which is the half a
# "settings.json now carries it too" implementation would leave passing.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 5: the environment settings ==="

new_fixture env-write
plant_cli_plugin "bionic@bionic" true
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$YES")"
expect_eq "consented: the task-list name is in settings.json" "1" \
  "$(jq -r '.env.CLAUDE_CODE_ENABLE_TODO_TOOLS // ""' "$FIX/ch/settings.json")"
expect_eq "consented: the long-command ceiling is there beside it" "1800000" \
  "$(jq -r '.env.BASH_MAX_TIMEOUT_MS // ""' "$FIX/ch/settings.json")"
# THE HALF THAT MATTERS MOST. Not "settings.json was written" — "and the shell
# rc was not", byte for byte. A machine that got both would still be carrying
# the footprint remove now has to clean up.
expect_eq "consented: the shell rc is untouched, byte for byte" "$RC_BEFORE" "$(cat "$FIX/rc")"

SETTINGS_AFTER_FIRST="$(cat "$FIX/ch/settings.json")"
OUT="$(run_setup "$YES")"
expect_eq "second run writes nothing (byte-identical settings.json)" \
  "$SETTINGS_AFTER_FIRST" "$(cat "$FIX/ch/settings.json")"
expect_no_match "…and asks no question it has no work behind" '*Write bionic*' "$OUT"

new_fixture env-declined
plant_cli_plugin "bionic@bionic" true
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$NO")"
expect_eq "declined: settings.json is untouched, byte for byte" \
  "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"
expect_eq "declined: and so is the shell rc" "$RC_BEFORE" "$(cat "$FIX/rc")"

# A settings.json that already carries every name bionic owns — written by hand,
# or by an earlier run — is already correct, and the merge must not disturb what
# else is in the file.
new_fixture env-preexisting
plant_cli_plugin "bionic@bionic" true
cat > "$FIX/ch/settings.json" <<'JSON'
{"env":{"OTHER":"x","CLAUDE_CODE_ENABLE_TODO_TOOLS":"1","BASH_MAX_TIMEOUT_MS":"1800000","CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}
JSON
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
# Narrowed to the item: a whole consented pass writes settings.json through the
# permission steps too, and this arm is about THIS step writing nothing.
SETUP_FLAGS="--only environment"
OUT="$(run_setup "$YES")"
SETUP_FLAGS=""
expect_eq "pre-existing values: nothing rewritten" \
  "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"

# A partial machine — one name there, one missing — is the state a ceiling added
# after the fact leaves behind, and it must be completed rather than skipped.
new_fixture env-partial
plant_cli_plugin "bionic@bionic" true
printf '%s\n' '{"env":{"CLAUDE_CODE_ENABLE_TODO_TOOLS":"1"}}' > "$FIX/ch/settings.json"
OUT="$(run_setup "$YES")"
expect_eq "a half-configured machine gets the missing name" "1800000" \
  "$(jq -r '.env.BASH_MAX_TIMEOUT_MS // ""' "$FIX/ch/settings.json")"
expect_eq "…and keeps the one it had" "1" \
  "$(jq -r '.env.CLAUDE_CODE_ENABLE_TODO_TOOLS // ""' "$FIX/ch/settings.json")"

# The retired rc block is REMOVE's to clean up, not setup's. Setup must neither
# write one nor delete one — an installer that tidied the rc would be mutating a
# file outside the item the user consented to.
new_fixture env-legacy-rc
plant_cli_plugin "bionic@bionic" true
# The block STATED, not derived from the script under test — the same discipline
# Group 6 keeps for the alias markers. These are the bytes setup.sh used to
# append, blank separator line included.
cat > "$FIX/rc" <<'RC'
export PATH="$HOME/bin:$PATH"

# ─── bionic:env:start ───
export CLAUDE_CODE_ENABLE_TODO_TOOLS=1
# ─── bionic:env:end ───
RC
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$YES")"
expect_eq "a machine carrying the retired rc block: setup leaves it alone" \
  "$RC_BEFORE" "$(cat "$FIX/rc")"
expect_eq "…and still writes the settings names" "1800000" \
  "$(jq -r '.env.BASH_MAX_TIMEOUT_MS // ""' "$FIX/ch/settings.json")"

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

# ─── THE MODE OF THE FILE SETUP REWRITES (critic F2) ─────────────────────────
#
# `_setup_rc_strip_block` and the unmarked-alias rewrite below it both build a
# `<rc>.bionic.tmp` and rename it over the user's shell rc. `mv` replaces the
# inode, so without a mode capture the rc comes back wearing the process umask
# instead of its own — and a shell rc is where people keep plaintext tokens. The
# same discipline `_dep_settings_write_jq` already carries for settings.json
# (lib/env.sh's header states the reasoning): capture the mode, stage under
# `umask 077`, chmod BEFORE the rename. Both directions, and the witness above
# measures the staged copy rather than only the published one.
# DEREFERENCING, deliberately (critic delta 2 N1). The property under test is the
# mode of the file the writer PUBLISHED, and for a symlinked rc or settings.json
# that file is the link's target. The non-`-L` spelling reads the link's own 755
# and is satisfiable only by a writer that DESTROYS the link — the exact
# behaviour S15 fixed away from — so it would pin the defect. `link_own_mode`
# below is the non-dereferencing reader, used only where the LINK's own mode is
# the thing being asserted about (the "this is the trap" fixture lines).
file_mode() { stat -L -f '%Lp' "$1" 2>/dev/null || stat -L -c '%a' "$1" 2>/dev/null; }
link_own_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

new_fixture alias-marked-mode-600
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\nexport SOME_API_TOKEN=sk-fixture-not-a-real-secret\n\n%s\n%s\n%s\n' \
  "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
chmod 600 "$FIX/rc"
expect_eq "fixture: the rc really starts at 0600 (the arm is not vacuous)" \
  "600" "$(file_mode "$FIX/rc")"
OUT="$(run_setup "$YES" BIONIC_TEST_MV_LOG="$TMP/mv-alias-600.log")"
expect_no_match "marked variant at 0600: the block really was stripped (not vacuous)" \
  "*${ALIAS_START}*" "$(cat "$FIX/rc")"
expect_eq "setup's marked-block strip leaves a 0600 rc at 0600" \
  "600" "$(file_mode "$FIX/rc")"
# An empty log satisfies the emptiness assertion below, so the log is proved
# non-empty first — and proved with a POSITIVE assertion: the earlier spelling
# was `expect_no_match … ""`, an empty glob standing in for "is not empty",
# which works only by accident of how the matcher treats the empty pattern.
expect_true "…and the mv witness really saw the rc rename (not vacuous)" \
  /usr/bin/grep -q 'rc\.bionic\.tmp' "$TMP/mv-alias-600.log"
expect_eq "…and every staged copy of the 0600 rc was itself 0600, before the rename" "" \
  "$(/usr/bin/grep 'rc\.bionic\.tmp' "$TMP/mv-alias-600.log" 2>/dev/null | /usr/bin/grep -v '^600 ' || true)"

new_fixture alias-marked-mode-644
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
chmod 644 "$FIX/rc"
OUT="$(run_setup "$YES")"
expect_eq "setup does not narrow a 0644 rc either" "644" "$(file_mode "$FIX/rc")"

# The OTHER rewriter: the unmarked legacy alias line, filtered out with grep -v.
new_fixture alias-unmarked-mode-600
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\nexport SOME_API_TOKEN=sk-fixture-not-a-real-secret\n%s\n' \
  "$ALIAS_CONTENT" > "$FIX/rc"
chmod 600 "$FIX/rc"
OUT="$(run_setup "$YES" BIONIC_TEST_MV_LOG="$TMP/mv-unmarked-600.log")"
expect_no_match "unmarked variant at 0600: the alias really was removed (not vacuous)" \
  '*dangerously-skip-permissions*' "$(cat "$FIX/rc")"
expect_eq "setup's unmarked-alias rewrite leaves a 0600 rc at 0600" \
  "600" "$(file_mode "$FIX/rc")"
expect_true "unmarked mode arm: the mv witness really saw the rc rename (not vacuous)" \
  /usr/bin/grep -q 'rc\.bionic\.tmp' "$TMP/mv-unmarked-600.log"
expect_eq "…and its staged copy was 0600 before the rename too" "" \
  "$(/usr/bin/grep 'rc\.bionic\.tmp' "$TMP/mv-unmarked-600.log" 2>/dev/null | /usr/bin/grep -v '^600 ' || true)"

new_fixture alias-unmarked-mode-644
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n%s\n' "$ALIAS_CONTENT" > "$FIX/rc"
chmod 644 "$FIX/rc"
OUT="$(run_setup "$YES")"
expect_eq "setup does not narrow a 0644 rc on the unmarked path either" \
  "644" "$(file_mode "$FIX/rc")"

# ─── ONE STAGING ORDER, MEASURED WHERE IT MATTERS (critic delta 2 N5) ────────
#
# S13 restructured both setup writers onto `_setup_stage_tmp` in the order
# "create empty under `umask 077` → chmod to the target's mode → caller writes",
# recorded as neutral. It was not neutral: on a 0644 rc under `umask 022` the tmp
# was already 0644 at the instant it began holding the whole file, where the
# pre-S13 order left it at 0600 until the publish. S14 then declined the same
# reorder for the four one-shot writers on the opposite reading of the same
# sentence, so the two doors disagreed about their own rule. S15 settles it in
# one direction for every writer: create at 0600, WRITE, chmod to the target's
# mode, rename. The tmp is never wider than 0600 while it holds content, and it
# is never wider than the file it replaces once it does.
#
# Both instants are asserted here, because either alone is satisfiable by the
# wrong order: 0600 DURING the write (the awk witness) and the target's 0644 AT
# the rename (the mv witness). `umask 022` is set explicitly — the property is
# about what the umask would otherwise have produced, so inheriting the runner's
# is measuring nothing in particular.
new_fixture stage-order-644
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\nexport SOME_API_TOKEN=sk-fixture-not-a-real-secret\n\n%s\n%s\n%s\n' \
  "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
chmod 644 "$FIX/rc"
STAGE_LOG="$TMP/stage-order-644.log";    : > "$STAGE_LOG"
STAGE_MV_LOG="$TMP/stage-order-644-mv.log"; : > "$STAGE_MV_LOG"
SAVED_UMASK="$(umask)"; umask 022
OUT="$(run_setup "$YES" \
  BIONIC_TEST_STAGE_LOG="$STAGE_LOG" \
  BIONIC_TEST_STAGE_TMP="$FIX/rc.bionic.tmp" \
  BIONIC_TEST_MV_LOG="$STAGE_MV_LOG")"
umask "$SAVED_UMASK"
expect_no_match "stage-order arm: the block really was stripped (not vacuous)" \
  "*${ALIAS_START}*" "$(cat "$FIX/rc")"
expect_true "stage-order arm: the during-write witness really fired (not vacuous)" \
  test -s "$STAGE_LOG"
expect_eq "the staged rc is 0600 while it HOLDS the content, whatever the umask says" "" \
  "$(/usr/bin/grep -v '^600 ' "$STAGE_LOG" 2>/dev/null || true)"
expect_true "stage-order arm: the mv witness really fired too (not vacuous)" \
  /usr/bin/grep -q 'rc\.bionic\.tmp' "$STAGE_MV_LOG"
expect_eq "…and it wears the target's 0644 at the RENAME, not one instant before it" "" \
  "$(/usr/bin/grep 'rc\.bionic\.tmp' "$STAGE_MV_LOG" 2>/dev/null | /usr/bin/grep -v '^644 ' || true)"
expect_eq "…and the published rc is the 0644 it started as" "644" "$(file_mode "$FIX/rc")"

# ─── THE RC THAT IS A SYMLINK (critic delta D1) ──────────────────────────────
#
# `stat -f '%Lp' <symlink>` reports the LINK's own mode — 755 — and never consults
# the file it points at. A `~/.zshrc` symlinked into a dotfiles repo is the
# commonest way people manage an rc, so a mode capture that does not dereference
# publishes the user's rc, tokens included, as `rwxr-xr-x`: WIDER than the file it
# replaced, which is the one outcome the capture exists to prevent. Both setup
# writers get an arm; `stat -L` is what makes them pass.
#
# AND THE LINK SURVIVES (critic delta 2 N1, decided at A6.S15.1). The rename used
# to replace the link with a regular file, leaving the dotfiles repo still holding
# the block setup had just reported removed. Both writers now resolve to the
# link's final target and publish onto it; each arm asserts the link still exists,
# still points where it did, and that the TARGET is what changed.
symlink_rc() {  # turns $FIX/rc into a link to $FIX/dotfiles/rc
  mkdir -p "$FIX/dotfiles"
  command mv "$FIX/rc" "$FIX/dotfiles/rc"
  ln -s "$FIX/dotfiles/rc" "$FIX/rc"
}

new_fixture alias-marked-symlink-600
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\nexport SOME_API_TOKEN=sk-fixture-not-a-real-secret\n\n%s\n%s\n%s\n' \
  "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
symlink_rc
chmod 600 "$FIX/dotfiles/rc"
expect_eq "fixture: the symlinked rc's TARGET really is 0600" \
  "600" "$(file_mode "$FIX/dotfiles/rc")"
expect_no_match "fixture: …and the LINK's own mode is not it — this is the trap" \
  "600" "$(link_own_mode "$FIX/rc")"
OUT="$(run_setup "$YES" BIONIC_TEST_MV_LOG="$TMP/mv-alias-symlink-600.log")"
expect_no_match "symlink arm: the block really was stripped (not vacuous)" \
  "*${ALIAS_START}*" "$(cat "$FIX/rc")"
expect_eq "a symlinked rc is published at its TARGET's 0600, never the link's 755" \
  "600" "$(file_mode "$FIX/rc")"
expect_true "symlink arm: the rc is STILL a symlink after the strip" test -L "$FIX/rc"
expect_eq "…and still points where it did" "$FIX/dotfiles/rc" "$(readlink "$FIX/rc")"
expect_no_match "…and it is the TARGET that was rewritten, not a detached copy" \
  "*${ALIAS_START}*" "$(cat "$FIX/dotfiles/rc")"
expect_true "symlink arm: the mv witness really saw the rc rename (not vacuous)" \
  /usr/bin/grep -q 'rc\.bionic\.tmp' "$TMP/mv-alias-symlink-600.log"
expect_eq "…and no staged copy of it was ever wider than 0600 either" "" \
  "$(/usr/bin/grep 'rc\.bionic\.tmp' "$TMP/mv-alias-symlink-600.log" 2>/dev/null | /usr/bin/grep -v '^600 ' || true)"

# The other writer: the unmarked legacy alias line, on the same shape.
new_fixture alias-unmarked-symlink-600
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\nexport SOME_API_TOKEN=sk-fixture-not-a-real-secret\n%s\n' \
  "$ALIAS_CONTENT" > "$FIX/rc"
symlink_rc
chmod 600 "$FIX/dotfiles/rc"
expect_eq "fixture: the unmarked symlink arm's target really is 0600" \
  "600" "$(file_mode "$FIX/dotfiles/rc")"
OUT="$(run_setup "$YES" BIONIC_TEST_MV_LOG="$TMP/mv-unmarked-symlink-600.log")"
expect_no_match "unmarked symlink arm: the alias really was removed (not vacuous)" \
  '*dangerously-skip-permissions*' "$(cat "$FIX/rc")"
expect_eq "the unmarked-alias rewrite publishes a symlinked rc at its target's 0600 too" \
  "600" "$(file_mode "$FIX/rc")"
expect_true "unmarked symlink arm: the rc is STILL a symlink after the rewrite" test -L "$FIX/rc"
expect_eq "…and still points where it did" "$FIX/dotfiles/rc" "$(readlink "$FIX/rc")"
expect_no_match "…and it is the TARGET that lost the alias, not a detached copy" \
  '*dangerously-skip-permissions*' "$(cat "$FIX/dotfiles/rc")"
expect_true "unmarked symlink arm: the mv witness really saw the rc rename (not vacuous)" \
  /usr/bin/grep -q 'rc\.bionic\.tmp' "$TMP/mv-unmarked-symlink-600.log"
expect_eq "…and its staged copy was never wider than 0600 either" "" \
  "$(/usr/bin/grep 'rc\.bionic\.tmp' "$TMP/mv-unmarked-symlink-600.log" 2>/dev/null | /usr/bin/grep -v '^600 ' || true)"

new_fixture alias-declined
plant_cli_plugin "bionic@bionic" true
printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
RC_BEFORE="$(cat "$FIX/rc")"
OUT="$(run_setup "$NO")"
expect_eq "declined removal: the rc is untouched, byte for byte" "$RC_BEFORE" "$(cat "$FIX/rc")"


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



new_fixture hooks-nojq
plant_cli_plugin "bionic@bionic" true
plant_legacy_channel_settings
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
OUT="$(SETUP_PATH="$NOJQ_BIN" run_setup "$YES")"
expect_eq "no jq: settings.json is never edited blind" "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"

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

new_fixture profile-declined
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_match "declined apply: no block applied" \
  'profile: applied=no*' "$(lib_query "$LIB_DIR/profile.sh" detect_profile_state)"

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

# ---------------------------------------------------------------------------
# Group 11 — the end summary carries named action lines (warn-and-continue).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 11: end summary ==="

new_fixture summary-rc
run_setup "$NO" >/dev/null 2>&1
expect_eq "a fully-declined run still exits 0 (warn-and-continue)" "0" "$?"


# ---------------------------------------------------------------------------
# Group 12 — mutation-and-restore ×3. RED evidence dies at green
# (memory: red-evidence-is-perishable), so the proof that each gate is
# load-bearing is taken here against a DOCTORED COPY of setup.sh. The
# production file is only ever read.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 12: mutation-and-restore ×3 ==="

MUT="$TMP/setup-mutated.sh"

# Mutation 1 — delete the environment consent gate. A declined run must now
# write settings.json; if it does not, the gate was never what stopped it.
# (Retargeted at W7 S4: the step this gate belongs to writes settings.json now,
# not a shell rc.)
grep -v '# consent gate: settings env' "$SETUP_SH" > "$MUT"
expect_true "mutation 1: the consent-gate line exists to delete" \
  bash -c "[ \"\$(wc -l < '$MUT')\" -lt \"\$(wc -l < '$SETUP_SH')\" ]"
new_fixture mut1
plant_cli_plugin "bionic@bionic" true
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
SETUP_UNDER_TEST="$MUT" run_setup "$NO" >/dev/null 2>&1
expect_no_match "MUTATED (consent gate removed): a declined run now writes settings.json" \
  "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"

new_fixture mut1-control
plant_cli_plugin "bionic@bionic" true
SETTINGS_BEFORE="$(cat "$FIX/ch/settings.json")"
run_setup "$NO" >/dev/null 2>&1
expect_eq "RESTORED (production setup.sh): a declined run leaves settings.json alone" \
  "$SETTINGS_BEFORE" "$(cat "$FIX/ch/settings.json")"

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

# Mutation 3 — delete the environment idempotence guard. A second run must now
# ASK AGAIN; if it does not, the guard was not what prevented it.
#
# THE TELL IS THE QUESTION, NOT THE BYTES, and that is forced by what the step
# writes. Re-writing the same two names produces a byte-identical settings.json,
# so a bytes-only arm would pass with the guard deleted and prove nothing. What
# the guard actually buys is that a user who is already configured is not asked
# to consent to a write with nothing behind it — so that is what is measured.
grep -v '# idempotence guard: settings env' "$SETUP_SH" > "$MUT"
expect_true "mutation 3: the idempotence-guard line exists to delete" \
  bash -c "[ \"\$(wc -l < '$MUT')\" -lt \"\$(wc -l < '$SETUP_SH')\" ]"
new_fixture mut3
plant_cli_plugin "bionic@bionic" true
SETUP_UNDER_TEST="$MUT" run_setup "$YES" >/dev/null 2>&1
MUT3_SECOND="$(SETUP_UNDER_TEST="$MUT" run_setup "$YES" 2>&1)"
expect_match "MUTATED (idempotence guard removed): the second run asks again" \
  '*Write bionic*environment settings*' "$MUT3_SECOND"

new_fixture mut3-control
plant_cli_plugin "bionic@bionic" true
run_setup "$YES" >/dev/null 2>&1
CTRL3_SECOND="$(run_setup "$YES" 2>&1)"
expect_no_match "RESTORED (production setup.sh): the second run asks nothing" \
  '*Write bionic*environment settings*' "$CTRL3_SECOND"

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

new_fixture skill-copy-declined
plant_cli_plugin "bionic@bionic" true
plant_legacy_skill_copy
FP_BEFORE="$(fingerprint "$FIX")"
OUT="$(run_setup "$NO")"
expect_eq "declined: the whole fixture tree is byte-identical" "$FP_BEFORE" "$(fingerprint "$FIX")"
expect_true "declined: the SKILL.md is still there" \
  test -f "$FIX/ch/skills/canonical-sdlc/SKILL.md"

# ABSENT IS A NO-OP, and specifically not a prompt. A machine that never ran
# the installer — every machine a cold user brings — must not be asked about a
# directory that does not exist, and must not collect an action line for it.
new_fixture skill-copy-absent
plant_cli_plugin "bionic@bionic" true
OUT="$(run_setup "$NO")"
expect_no_match "absent: setup does not ask about a copy that is not there" \
  '*Remove *skills/canonical-sdlc*' "$OUT"
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
echo ""
echo "=== Group 14: the load-state read is bounded (critic F-3) ==="
# ---------------------------------------------------------------------------
#
# THE ASYMMETRY THIS CLOSES. Doctor bounds the three external calls it does not
# control, on the stated ground that any of them can wedge and an unbounded
# probe wedges the report with them. Setup ran the SAME plugin listing, through
# the same probe, unbounded — after the install, with the report half-printed
# and no way for the user to tell a wedge from a crash. Setup is the command a
# stranger runs first, so it is the worse place to hang, not the better one.
#
# The bound is one owner now (`detect_bounded` in detect.sh); this arm measures
# the CALLER being released, because a bound that stops waiting on its own child
# while the caller's pipe stays open is not a bound (the same defect the six-axis
# review's C-1 found in doctor's first cut).

new_fixture bounded-load-state
plant_cli_plugin "bionic@bionic" true
WEDGE="$TMP/wedged-listing"
cat > "$WEDGE" <<'STUB'
#!/bin/bash
# A listing that never answers: a CLI mid-update, a lock nobody releases.
/bin/sleep 45
echo "too late"
STUB
chmod +x "$WEDGE"

WEDGE_START="$(date +%s)"
OUT="$(run_setup "$NO" "BIONIC_PLUGIN_LIST_CMD=$WEDGE" "BIONIC_DOCTOR_PROBE_SECONDS=2")"
WEDGE_ELAPSED=$(( $(date +%s) - WEDGE_START ))

expect_true "a wedged listing does not wedge setup: the whole run returns inside 10s" \
  bash -c '[ "$1" -le 10 ]' _ "$WEDGE_ELAPSED"
# The measured elapsed is printed so a failure is diagnosable from the log alone.
echo "      (bounded load-state arm: elapsed=${WEDGE_ELAPSED}s, bound=2s, probe sleeps 45s)"

# ONE OWNER FOR THE BOUND. setup.sh must not carry a second implementation, and
# the fifteen-second shipped default must live where both callers read it.
expect_true "the bound's shipped default lives in detect.sh, the one both scripts read" \
  /usr/bin/grep -q 'BIONIC_DOCTOR_PROBE_SECONDS:-15' "$LIB_DIR/detect.sh"
expect_eq "setup.sh implements no bound of its own" "" \
  "$(/usr/bin/grep -n 'kill -TERM' "$SETUP_SH" || true)"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 14b: the DUPLICATES read is bounded on both doors (A-6.6 (b)) ==="
# ---------------------------------------------------------------------------
#
# THE SECOND HALF OF GROUP 14's BOUND. Group 14 pins the load-state probe. The duplicates
# probe was left unbounded because it reads a file — but the reader is `jq`, over a path
# that can sit on a stalled mount, and S12 put that read on `--list`, which is the first
# thing a stranger runs and the one door that prints nothing else first. Both doors are
# measured here: the roster (`--list`) and the full pass, each against the same wedge.
#
# THE ANSWER ON TIMEOUT IS "NOT A DUPLICATE", never a hang and never an invented one:
# `--list` publishes no `duplicate:` row it could not confirm, and the full pass says out
# loud that it could not look, carrying the cause the bound gave it.

new_fixture bounded-duplicates
plant_cli_plugin "bionic@bionic" true
# Two catalogs, one bare name — a real collision the unwedged probe would find.
jq '.plugins["superpowers@claude-plugins-official"] = [{"scope":"user","installPath":"/fixture/sp2","version":"6.3.0"}]' \
  "$FIX/ch/plugins/installed_plugins.json" > "$FIX/ch/plugins/installed_plugins.json.tmp" \
  && mv "$FIX/ch/plugins/installed_plugins.json.tmp" "$FIX/ch/plugins/installed_plugins.json"
plant_installed "superpowers@bionic" "6.3.0"

# A jq that stalls on the duplicates program ONLY — every other registry parse the run
# makes is the real jq, so this measures one probe's bound and not a broken PATH.
SLOWJQ="$TMP/bin-slowjq"; mkdir -p "$SLOWJQ"
for f in "$BIN"/*; do
  case "${f##*/}" in jq) continue ;; esac
  ln -sf "$(readlink "$f" 2>/dev/null || echo "$f")" "${SLOWJQ}/${f##*/}" 2>/dev/null
done
JQ_REAL="$(command -v jq)"
cat > "${SLOWJQ}/jq" <<STUB
#!/bin/bash
case "\$*" in
  *'group_by(split("@")[0])'*) /bin/sleep 45; echo "too late"; exit 0 ;;
  *) exec "${JQ_REAL}" "\$@" ;;
esac
STUB
chmod +x "${SLOWJQ}/jq"

# ---- door 1: the roster ----
SETUP_FLAGS="--list"
DUPL_START="$(date +%s)"
DUPL_LIST="$(SETUP_PATH="$SLOWJQ" run_setup "" BIONIC_DOCTOR_PROBE_SECONDS=2)"
DUPL_LIST_ELAPSED=$(( $(date +%s) - DUPL_START ))
SETUP_FLAGS=""

expect_true "--list does not wedge on a stalled registry read: it returns inside 15s" \
  bash -c '[ "$1" -le 15 ]' _ "$DUPL_LIST_ELAPSED"
expect_match "…and still publishes the roster it can answer for" '*permission-mode*' "$DUPL_LIST"
expect_no_match "…and names no duplicate it never confirmed" '*duplicate:*' "$DUPL_LIST"
echo "      (bounded --list arm: elapsed=${DUPL_LIST_ELAPSED}s, bound=2s, probe sleeps 45s)"

# ---- door 2: the full pass ----
DUPF_START="$(date +%s)"
DUPL_FULL="$(SETUP_PATH="$SLOWJQ" run_setup "$NO" BIONIC_DOCTOR_PROBE_SECONDS=2)"
DUPL_FULL_ELAPSED=$(( $(date +%s) - DUPF_START ))

expect_true "a full pass does not wedge on it either: inside 20s" \
  bash -c '[ "$1" -le 20 ]' _ "$DUPL_FULL_ELAPSED"
expect_no_match "…and invents no collision out of a read it never finished" \
  '*is installed twice*' "$DUPL_FULL"
echo "      (bounded full-pass arm: elapsed=${DUPL_FULL_ELAPSED}s, bound=2s, probe sleeps 45s)"

# ---- and the unwedged run still finds the collision it is there to find ----
DUPL_OK="$(run_setup "$NO")"
expect_match "with a jq that answers, the full pass reports the duplicate" \
  '*is installed twice*' "$DUPL_OK"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 16: the yes is addressable — --list and --only (critic F-2) ==="
# ---------------------------------------------------------------------------
#
# WHAT WAS UNSAFE. Group 15 made the instruction honest; it did not make the
# answer aimable. The one channel that works is an answer delivered on this
# script's input, and an answer delivered that way is POSITIONAL — it is read by
# the FIRST question asked, which is whichever item this machine happens to have
# unfinished. A user who said "yes, set the permission mode" and had that yes
# relayed the obvious way got question one instead, which on the wave's own live
# capture was an offer to install a documentation server.
#
# WHAT THESE ARMS PIN. `--only <name>` runs exactly the item named and asks
# about nothing else, so the answer can only reach the question it was given
# for; `--list` publishes the names; and the two agree, so a name a reader can
# see is a name the dispatcher takes. The declined action lines carry that route
# with the item's own name in it.
#
# WHAT THEY MUST NOT SHOW, and Group 10 above is the standing proof: no arm here
# introduces a way to answer a question without answering it. `--only` narrows
# WHICH question is asked; the answer is still one `y` on the standard input,
# and a run with nothing on that input still declines.

# ---- the roster, and its agreement with the dispatcher ----
new_fixture only-list
plant_cli_plugin "bionic@bionic" true
SETUP_FLAGS="--list"
LIST_OUT="$(run_setup "")"
SETUP_FLAGS=""

expect_match "--list names the permission-mode item" '*permission-mode*' "$LIST_OUT"
# THE NAME IS THE USER'S WORD FOR THE THING, and the thing stopped being a shell
# file at W7: the item writes settings.json now, so `shell-env` named a mechanism
# that is gone. A machine that kept the old name would take `--only shell-env`
# and do something the name does not describe.
expect_match "--list names the environment item" '*environment*' "$LIST_OUT"
expect_no_match "…and no longer names it after a shell file" '*shell-env*' "$LIST_OUT"
expect_match "--list names a tool row read from the dependency table" '*tool:git*' "$LIST_OUT"
expect_match "--list names a core dependency row" '*dependency:superpowers*' "$LIST_OUT"

# Every line is a bare pasteable name: no header, no prose, no leading spaces.
LIST_JUNK=""
while IFS= read -r _id; do
  case "$_id" in
    ''|*' '*|*$'\t'*) LIST_JUNK="${LIST_JUNK}[${_id}]" ;;
  esac
done <<< "$LIST_OUT"
expect_eq "--list prints names only — one per line, nothing a reader cannot paste" "" "$LIST_JUNK"

# AC-11 still holds through the new door: the flag cannot reach a row the full
# pass would never offer. `impeccable` is when-needed and native-kind, which
# install_dep is required to refuse outright.
expect_no_match "--list offers no when-needed row (AC-11 holds through the flag)" \
  '*tool:impeccable*' "$LIST_OUT"

# THE AGREEMENT ARM. One owner for the roster means every printed name is a name
# `--only` accepts. Exit 2 is the dispatcher's "no such item", so any 2 here is a
# name that could be read and not used.
# Lines that are not bare names are the junk arm's business, not this one's;
# driving a whole setup run for each of them is how this arm would take minutes
# against a tree that has no --list at all.
LIST_REJECTED=""
while IFS= read -r _id; do
  [ -n "$_id" ] || continue
  case "$_id" in *' '*|*$'\t'*) continue ;; esac
  SETUP_FLAGS="--only $_id"
  run_setup "" >/dev/null 2>&1
  [ "$?" = "2" ] && LIST_REJECTED="${LIST_REJECTED}${_id} "
  SETUP_FLAGS=""
done <<< "$LIST_OUT"
expect_eq "every name --list prints is a name --only accepts" "" "$LIST_REJECTED"

# ---- an unknown name is refused, and says where the names are ----
new_fixture only-unknown
plant_cli_plugin "bionic@bionic" true
SETUP_FLAGS="--only not-an-item"
UNKNOWN_OUT="$(run_setup "")"; UNKNOWN_RC=$?
SETUP_FLAGS=""
expect_eq "--only with an unknown name exits 2" "2" "$UNKNOWN_RC"
expect_no_match "…and asks nothing before refusing" '*\[y/N\]*' "$UNKNOWN_OUT"

SETUP_FLAGS="--only"
MISSING_OUT="$(run_setup "")"; MISSING_RC=$?
SETUP_FLAGS=""
expect_eq "--only with no name at all exits 2 rather than running everything" "2" "$MISSING_RC"

# ---- one consented item, and NOTHING else, by bytes ----
#
# The claim is not "the mode was written" — it is "the mode was written and
# nothing else moved". So the whole fixture tree is fingerprinted either side of
# the run and the difference has to be one file.
new_fixture only-one-mutation
plant_cli_plugin "bionic@bionic" true
RC_BEFORE="$(cat "$FIX/rc")"
FP_BEFORE="$(fingerprint "$FIX")"
SETUP_FLAGS="--only permission-mode"
ONE_OUT="$(run_setup "y
")"
SETUP_FLAGS=""
FP_AFTER="$(fingerprint "$FIX")"

expect_eq "--only permission-mode writes the mode deps.sh owns" "auto" \
  "$(jq -r '.permissions.defaultMode // ""' "$FIX/ch/settings.json")"
expect_eq "…and the shell rc is byte-identical" "$RC_BEFORE" "$(cat "$FIX/rc")"
printf '%s\n' "$FP_BEFORE" > "$TMP/fp-before.txt"
printf '%s\n' "$FP_AFTER"  > "$TMP/fp-after.txt"
diff "$TMP/fp-before.txt" "$TMP/fp-after.txt" > "$TMP/fp-diff.txt" 2>&1
CHANGED="$(/usr/bin/grep -c '^[<>]' "$TMP/fp-diff.txt" | tr -d ' ')"
expect_eq "…and one file in the tree changed — the settings file, and only it" "2" "$CHANGED"
expect_true "…and that file is settings.json" \
  /usr/bin/grep -q 'settings.json' "$TMP/fp-diff.txt"
expect_match "…and the one question asked was that item's own" \
  '*default permission mode*' "$ONE_OUT"
expect_no_match "…and no other step printed a header" '*3. Tools*' "$ONE_OUT"
expect_no_match "…nor the environment step" '*5. Environment*' "$ONE_OUT"
expect_no_match "…nor the permission-profile half of its own step" \
  '*bionic ships a permission profile*' "$ONE_OUT"

# ---- exactly ONE question is asked, so the answer cannot land on another ----
#
# This is the defect stated as a count. Two questions and one answer is the
# positional hazard; one question and one answer is the fix.
new_fixture only-one-question
plant_cli_plugin "bionic@bionic" true
SETUP_FLAGS="--only environment"
DECLINE_OUT="$(run_setup "")"
SETUP_FLAGS=""
printf '%s\n' "$DECLINE_OUT" > "$TMP/only-decline.txt"
QCOUNT="$(/usr/bin/grep -c '\[y/N\]' "$TMP/only-decline.txt" | tr -d ' ')"
expect_eq "--only asks exactly one question" "1" "$QCOUNT"
expect_match "…the one it was told to ask" '*environment settings*' "$DECLINE_OUT"
expect_eq "…and settings.json is untouched when nobody answered" "$(printf '%s' '{}')" \
  "$(cat "$FIX/ch/settings.json")"
expect_eq "…and the rc file is untouched either way" "$(printf 'export PATH="$HOME/bin:$PATH"\n')" \
  "$(cat "$FIX/rc")"





# ---------------------------------------------------------------------------
# Group 17 — one answer over a printed plan: --all (AC-8)
# ---------------------------------------------------------------------------
#
# THE UNIT OF CONSENT IS A PLAN, NOT A FLAG THAT ANSWERS. Per-item consent is
# the right default and a poor experience for the person who has already decided
# to set the whole machine up: nine questions is nine chances to lose the
# thread, and the shape people reach for instead — an assume-yes flag — is the
# hole in "consent per event, never silent, never unattended", because a row
# added to the roster later would run on a machine whose owner never saw it.
#
# So the whole run becomes ONE event. `--all` prints every item it would ask
# about, one line each naming what that item changes, and asks a single question
# over that printed page. Nothing runs that was not on it, and a new item shows
# up there before it shows up on anybody's machine.

echo ""
echo "=== Group 17: one answer over a printed plan — --all (AC-8) ==="

# ONE ANSWER, AND A SECOND LINE THE RUN MUST NEVER REACH FOR. A bare
# `$(printf 'y\n')` loses its trailing newline to command substitution, and a
# `read` on an unterminated line reports EOF — which this script treats as "not
# asked", not as a yes. The second line keeps the first one terminated, and it
# is a token no question here would accept: if a second question were ever
# asked, it would be answered with it and declined, not silently consented to.
ONE_YES="$(printf 'y\nunanswerable\n')"
ONE_NO="$(printf 'n\nunanswerable\n')"

# Every item on the roster with something to do: a disabled core dependency, no
# environment settings, the retired alias block, legacy-channel hook entries, a
# pre-plugin skill copy, no permission profile and no default mode.
plant_everything_setup() {
  plant_cli_plugin "bionic@bionic" true
  plant_cli_plugin "superpowers@bionic" false
  plant_cli_plugin "agent-skills@bionic" true
  plant_installed "superpowers@bionic" "6.3.0"
  plant_installed "agent-skills@bionic" "0.6.7"
  plant_legacy_channel_settings
  printf 'export PATH="$HOME/bin:$PATH"\n\n%s\n%s\n%s\n' "$ALIAS_START" "$ALIAS_CONTENT" "$ALIAS_END" > "$FIX/rc"
  mkdir -p "$FIX/ch/skills/canonical-sdlc"
  printf -- '---\nname: canonical-sdlc\n---\nbody\n' > "$FIX/ch/skills/canonical-sdlc/SKILL.md"
}

new_fixture all-everything
plant_everything_setup
SETUP_FLAGS="--all"
ALL_OUT="$(run_setup "$ONE_YES")"
SETUP_FLAGS=""
printf '%s\n' "$ALL_OUT" > "$TMP/setup-all-yes.txt"


expect_eq "--all asks exactly one question for the whole run" "1" \
  "$(/usr/bin/grep -c '\[y/N\]' "$TMP/setup-all-yes.txt" | tr -d ' ')"

expect_eq "--all: the environment settings were written" "1800000" \
  "$(jq -r '.env.BASH_MAX_TIMEOUT_MS // ""' "$FIX/ch/settings.json")"
expect_eq "--all: the default permission mode was set" "auto" \
  "$(jq -r '.permissions.defaultMode // ""' "$FIX/ch/settings.json")"
expect_no_match "--all: the retired alias block is gone" "*${ALIAS_START}*" "$(cat "$FIX/rc")"
expect_true "--all: the pre-plugin skill copy is gone" \
  bash -c '[ ! -e "$1" ]' _ "$FIX/ch/skills/canonical-sdlc"
expect_match "--all: the disabled dependency was enabled" \
  '*plugin enable superpowers@bionic*' "$(cat "$CALLS")"
expect_eq "--all: the legacy-channel hook entries are gone" "env:legacy-channel-hooks count=0" \
  "$(lib_query "$LIB_DIR/detect.sh" detect_legacy_channel_hooks)"


# ---- a no runs nothing and says so ----
new_fixture all-declined
plant_everything_setup
FP_BEFORE="$(fingerprint "$FIX")"
SETUP_FLAGS="--all"
NO_OUT="$(run_setup "$ONE_NO")"
SETUP_FLAGS=""
expect_eq "--all declined: the whole fixture tree is byte-identical" \
  "$FP_BEFORE" "$(fingerprint "$FIX")"
expect_eq "--all declined: not one mutating command ran" "" \
  "$(grep -E 'plugin install|plugin enable|brew install|npm install|uv tool install|mcp add' "$CALLS" 2>/dev/null || true)"

# An unanswered first pass is a no as well — the rule that keeps `--all` from
# being an assume-yes flag wearing a plan.
new_fixture all-eof
plant_everything_setup
FP_BEFORE="$(fingerprint "$FIX")"
SETUP_FLAGS="--all"
EOF_OUT="$(run_setup "")"
SETUP_FLAGS=""
expect_eq "--all with nobody there to ask: the fixture tree is byte-identical" \
  "$FP_BEFORE" "$(fingerprint "$FIX")"


# ---- THE PLAN AND THE QUESTIONS ARE ONE ROSTER, READ TWICE ----
#
# The defect this walls off is drift: a plan built from its own idea of what is
# outstanding would come to disagree with the run it is a plan FOR, and the user
# would consent to one list and get another. One plan line per question a whole
# per-item pass asks is the check.
new_fixture all-agreement-plan
plant_everything_setup
SETUP_FLAGS="--all"
AGREE_PLAN="$(run_setup "$ONE_NO")"
SETUP_FLAGS=""
printf '%s\n' "$AGREE_PLAN" > "$TMP/setup-agree-plan.txt"

new_fixture all-agreement-pass
plant_everything_setup
AGREE_PASS="$(run_setup "$NO")"
printf '%s\n' "$AGREE_PASS" > "$TMP/setup-agree-pass.txt"

AGREE_PLAN_LINES="$(/usr/bin/grep -c '^  • ' "$TMP/setup-agree-plan.txt" | tr -d ' ')"
AGREE_QUESTIONS="$(/usr/bin/grep -c '\[y/N\]' "$TMP/setup-agree-pass.txt" | tr -d ' ')"
expect_true "agreement arm is not vacuous: the per-item pass really did ask something" \
  bash -c '[ "$1" -gt 1 ]' _ "$AGREE_QUESTIONS"
expect_eq "the plan names exactly the items a per-item pass asks about" \
  "$AGREE_PLAN_LINES" "$AGREE_QUESTIONS"

# ---- --all and --only are two different narrowings and cannot be combined ----
new_fixture all-and-only
plant_everything_setup
SETUP_FLAGS="--all --only environment"
COMBO_OUT="$(run_setup "$YES")"; COMBO_RC=$?
SETUP_FLAGS=""
expect_eq "--all with --only exits 2" "2" "$COMBO_RC"
expect_no_match "…and asks nothing before refusing" '*\[y/N\]*' "$COMBO_OUT"
expect_eq "…and changes nothing" "" \
  "$(jq -r '.env // "" | tostring | select(. != "\"\"")' "$FIX/ch/settings.json" 2>/dev/null | grep -F 'BASH_MAX' || true)"

# ---- --list is unchanged by the new flag ----
SETUP_FLAGS="--list"
ALL_LIST_OUT="$(run_setup "")"
SETUP_FLAGS=""
expect_match "--list still prints the roster --all reads" '*permission-mode*' "$ALL_LIST_OUT"
expect_no_match "--list prints names, never plan lines" '*•*' "$ALL_LIST_OUT"

# NO ASSUME-YES CAME IN WITH THE FLAG. The wave's ratified rule is consent per
# item from the standard input, and the two shapes that would break it are a
# flag and an environment knob. Neither exists, and this arm is what keeps it
# that way when the next flag is added.
# Anchored on an argument arm, not on the characters: `--yes)` also closes the
# install argv this script prints.
#
# `--all` USED TO BE ON THIS LIST AND IS NOT ANY MORE (W7, AC-8). It was there
# while every shape proposed for it was "answer the questions for me", which is
# the thing this arm keeps out. What shipped is not that: `--all` PRINTS the
# whole plan and asks one question over it, so the run still turns on an
# explicit `y` read from this script's own input, and a row added to the roster
# later still reaches the user's eyes before it reaches their machine. Group 17
# is the wall on that shape.
expect_eq "setup.sh takes no assume-yes argument" "" \
  "$(/usr/bin/grep -nE '^[[:space:]]*--yes\)' "$SETUP_SH" || true)"
expect_eq "setup.sh reads no assume-yes environment knob" "" \
  "$(/usr/bin/grep -niE 'BIONIC_(ASSUME_YES|YES|NONINTERACTIVE)' "$SETUP_SH" || true)"

# ---- NO ENVIRONMENT VALUE GRANTS CONSENT (W7 S11, six-axis review axis 4) ----
#
# The two greps above are a wall against a knob NAMED assume-yes. They cannot see
# a knob spelled something else, and one was spelled something else: `_dep_consent`
# short-circuits on `SETUP_ALL` OR `RM_ALL`, and this script used to zero only its
# own name. An exported `RM_ALL=1` therefore walked in from the environment and
# answered every question here — proven by the reviewer, who wrote both settings
# keys onto a scratch machine with the answer channel closed.
#
# So the wall becomes behavioural rather than lexical: both names arrive SET, there
# is nothing on the standard input to answer with, and the machine must be
# untouched afterwards. A grep can be routed around by renaming a variable; this
# arm cannot.
new_fixture env-consent-knob
plant_cli_plugin "bionic@bionic" true
FP_KNOB_BEFORE="$(fingerprint "$FIX")"
SETUP_FLAGS="--only environment"
KNOB_OUT="$(run_setup "" SETUP_ALL=1 RM_ALL=1)"
SETUP_FLAGS=""
expect_eq "…and settings.json still holds nothing of bionic's" "$(printf '%s' '{}')" \
  "$(cat "$FIX/ch/settings.json")"
expect_eq "…and the whole fixture tree is byte-identical" \
  "$FP_KNOB_BEFORE" "$(fingerprint "$FIX")"

# The same over the whole page: `--all` under both exported names still ends at the
# one question, unanswered, and therefore at "nothing changed."
new_fixture env-consent-knob-all
plant_everything_setup
FP_KNOB_ALL_BEFORE="$(fingerprint "$FIX")"
SETUP_FLAGS="--all"
KNOB_ALL_OUT="$(run_setup "" SETUP_ALL=1 RM_ALL=1)"
SETUP_FLAGS=""
expect_eq "…and the whole fixture tree is byte-identical" \
  "$FP_KNOB_ALL_BEFORE" "$(fingerprint "$FIX")"
expect_eq "…and not one mutating command ran" "" \
  "$(grep -E 'plugin install|plugin enable|brew install|npm install|uv tool install|mcp add' "$CALLS" 2>/dev/null || true)"

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
