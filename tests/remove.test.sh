#!/bin/bash
# REMOVE — epic-17 wave-03 slice S8 (spec AC-4; ownership table row
# "footprint removal | scripts/remove.sh").
#
# WHAT THIS SUITE OWNS. `payload/scripts/remove.sh` — the consented teardown of
# bionic's machine footprint — and `payload/commands/remove.md`, the wrapper
# that must add no logic to it.
#
# THE TWO WALLS THIS SUITE EXISTS FOR.
#
#   1. THE NEVER-LIST. The reset charter names an excluded class that consent
#      cannot unlock: `.bionic/` trees (plans, memory, record), and shared
#      binaries bionic ensured but does not own. An all-yes run is the hostile
#      case — a user who answered yes to everything — and after it those files
#      must be byte-identical. A removal script is only as good as what it
#      refuses to remove.
#
#   2. THE STANDALONE DOOR. The identical script, curl-fetched to a machine
#      whose plugin is already gone, must still work: `payload/scripts/lib/*`
#      do not exist there. The arm below copies remove.sh ALONE to a temp
#      directory with no `lib/` beside it and drives it against a fixture tree.
#      "The remover must not depend on the thing it removes" is not a comment
#      in the script; it is this arm.
#
# HERMETIC. No network, no live `~/.claude`, no real `claude`/`npm`/`brew`. Every
# run gets a fixture HOME, a fixture PATH holding recorder stubs, and the same
# root env vars the payload libraries read. The stubs are not a seam that
# substitutes the value under test: they are the real `command -v` / `claude` /
# `npm` lookups resolved against a directory this suite controls, so a mutation
# that would have run really runs — against a recorder — and its absence is
# provable from the log rather than from a dry-run flag production never sets.
#
# CONSENT IS DRIVEN BY STDIN, NOT BY A KNOB. deps.sh ratified "no assume-yes
# knob exists"; remove.sh inherits that, so every arm here feeds answers on
# stdin from a FILE (never a pipe — `yes y | script` is a SIGPIPE race under
# pipefail, tests/assert-helper-race.test.sh).
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below, same reason.
#
# Usage: bash tests/remove.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
REMOVE_SH="${REPO}/payload/scripts/remove.sh"
REMOVE_MD="${REPO}/payload/commands/remove.md"
PROFILE_SH="${REPO}/payload/scripts/lib/profile.sh"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"
HOOKS_SH="${REPO}/payload/scripts/lib/hooks.sh"
DEPS_SH="${REPO}/payload/scripts/lib/deps.sh"
# Read, never run: Group 19's ownership arms are about a value setup.sh WRITES and
# this script resets, and a shared value with only one reader is not shared.
SETUP_SH="${REPO}/payload/scripts/setup.sh"
TEMPLATE="${REPO}/payload/permissions/profile.template.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq()    { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_ne()    { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "expected NOT '$2'"; fi; }
expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
# In-process containment — no pipe into grep -q, so no SIGPIPE race.
expect_contains()     { local l="$1" n="$2" h="$3"; if [[ "$h" == *"$n"* ]]; then ok "$l"; else no "$l" "expected to contain '$n'"; fi; }
expect_not_contains() { local l="$1" n="$2" h="$3"; if [[ "$h" == *"$n"* ]]; then no "$l" "expected NOT to contain '$n'"; else ok "$l"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture machinery
# ---------------------------------------------------------------------------

# A recorder stub: appends its own argv to $BIONIC_TEST_CALLS and exits 0.
make_stub() {  # <bindir> <name> [body]
  local bindir="$1" name="$2" body="${3:-}"
  mkdir -p "$bindir"
  {
    echo '#!/bin/bash'
    echo 'echo "'"$name"' $*" >> "$BIONIC_TEST_CALLS"'
    [ -n "$body" ] && echo "$body"
    echo 'exit 0'
  } > "${bindir}/${name}"
  chmod +x "${bindir}/${name}"
}

# A bin dir carrying only what a hermetic run legitimately needs. PATH is
# REPLACED, never prefixed, so a real brew/npm/claude can never be reached.
BASE_BIN="$TMP/base-bin"
mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod stat ls tr head tail sort uniq wc find jq shasum date; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

# Everything a fixture machine needs, built fresh per arm.
#   <arm>/home/.zshrc
#   <arm>/home/.claude/settings.json
#   <arm>/home/.claude/plugins/data/...
#   <arm>/home/.bionic/…            never-list
#   <arm>/project/.bionic/…         never-list
#   <arm>/bin                       PATH for the run
new_arm() {  # <name> -> echoes the arm dir
  local arm="$TMP/$1"
  mkdir -p "$arm/home/.claude/plugins/data" "$arm/bin" "$arm/project"
  cp -R "$BASE_BIN/." "$arm/bin/" 2>/dev/null
  : > "$arm/calls.log"
  echo "$arm"
}

# The never-list fixtures: two `.bionic/` trees (one under HOME, one in a
# project) with memory inside, and a shared binary on PATH.
plant_never_list() {  # <arm>
  local arm="$1"
  mkdir -p "$arm/home/.bionic/memory" "$arm/home/.bionic/docs/record" "$arm/project/.bionic/docs/plans"
  printf 'a memory that must survive an all-yes remove\n' > "$arm/home/.bionic/memory/note.md"
  printf 'wave plan\n' > "$arm/project/.bionic/docs/plans/epic.plan.md"
  printf 'record\n' > "$arm/home/.bionic/docs/record/session.md"
  make_stub "$arm/bin" rg 'true'
  make_stub "$arm/bin" git 'true'
}

plant_zshrc_marked() {  # <arm>
  cat > "$1/home/.zshrc" <<'RC'
export EDITOR=vim

# ─── bionic:start ───
alias claude='claude --dangerously-skip-permissions'
# ─── bionic:end ───

export PATH="$HOME/bin:$PATH"
RC
}

plant_zshrc_legacy_unmarked() {  # <arm>
  cat > "$1/home/.zshrc" <<'RC'
export EDITOR=vim
alias claude='claude --dangerously-skip-permissions'
export PATH="$HOME/bin:$PATH"
RC
}

plant_todo_export() {  # <arm>
  cat >> "$1/home/.zshrc" <<'RC'
export CLAUDE_CODE_ENABLE_TODO_TOOLS=1
# export CLAUDE_CODE_ENABLE_TODO_TOOLS=1   (commented — not a live export)
RC
}

# settings.json carrying two legacy-channel managed-hook entries (the pre-plugin
# ~/.claude/hooks/ copies) plus one foreign entry that must survive.
plant_legacy_channel_hooks() {  # <arm>
  cat > "$1/home/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "~/.claude/hooks/protect-main.sh" } ] },
      { "matcher": "Write", "hooks": [ { "type": "command", "command": "/opt/other-tool/guard.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/landing-gate.sh" } ] }
    ]
  },
  "model": "opus"
}
JSON
}

# The rendered permission block, applied exactly as profile.sh would apply it.
#
# TWO SHAPES, because the strip has two branches an accretion rule hides. With a
# rule outside the block, removing the block leaves `permissions.allow`
# non-empty and the container-collapse steps never run. With the block as the
# ONLY allow entry, the array empties (`del(.permissions.allow)`) and then the
# object does (`del(.permissions)`) — the branches that decide whether a cleaned
# settings file is `{}`-littered or tidy. Mode `block-only` reaches them; the
# default keeps the accretion rule and is what every earlier arm asserts on.
plant_profile_block() {  # <arm> [with-accretion|block-only]
  # One `local` per line: `local a="$1" b="$a/x"` reads the OLD $a, which under
  # `set -u` is an unbound-variable abort (the trap the S8 brief names).
  local arm="$1"
  local mode="${2:-with-accretion}"
  local rendered="${arm}/rendered.json"
  BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
  BIONIC_SETTINGS_FILE="$arm/home/.claude/settings.json" \
    bash -c '. "$1"; render_profile "$2" "$3" > "$4"' _ \
      "$PROFILE_SH" "$TEMPLATE" "/fixture/plugin/root" "$rendered"
  if [ "$mode" = "block-only" ]; then
    # A settings file with a key that is not permissions, so the arm proves
    # `.permissions` is deleted rather than the whole file being emptied.
    printf '%s' '{"model":"opus"}' > "$arm/home/.claude/settings.json"
  else
    # An accretion rule the machine owns, planted BEFORE the block goes in.
    if [ -f "$arm/home/.claude/settings.json" ]; then
      jq '.permissions.allow = ((.permissions.allow // []) + ["Bash(echo the-machines-own-rule)"])' \
        "$arm/home/.claude/settings.json" > "$arm/tmp.json" && mv "$arm/tmp.json" "$arm/home/.claude/settings.json"
    else
      printf '%s' '{"permissions":{"allow":["Bash(echo the-machines-own-rule)"]}}' > "$arm/home/.claude/settings.json"
    fi
  fi
  BIONIC_SETTINGS_FILE="$arm/home/.claude/settings.json" \
    bash -c '. "$1"; profile_apply "$2" --consented' _ "$PROFILE_SH" "$rendered" >/dev/null 2>&1
}

# A plugin in the CLI's own install registry — the file `check_dep` reads for a
# `native` row. This is how a machine that took the design route's mid-session
# offer looks afterwards: `impeccable@bionic` installed, declared by nobody.
plant_native_plugin() {  # <arm> <name> <version>
  local arm="$1" name="$2" version="$3"
  local file="$arm/home/.claude/plugins/installed_plugins.json"
  mkdir -p "${file%/*}"
  [ -f "$file" ] || printf '%s\n' '{"plugins":{}}' > "$file"
  jq --arg k "${name}@bionic" --arg v "$version" \
     '.plugins[$k] = [ { "scope": "user", "installPath": ("/fixture/" + $k), "version": $v } ]' \
     "$file" > "$arm/reg.tmp" && mv "$arm/reg.tmp" "$file"
}

plant_plugin_data() {  # <arm>
  local d="$1/home/.claude/plugins/data"
  mkdir -p "$d/bionic-bionic" "$d/superpowers-bionic"
  printf 'bionic state\n' > "$d/bionic-bionic/state.json"
  printf 'not bionics\n' > "$d/superpowers-bionic/state.json"
}

# `claude` stub: `plugin list --json` answers with bionic registered (or not),
# `plugin prune --dry-run` answers with orphans (or not). Everything else is a
# plain recorder.
plant_claude_stub() {  # <arm> <registered:yes|no> <orphans:yes|no>
  local arm="$1" registered="$2" orphans="$3"
  local listing='[]' prune_out='No auto-installed plugins to prune.'
  [ "$registered" = "yes" ] && listing='[{"id":"bionic@bionic","version":"0.1.0","scope":"user","enabled":true}]'
  [ "$orphans" = "yes" ] && prune_out='2 auto-installed plugins no longer needed at user scope:
  superpowers@bionic (6.3.0)
  agent-skills@bionic (0.6.7)
(dry run — nothing removed)'
  cat > "$arm/bin/claude" <<STUB
#!/bin/bash
echo "claude \$*" >> "\$BIONIC_TEST_CALLS"
case "\$*" in
  "plugin list --json") printf '%s\n' '${listing}' ;;
  "plugin prune --dry-run") printf '%s\n' '${prune_out}' ;;
  "mcp get"*) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$arm/bin/claude"
}

