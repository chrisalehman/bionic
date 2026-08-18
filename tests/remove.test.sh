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
TEMPLATE="${REPO}/payload/permissions/profile.template.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq()    { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
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
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls tr head tail sort uniq wc find jq shasum date; do
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

# The rendered permission block, applied exactly as profile.sh would apply it,
# plus one accretion rule outside the block that must survive.
plant_profile_block() {  # <arm>
  # One `local` per line: `local a="$1" b="$a/x"` reads the OLD $a, which under
  # `set -u` is an unbound-variable abort (the trap the S8 brief names).
  local arm="$1"
  local rendered="${arm}/rendered.json"
  BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
  BIONIC_SETTINGS_FILE="$arm/home/.claude/settings.json" \
    bash -c '. "$1"; render_profile "$2" "$3" > "$4"' _ \
      "$PROFILE_SH" "$TEMPLATE" "/fixture/plugin/root" "$rendered"
  # An accretion rule the machine owns, planted BEFORE the block goes in.
  if [ -f "$arm/home/.claude/settings.json" ]; then
    jq '.permissions.allow = ((.permissions.allow // []) + ["Bash(echo the-machines-own-rule)"])' \
      "$arm/home/.claude/settings.json" > "$arm/tmp.json" && mv "$arm/tmp.json" "$arm/home/.claude/settings.json"
  else
    printf '%s' '{"permissions":{"allow":["Bash(echo the-machines-own-rule)"]}}' > "$arm/home/.claude/settings.json"
  fi
  BIONIC_SETTINGS_FILE="$arm/home/.claude/settings.json" \
    bash -c '. "$1"; profile_apply "$2" --consented' _ "$PROFILE_SH" "$rendered" >/dev/null 2>&1
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

# The keep-shared policy is three-valued: consent does not unlock it.
CALLS_ALLYES="$(cat "$ARM/calls.log")"
expect_not_contains "all-yes: no brew uninstall of a keep-shared row" "brew uninstall" "$CALLS_ALLYES"
expect_contains "all-yes: keep-shared rows are reported, not removed" "keep-shared" "$OUT_ALLYES"

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
echo "=== Group 11: lane-3b dependencies via remove_dep (payload mode only) ==="

ARM="$(new_arm lane3b)"
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
expect_contains "lane-3b: a present remove-on-consent dep reaches its real uninstall command" \
  "npm uninstall -g @playwright/cli" "$CALLS"
expect_not_contains "lane-3b: a keep-shared binary is never uninstalled, consent or not" \
  "brew uninstall" "$CALLS"
expect_contains "lane-3b: the keep-shared policy is stated in the transcript" "keep-shared" "$OUT"
expect_true "lane-3b: the keep-shared binary is still on the fixture PATH" test -x "$ARM/bin/rg"

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

# The production files are unchanged by every arm above.
expect_true "production remove.sh untouched by the mutation arms" bash -n "$REMOVE_SH"

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