# `claude` stub whose `plugin uninstall` recreates plugins/data/bionic-bionic
# as a side effect — the exact shape of Chris's live-teardown finding
# (r1-surface-map.md Item 4): bionic registered, one orphan to prune, and the
# uninstall itself repopulates the data directory it was supposed to empty.
plant_claude_stub_data_recreated() {  # <arm>
  local arm="$1"
  cat > "$arm/bin/claude" <<'STUB'
#!/bin/bash
echo "claude $*" >> "$BIONIC_TEST_CALLS"
DATA_DIR="${BIONIC_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data}"
case "$*" in
  "plugin list --json") printf '%s\n' '[{"id":"bionic@bionic","version":"0.1.0","scope":"user","enabled":true}]' ;;
  "plugin prune --dry-run") printf '%s\n' '1 auto-installed plugin no longer needed at user scope:
  superpowers@bionic (6.3.0)
(dry run — nothing removed)' ;;
  "plugin uninstall bionic@bionic --yes")
    mkdir -p "${DATA_DIR}/bionic-bionic"
    printf 'recreated by uninstall\n' > "${DATA_DIR}/bionic-bionic/state.json"
    ;;
  "mcp get"*) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$arm/bin/claude"
}

answers_file() {  # <path> <token> [count]
  local path="$1" token="$2" count="${3:-60}" i
  : > "$path"
  for ((i = 0; i < count; i++)); do echo "$token" >> "$path"; done
}

ALL_YES="$TMP/answers-yes"; answers_file "$ALL_YES" y
ALL_NO="$TMP/answers-no";  answers_file "$ALL_NO" n

# One run of a remove script against one arm. The env vars are exactly the
# roots the payload libraries already read, plus the two this script adds.
run_remove() {  # <script> <arm> <answers-file> [extra env assignments...]
  local script="$1" arm="$2" answers="$3"; shift 3
  env -i \
    HOME="$arm/home" \
    PATH="$arm/bin" \
    BIONIC_TEST_CALLS="$arm/calls.log" \
    BIONIC_CLAUDE_HOME="$arm/home/.claude" \
    BIONIC_SETTINGS_FILE="$arm/home/.claude/settings.json" \
    BIONIC_SHELL_RC="$arm/home/.zshrc" \
    BIONIC_PLUGIN_DATA_DIR="$arm/home/.claude/plugins/data" \
    BIONIC_INSTALLED_PLUGINS_FILE="$arm/home/.claude/plugins/installed_plugins.json" \
    BIONIC_PLAYWRIGHT_CACHE="$arm/home/.cache/ms-playwright" \
    BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
    "$@" \
    bash "$script" < "$answers" 2>&1
}

# Names + content of every file under a directory, path-relative so two arms
# are comparable and an arm is comparable with itself across a run.
fingerprint() {  # <dir>
  local d="$1"
  [ -d "$d" ] || { echo "MISSING $d"; return 0; }
  ( cd "$d" && find . -print | sort && find . -type f -print0 | sort -z | xargs -0 shasum 2>/dev/null )
}

# ---------------------------------------------------------------------------

echo "=== Group 1: the deliverables exist and are well-formed ==="

expect_true "payload/scripts/remove.sh exists" test -f "$REMOVE_SH"
expect_true "payload/commands/remove.md exists" test -f "$REMOVE_MD"
expect_true "remove.sh passes bash -n" bash -n "$REMOVE_SH"
expect_true "remove.sh is executable" test -x "$REMOVE_SH"

echo ""
echo "=== Group 2: the wrapper adds NO logic (ownership-table agreement test) ==="

if [ -f "$REMOVE_MD" ]; then
  MD_TEXT="$(cat "$REMOVE_MD")"

  expect_contains "remove.md invokes the script via literal \${CLAUDE_PLUGIN_ROOT}" \
    '${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh' "$MD_TEXT"

  # Every teardown mechanic the script owns, asserted ABSENT from the wrapper.
  # A wrapper that knew any of these would be a second author of the footprint.
  for needle in 'rm -rf' 'jq ' 'npm uninstall' 'uv tool uninstall' \
                'claude plugin uninstall' 'claude plugin prune' \
                'bionic:start' 'bionic-profile-begin' \
                'CLAUDE_CODE_ENABLE_TODO_TOOLS' 'plugins/data' 'settings.json'; do
    expect_not_contains "remove.md carries no teardown logic: '${needle}'" "$needle" "$MD_TEXT"
  done

  # The only script invocation in the file is remove.sh itself.
  sh_tokens="$(grep -oE '[^[:space:]"'"'"'`]+\.sh' "$REMOVE_MD" 2>/dev/null | sort -u)"
  expect_eq "remove.md names exactly one script, the rooted remove.sh" \
    '${CLAUDE_PLUGIN_ROOT}/scripts/remove.sh' "$sh_tokens"

  # Frontmatter description (command-format.test.sh owns the convention; this
  # pin is here so the wrapper rule is provable from this suite alone).
  desc="$(awk '/^---$/ { c++; next } c==1 && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit } c>=2 { exit }' "$REMOVE_MD")"
  # `test -n` on the value directly — never interpolated into a `bash -c` string,
  # where an apostrophe in the description would break the quoting rather than
  # the rule.
  expect_true "remove.md frontmatter has a non-empty description" test -n "$desc"
else
  echo "SKIP: Group 2 (remove.md missing)"
fi

echo ""
echo "=== Group 3: the never-list survives an ALL-YES run (the wall) ==="

ARM="$(new_arm never-list)"
plant_never_list "$ARM"
plant_zshrc_marked "$ARM"
plant_todo_export "$ARM"
plant_legacy_channel_hooks "$ARM"
plant_profile_block "$ARM"
plant_plugin_data "$ARM"
plant_claude_stub "$ARM" yes yes
# npm reports @playwright/cli present so the lane-3b removal path is live.
make_stub "$ARM/bin" npm 'true'

FP_BIONIC_HOME_BEFORE="$(fingerprint "$ARM/home/.bionic")"
FP_BIONIC_PROJ_BEFORE="$(fingerprint "$ARM/project/.bionic")"
FP_RG_BEFORE="$(shasum "$ARM/bin/rg" | awk '{print $1}')"
FP_GIT_BEFORE="$(shasum "$ARM/bin/git" | awk '{print $1}')"

OUT_ALLYES="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"

expect_eq "all-yes: HOME/.bionic tree byte-identical" \
  "$FP_BIONIC_HOME_BEFORE" "$(fingerprint "$ARM/home/.bionic")"
expect_eq "all-yes: project/.bionic tree byte-identical" \
  "$FP_BIONIC_PROJ_BEFORE" "$(fingerprint "$ARM/project/.bionic")"
expect_true "all-yes: HOME/.bionic/memory/note.md still present" test -f "$ARM/home/.bionic/memory/note.md"
expect_eq "all-yes: shared binary rg untouched" "$FP_RG_BEFORE" "$(shasum "$ARM/bin/rg" | awk '{print $1}')"
expect_eq "all-yes: shared binary git untouched" "$FP_GIT_BEFORE" "$(shasum "$ARM/bin/git" | awk '{print $1}')"
expect_contains "all-yes: the summary names what is left in place by design" \
  "Left in place by design" "$OUT_ALLYES"
# R-1: the transcript's second line used to be `mode: payload — the plugin's
# libraries are beside this script`, which is the script telling the user which
# of its own branches it took. What a user needs from that line is whether the
# full teardown is available.
expect_contains "all-yes: the run says what it can do, in words" \
  "running from the plugin" "$OUT_ALLYES"
expect_not_contains "all-yes: and not as an internal mode value" "mode: payload" "$OUT_ALLYES"

# The keep-shared policy is three-valued: consent does not unlock it.
CALLS_ALLYES="$(cat "$ARM/calls.log")"
expect_not_contains "all-yes: no brew uninstall of a keep-shared row" "brew uninstall" "$CALLS_ALLYES"
expect_contains "all-yes: the shared binaries are reported, not removed" \
  "kept — shared with other tools" "$OUT_ALLYES"
# R-1: and the POLICY NAME never reaches the terminal — `keep-shared` is a column
# value in deps.sh's table, not a thing a user has any way to know.
expect_not_contains "all-yes: and the removal-policy value is not printed at the user" \
  "keep-shared" "$OUT_ALLYES"

echo ""
echo "=== Group 4: per-item consent — an ALL-NO run leaves the machine byte-identical ==="

ARM="$(new_arm all-no)"
plant_never_list "$ARM"
plant_zshrc_marked "$ARM"
plant_todo_export "$ARM"
plant_legacy_channel_hooks "$ARM"
plant_profile_block "$ARM"
plant_plugin_data "$ARM"
plant_claude_stub "$ARM" yes yes
make_stub "$ARM/bin" npm 'true'

FP_HOME_BEFORE="$(fingerprint "$ARM/home")"
OUT_ALLNO="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_NO")"
expect_eq "all-no: the entire fixture HOME is byte-identical after a declined run" \
  "$FP_HOME_BEFORE" "$(fingerprint "$ARM/home")"

CALLS_ALLNO="$(cat "$ARM/calls.log")"
expect_not_contains "all-no: the native uninstall was never invoked" "plugin uninstall" "$CALLS_ALLNO"
expect_not_contains "all-no: prune was never executed" "plugin prune --yes" "$CALLS_ALLNO"
expect_contains "all-no: declined items are reported as skipped" "skipped" "$OUT_ALLNO"

echo ""
echo "=== Group 5: .zshrc strip — both variants, fixture-faithful to claude-reset.sh ==="

ARM="$(new_arm zshrc-marked)"
plant_zshrc_marked "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
RC_TEXT="$(cat "$ARM/home/.zshrc")"
expect_not_contains "marked variant: the bionic:start marker is gone" "bionic:start" "$RC_TEXT"
expect_not_contains "marked variant: the bionic:end marker is gone" "bionic:end" "$RC_TEXT"
expect_not_contains "marked variant: the alias line is gone" "dangerously-skip-permissions" "$RC_TEXT"
expect_contains "marked variant: unrelated rc lines survive (EDITOR)" "export EDITOR=vim" "$RC_TEXT"
expect_contains "marked variant: unrelated rc lines survive (PATH)" 'export PATH="$HOME/bin:$PATH"' "$RC_TEXT"

ARM="$(new_arm zshrc-unmarked)"
plant_zshrc_legacy_unmarked "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
RC_TEXT="$(cat "$ARM/home/.zshrc")"
expect_not_contains "unmarked legacy variant: the bare alias line is gone" "dangerously-skip-permissions" "$RC_TEXT"
expect_contains "unmarked legacy variant: unrelated rc lines survive" "export EDITOR=vim" "$RC_TEXT"

# A machine that never had either variant must not be touched at all.
ARM="$(new_arm zshrc-clean)"
printf 'export EDITOR=vim\n' > "$ARM/home/.zshrc"
plant_claude_stub "$ARM" no no
RC_BEFORE="$(shasum "$ARM/home/.zshrc" | awk '{print $1}')"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_eq "clean rc: untouched (no rewrite that happens to produce the same text)" \
  "$RC_BEFORE" "$(shasum "$ARM/home/.zshrc" | awk '{print $1}')"

echo ""
echo "=== Group 6: the TODO_TOOLS export ==="

ARM="$(new_arm todo-export)"
printf 'export EDITOR=vim\n' > "$ARM/home/.zshrc"
plant_todo_export "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
RC_TEXT="$(cat "$ARM/home/.zshrc")"
expect_true "todo export: the live export line is gone" \
  bash -c '! grep -qE "^[[:space:]]*export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1" "$1"' _ "$ARM/home/.zshrc"
expect_contains "todo export: the commented-out line survives (detect.sh does not count it)" \
  "# export CLAUDE_CODE_ENABLE_TODO_TOOLS=1" "$RC_TEXT"
expect_contains "todo export: unrelated rc lines survive" "export EDITOR=vim" "$RC_TEXT"

# The removal predicate and detect.sh's presence predicate are the same regex.
# remove.sh cannot SOURCE detect.sh (the standalone door forbids it), so the
# shared literal is pinned instead — the only other way they stay in step.
TODO_PREDICATE='export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1'
expect_true "remove.sh carries detect.sh's todo-tools predicate verbatim" \
  bash -c 'grep -qF "$1" "$2"' _ "$TODO_PREDICATE" "$REMOVE_SH"
expect_true "detect.sh carries the same predicate (the pin has two ends)" \
  bash -c 'grep -qF "$1" "$2"' _ "$TODO_PREDICATE" "$DETECT_SH"

echo ""
echo "=== Group 7: legacy-channel managed-hook entries in settings.json ==="

ARM="$(new_arm legacy-channel-hooks)"
plant_legacy_channel_hooks "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
SETTINGS_TEXT="$(cat "$ARM/home/.claude/settings.json")"
expect_not_contains "legacy-channel hooks: the ~/.claude/hooks/ PreToolUse entry is gone" \
  ".claude/hooks/protect-main.sh" "$SETTINGS_TEXT"
expect_not_contains "legacy-channel hooks: the ~/.claude/hooks/ Stop entry is gone" \
  ".claude/hooks/landing-gate.sh" "$SETTINGS_TEXT"
expect_contains "legacy-channel hooks: a FOREIGN hook entry survives" "/opt/other-tool/guard.sh" "$SETTINGS_TEXT"
expect_contains "legacy-channel hooks: unrelated settings keys survive" '"model"' "$SETTINGS_TEXT"
expect_true "legacy-channel hooks: the result is still valid JSON" jq -e . "$ARM/home/.claude/settings.json"
expect_eq "legacy-channel hooks: detect.sh now counts zero" "env:legacy-channel-hooks count=0" \
  "$(BIONIC_SETTINGS_FILE="$ARM/home/.claude/settings.json" bash -c '. "$1"; detect_legacy_channel_hooks' _ "$DETECT_SH")"

# THE MODE, which no other assertion here measures. Every settings writer in the
# payload is `write tmp` + `mv`, and `mv` replaces the inode: the file comes back
# wearing the umask's mode rather than its own. ~/.claude/settings.json routinely
# carries an `env` block with tokens, so a machine that chose 0600 for it must
# still have 0600 after /bionic:remove rewrites it — silently widening a
# credential-bearing file to 0644 is a machine side effect, not a formatting
# detail. Both writers that touch this file are asserted: remove.sh's own
# _rm_write (the standalone door) and hooks_strip_legacy_channel (the payload
# door setup calls).
#
# Both directions are asserted for each, so neither arm can pass by pinning one
# constant: a writer that narrowed every file to 0600 fails the 0644 arm.

file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

ARM="$(new_arm hook-strip-mode-600)"
plant_legacy_channel_hooks "$ARM"
plant_claude_stub "$ARM" no no
chmod 600 "$ARM/home/.claude/settings.json"
expect_eq "fixture: settings.json really starts at 0600 (the arm is not vacuous)" \
  "600" "$(file_mode "$ARM/home/.claude/settings.json")"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_not_contains "mode arm: remove.sh really did rewrite the file" \
  ".claude/hooks/protect-main.sh" "$(cat "$ARM/home/.claude/settings.json")"
expect_eq "remove.sh's rewrite leaves a 0600 settings.json at 0600" \
  "600" "$(file_mode "$ARM/home/.claude/settings.json")"

ARM="$(new_arm hook-strip-mode-644)"
plant_legacy_channel_hooks "$ARM"
plant_claude_stub "$ARM" no no
chmod 644 "$ARM/home/.claude/settings.json"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_eq "remove.sh does not narrow a 0644 settings.json either" \
  "644" "$(file_mode "$ARM/home/.claude/settings.json")"

ARM="$(new_arm lib-strip-mode)"
LIB_MODE_SETTINGS="$ARM/home/.claude/settings.json"
plant_legacy_channel_hooks "$ARM"
chmod 600 "$LIB_MODE_SETTINGS"
expect_true "hooks_strip_legacy_channel rewrote the 0600 fixture" \
  bash -c '. "$1"; hooks_strip_legacy_channel "$2"' _ "$HOOKS_SH" "$LIB_MODE_SETTINGS"
expect_not_contains "mode arm: the library really did rewrite the file" \
  ".claude/hooks/protect-main.sh" "$(cat "$LIB_MODE_SETTINGS")"
expect_eq "hooks_strip_legacy_channel leaves a 0600 settings.json at 0600" \
  "600" "$(file_mode "$LIB_MODE_SETTINGS")"

plant_legacy_channel_hooks "$ARM"
chmod 644 "$LIB_MODE_SETTINGS"
expect_true "hooks_strip_legacy_channel rewrote the 0644 fixture too" \
  bash -c '. "$1"; hooks_strip_legacy_channel "$2"' _ "$HOOKS_SH" "$LIB_MODE_SETTINGS"
expect_eq "hooks_strip_legacy_channel does not narrow a 0644 file" \
  "644" "$(file_mode "$LIB_MODE_SETTINGS")"

# R-1. The mode must be right AT THE RENAME, not repaired after it.
#
# The arms above measure the mode once the writer has returned, which a writer
# that publishes a 0644 inode and then chmods it back would also satisfy — while
# leaving the tmp file (predictable name, full settings content, tokens included)
# world-readable for the span before the rename, and while leaving the widening
# PERMANENT if the process dies between `mv` and `chmod`. That second case is the
# very defect these arms were added to close, so the property is stronger than
# they state: the inode the rename publishes is already correct and no repair is
# owed. profile.test.sh Group 14b makes the same measurement on the shared
# `_profile_write`/`_rm_write` body; this is the payload door's own writer, which
# is a different function and cannot be covered by the byte-identity pin below.
#
# The shim shadows only `mv` and `chmod`, and only to observe and to stop the
# clock — `hooks_strip_legacy_channel` itself is the shipped one doing real work.
HOOK_WRITE_SHIM="$TMP/hook-write-instant-shim.sh"
cat > "$HOOK_WRITE_SHIM" <<'SHIM'
_BIONIC_TEST_DEAD=0
mv() {
  { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; } >> "$BIONIC_TEST_MODE_LOG"
  command mv "$@"
  local rc=$?
  _BIONIC_TEST_DEAD=1
  return $rc
}
chmod() {
  if [ "$_BIONIC_TEST_DEAD" = "1" ]; then return 0; fi
  command chmod "$@"
}
SHIM

ARM="$(new_arm lib-strip-mode-instant)"
INST_SETTINGS="$ARM/home/.claude/settings.json"
plant_legacy_channel_hooks "$ARM"
chmod 600 "$INST_SETTINGS"
INST_LOG="$TMP/hook-instant-mode.log"; : > "$INST_LOG"
expect_eq "instant arm fixture: settings.json really starts at 0600" \
  "600" "$(file_mode "$INST_SETTINGS")"
expect_true "hooks_strip_legacy_channel rewrote the instant-arm fixture" \
  env BIONIC_TEST_MODE_LOG="$INST_LOG" \
    bash -c '. "$1"; . "$2"; hooks_strip_legacy_channel "$3"' _ "$HOOKS_SH" "$HOOK_WRITE_SHIM" "$INST_SETTINGS"
expect_true "instant arm: the shimmed rename really was reached (not vacuous)" \
  test -s "$INST_LOG"
expect_eq "hooks_strip_legacy_channel's tmp already wears 0600 when mv renames it" \
  "600" "$(head -1 "$INST_LOG" | tr -d ' ')"
expect_eq "a process that dies the instant that mv lands still leaves it at 0600" \
  "600" "$(file_mode "$INST_SETTINGS")"

# The other direction, so neither arm can pass by hard-coding 0600.
ARM="$(new_arm lib-strip-mode-instant-644)"
INST_SETTINGS_644="$ARM/home/.claude/settings.json"
plant_legacy_channel_hooks "$ARM"
chmod 644 "$INST_SETTINGS_644"
INST_LOG_644="$TMP/hook-instant-mode-644.log"; : > "$INST_LOG_644"
expect_true "hooks_strip_legacy_channel rewrote the 0644 instant-arm fixture" \
  env BIONIC_TEST_MODE_LOG="$INST_LOG_644" \
    bash -c '. "$1"; . "$2"; hooks_strip_legacy_channel "$3"' _ "$HOOKS_SH" "$HOOK_WRITE_SHIM" "$INST_SETTINGS_644"
expect_eq "the tmp for a 0644 settings file is 0644 at the rename, not narrowed" \
  "644" "$(head -1 "$INST_LOG_644" | tr -d ' ')"
expect_eq "and dying right after that rename leaves it at 0644" \
  "644" "$(file_mode "$INST_SETTINGS_644")"

# N-1. The `umask 077` half, measured rather than grepped.
#
# The arms above stop the clock at the RENAME, which is downstream of the chmod:
# a writer whose umask no longer reaches the redirect still hands `mv` a 0600
# tmp, because the chmod put it there. The pin below (`writer_shape_ok`) asserts
# the `umask 077` token is present and above the rename, and a token is not a
# mode — detach the umask from the redirect and every one of those arms stays
# green while the tmp goes back to being born 0644 with the tokens in it. That
# window is the whole of R-1's first half, so it is measured here directly: stop
# the clock at the CHMOD instead, and read the mode the tmp was BORN with.
#
# The fixture is 0644 deliberately. On a 0600 fixture the expected value would
# also be the destination's own mode, and an arm that cannot tell the umask from
# the chmod is the arm that let this through. Here the umask's 0600 and the
# destination's 0644 are different numbers, so only the umask can produce it —
# and the last arm shows the chmod still restores the user's 0644 afterwards.
#
# The ambient umask is pinned to 022 inside the run: what is under test is the
# writer's own umask, not the one the suite happened to inherit, and a runner
# whose umask were already 077 would make this arm pass on the shim's borrowed
# strictness. The shim shadows only `chmod`, and only to observe.
HOOK_UMASK_SHIM="$TMP/hook-umask-birth-shim.sh"
cat > "$HOOK_UMASK_SHIM" <<'SHIM'
chmod() {
  { stat -f '%Lp' "$2" 2>/dev/null || stat -c '%a' "$2" 2>/dev/null; } >> "$BIONIC_TEST_BIRTH_LOG"
  command chmod "$@"
}
SHIM

ARM="$(new_arm lib-strip-umask-birth)"
BIRTH_SETTINGS="$ARM/home/.claude/settings.json"
plant_legacy_channel_hooks "$ARM"
chmod 644 "$BIRTH_SETTINGS"
BIRTH_LOG="$TMP/hook-birth-mode.log"; : > "$BIRTH_LOG"
expect_eq "birth arm fixture: settings.json really starts at 0644" \
  "644" "$(file_mode "$BIRTH_SETTINGS")"
expect_true "hooks_strip_legacy_channel rewrote the birth-arm fixture" \
  env BIONIC_TEST_BIRTH_LOG="$BIRTH_LOG" \
    bash -c 'umask 022; . "$1"; . "$2"; hooks_strip_legacy_channel "$3"' \
      _ "$HOOKS_SH" "$HOOK_UMASK_SHIM" "$BIRTH_SETTINGS"
expect_true "birth arm: the shimmed chmod really was reached (not vacuous)" \
  test -s "$BIRTH_LOG"
expect_eq "the tmp is BORN 0600 under the writer's own umask, before any chmod" \
  "600" "$(head -1 "$BIRTH_LOG" | tr -d ' ')"
expect_eq "and the chmod still hands the destination back its own 0644" \
  "644" "$(file_mode "$BIRTH_SETTINGS")"

echo ""
echo "=== Group 8: the permission marker block (profile_strip semantics) ==="

ARM="$(new_arm profile-block)"
plant_claude_stub "$ARM" no no
plant_profile_block "$ARM"
expect_contains "fixture: the marker block really was applied" \
  "bionic-profile-begin" "$(cat "$ARM/home/.claude/settings.json")"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
SETTINGS_TEXT="$(cat "$ARM/home/.claude/settings.json")"
expect_not_contains "profile: the begin marker is gone" "bionic-profile-begin" "$SETTINGS_TEXT"
expect_not_contains "profile: the end marker is gone" "bionic-profile-end" "$SETTINGS_TEXT"
expect_not_contains "profile: a rendered rule inside the block is gone" \
  "/fixture/plugin/root/scripts/setup.sh" "$SETTINGS_TEXT"
expect_contains "profile: the machine's own accretion rule survives" \
  "the-machines-own-rule" "$SETTINGS_TEXT"
expect_true "profile: the result is still valid JSON" jq -e . "$ARM/home/.claude/settings.json"

# Same pin, other constant pair: the sentinels remove.sh matches on are
# profile.sh's own. A block written under one spelling and hunted under another
# would leave every machine's marker block orphaned in place.
for sentinel in 'Bash(: bionic-profile-begin version=' 'Bash(: bionic-profile-end)'; do
  expect_true "remove.sh carries profile.sh's sentinel verbatim: ${sentinel}" \
    bash -c 'grep -qF "$1" "$2"' _ "$sentinel" "$REMOVE_SH"
  expect_true "profile.sh carries it too (the pin has two ends): ${sentinel}" \
    bash -c 'grep -qF "$1" "$2"' _ "$sentinel" "$PROFILE_SH"
done

# And the third: the legacy-channel managed-hook substring detect.sh counts on.
expect_true "remove.sh carries detect.sh's legacy-channel-hook predicate verbatim" \
  bash -c 'grep -qF ".claude/hooks/" "$1"' _ "$REMOVE_SH"
expect_true "detect.sh carries the same predicate" \
  bash -c 'grep -qF ".claude/hooks/" "$1"' _ "$DETECT_SH"

# D-1. The predicate was pinned; the REWRITE was not, in either direction. Two
# structurally different jq programs did the same job — setup.sh's inline copy
# and remove.sh's — and fixing one file's group-collapse behaviour would have
# left the other silently on the old shape. setup.sh's copy is gone (it calls
# hooks.sh, which it always has beside it); remove.sh's stays, because the
# standalone door has to run where hooks.sh does not exist. So the surviving
# pair is pinned on the program itself.
#
# The two files differ legitimately on exactly one thing: the NAME of the
# variable holding the predicate substring. Extract each program's body and
# neutralise that one difference, then require equality.
jq_strip_program() {  # <file> <VAR_NAME>
  sed -n "/^$2='\$/,/^'\$/p" "$1" \
    | sed -e '1d' -e '$d' -e 's/'"'"'"\${[A-Za-z_][A-Za-z0-9_]*}"'"'"'/<PREDICATE>/g'
}
LIB_STRIP_PROGRAM="$(jq_strip_program "$HOOKS_SH" BIONIC_LEGACY_HOOK_STRIP_JQ)"
RM_STRIP_PROGRAM="$(jq_strip_program "$REMOVE_SH" RM_LEGACY_HOOK_STRIP_JQ)"
expect_true "the library's strip program was extracted (the pin is not vacuous)" \
  test -n "$LIB_STRIP_PROGRAM"
expect_true "remove.sh's inline strip program was extracted" test -n "$RM_STRIP_PROGRAM"
expect_eq "hooks.sh and remove.sh's standalone copy are the same strip program" \
  "$LIB_STRIP_PROGRAM" "$RM_STRIP_PROGRAM"
expect_true "the extracted program is the real one (it carries the predicate)" \
  bash -c 'case "$1" in *"<PREDICATE>"*) exit 0 ;; esac; exit 1' _ "$LIB_STRIP_PROGRAM"

# C-6. The same argument, unchanged, applied to the COUNT — which the strip pin
# left out. hooks.sh's own header states the case: "Only the SUBSTRING was
# pinned between them, never the rewrite: fix one file's group-collapse
# behaviour and the other silently keeps the old one." detect.sh's count and
# remove.sh's are the same jq program modulo the predicate's variable name, and
# detect.sh is the DECLARED single source for machine facts — its ownership row
# reads "no second detect implementation (grep wall); doors call detect.sh",
# while remove.sh's standalone door carries exactly such a second
# implementation. It is entitled to (the door has to run where the libraries do
# not), which makes it a decision needing a pin, not a violation.
#
# The pin could not reach it before: detect.sh spelled its program INLINE inside
# the function, so there was no assignment for the extractor to find. It is a
# named variable now, in the same shape remove.sh's is, and the two are compared
# the way the strip programs are.
COUNT_PROGRAM_DETECT="$(jq_strip_program "$DETECT_SH" DETECT_LEGACY_HOOK_COUNT_JQ)"
COUNT_PROGRAM_RM="$(jq_strip_program "$REMOVE_SH" RM_LEGACY_HOOK_COUNT_JQ)"
expect_true "detect.sh's count program was extracted (the pin is not vacuous)" \
  test -n "$COUNT_PROGRAM_DETECT"
expect_true "remove.sh's inline count program was extracted" test -n "$COUNT_PROGRAM_RM"
expect_eq "detect.sh and remove.sh's standalone copy are the same count program" \
  "$COUNT_PROGRAM_DETECT" "$COUNT_PROGRAM_RM"
expect_true "the extracted count program is the real one (it carries the predicate)" \
  bash -c 'case "$1" in *"<PREDICATE>"*) exit 0 ;; esac; exit 1' _ "$COUNT_PROGRAM_DETECT"
expect_true "and it is the counting program, not the stripping one" \
  bash -c 'case "$1" in *"| length"*) exit 0 ;; esac; exit 1' _ "$COUNT_PROGRAM_DETECT"

# C-1's corollary. The settings WRITER is the second thing duplicated across the
# payload/standalone seam — profile.sh's `_profile_write` and remove.sh's
# `_rm_write` are the same function under two names, and the mode-preservation
# fix above had to be made in both. D-1's argument applies unchanged: pinning the
# behaviour in one file and not the other is how the two drift. The only
# legitimate difference is the function's NAME, so that is what gets neutralised.
sh_function_body() {  # <file> <fn-name>
  sed -n "/^$2() {/,/^}/p" "$1" | sed -e '1s/^[A-Za-z_][A-Za-z0-9_]*()/<WRITER>()/'
}
PROFILE_WRITER="$(sh_function_body "$PROFILE_SH" _profile_write)"
RM_WRITER="$(sh_function_body "$REMOVE_SH" _rm_write)"
expect_true "profile.sh's writer was extracted (the pin is not vacuous)" test -n "$PROFILE_WRITER"
expect_true "remove.sh's writer was extracted" test -n "$RM_WRITER"
expect_eq "profile.sh and remove.sh carry the same settings writer" "$PROFILE_WRITER" "$RM_WRITER"
expect_true "the extracted writer is the real one (it carries the mode capture)" \
  bash -c 'case "$1" in *"stat -f"*) exit 0 ;; esac; exit 1' _ "$PROFILE_WRITER"

# R-1's pin, and the reason it is SHAPE rather than byte-identity. There is a
# THIRD settings writer — hooks.sh's `hooks_strip_legacy_channel` — and the pin
# above cannot reach it: it is a jq rewrite with its own failure cleanup, not the
# same function under a third name, so byte-equality would be a false demand. The
# ORDERING is what all three must share, and it is what R-1 found missing:
#
#   1. the tmp is created inside a `umask 077` subshell, so the file that holds
#      the settings content is never briefly world-readable under a predictable
#      name; and
#   2. the captured mode is applied to the TMP, BEFORE the rename, so `mv`
#      publishes an already-correct inode and a crash right after it owes nothing.
#
# A writer that chmods the DESTINATION is the pre-R-1 shape and fails (2) here.
writer_shape_ok() {  # <label> <body>
  local body="$2" umask_line chmod_line mv_line
  case "$body" in *"umask 077"*) ;; *) return 1 ;; esac
  # Line numbers, so "chmod before mv" is asserted as ordering and not merely as
  # co-presence — the pre-R-1 body contains both tokens too.
  umask_line="$(printf '%s\n' "$body" | grep -n 'umask 077' | head -1 | cut -d: -f1)"
  chmod_line="$(printf '%s\n' "$body" | grep -n 'chmod "\$mode" "\$tmp"' | head -1 | cut -d: -f1)"
  mv_line="$(printf '%s\n' "$body" | grep -n 'mv "\$tmp"' | head -1 | cut -d: -f1)"
  [ -n "$umask_line" ] && [ -n "$chmod_line" ] && [ -n "$mv_line" ] || return 1
  [ "$umask_line" -lt "$mv_line" ] && [ "$chmod_line" -lt "$mv_line" ]
}

HOOKS_WRITER="$(sh_function_body "$HOOKS_SH" hooks_strip_legacy_channel)"
expect_true "hooks.sh's writer was extracted (the third-writer pin is not vacuous)" \
  test -n "$HOOKS_WRITER"
expect_true "profile.sh's writer chmods the tmp under umask 077 before the rename" \
  writer_shape_ok profile "$PROFILE_WRITER"
expect_true "remove.sh's writer does too" \
  writer_shape_ok remove "$RM_WRITER"
expect_true "and so does hooks.sh's, which byte-identity cannot reach" \
  writer_shape_ok hooks "$HOOKS_WRITER"
# The shape check discriminates: the pre-R-1 body — same tokens, chmod after the
# rename and on the destination — must fail it, or it is pinning nothing.
PRE_R1_BODY='_w() {
  mv "$tmp" "$file" || return 1
  [ -n "$mode" ] && chmod "$mode" "$file"
}'
expect_false "the pre-R-1 writer shape (chmod after mv, on the destination) fails this pin" \
  writer_shape_ok pre-r1 "$PRE_R1_BODY"

# The FOURTH writer, and the wall that stops a fifth appearing unpinned.
#
# deps.sh records and clears the statusline, and both of those are edits to the
# same ~/.claude/settings.json — two more `jq … > tmp && mv` writers, which the
# three pins above said nothing about. They were measurably worse than the ones
# above ever were: no mode capture at all, so a 0600 settings.json came back at
# 0644 on EVERY install and every removal, no crash required. They are now one
# shared writer, `_dep_settings_write_jq`, and it is held to the same shape.
DEPS_WRITER="$(sh_function_body "$DEPS_SH" _dep_settings_write_jq)"
expect_true "deps.sh's settings writer was extracted (the fourth-writer pin is not vacuous)" \
  test -n "$DEPS_WRITER"
expect_true "and deps.sh's writer chmods the tmp under umask 077 before the rename too" \
  writer_shape_ok deps "$DEPS_WRITER"

# The wall. A pin over the writers that exist cannot stop a SIXTH being written
# beside them, and that is exactly how deps.sh's two came to be missed: nothing
# failed when they were added. Every rename of a tmp over a settings file in the
# payload is counted, and the count is pinned to the writers that are pinned
# above — `_profile_write`/`_rm_write` rename over a generic `$file` and are held
# by byte-identity, so the signature that matters here is the settings-named one.
# A new one fails this arm and its author has to route through a pinned writer or
# extend the pin.
SETTINGS_MV_LINES="$(/usr/bin/grep -rln 'mv "\$tmp" "\$settings"' "${REPO}/payload" | sort)"
expect_eq "exactly two files in the payload rename a tmp over a settings file" \
  "${REPO}/payload/scripts/lib/deps.sh
${REPO}/payload/scripts/lib/hooks.sh" \
  "$SETTINGS_MV_LINES"
expect_eq "and deps.sh does it in exactly one place (both statusline arms share one writer)" \
  "1" "$(/usr/bin/grep -c 'mv "\$tmp" "\$settings"' "$DEPS_SH" | tr -d ' ')"
# The same count for hooks.sh, because the file list above cannot see inside a
# file: a SECOND writer appended to hooks.sh leaves the list at two names and
# walks past the wall. deps.sh was counted and hooks.sh was not, which made the
# wall asymmetric between the only two files it names.
expect_eq "and hooks.sh does it in exactly one place too (a second writer inside it is not a new file)" \
  "1" "$(/usr/bin/grep -c 'mv "\$tmp" "\$settings"' "$HOOKS_SH" | tr -d ' ')"

# F-S4. The consent RULE, pinned across the payload/standalone seam.
#
# remove.sh's standalone door reimplements the prompt as `_rm_consent`, because
# on the machine that door exists for, deps.sh is gone. Both gates are exercised
# — Group 15's mutation 3 here, setup.test.sh's all-decline arms there — but
# nothing asserted the two obey the SAME rule, so an edit to one was invisible
# to the other. The rule has two halves and both are load-bearing: only an
# explicit yes proceeds, and EOF on stdin declines (the fail-closed direction,
# which is what makes an unattended run safe).
for consent_rule in \
  'IFS= read -r answer || { echo ""; return 1; }' \
  'case "$answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac'
do
  expect_true "remove.sh's _rm_consent carries the rule verbatim: ${consent_rule}" \
    bash -c 'grep -qF "$1" "$2"' _ "$consent_rule" "$REMOVE_SH"
  expect_true "deps.sh's _dep_consent carries it too (the pin has two ends): ${consent_rule}" \
    bash -c 'grep -qF "$1" "$2"' _ "$consent_rule" "$DEPS_SH"
done

echo ""
echo "=== Group 9: payload mode and standalone mode agree on the profile strip ==="

# The one place remove.sh has two implementations: it calls profile.sh's
# profile_strip when the library is beside it, and its own inline strip when it
# is not. Two implementations of one behavior is exactly the drift the
# ownership table exists to prevent, so the two are pinned against each other:
# same fixture in, byte-identical settings file out.
STANDALONE_DIR="$TMP/standalone"
mkdir -p "$STANDALONE_DIR"
cp "$REMOVE_SH" "$STANDALONE_DIR/remove.sh" 2>/dev/null
expect_true "standalone copy has NO lib/ directory beside it" bash -c '[ ! -d "$1/lib" ]' _ "$STANDALONE_DIR"

ARM_P="$(new_arm strip-payload)"; plant_claude_stub "$ARM_P" no no; plant_profile_block "$ARM_P"
ARM_S="$(new_arm strip-standalone)"; plant_claude_stub "$ARM_S" no no; plant_profile_block "$ARM_S"
expect_eq "fixture parity: both arms start byte-identical" \
  "$(shasum < "$ARM_P/home/.claude/settings.json")" "$(shasum < "$ARM_S/home/.claude/settings.json")"

OUT_P="$(run_remove "$REMOVE_SH" "$ARM_P" "$ALL_YES")"
OUT_S="$(run_remove "$STANDALONE_DIR/remove.sh" "$ARM_S" "$ALL_YES")"
expect_eq "payload-mode strip and standalone-mode strip produce byte-identical settings" \
  "$(shasum < "$ARM_P/home/.claude/settings.json")" "$(shasum < "$ARM_S/home/.claude/settings.json")"

# D-3(a). The arm above is a single fixture, and its accretion rule keeps
# `permissions.allow` non-empty after the block comes out — so the two
# container-collapse branches never execute and the differential says nothing
# about them. This second arm plants the block as the ONLY allow entry, which
# is the ordinary state of a machine that never added a rule of its own.
ARM_P2="$(new_arm strip-payload-blockonly)"
plant_claude_stub "$ARM_P2" no no; plant_profile_block "$ARM_P2" block-only
ARM_S2="$(new_arm strip-standalone-blockonly)"
plant_claude_stub "$ARM_S2" no no; plant_profile_block "$ARM_S2" block-only
expect_eq "block-only fixture parity: both arms start byte-identical" \
  "$(shasum < "$ARM_P2/home/.claude/settings.json")" "$(shasum < "$ARM_S2/home/.claude/settings.json")"

run_remove "$REMOVE_SH" "$ARM_P2" "$ALL_YES" >/dev/null 2>&1
run_remove "$STANDALONE_DIR/remove.sh" "$ARM_S2" "$ALL_YES" >/dev/null 2>&1
expect_eq "block-only: payload and standalone strips still produce byte-identical settings" \
  "$(shasum < "$ARM_P2/home/.claude/settings.json")" "$(shasum < "$ARM_S2/home/.claude/settings.json")"
# And the collapse actually happened — otherwise the arm proves only that two
# implementations agree on doing nothing.
P2_TEXT="$(cat "$ARM_P2/home/.claude/settings.json")"
expect_not_contains "block-only: the emptied permissions object is deleted, not left as {}" \
  '"permissions"' "$P2_TEXT"
expect_contains "block-only: the unrelated settings key survives" '"model"' "$P2_TEXT"

echo ""
echo "=== Group 10: the STANDALONE door (no payload libraries anywhere) ==="

ARM="$(new_arm standalone-door)"
plant_never_list "$ARM"
plant_zshrc_marked "$ARM"
plant_todo_export "$ARM"
plant_legacy_channel_hooks "$ARM"
plant_profile_block "$ARM"
plant_plugin_data "$ARM"
# The machine this door exists for: the plugin is already gone from the CLI.
plant_claude_stub "$ARM" no no

FP_NEVER_BEFORE="$(fingerprint "$ARM/home/.bionic")"
OUT_STANDALONE="$(run_remove "$STANDALONE_DIR/remove.sh" "$ARM" "$ALL_YES")"
RC_TEXT="$(cat "$ARM/home/.zshrc")"
SETTINGS_TEXT="$(cat "$ARM/home/.claude/settings.json")"

expect_contains "standalone: announces the mode it is running in" "standalone" "$OUT_STANDALONE"
# R-1: it announces it in words, not as `mode: <internal value>` — the transcript's
# second line was the internal runtime word, printed before anything else.
expect_not_contains "standalone: and not as an internal mode value" "mode: standalone" "$OUT_STANDALONE"
expect_not_contains "standalone: the zshrc block was still removed" "bionic:start" "$RC_TEXT"
expect_true "standalone: the todo-tools export was still removed" \
  bash -c '! grep -qE "^[[:space:]]*export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1" "$1"' _ "$ARM/home/.zshrc"
expect_not_contains "standalone: the legacy-channel managed-hook entry was still removed" \
  ".claude/hooks/protect-main.sh" "$SETTINGS_TEXT"
expect_not_contains "standalone: the permission marker block was still removed" \
  "bionic-profile-begin" "$SETTINGS_TEXT"
expect_contains "standalone: the machine's own accretion rule still survives" \
  "the-machines-own-rule" "$SETTINGS_TEXT"
expect_true "standalone: bionic plugin data was still removed" \
  bash -c '[ ! -d "$1" ]' _ "$ARM/home/.claude/plugins/data/bionic-bionic"
expect_true "standalone: another plugin's data was NOT touched" \
  test -f "$ARM/home/.claude/plugins/data/superpowers-bionic/state.json"
expect_eq "standalone: the never-list still survives an all-yes run" \
  "$FP_NEVER_BEFORE" "$(fingerprint "$ARM/home/.bionic")"

# Honesty, both halves: the dependency table is not available standalone, and
# there is no plugin left to uninstall.
expect_contains "standalone: the lane-3b step is reported as unavailable, not silently skipped" \
  "not available standalone" "$OUT_STANDALONE"
expect_contains "standalone: the uninstall step reports the plugin is not registered" \
  "not registered" "$OUT_STANDALONE"
CALLS_STANDALONE="$(cat "$ARM/calls.log")"
expect_not_contains "standalone: no uninstall was invoked for an absent plugin" \
  "plugin uninstall" "$CALLS_STANDALONE"
expect_contains "standalone: it still asked the CLI what is registered" \
  "plugin list --json" "$CALLS_STANDALONE"

# The door's whole premise: the script never sources a payload library.
expect_true "standalone: run completed and printed its end summary" \
  bash -c 'case "$1" in *"remove complete"*|*"remove finished"*) exit 0 ;; *) exit 1 ;; esac' _ "$OUT_STANDALONE"

echo ""
echo "=== Group 10b: the standalone door on a machine with NO text tools ==="

# The half-uninstalled machine the door serves is not a healthy one, and a
# `grep` that is missing — or shadowed by a lookalike on the user's PATH —
# would otherwise report a dirty machine as clean. So the door is driven here
# against a PATH holding only bash, the three file-mutating utilities bash has
# no builtin for, and jq: no grep, no awk, no sed, no cat, no tr, no find.
BARE_BIN="$TMP/bare-bin"
mkdir -p "$BARE_BIN"
for real in bash rm mv mkdir jq; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BARE_BIN}/${real}" 2>/dev/null
done

ARM="$(new_arm bare-path)"
plant_never_list "$ARM"
plant_zshrc_marked "$ARM"
plant_todo_export "$ARM"
plant_legacy_channel_hooks "$ARM"
plant_profile_block "$ARM"
plant_plugin_data "$ARM"
plant_claude_stub "$ARM" no no
# PATH is replaced wholesale, so even the fixture's own stubs are out of reach
# except the ones planted in the bare dir.
cp "$ARM/bin/claude" "$BARE_BIN/claude" 2>/dev/null
rm -rf "$ARM/bin"; mkdir -p "$ARM/bin"; cp -R "$BARE_BIN/." "$ARM/bin/"

OUT_BARE="$(run_remove "$STANDALONE_DIR/remove.sh" "$ARM" "$ALL_YES")"
RC_TEXT="$(cat "$ARM/home/.zshrc")"
SETTINGS_TEXT="$(cat "$ARM/home/.claude/settings.json")"
expect_not_contains "bare PATH: the marker block was still found and removed" "bionic:start" "$RC_TEXT"
expect_contains "bare PATH: unrelated rc lines still survive" "export EDITOR=vim" "$RC_TEXT"
expect_true "bare PATH: the todo-tools export was still found and removed" \
  bash -c '! grep -qE "^[[:space:]]*export[[:space:]]+CLAUDE_CODE_ENABLE_TODO_TOOLS=1" "$1"' _ "$ARM/home/.zshrc"
expect_not_contains "bare PATH: the permission marker block was still removed" \
  "bionic-profile-begin" "$SETTINGS_TEXT"
expect_not_contains "bare PATH: the legacy-channel managed-hook entry was still removed" \
  ".claude/hooks/protect-main.sh" "$SETTINGS_TEXT"
expect_not_contains "bare PATH: no command-not-found anywhere in the transcript" \
  "command not found" "$OUT_BARE"
expect_eq "bare PATH: the never-list still survives" \
  "$FP_NEVER_BEFORE" "$(fingerprint "$ARM/home/.bionic")"

echo ""
echo "=== Group 11: the tool pass — every class bionic installs itself (payload mode only) ==="
#
# ENUMERATED BY CLASS, NOT BY THE RETIRED LANE VIEW (six-axis review A-1). The
# teardown candidates are `basic|when-needed|extra` — every row except `core`,
# which is the bionic plugin's own declared dependencies and belongs to the
# native uninstall and prune in Group 12. `dep_names_lane 3b` used to compute
# this set as "kind != native", which silently dropped the one native row that
# is not core (A-2, below) and printed the new taxonomy's words over the old
# taxonomy's set.
ARM="$(new_arm toolpass)"
plant_never_list "$ARM"
plant_claude_stub "$ARM" no no
# npm answers "installed" for the package probe, and records the uninstall.
cat > "$ARM/bin/npm" <<'STUB'
#!/bin/bash
echo "npm $*" >> "$BIONIC_TEST_CALLS"
case "$*" in
  "list -g --depth=0 @playwright/cli") echo "/usr/local/lib"; echo "└── @playwright/cli@1.55.0"; exit 0 ;;
  "list -g --depth=0"*) exit 1 ;;
esac
exit 0
STUB
chmod +x "$ARM/bin/npm"

OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
CALLS="$(cat "$ARM/calls.log")"
expect_contains "tool pass: a present consented dep reaches its real uninstall command" \
  "npm uninstall -g @playwright/cli" "$CALLS"
expect_not_contains "tool pass: a shared binary is never uninstalled, consent or not" \
  "brew uninstall" "$CALLS"
# R-1: the policy is stated in words the user can act on, and the table's own
# value for it stays in the table.
expect_contains "tool pass: the shared-binary policy is stated in the transcript" \
  "kept — shared with other tools, bionic never removes it" "$OUT"
expect_not_contains "tool pass: …and stated without the table's column value" "keep-shared" "$OUT"
expect_true "tool pass: the shared binary is still on the fixture PATH" test -x "$ARM/bin/rg"

# ---- A-2: the plugin the JIT route can install, and nothing could remove ----
#
# `install_plugin_native` puts `impeccable@bionic` on a machine mid-session, on
# one consent, from `jit_offer`. It is `kind=native` and class `when-needed`, so
# the old lane-3b walk never saw it — and its `native-uninstall-offer` arm said
# "removed by the plugin uninstall, not here", which is false by construction:
# A-3.1 rules that bionic's plugin.json declares the two core rows only, so
# nothing about removing bionic touches this one. A machine that used the design
# route once kept the plugin after a full, all-yes teardown.
ARM="$(new_arm native-when-needed-present)"
plant_never_list "$ARM"
plant_claude_stub "$ARM" no no
plant_native_plugin "$ARM" impeccable 4.1.1
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
CALLS="$(cat "$ARM/calls.log")"
expect_contains "installed plugin: the teardown asks about it, in the same words as any other row" \
  "Remove impeccable now?" "$OUT"
expect_contains "installed plugin: a consented removal runs the CLI's own uninstall" \
  "plugin uninstall impeccable@bionic" "$CALLS"
expect_not_contains "installed plugin: and never claims some other step already took it" \
  "removed by the plugin uninstall" "$OUT"
# The counter is the only trace a dependency removal leaves in the summary, and
# this arm plants exactly one removable thing, so the count is the assertion.
expect_contains "installed plugin: counted as removed in the summary" "1 removed" "$OUT"

# ---- declined: the offer is an offer ----
ARM="$(new_arm native-when-needed-declined)"
plant_never_list "$ARM"
plant_claude_stub "$ARM" no no
plant_native_plugin "$ARM" impeccable 4.1.1
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_NO")"
CALLS="$(cat "$ARM/calls.log")"
expect_not_contains "installed plugin: a declined offer uninstalls nothing" \
  "plugin uninstall impeccable@bionic" "$CALLS"
expect_contains "installed plugin: and says so in the skipped shape the script already uses" \
  "declined — impeccable left in place." "$OUT"

# ---- absent: no question about a plugin this machine never installed ----
ARM="$(new_arm native-when-needed-absent)"
plant_never_list "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
CALLS="$(cat "$ARM/calls.log")"
expect_not_contains "absent plugin: nothing is asked" "Remove impeccable now?" "$OUT"
expect_not_contains "absent plugin: nothing is uninstalled" \
  "plugin uninstall impeccable@bionic" "$CALLS"
expect_contains "absent plugin: it opens already clean, like any absent row" \
  "dependency impeccable (not installed)" "$OUT"

echo ""
echo "=== Group 12: the native finisher — uninstall, --keep-data, prune ==="

# 12a. Plugin data CONSENTED: the CLI is left to its default (data removed).
ARM="$(new_arm finisher-consented)"
plant_plugin_data "$ARM"
plant_claude_stub "$ARM" yes yes
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
CALLS="$(cat "$ARM/calls.log")"
expect_contains "finisher: the native uninstall is invoked directly (probe VERDICT IMMEDIATE)" \
  "plugin uninstall bionic@bionic" "$CALLS"
expect_not_contains "finisher: no print-the-command fallback branch" \
  "run this command yourself" "$OUT"
expect_not_contains "finisher: --keep-data absent when the user consented to removing plugin data" \
  "--keep-data" "$CALLS"
expect_true "finisher: bionic plugin data really is gone" \
  bash -c '[ ! -d "$1" ]' _ "$ARM/home/.claude/plugins/data/bionic-bionic"
expect_contains "finisher: prune is offered from the CLI's own dry-run listing" \
  "plugin prune --dry-run" "$CALLS"
expect_contains "finisher: a consented prune actually runs" "plugin prune --yes" "$CALLS"

# 12b. Plugin data DECLINED: the declined answer must bind the finisher too,
# because `claude plugin uninstall` deletes the data directory by default.
ARM="$(new_arm finisher-keepdata)"
plant_plugin_data "$ARM"
plant_claude_stub "$ARM" yes no
printf 'n\ny\n' > "$ARM/answers"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ARM/answers")"
CALLS="$(cat "$ARM/calls.log")"
expect_contains "finisher: --keep-data is passed when the user declined plugin-data removal" \
  "--keep-data" "$CALLS"
expect_true "finisher: the declined plugin data survives the native uninstall" \
  test -f "$ARM/home/.claude/plugins/data/bionic-bionic/state.json"

# 12c. No orphans: nothing to prune means nothing is offered.
ARM="$(new_arm finisher-no-orphans)"
plant_claude_stub "$ARM" yes no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
CALLS="$(cat "$ARM/calls.log")"
expect_not_contains "finisher: prune is not executed when the dry-run names no orphans" \
  "plugin prune --yes" "$CALLS"

# 12d. No claude CLI at all — the honest-degradation arm.
ARM="$(new_arm finisher-no-cli)"
plant_zshrc_marked "$ARM"
rm -f "$ARM/bin/claude"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_contains "finisher: a machine with no claude CLI is told so, not failed at" \
  "claude CLI" "$OUT"
expect_not_contains "finisher: the zshrc teardown still completed without the CLI" \
  "bionic:start" "$(cat "$ARM/home/.zshrc")"

echo ""
echo "=== Group 13: the end summary ==="

ARM="$(new_arm summary)"
plant_never_list "$ARM"
plant_zshrc_marked "$ARM"
plant_plugin_data "$ARM"
plant_claude_stub "$ARM" yes no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_contains "summary: counts line names removed" "removed" "$OUT"
expect_contains "summary: counts line names already clean" "already clean" "$OUT"
expect_contains "summary: counts line names skipped" "skipped" "$OUT"
expect_contains "summary: names .bionic trees as left in place by design" ".bionic/" "$OUT"
expect_contains "summary: names shared binaries as left in place by design" "shared" "$OUT"
expect_contains "summary: tells the user how to restore" "install" "$OUT"

echo ""
echo "=== Group 14: exit status ==="

ARM="$(new_arm exit-status)"
plant_zshrc_marked "$ARM"
plant_claude_stub "$ARM" yes no
run_remove "$REMOVE_SH" "$ARM" "$ALL_YES" >/dev/null 2>&1
expect_eq "a completed run exits 0" "0" "$?"

ARM="$(new_arm exit-status-declined)"
plant_zshrc_marked "$ARM"
plant_claude_stub "$ARM" yes no
run_remove "$REMOVE_SH" "$ARM" "$ALL_NO" >/dev/null 2>&1
expect_eq "a fully declined run also exits 0 (declining is not an error)" "0" "$?"

echo ""
echo "=== Group 15: mutation-and-restore — the checks discriminate ==="

# RED evidence dies at green (memory: red-evidence-is-perishable), so the proof
# that these assertions can fail is taken here, against DOCTORED COPIES of the
# production files. The production files are never written.

MUT="$TMP/mutants"; mkdir -p "$MUT"
REMOVE_SH_CKSUM_BEFORE="$(shasum < "$REMOVE_SH")"

# Mutation 1: a remove.sh that ignores the never-list and deletes .bionic.
sed 's|^# ─── Item: the shell rc|rm -rf "${HOME}/.bionic"\n# ─── Item: the shell rc|' "$REMOVE_SH" > "$MUT/remove-nukes-bionic.sh"
if [ "$(shasum < "$MUT/remove-nukes-bionic.sh")" != "$(shasum < "$REMOVE_SH")" ]; then
  ARM="$(new_arm mutant-never-list)"
  plant_never_list "$ARM"
  plant_claude_stub "$ARM" no no
  run_remove "$MUT/remove-nukes-bionic.sh" "$ARM" "$ALL_YES" >/dev/null 2>&1
  expect_false "MUTANT (deletes .bionic): the never-list wall goes red as expected" \
    test -f "$ARM/home/.bionic/memory/note.md"
else
  no "MUTANT (deletes .bionic): mutation did not apply — the anchor comment moved"
fi

# Mutation 2: a remove.md that carries teardown logic — the wrapper rule must catch it.
cp "$REMOVE_MD" "$MUT/remove-with-logic.md" 2>/dev/null
printf '\n```bash\njq "del(.permissions)" ~/.claude/settings.json\n```\n' >> "$MUT/remove-with-logic.md"
mutant_md="$(cat "$MUT/remove-with-logic.md")"
expect_contains "MUTANT (wrapper with logic): the no-logic rule goes red as expected" \
  "jq " "$mutant_md"
mutant_tokens="$(grep -oE '[^[:space:]"'"'"'`]+\.sh' "$MUT/remove-with-logic.md" 2>/dev/null | sort -u)"
expect_true "MUTANT (wrapper with logic): still parses, so the failure is the RULE not a crash" \
  bash -c '[ -n "$1" ]' _ "$mutant_tokens"

# Mutation 3: a consent gate that does not gate — the all-no wall must catch it.
sed 's|^_rm_consent() {|_rm_consent() { return 0; #|' "$REMOVE_SH" > "$MUT/remove-no-consent.sh"
if [ "$(shasum < "$MUT/remove-no-consent.sh")" != "$(shasum < "$REMOVE_SH")" ]; then
  ARM="$(new_arm mutant-consent)"
  plant_zshrc_marked "$ARM"
  plant_claude_stub "$ARM" no no
  FP_RC="$(shasum < "$ARM/home/.zshrc")"
  run_remove "$MUT/remove-no-consent.sh" "$ARM" "$ALL_NO" >/dev/null 2>&1
  if [ "$FP_RC" = "$(shasum < "$ARM/home/.zshrc")" ]; then
    no "MUTANT (consent always yes): the all-no wall failed to discriminate"
  else
    ok "MUTANT (consent always yes): the all-no wall goes red as expected"
  fi
else
  no "MUTANT (consent always yes): mutation did not apply — _rm_consent was renamed"
fi

# Mutation 4: perturb the INLINE profile-strip jq itself. The three mutations
# above cover the never-list, the wrapper rule and the consent gate; none
# touched RM_PROFILE_STRIP_JQ, so Group 9's differential — the only thing
# standing between remove.sh's standalone copy and profile.sh's original — had
# never been shown able to fail. Dropping the container-collapse step is the
# smallest edit that changes the OUTPUT rather than crashing the program, and
# it is invisible on a fixture carrying an accretion rule, which is why this
# runs on the block-only shape.
sed 's|^    then del(\.permissions) else \. end$|    then . else . end|' "$REMOVE_SH" > "$MUT/remove-weak-strip.sh"
if [ "$(shasum < "$MUT/remove-weak-strip.sh")" != "$(shasum < "$REMOVE_SH")" ]; then
  ARM_MP="$(new_arm mutant-strip-payload)"
  plant_claude_stub "$ARM_MP" no no; plant_profile_block "$ARM_MP" block-only
  ARM_MS="$(new_arm mutant-strip-standalone)"
  plant_claude_stub "$ARM_MS" no no; plant_profile_block "$ARM_MS" block-only
  MUT_STANDALONE="$TMP/standalone-mutant"; mkdir -p "$MUT_STANDALONE"
  cp "$MUT/remove-weak-strip.sh" "$MUT_STANDALONE/remove.sh"
  run_remove "$REMOVE_SH" "$ARM_MP" "$ALL_YES" >/dev/null 2>&1
  run_remove "$MUT_STANDALONE/remove.sh" "$ARM_MS" "$ALL_YES" >/dev/null 2>&1
  if [ "$(shasum < "$ARM_MP/home/.claude/settings.json")" = "$(shasum < "$ARM_MS/home/.claude/settings.json")" ]; then
    no "MUTANT (weakened profile strip): Group 9's differential failed to discriminate"
  else
    ok "MUTANT (weakened profile strip): Group 9's differential goes red as expected"
  fi
  expect_contains "MUTANT (weakened profile strip): the mutant leaves the empty permissions object behind" \
    '"permissions"' "$(cat "$ARM_MS/home/.claude/settings.json")"
else
  no "MUTANT (weakened profile strip): mutation did not apply — RM_PROFILE_STRIP_JQ was reshaped"
fi

# The production files are unchanged by every arm above.
expect_true "production remove.sh untouched by the mutation arms" bash -n "$REMOVE_SH"
expect_eq "production remove.sh is byte-identical to before the mutation arms" \
  "$REMOVE_SH_CKSUM_BEFORE" "$(shasum < "$REMOVE_SH")"

echo ""
echo "=== Group 17: the legacy installed skill copy — the thing remove.sh left behind (W5 RV-6) ==="
#
# THE FINDING, and it is the worst kind: remove.sh finished, printed "Claude Code still
# works, without bionic's skills, hooks and agents", and left a rendered canonical-sdlc
# sitting in the CLI's own skills directory with eleven hook registrations in its
# frontmatter. On a pre-plugin machine the user ran a teardown, was told bionic was gone,
# and kept arming bionic's walls every session. Setup step 7 already removed it; the
# REMOVER did not know it existed.
#
# WHY THIS IS AN INLINE PREDICATE AND NOT A detect.sh CALL. remove.sh is the one payload
# script reachable standalone — curl-fetched onto a machine whose plugin is already gone,
# where scripts/lib/ does not exist — so it may not source detect.sh, by the rule stated at
# the top of that file. The established answer is a SHARED LITERAL pinned at both ends, the
# same treatment RM_RC_START and the todo-tools regex get. The predicate is pinned here too,
# not just the name: directory PLUS SKILL.md, because this authorises a recursive delete and
# a bare directory of that name is not evidence the installer rendered anything.

plant_legacy_skill_copy() {  # <arm>
  mkdir -p "$1/home/.claude/skills/canonical-sdlc"
  printf -- '---\nname: canonical-sdlc\nhooks:\n  PreToolUse: []\n---\nThe copy the installer rendered.\n' \
    > "$1/home/.claude/skills/canonical-sdlc/SKILL.md"
}

# ---- consent given: it goes ----
ARM="$(new_arm legacy-skill-copy-yes)"
plant_legacy_skill_copy "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_true "skill copy: consented, the directory is gone" \
  bash -c '! test -e "$1"' _ "$ARM/home/.claude/skills/canonical-sdlc"
# The item's own label, not the word "removed": every step in this script reports
# removals, so a bare "removed" arm would pass on somebody else's line.
RM_SKILL_LABEL="legacy installed skill copy"
expect_contains "skill copy: and the run names THIS item as removed" \
  "✓ ${RM_SKILL_LABEL}" "$OUT"

# ---- consent declined: it stays, and the report says so ----
ARM="$(new_arm legacy-skill-copy-no)"
plant_legacy_skill_copy "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_NO")"
expect_true "skill copy: declined, the directory is untouched" \
  test -f "$ARM/home/.claude/skills/canonical-sdlc/SKILL.md"
# "Skipped" alone is in every run's summary header. What has to be true is that THIS
# item is named in the list under it.
expect_contains "skill copy: declining lands THIS item in the Skipped list, not silence" \
  "${RM_SKILL_LABEL}" "$OUT"

# ---- absent: a no-op, and never a phantom prompt ----
ARM="$(new_arm legacy-skill-copy-absent)"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
# Same trap: "already clean" appears on several lines of a clean run. Pin the label.
expect_contains "skill copy: absent reports THIS item already-clean rather than nothing at all" \
  "${RM_SKILL_LABEL} — already clean" "$OUT"
expect_true "skill copy: absent creates no skills directory as a side effect" \
  bash -c '! test -e "$1"' _ "$ARM/home/.claude/skills"

# ---- IDEMPOTENT: a second all-yes run over the same arm changes nothing more ----
ARM="$(new_arm legacy-skill-copy-twice)"
plant_legacy_skill_copy "$ARM"
plant_claude_stub "$ARM" no no
run_remove "$REMOVE_SH" "$ARM" "$ALL_YES" >/dev/null 2>&1
FP_ONCE="$(fingerprint "$ARM/home")"
run_remove "$REMOVE_SH" "$ARM" "$ALL_YES" >/dev/null 2>&1
expect_eq "skill copy: a second remove run is a no-op on the machine" "$FP_ONCE" "$(fingerprint "$ARM/home")"

# ---- the bare-directory guard: a directory without SKILL.md is not a rendered skill ----
ARM="$(new_arm legacy-skill-copy-bare)"
mkdir -p "$ARM/home/.claude/skills/canonical-sdlc"
printf 'a note the user left here\n' > "$ARM/home/.claude/skills/canonical-sdlc/README.md"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_true "skill copy: a directory with no SKILL.md is NOT deleted (the delete is recursive)" \
  test -f "$ARM/home/.claude/skills/canonical-sdlc/README.md"

# ---- the shared literal and the predicate, pinned at BOTH ends ----
expect_true "remove.sh carries detect.sh's legacy skill name verbatim" \
  bash -c 'grep -qF "canonical-sdlc" "$1"' _ "$REMOVE_SH"
expect_true "detect.sh states it as the constant remove.sh copies" \
  bash -c 'grep -qF "DETECT_LEGACY_SKILL_NAME=" "$1"' _ "$DETECT_SH"
DETECT_SKILL_NAME="$(sed -n "s/^DETECT_LEGACY_SKILL_NAME='\(.*\)'\$/\1/p" "$DETECT_SH" | head -1)"
RM_SKILL_NAME="$(sed -n "s/^RM_LEGACY_SKILL_NAME='\(.*\)'\$/\1/p" "$REMOVE_SH" | head -1)"
expect_eq "the two constants are the same string (the pin has two ends)" \
  "$DETECT_SKILL_NAME" "$RM_SKILL_NAME"
expect_ne "…and neither is empty, which would make the arm above vacuous" "" "$RM_SKILL_NAME"

# ---- the closing claim is TRUE on every machine, which is the other half of RV-6 ----
#
# "Claude Code still works, without bionic's skills, hooks and agents" was printed
# unconditionally, including on the run that had just been told NOT to remove the skill
# copy. A summary that contradicts its own Skipped list four lines above it is worse than
# no summary: it teaches the reader to stop reading it.
ARM="$(new_arm closing-claim-declined)"
plant_legacy_skill_copy "$ARM"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_NO")"
expect_not_contains "closing claim: a run that skipped things does not claim bionic is gone" \
  "without bionic's skills, hooks and agents" "$OUT"
ARM="$(new_arm closing-claim-clean)"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_contains "closing claim: a run that finished everything still says so plainly" \
  "without bionic's skills, hooks and agents" "$OUT"

echo ""
echo "=== Group 18: remove.sh finishes in one pass — the uninstall recreates plugin data (AC-7) ==="
#
# r1-surface-map.md Item 4: `claude plugin uninstall` re-creates an empty
# plugins/data/bionic-bionic directory as a side effect, and the plugin-data
# question in this script only ever ran BEFORE the uninstall — so the
# recreated directory had no code path checking it again before the summary.
# The order is: native uninstall runs, then a re-check of the data directory,
# then the prune offer — all in the same pass, with zero stray dirs left.

ARM="$(new_arm one-pass-recreated-data)"
plant_plugin_data "$ARM"
plant_claude_stub_data_recreated "$ARM"
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
CALLS="$(cat "$ARM/calls.log")"
expect_true "one pass: the uninstall-recreated plugin data directory is gone at the end" \
  bash -c '[ ! -d "$1" ]' _ "$ARM/home/.claude/plugins/data/bionic-bionic"
expect_contains "one pass: the prune offer is reached in the same run" \
  "the CLI reports these auto-installed dependencies are no longer needed" "$OUT"
expect_contains "one pass: a consented prune actually runs" \
  "plugin prune --yes" "$CALLS"
expect_contains "one pass: the uninstall itself ran (this is not a no-op arm)" \
  "plugin uninstall bionic@bionic --yes" "$CALLS"

# ---- a second run over the same arm: the plugin-data item opens already clean ----
OUT2="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_contains "one pass: a second run finds the plugin-data item already clean" \
  "plugin data under ${ARM}/home/.claude/plugins/data — already clean" "$OUT2"
expect_true "one pass: the second run still ends with zero recreated data" \
  bash -c '[ ! -d "$1" ]' _ "$ARM/home/.claude/plugins/data/bionic-bionic"

echo ""
echo "=== Group 19: bionic's default permission mode (A-4.S5.F-RULING (a)) ==="
#
# setup.sh's _setup_default_mode (AC-12) writes `.permissions.defaultMode = "auto"`
# OUTSIDE the marker block the item above strips — a preference of the machine's, not
# one of bionic's rendered rules — so a machine torn down after answering yes to that
# question keeps `defaultMode: auto` behind. This item closes that footprint leftover:
# ask to reset it only when the value is still exactly what bionic offers; any other
# value, or no key at all, is left alone with no question at all.

plant_default_mode() {  # <arm> <value>
  local arm="$1" value="$2" settings="$1/home/.claude/settings.json"
  if [ -f "$settings" ]; then
    jq --arg v "$value" '.permissions.defaultMode = $v' "$settings" > "$arm/tmp.json" && mv "$arm/tmp.json" "$settings"
  else
    printf '{"permissions":{"defaultMode":"%s"}}\n' "$value" > "$settings"
  fi
}

# ---- defaultMode=auto, consent given: the key goes, counted as removed ----
ARM="$(new_arm default-mode-auto-yes)"
plant_default_mode "$ARM" auto
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_contains "default mode: asks the exact question when it is bionic's auto" \
  "Reset Claude Code's default permission mode? bionic set it to auto at setup. [y/N]" "$OUT"
expect_eq "default mode: consented — the key is gone" \
  "" "$(jq -r '.permissions.defaultMode // ""' "$ARM/home/.claude/settings.json")"
expect_contains "default mode: consented — counted as removed" \
  "✓ default permission mode" "$OUT"

# ---- defaultMode=auto, consent declined: the key stays, reported skipped ----
ARM="$(new_arm default-mode-auto-no)"
plant_default_mode "$ARM" auto
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_NO")"
expect_eq "default mode: declined — the key is untouched" \
  "auto" "$(jq -r '.permissions.defaultMode // ""' "$ARM/home/.claude/settings.json")"
expect_contains "default mode: declined — reported in the Skipped list" \
  "default permission mode" "$OUT"
expect_contains "default mode: declined — the skipped-line shape the script already uses" \
  "declined — default permission mode" "$OUT"

# ---- defaultMode=plan (not bionic's value): no question, untouched ----
ARM="$(new_arm default-mode-plan)"
plant_default_mode "$ARM" plan
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_not_contains "default mode: a non-auto value is never asked about" \
  "Reset Claude Code's default permission mode" "$OUT"
expect_eq "default mode: a non-auto value is left exactly as it was" \
  "plan" "$(jq -r '.permissions.defaultMode // ""' "$ARM/home/.claude/settings.json")"
expect_contains "default mode: a non-auto value reports already clean" \
  "default permission mode" "$OUT"

# ---- no key at all: already clean, no question ----
ARM="$(new_arm default-mode-absent)"
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$REMOVE_SH" "$ARM" "$ALL_YES")"
expect_not_contains "default mode: no key — never asked about" \
  "Reset Claude Code's default permission mode" "$OUT"
expect_contains "default mode: no key — already clean" \
  "default permission mode" "$OUT"
expect_contains "default mode: no key — the already-clean shape the script already uses" \
  "default permission mode in ${ARM}/home/.claude/settings.json — already clean" "$OUT"

# ---- D-1: ONE OWNER for the value, and both ends read it ----
#
# `auto` used to be a bare literal in two files — setup.sh wrote it, this script
# compared against it — with nothing making them agree. The reset is DEFINED as
# "the one value bionic knows it wrote", so a setup that started writing
# `acceptEdits` would leave both suites green while the teardown silently matched
# nothing and left the setting behind. deps.sh owns the value now.
#
# THE STANDALONE DOOR IS WHY THIS IS A FALLBACK AND NOT A SECOND OWNER. Fetched
# by URL onto a machine with no payload beside it, this script has no deps.sh to
# read — the same reason every literal in its "shared literals" section exists.
# So: the owner's value when there is an owner, one declared fallback when there
# is not, and the arms below pin the fallback to the owner and pin the BEHAVIOUR
# to whatever the owner currently says.
DEPS_MODE="$(bash -c '. "$1"; printf "%s" "${BIONIC_DEFAULT_PERMISSION_MODE:-}"' _ "$DEPS_SH")"
expect_eq "one owner: deps.sh holds the default permission mode bionic offers" "auto" "$DEPS_MODE"

# Non-comment lines carrying the value as a literal, in either script. The word
# on its own — `automatic` and `auto-update` are not the value, and `${…:-auto}`
# is. Comments are exempt: a comment is where the rule gets explained, and a lint
# that could not tell a prohibition from a violation would forbid writing it down.
auto_literals() {  # <script>
  /usr/bin/grep -nE '(^|[^A-Za-z])auto([^A-Za-z-]|$)' "$1" \
    | /usr/bin/grep -vE '^[0-9]+:[[:space:]]*#' || true
}
expect_eq "one owner: setup.sh carries the value nowhere — it reads the owner's" \
  "" "$(auto_literals "$SETUP_SH")"
RM_AUTO="$(auto_literals "$REMOVE_SH")"
expect_eq "one owner: remove.sh carries exactly one, and it is the standalone fallback" "1" \
  "$(printf '%s' "$RM_AUTO" | /usr/bin/grep -c 'BIONIC_DEFAULT_PERMISSION_MODE:-auto' | tr -d ' ')"
expect_eq "one owner: …and nothing else in remove.sh spells the value out" "1" \
  "$(printf '%s' "$RM_AUTO" | /usr/bin/grep -c . | tr -d ' ')"

# ---- the mutation arm: move the owner's value, and the teardown follows it ----
#
# An agreement test that only reads source can be satisfied by a coincidence.
# This one changes the constant in a COPY of the payload and drives the real
# script against it: the value it resets, and the value it names in the question,
# both have to move.
MUT="$TMP/mutant-payload"; mkdir -p "$MUT/lib"
cp "$REMOVE_SH" "$MUT/remove.sh"
cp "${REPO}/payload/scripts/lib/"*.sh "$MUT/lib/"
sed 's/^BIONIC_DEFAULT_PERMISSION_MODE=.*/BIONIC_DEFAULT_PERMISSION_MODE="plan"/' "$DEPS_SH" > "$MUT/lib/deps.sh"
expect_true "mutation: the copy really carries the moved value" \
  bash -c 'grep -qF "BIONIC_DEFAULT_PERMISSION_MODE=\"plan\"" "$1"' _ "$MUT/lib/deps.sh"

ARM="$(new_arm mutated-owner-plan)"
plant_default_mode "$ARM" plan
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$MUT/remove.sh" "$ARM" "$ALL_YES")"
expect_eq "mutation: the teardown resets the value the owner now names" "" \
  "$(jq -r '.permissions.defaultMode // ""' "$ARM/home/.claude/settings.json")"
expect_contains "mutation: and the question it asks names that value too" \
  "bionic set it to plan at setup." "$OUT"

ARM="$(new_arm mutated-owner-auto)"
plant_default_mode "$ARM" auto
plant_claude_stub "$ARM" no no
OUT="$(run_remove "$MUT/remove.sh" "$ARM" "$ALL_YES")"
expect_eq "mutation: a planted auto is now somebody else's setting and is left alone" \
  "auto" "$(jq -r '.permissions.defaultMode // ""' "$ARM/home/.claude/settings.json")"
expect_not_contains "mutation: and it is not even asked about" \
  "Reset Claude Code's default permission mode?" "$OUT"

# ---- the one-pass property: the item sits with the profile strip, before the finisher ----
expect_true "default mode: the item's source sits before the native-uninstall finisher" \
  bash -c '
    a=$(grep -n "default permission mode:" "$1" | head -1 | cut -d: -f1)
    b=$(grep -n "native plugin uninstall:" "$1" | head -1 | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
  ' _ "$REMOVE_SH"

echo ""
echo "=== Group 16: the suite is registered in tests/run.sh by name ==="

expect_true "tests/run.sh runs remove.test.sh by name" \
  grep -qF 'run "remove.test.sh" bash tests/remove.test.sh' "${REPO}/tests/run.sh"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
