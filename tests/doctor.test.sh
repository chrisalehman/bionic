#!/bin/bash
# DOCTOR — epic-17 wave-03 slice S7 (spec AC-3; design ownership table: doctor is
# the RENDERING SURFACE of detect.sh's facts, the dependency-constraint agreement
# surface, and the permission-profile diff).
#
# WHAT THIS SUITE OWNS. payload/scripts/doctor.sh and payload/commands/doctor.md
# — the read-only diagnosis and its thin wrapper. Not the facts themselves:
# detect.sh's and deps.sh's behaviour is tests/plugin-lib.test.sh's subject and
# profile.sh's is tests/profile.test.sh's. What is proven HERE is that doctor
# renders those facts honestly, names a fix for every broken one, and touches
# nothing.
#
# THE AXIS TEST IS THE NO-MUTATION WALL. The ownership table's word for doctor
# is "read-only"; every other assertion in this file is downstream of that. So a
# whole fixture machine — settings file, rc file, plugin tree, plugin registry,
# caches — is sha256'd file by file AND enumerated path by path (an empty file
# or a new directory has no checksum to change) before and after a full doctor
# run, on every fixture arm. Group 9 does that; Group 10 proves the wall
# discriminates by breaking read-only on a doctored copy and watching it fire.
#
# HERMETIC. No network, no `claude` CLI, no live ~/.claude, no brew/npm/uv.
# `env -i` with a REPLACED PATH (not a prefixed one) so a real binary on this
# machine cannot be reached by accident, and every root handed over by env var.
# The stubs are not a seam that substitutes the value under test — they are the
# real `command -v` / `npm list` / `claude mcp get` lookups resolved against a
# directory this suite controls, which is why doctor's own probe path runs
# unmodified.
#
# BOTH ARMS, ALWAYS — plus the third. Every section is rendered on a fully
# HEALTHY machine and on a BROKEN one (absences, a constraint violation, a stale
# profile, a legacy rc block, legacy-channel hook entries, half-uninstalled). A
# section that only ever renders one way proves nothing. The third arm is
# UNKNOWN: S1's resolution makes `present=unknown` and `count=unknown` legal
# values, and a doctor that coerced them to `no`/`0` would report a machine it
# could not read as a machine it had read clean.
#
# FIXTURE FIDELITY. Every value below was captured from this machine on
# 2026-08-17; the capture command is quoted beside each fixture:
#   * `--version` lines             `git --version`, `node --version`, ... (Group F1)
#   * npm global listing shape      `npm list -g --depth=0 @playwright/cli`
#   * installed_plugins.json shape  `jq '.plugins | to_entries[0]' ~/.claude/plugins/installed_plugins.json`
#   * roster counts 14 and 24+4     `ls <installPath>/skills/*/SKILL.md | wc -l`
#                                   `ls <installPath>/agents/*.md | wc -l`
#   * settings.json hook block      claude-bootstrap.sh's wire_managed_hooks shape
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh). doctor's output is captured to a FILE and
# every extraction greps that file directly; containment checks use bash
# `[[ == * ]]` in-process.
#
# Usage: bash tests/doctor.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
DOCTOR_SH="${REPO}/payload/scripts/doctor.sh"
DOCTOR_MD="${REPO}/payload/commands/doctor.md"
TEMPLATE="${REPO}/payload/permissions/profile.template.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq()   { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_ne()   { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "expected NOT '$2'"; fi; }
expect_true() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
# shellcheck disable=SC2053  # RHS is a glob on purpose
expect_match()     { local l="$1" p="$2" a="$3"; if [[ "$a" == $p ]]; then ok "$l"; else no "$l" "'$a' does not match '$p'"; fi; }
# shellcheck disable=SC2053
expect_not_match() { local l="$1" p="$2" a="$3"; if [[ "$a" == $p ]]; then no "$l" "'$a' unexpectedly matches '$p'"; else ok "$l"; fi; }
expect_contains()     { local l="$1" n="$2" h="$3"; if [[ "$h" == *"$n"* ]]; then ok "$l"; else no "$l" "expected to contain '$n'"; fi; }
expect_not_contains() { local l="$1" n="$2" h="$3"; if [[ "$h" == *"$n"* ]]; then no "$l" "expected NOT to contain '$n'"; else ok "$l"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CALLS="$TMP/calls.log"; : > "$CALLS"

# First matching line of a FILE. grep against a file argument, never a pipe from
# another process, so no SIGPIPE race is possible.
line_of() { grep -F -m1 -- "$2" "$1" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# A stub that answers `--version` with a real captured line and records every
# other invocation. Captured 2026-08-17 with `<name> --version | head -1`.
make_version_stub() {  # <bindir> <name> <version-line>
  mkdir -p "$1"
  cat > "$1/$2" <<STUB
#!/bin/bash
case "\${1:-}" in --version|-v|version) echo "$3"; exit 0 ;; esac
echo "$2 \$*" >> "\${BIONIC_TEST_CALLS:-/dev/null}"
exit 0
STUB
  chmod +x "$1/$2"
}

# The bin dir every arm starts from: real coreutils and the real jq, nothing else.
BASE_BIN="$TMP/bin-base"; mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls tr head tail sort uniq wc jq python3 find shasum; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

# A machine with every lane-3b binary present, at its real version line.
FULL_BIN="$TMP/bin-full"; mkdir -p "$FULL_BIN"; cp -R "$BASE_BIN"/. "$FULL_BIN"/
make_version_stub "$FULL_BIN" git    "git version 2.50.1 (Apple Git-155)"
make_version_stub "$FULL_BIN" node   "v26.7.0"
make_version_stub "$FULL_BIN" pnpm   "11.22.0"
make_version_stub "$FULL_BIN" gh     "gh version 2.97.0 (2026-07-31)"
make_version_stub "$FULL_BIN" rg     "ripgrep 15.2.0"
make_version_stub "$FULL_BIN" uv     "uv 0.12.5 (Homebrew 2026-08-14 aarch64-apple-darwin)"
make_version_stub "$FULL_BIN" docker "Docker version 29.2.1, build a5c7197"
make_version_stub "$FULL_BIN" yq     "yq (https://github.com/mikefarah/yq/) version v4.53.3"
make_version_stub "$FULL_BIN" aws    "aws-cli/2.25.1 Python/3.12.9 Darwin/25.5.0 exe/x86_64"
make_version_stub "$FULL_BIN" gcloud "Google Cloud SDK 495.0.0"
make_version_stub "$FULL_BIN" notebooklm "notebooklm 0.9.3"

# `npm list -g --depth=0 <pkg>`, real shape — captured 2026-08-17:
#     /opt/homebrew/lib
#     └── @playwright/cli@0.1.18
cat > "$FULL_BIN/npm" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "list" ]; then
  pkg=""
  for a in "$@"; do case "$a" in -*|list) ;; *) pkg="$a" ;; esac; done
  echo "/opt/homebrew/lib"
  case "$pkg" in
    @playwright/cli) echo "└── @playwright/cli@0.1.18" ;;
    @pencil.dev/cli) echo "└── @pencil.dev/cli@0.4.2" ;;
    *)               echo "└── (empty)" ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$FULL_BIN/npm"

# `claude mcp get <name>` — exit 0 for a registered server, non-zero otherwise.
cat > "$FULL_BIN/claude" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "mcp" ] && [ "${2:-}" = "get" ]; then
  case "${3:-}" in context7|chrome-devtools) exit 0 ;; *) exit 1 ;; esac
fi
exit 0
STUB
chmod +x "$FULL_BIN/claude"

# The broken machine's PATH: base plus four binaries. pnpm/gh/uv/docker/yq/aws/
# gcloud/notebooklm are ABSENT (present=no); npm and claude are absent too, which
# is a different fact — their mechanisms cannot answer at all (present=unknown).
BROKEN_BIN="$TMP/bin-broken"; mkdir -p "$BROKEN_BIN"; cp -R "$BASE_BIN"/. "$BROKEN_BIN"/
make_version_stub "$BROKEN_BIN" git  "git version 2.50.1 (Apple Git-155)"
make_version_stub "$BROKEN_BIN" node "v26.7.0"
make_version_stub "$BROKEN_BIN" rg   "ripgrep 15.2.0"

# The unknown machine's PATH: the healthy one with jq removed. jq is itself a row
# in the dependency table, and without it the plugin registry, settings.json and
# the applied permission block are all unreadable.
NOJQ_BIN="$TMP/bin-nojq"; mkdir -p "$NOJQ_BIN"; cp -R "$FULL_BIN"/. "$NOJQ_BIN"/; rm -f "$NOJQ_BIN/jq"

# A machine with no sha256 tool at all. The integrity check is the only fact
# that needs one, and a box that cannot digest a file has not been read clean —
# it has not been read. Both spellings go, because either would answer.
NOSHA_BIN="$TMP/bin-nosha"; mkdir -p "$NOSHA_BIN"; cp -R "$FULL_BIN"/. "$NOSHA_BIN"/
rm -f "$NOSHA_BIN/shasum" "$NOSHA_BIN/sha256sum"

# A plugin-shaped dependency's installed tree. Roster lines are what this exists
# to carry: `skills/*/SKILL.md` + `agents/*.md`, the counting method doctor
# declares. Counts are the real ones on this machine (superpowers 14 + 0,
# agent-skills 24 + 4).
plant_installed_tree() {  # <dir> <skill-count> <agent-count>
  local dir="$1" skills="$2" agents="$3" i
  mkdir -p "$dir/skills"
  for ((i = 1; i <= skills; i++)); do
    mkdir -p "$dir/skills/skill-${i}"
    printf -- '---\nname: skill-%s\ndescription: fixture skill %s\n---\n' "$i" "$i" > "$dir/skills/skill-${i}/SKILL.md"
  done
  if [ "$agents" -gt 0 ]; then
    mkdir -p "$dir/agents"
    for ((i = 1; i <= agents; i++)); do
      printf -- '---\nname: agent-%s\ndescription: fixture agent %s\n---\n' "$i" "$i" > "$dir/agents/agent-${i}.md"
    done
  fi
}

# The rendered marker block, produced INDEPENDENTLY of profile.sh's
# render_profile — a fixture built by the code under test could pin the test away
# (memory: fixtures-can-pin-away-the-test). Plain text substitution in python3.
render_block_json() {  # <template> <root> -> the allow array as JSON
  python3 -c '
import json, sys
text = open(sys.argv[1]).read().replace("__BIONIC_PLUGIN_ROOT__", sys.argv[2].rstrip("/"))
print(json.dumps(json.loads(text)["permissions"]["allow"]))
' "$1" "$2"
}

# A whole fixture machine. `flavor` is healthy | broken.
plant_machine() {  # <machine-root> <flavor>
  local m="$1" flavor="$2" block accretion
  mkdir -p "$m/home" "$m/plugin/.claude-plugin" "$m/plugin/hooks" \
           "$m/claude-home/plugins" "$m/installs"

  # ── the payload tree doctor is diagnosing ────────────────────────────────
  printf '{ "name": "bionic", "version": "0.1.0" }\n' > "$m/plugin/.claude-plugin/plugin.json"
  cat > "$m/plugin/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh", "timeout": 10 } ] }
    ]
  }
}
JSON
  # healthy: the named script is there (hooks=ok). broken: it is not, which is
  # exactly what a partial update leaves behind (hooks=degraded).
  if [ "$flavor" = "healthy" ]; then
    printf '#!/bin/bash\nexit 0\n' > "$m/plugin/hooks/protect-main.sh"
    chmod +x "$m/plugin/hooks/protect-main.sh"
  fi

  # ── the rendered agent files and the shipped checksum manifest ───────────
  #
  # AC-4's subject. The manifest is written HERE by shasum directly rather than
  # by agents-src/render.sh: a fixture built by the code under test can pin the
  # test away (memory: fixtures-can-pin-away-the-test), and what is under test
  # is doctor's READING of a manifest, not the writer's ability to agree with
  # itself. The `#` header line is included because the shipped manifest carries
  # one, so the comment-skipping path is exercised rather than assumed.
  #
  # healthy = STOCK (every file matches). broken = MODIFIED-LOCALLY: one file
  # gains a line AFTER the manifest is taken, which is exactly the shape of a
  # user editing an installed role file.
  mkdir -p "$m/plugin/agents" "$m/plugin/integrity"
  for a in auditor critic implementor researcher senior-implementor test-runner; do
    printf -- '---\nname: %s\n---\nFixture role file for %s.\n' "$a" "$a" > "$m/plugin/agents/${a}.md"
  done
  {
    printf '# sha256 of the rendered agent files, relative to the plugin root.\n'
    ( cd "$m/plugin" && for a in agents/*.md; do
        printf '%s  %s\n' "$(shasum -a 256 "$a" | awk '{print $1}')" "$a"
      done )
  } > "$m/plugin/integrity/agents.sha256"
  if [ "$flavor" != "healthy" ]; then
    printf 'A line the user added by hand.\n' >> "$m/plugin/agents/critic.md"
  fi

  # ── the plugin registry ──────────────────────────────────────────────────
  # Shape captured from the real file:
  #   jq '.plugins | to_entries[0]' ~/.claude/plugins/installed_plugins.json
  if [ "$flavor" = "healthy" ]; then
    plant_installed_tree "$m/installs/superpowers"  14 0
    plant_installed_tree "$m/installs/agent-skills" 24 4
    cat > "$m/claude-home/plugins/installed_plugins.json" <<JSON
{ "plugins": {
    "bionic@bionic": [ { "scope": "user", "installPath": "${m}/plugin", "version": "0.1.0",
                         "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "superpowers@bionic": [ { "scope": "user", "installPath": "${m}/installs/superpowers", "version": "6.3.0",
                              "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "agent-skills@bionic": [ { "scope": "user", "installPath": "${m}/installs/agent-skills", "version": "0.6.1",
                               "installedAt": "2026-08-17T00:00:00.000Z" } ] } }
JSON
  else
    # bionic itself is gone from the registry — the half-uninstalled precondition.
    # superpowers is present but BELOW its ^6.3.0 floor; agent-skills is absent.
    plant_installed_tree "$m/installs/superpowers" 14 0
    cat > "$m/claude-home/plugins/installed_plugins.json" <<JSON
{ "plugins": {
    "superpowers@bionic": [ { "scope": "user", "installPath": "${m}/installs/superpowers", "version": "6.2.0",
                              "installedAt": "2026-08-17T00:00:00.000Z" } ] } }
JSON
  fi

  # ── user settings.json ───────────────────────────────────────────────────
  if [ "$flavor" = "healthy" ]; then
    # The applied block is rendered against THIS machine's plugin root, so the
    # re-render doctor performs must come back `identical`.
    block="$(render_block_json "$TEMPLATE" "$m/plugin")"
    accretion='["Bash(ls:*)","Bash(git status:*)"]'
    python3 -c '
import json, sys
allow = json.loads(sys.argv[2]) + json.loads(sys.argv[1])
json.dump({"statusLine": {"type": "command", "command": "npx ccstatusline@latest"},
           "permissions": {"allow": allow},
           "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
               {"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh"}]}]}},
          open(sys.argv[3], "w"), indent=2)
' "$block" "$accretion" "$m/claude-home/settings.json"
  else
    # Rendered against a DIFFERENT root — the post-update staleness case — plus
    # two legacy managed-hook entries and no statusline.
    block="$(render_block_json "$TEMPLATE" "/opt/old/bionic-install")"
    accretion='["Bash(ls:*)","Bash(git status:*)","Bash(make:*)"]'
    python3 -c '
import json, sys
allow = json.loads(sys.argv[2]) + json.loads(sys.argv[1])
json.dump({"permissions": {"allow": allow},
           "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
               {"type": "command", "command": "~/.claude/hooks/protect-main.sh"},
               {"type": "command", "command": "~/.claude/hooks/protect-database.sh"}]}]}},
          open(sys.argv[3], "w"), indent=2)
' "$block" "$accretion" "$m/claude-home/settings.json"
  fi

  # ── shell rc ─────────────────────────────────────────────────────────────
  # Legacy marker literals verbatim from claude-bootstrap.sh's ALIAS_START/END.
  if [ "$flavor" = "healthy" ]; then
    printf 'export PATH="$HOME/bin:$PATH"\nexport CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n' > "$m/rc"
  else
    cat > "$m/rc" <<'RC'
export PATH="$HOME/bin:$PATH"
# ─── bionic:start ───
alias claude='claude --dangerously-skip-permissions'
# ─── bionic:end ───
RC
  fi

  # ── the playwright browser cache ─────────────────────────────────────────
  if [ "$flavor" = "healthy" ]; then
    mkdir -p "$m/playwright-cache/chromium-1187"
    : > "$m/playwright-cache/chromium-1187/INSTALLATION_COMPLETE"
  fi
}

# Run a doctor script against a fixture machine with a controlled environment.
doctor_run() {  # <doctor.sh> <bin-dir> <machine-root> [extra env assignments...]
  local sh="$1" bin="$2" m="$3"; shift 3
  env -i \
    HOME="$m/home" \
    PATH="$bin" \
    BIONIC_TEST_CALLS="$CALLS" \
    BIONIC_PLUGIN_ROOT="$m/plugin" \
    BIONIC_CLAUDE_HOME="$m/claude-home" \
    BIONIC_SETTINGS_FILE="$m/claude-home/settings.json" \
    BIONIC_INSTALLED_PLUGINS_FILE="$m/claude-home/plugins/installed_plugins.json" \
    BIONIC_SHELL_RC="$m/rc" \
    BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
    BIONIC_PLAYWRIGHT_CACHE="$m/playwright-cache" \
    "$@" \
    bash "$sh" 2>&1
}

# The no-mutation wall's sensor: content AND shape. A checksum per file catches
# an edit; the path enumeration catches a creation or a deletion that a checksum
# list would silently absorb (a new empty file has nothing to compare against).
fingerprint() {  # <dir>
  find "$1" -type f -exec shasum -a 256 {} \; 2>/dev/null | sort
  echo "--- paths ---"
  find "$1" 2>/dev/null | sort
}

HEALTHY="$TMP/machine-healthy"; plant_machine "$HEALTHY" healthy
BROKEN="$TMP/machine-broken";   plant_machine "$BROKEN"  broken

# ---------------------------------------------------------------------------
echo "=== Group 1: the files exist, parse, and follow command conventions ==="
# ---------------------------------------------------------------------------

expect_true "payload/scripts/doctor.sh exists" test -f "$DOCTOR_SH"
expect_true "payload/commands/doctor.md exists" test -f "$DOCTOR_MD"
expect_true "doctor.sh passes bash -n" bash -n "$DOCTOR_SH"

if [ -f "$DOCTOR_MD" ]; then
  MD_TEXT="$(cat "$DOCTOR_MD")"
  MD_DESC="$(awk '/^---$/ { c++; next } c==1 && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit } c>=2 { exit }' "$DOCTOR_MD")"
  # `test -n` on the value directly, never `bash -c "[ -n '$v' ]"`: a description
  # containing an apostrophe would terminate the single-quoted string and turn a
  # content assertion into a shell syntax error reported as a content failure.
  expect_true "doctor.md frontmatter carries a non-empty description" test -n "$MD_DESC"
  # The one invocation rule tests/command-format.test.sh enforces across the set:
  # every `.sh` token is rooted at the LITERAL ${CLAUDE_PLUGIN_ROOT} spelling.
  MD_BAD="$(grep -oE '[^[:space:]"'"'"'`]+\.sh' "$DOCTOR_MD" 2>/dev/null | grep -v '^\${CLAUDE_PLUGIN_ROOT}' || true)"
  expect_eq "doctor.md: every .sh invocation is rooted at \${CLAUDE_PLUGIN_ROOT}" "" "$MD_BAD"
  expect_contains "doctor.md invokes scripts/doctor.sh" '${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh' "$MD_TEXT"
  # A thin wrapper: no installation or diagnosis logic in command prose (design
  # boundaries — "installation logic NEVER lives in command prose").
  MD_SH_COUNT="$(grep -c 'CLAUDE_PLUGIN_ROOT' "$DOCTOR_MD" 2>/dev/null | tr -d ' ')"
  expect_eq "doctor.md invokes exactly one script (thin wrapper)" "1" "$MD_SH_COUNT"
fi

if [ ! -f "$DOCTOR_SH" ]; then
  echo ""
  echo "FATAL: payload/scripts/doctor.sh is missing — every remaining group needs it."
  echo "Results: $PASS/$TOTAL passed, $((TOTAL - PASS)) failed"
  exit 1
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 2: the healthy machine — every section renders, exit 0 ==="
# ---------------------------------------------------------------------------

H_OUT="$TMP/healthy.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" > "$H_OUT" 2>&1
H_RC=$?
H="$(cat "$H_OUT")"

expect_eq "doctor exits 0 on a healthy machine (a diagnosis is not a failure)" "0" "$H_RC"

for section in "=== PLUGIN INTEGRITY ===" "=== TIER STATE ===" "=== DEPENDENCIES ===" \
               "=== ENVIRONMENT ===" "=== PERMISSION PROFILE ===" "=== ROSTER FOOTPRINT ===" \
               "=== DEGRADATION MAP ===" "=== SUMMARY ==="; do
  expect_contains "healthy: section renders — ${section}" "$section" "$H"
done

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 3: the healthy machine — the facts, not just the headings ==="
# ---------------------------------------------------------------------------

expect_match "healthy: plugin version rendered from the payload manifest" \
  "*0.1.0*" "$(line_of "$H_OUT" "payload version")"
expect_match "healthy: hooks state renders ok" \
  "*ok*" "$(line_of "$H_OUT" "hooks")"

# AC-4, the STOCK arm. One line, in the integrity section, naming the state and
# how many files it covers — a "stock" with no count is a claim the reader
# cannot size.
H_AGENTS="$(line_of "$H_OUT" "agent files")"
expect_match "healthy: the agent-integrity line reports stock" "*stock*" "$H_AGENTS"
expect_match "healthy: the stock line says how many files it covers" "*6*" "$H_AGENTS"
expect_not_match "healthy: a stock machine is not called modified" "*modified*" "$H_AGENTS"
expect_not_contains "healthy: no reinstall nag when the files are stock" \
  "reinstall restores stock" "$H"

# Both lanes, presence AND version AND constraint AND verdict — the dep table is
# the sole constraint-agreement surface (AC-3, AC-8), so the verdict must be
# rendered per row, not inferred by the reader.
expect_match "healthy: lane-3a superpowers row carries lane/present/version/constraint/verdict" \
  "*3a*superpowers*yes*6.3.0*^6.3.0*ok*" "$(line_of "$H_OUT" "superpowers")"
expect_match "healthy: lane-3a agent-skills row satisfies the corrected ^0.6.0 constraint" \
  "*3a*agent-skills*yes*0.6.1*^0.6.0*ok*" "$(line_of "$H_OUT" "agent-skills")"
expect_match "healthy: lane-3b rg row renders present with its captured version" \
  "*3b*rg*yes*15.2.0*any*ok*" "$(line_of "$H_OUT" " rg ")"
expect_match "healthy: lane-3b npm-global row renders the package version npm reported" \
  "*3b*@playwright/cli*yes*0.1.18*" "$(line_of "$H_OUT" "@playwright/cli")"
expect_match "healthy: mcp-server row renders present" \
  "*3b*context7*yes*" "$(line_of "$H_OUT" "context7")"
expect_match "healthy: playwright browser cache row renders present" \
  "*3b*playwright-chromium*yes*" "$(line_of "$H_OUT" "playwright-chromium")"

# Environment class.
expect_match "healthy: TODO_TOOLS export reported present" \
  "*present*" "$(line_of "$H_OUT" "CLAUDE_CODE_ENABLE_TODO_TOOLS")"
expect_match "healthy: legacy .zshrc alias block reported absent" \
  "*absent*" "$(line_of "$H_OUT" "legacy .zshrc")"
expect_match "healthy: zero legacy-channel managed-hook entries" \
  "*0*" "$(line_of "$H_OUT" "legacy-channel managed-hook entries")"
expect_match "healthy: ccstatusline reported present" \
  "*present*" "$(line_of "$H_OUT" "ccstatusline statusline")"

# Permission profile — the three-way diff.
expect_match "healthy: shipped template version rendered" \
  "*0.1.0*" "$(line_of "$H_OUT" "shipped template version")"
expect_match "healthy: applied block version rendered" \
  "*0.1.0*" "$(line_of "$H_OUT" "applied block version")"
expect_match "healthy: render diff is identical when the block was rendered for this root" \
  "*identical*" "$(line_of "$H_OUT" "render diff")"
expect_match "healthy: accretion counts the two rules outside bionic's block" \
  "*2*" "$(line_of "$H_OUT" "accretion outside block")"
expect_not_contains "healthy: no staleness action line" "the applied permission profile is stale" "$H"

# Roster footprint — the D6 admission criterion, counted from the installed layout.
expect_contains "healthy: roster-footprint section declares its counting method" \
  "method:" "$H"
expect_contains "healthy: the method names skills/*/SKILL.md" "skills/*/SKILL.md" "$H"
expect_contains "healthy: the method names agents/*.md" "agents/*.md" "$H"
roster_line_of() {  # <doctor-output-file> <dep name>
  awk '/=== ROSTER FOOTPRINT ===/,/=== DEGRADATION MAP ===/' "$1" > "$TMP/roster-section.txt"
  grep -F -m1 -- "$2" "$TMP/roster-section.txt" 2>/dev/null || true
}

expect_match "healthy: superpowers contributes 14 roster lines (14 skills + 0 agents)" \
  "*14*14 skills*0 agents*" "$(roster_line_of "$H_OUT" "superpowers")"
expect_match "healthy: agent-skills contributes 28 roster lines (24 skills + 4 agents)" \
  "*28*24 skills*4 agents*" "$(roster_line_of "$H_OUT" "agent-skills")"
expect_match "healthy: a lane-3b dependency contributes no roster lines" \
  "*0*" "$(roster_line_of "$H_OUT" " git ")"

# Half-uninstalled and the summary.
expect_match "healthy: half-uninstalled reported no" \
  "*no*" "$(line_of "$H_OUT" "half-uninstalled")"
expect_not_contains "healthy: no curl fallback one-liner on a registered machine" \
  "remove.sh | bash" "$H"
expect_contains "healthy: summary says there is nothing to do" "nothing to do" "$H"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 4: the broken machine — every failure renders WITH its named fix ==="
# ---------------------------------------------------------------------------

B_OUT="$TMP/broken.out"
doctor_run "$DOCTOR_SH" "$BROKEN_BIN" "$BROKEN" > "$B_OUT" 2>&1
B_RC=$?
B="$(cat "$B_OUT")"

expect_eq "doctor exits 0 on a broken machine too (a diagnosis is not a failure)" "0" "$B_RC"

for section in "=== PLUGIN INTEGRITY ===" "=== TIER STATE ===" "=== DEPENDENCIES ===" \
               "=== ENVIRONMENT ===" "=== PERMISSION PROFILE ===" "=== ROSTER FOOTPRINT ===" \
               "=== DEGRADATION MAP ===" "=== SUMMARY ==="; do
  expect_contains "broken: section still renders — ${section}" "$section" "$B"
done

expect_match "broken: hooks.json naming a missing script renders degraded" \
  "*degraded*" "$(line_of "$B_OUT" "hooks ")"

# AC-4, the MODIFIED-LOCALLY arm. The framing is fixed by the AC and is the
# whole difference between a report and a scolding: an edited role file is a
# legitimate thing for a user to have done, and the line says so before it says
# how to undo it.
B_AGENTS="$(line_of "$B_OUT" "agent files")"
expect_match "broken: the agent-integrity line reports the local modification" \
  "*modified locally*" "$B_AGENTS"
expect_match "broken: the modified line counts them against the shipped total" \
  "*1 of 6*" "$B_AGENTS"
expect_match "broken: the modified line NAMES the file that differs" "*critic.md*" "$B_AGENTS"
expect_contains "broken: the modified line carries the AC's exact framing" \
  "may be intentional; reinstall restores stock" "$B_AGENTS"
# REPORT-NEVER-POLICE. Exactly one line about integrity, and none of it in the
# SUMMARY: the summary is the action list, and a local edit is not a defect to
# be actioned. (Exit 0 is asserted at the top of this group for the whole run.)
B_AGENT_LINES="$(grep -c "agent files" "$B_OUT" 2>/dev/null | tr -d ' ')"
expect_eq "broken: integrity is ONE line, not a section of nagging" "1" "$B_AGENT_LINES"

# The constraint violation — the whole point of carrying the dep table's
# constraint into the report.
expect_match "broken: superpowers 6.2.0 under ^6.3.0 renders verdict=violation" \
  "*3a*superpowers*yes*6.2.0*^6.3.0*violation*" "$(line_of "$B_OUT" "superpowers")"
expect_contains "broken: the violation appears in the degradation map with its constraint" \
  "violates constraint ^6.3.0" "$B"
expect_match "broken: the violation line names /bionic:setup as the fix" \
  "*/bionic:setup*" "$(line_of "$B_OUT" "violates constraint")"

# Absences, both lanes, each with a named fix.
expect_match "broken: absent lane-3a dependency renders present=no" \
  "*3a*agent-skills*no*" "$(line_of "$B_OUT" "agent-skills")"
expect_match "broken: absent lane-3b dependency renders present=no" \
  "*3b*yq*no*" "$(line_of "$B_OUT" " yq ")"
DEG="$(awk '/=== DEGRADATION MAP ===/,/=== SUMMARY ===/' "$B_OUT")"
expect_contains "broken: the degradation map names the absent lane-3a dependency" "agent-skills" "$DEG"
expect_contains "broken: the degradation map names the absent lane-3b dependency" "yq" "$DEG"
expect_contains "broken: an absent lane-3b dependency is offered the just-in-time install wording" \
  "just-in-time" "$DEG"
expect_contains "broken: every degradation line names a fix (arrow-delimited)" "→" "$DEG"

# Environment class, the other way round from healthy.
expect_match "broken: TODO_TOOLS export reported absent" \
  "*absent*" "$(line_of "$B_OUT" "CLAUDE_CODE_ENABLE_TODO_TOOLS")"
expect_match "broken: legacy .zshrc alias block reported present" \
  "*present*" "$(line_of "$B_OUT" "legacy .zshrc")"
expect_match "broken: two legacy-channel managed-hook entries counted" \
  "*2*" "$(line_of "$B_OUT" "legacy-channel managed-hook entries")"
expect_match "broken: ccstatusline reported absent" \
  "*absent*" "$(line_of "$B_OUT" "ccstatusline statusline")"

# Stale permission profile — the post-update path-drift case, named with its fix.
expect_match "broken: a block rendered for another root reads stale" \
  "*stale*" "$(line_of "$B_OUT" "render diff")"
expect_match "broken: accretion counts the three rules outside bionic's block" \
  "*3*" "$(line_of "$B_OUT" "accretion outside block")"
expect_contains "broken: staleness names /bionic:setup as the action" \
  "the applied permission profile is stale" "$B"

# Half-uninstalled — the curl fallback one-liner is its action line (D5a: the
# remover must not depend on the thing it removes).
expect_match "broken: half-uninstalled reported yes" \
  "*yes*" "$(line_of "$B_OUT" "half-uninstalled")"
expect_contains "broken: the half-uninstalled action line is the curl fallback one-liner" \
  "curl -fsSL" "$B"
expect_contains "broken: the curl one-liner targets the raw remove.sh URL" \
  "/payload/scripts/remove.sh" "$B"

# R-3.1 — the door's URL is pinned to the shipped script's real location.
#
# The constant is a lone string: nothing connects it to the file it serves, so
# moving or renaming payload/scripts/remove.sh in a later wave breaks the only
# fix a half-uninstalled machine has, silently and at a distance. The URL is
# <scheme>://<host>/<owner>/<repo>/<ref>/<repo-relative-path>, so field 7 on is
# a path this checkout can be asked about directly. The `test -f` is the half
# that catches a rename nobody thought to mirror here.
DOOR_URL="$(awk -F'"' '/^BIONIC_REMOVE_RAW_URL=/ { print $2; exit }' "$DOCTOR_SH")"
DOOR_PATH="$(printf '%s\n' "$DOOR_URL" | cut -d/ -f7-)"
REMOVE_SH="${REPO}/payload/scripts/remove.sh"
expect_eq "the door URL's path tail is the shipped remover's repo-relative path" \
  "${REMOVE_SH#"${REPO}/"}" "$DOOR_PATH"
expect_true "the path the door URL serves names a file that exists in this checkout" \
  test -f "${REPO}/${DOOR_PATH}"

# R-3.2 — the one-liner's FAILURE must reach the person who ran it.
#
# `<fetch> | bash` gives the pipeline bash's status, not curl's: a fetch that
# 404s pipes an empty stream into a shell that exits 0, so the only fix a
# half-uninstalled machine has appears to succeed while doing nothing. Pinning
# the literal text cannot see this — the spelling that swallows the status and
# the spelling that reports it both contain "curl -fsSL". So drive it: take the
# line doctor actually printed, run it with a `curl` that fails the way a 404
# fails, and require a non-zero status out the other end.
ONELINER="$(awk '/curl -fsSL/ { sub(/^[[:space:]]+/, ""); print; exit }' "$B_OUT")"
expect_true "the printed one-liner was extracted" test -n "$ONELINER"

FAILING_CURL_BIN="$TMP/failing-curl-bin"; mkdir -p "$FAILING_CURL_BIN"
cat > "$FAILING_CURL_BIN/curl" <<'STUB'
#!/bin/bash
echo "curl: (56) The requested URL returned error: 404" >&2
exit 22
STUB
chmod +x "$FAILING_CURL_BIN/curl"

ONELINER_RC=0
PATH="$FAILING_CURL_BIN:$PATH" bash -c "$ONELINER" >/dev/null 2>&1 || ONELINER_RC=$?
expect_true "the one-liner exits non-zero when the fetch fails (the pipe does not eat it)" \
  test "$ONELINER_RC" -ne 0

ONELINER_ERR="$(PATH="$FAILING_CURL_BIN:$PATH" bash -c "$ONELINER" 2>&1 >/dev/null)"
expect_contains "the one-liner lets the transport error reach the user's terminal" \
  "404" "$ONELINER_ERR"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 5: unknown-valued facts render as unknown, never coerced ==="
# ---------------------------------------------------------------------------
#
# S1's resolution: `present=unknown` and `count=unknown` are LEGAL values. A
# doctor that printed `no` or `0` there would report a machine it could not read
# as a machine it had read clean — the confident wrong answer detect.sh's header
# refuses to give.

U_OUT="$TMP/unknown.out"
doctor_run "$DOCTOR_SH" "$NOJQ_BIN" "$HEALTHY" > "$U_OUT" 2>&1
U_RC=$?
U="$(cat "$U_OUT")"

expect_eq "doctor exits 0 with jq absent" "0" "$U_RC"

SP_LINE="$(line_of "$U_OUT" "superpowers")"
expect_match "no jq: lane-3a presence renders unknown" "*unknown*" "$SP_LINE"
# The negative is written as ` no ` with its surrounding column spaces on purpose:
# a bare `no` is a substring of `unknown`, so the obvious spelling of this
# assertion would pass on the very value it is meant to reject.
expect_not_match "no jq: lane-3a presence is NOT coerced to no" "*superpowers* no *" "$SP_LINE"

LEGACY_HOOK_LINE="$(line_of "$U_OUT" "legacy-channel managed-hook entries")"
expect_match "no jq: the legacy-channel hook COUNT renders unknown" "*unknown*" "$LEGACY_HOOK_LINE"
expect_not_match "no jq: the legacy-channel hook count is NOT coerced to 0" "*entries*0*" "$LEGACY_HOOK_LINE"

ACC_LINE="$(line_of "$U_OUT" "accretion outside block")"
expect_match "no jq: accretion renders unknown" "*unknown*" "$ACC_LINE"

expect_match "no jq: the roster count renders unknown, not 0" "*unknown*" \
  "$(roster_line_of "$U_OUT" "superpowers")"

# Every unknown carries a NAMED CAUSE — "unknown" alone is a shrug, not a
# diagnosis.
expect_contains "no jq: the cause of the unknowns is named" "jq is not on PATH" "$U"
expect_contains "no jq: the summary names installing jq as an action" "install jq" "$U"

# AC-4's third value. Two ways the integrity question cannot be answered — no
# digest tool, and no manifest to compare against — and both must read `unknown`
# with a named cause rather than the confident wrong answer in either direction.
# Calling an unreadable machine "stock" is the dangerous one: it is the state
# this line exists to detect, reported as the state it exists to reassure about.
NS_OUT="$TMP/nosha.out"
doctor_run "$DOCTOR_SH" "$NOSHA_BIN" "$HEALTHY" > "$NS_OUT" 2>&1
NS_RC=$?
expect_eq "no sha tool: doctor still exits 0" "0" "$NS_RC"
NS_AGENTS="$(line_of "$NS_OUT" "agent files")"
expect_match "no sha tool: the integrity line renders unknown" "*unknown*" "$NS_AGENTS"
expect_not_match "no sha tool: an unreadable machine is NOT reported stock" "*stock*" "$NS_AGENTS"
expect_match "no sha tool: the unknown names its cause" "*sha*" "$NS_AGENTS"

NOMAN="$TMP/machine-nomanifest"; cp -R "$HEALTHY" "$NOMAN"; rm -rf "$NOMAN/plugin/integrity"
NM_OUT="$TMP/nomanifest.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$NOMAN" > "$NM_OUT" 2>&1
NM_RC=$?
expect_eq "no manifest: doctor still exits 0" "0" "$NM_RC"
NM_AGENTS="$(line_of "$NM_OUT" "agent files")"
expect_match "no manifest: the integrity line renders unknown" "*unknown*" "$NM_AGENTS"
expect_not_match "no manifest: a payload with nothing to compare is NOT reported stock" \
  "*stock*" "$NM_AGENTS"
expect_match "no manifest: the unknown names the missing manifest as its cause" \
  "*manifest*" "$NM_AGENTS"

# The mechanism-level unknown, present on a fully healthy machine: the pnpm
# content-addressable store is a cache with no installed-state to read, so `no`
# would be a lie on a warm machine.
MOTION_LINE="$(line_of "$H_OUT" " motion ")"
expect_match "healthy: the pnpm-store dependency renders present=unknown" "*unknown*" "$MOTION_LINE"
expect_contains "healthy: the pnpm-store unknown carries its named cause" \
  "content-addressable store is a cache" "$H"
expect_not_contains "healthy: a no-action unknown does not manufacture a setup reason" \
  "→ run /bionic:setup" "$H"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 6: the SUMMARY block — action lines only ==="
# ---------------------------------------------------------------------------

H_SUM="$(awk '/=== SUMMARY ===/{f=1; next} f' "$H_OUT")"
B_SUM="$(awk '/=== SUMMARY ===/{f=1; next} f' "$B_OUT")"

H_SUM_SQUASHED="$(printf '%s' "$H_SUM" | tr -d '[:space:]')"
expect_true "healthy: the summary block is non-empty" test -n "$H_SUM_SQUASHED"
expect_contains "broken: the summary names /bionic:setup" "/bionic:setup" "$B_SUM"
expect_contains "broken: the summary carries the curl fallback one-liner" "curl -fsSL" "$B_SUM"

# "Action lines only": every non-blank summary line either starts an action
# (`→`) or is the indented continuation of one. No fact restatements.
SUM_NON_ACTION="$(awk '/=== SUMMARY ===/{f=1; next} f && NF && $0 !~ /→/ && $0 !~ /^ {6}/' "$B_OUT")"
expect_eq "broken: the summary contains action lines only (no restated facts)" "" "$SUM_NON_ACTION"

# The setup action states WHY it is being recommended — a bare "run /bionic:setup"
# is not a diagnosis. Extracted from the SUMMARY SECTION, not the whole report:
# the degradation map names the same command per row, and grepping the file would
# return one of those rows instead.
awk '/=== SUMMARY ===/{f=1; next} f' "$B_OUT" > "$TMP/broken-summary.txt"
SETUP_ACTION="$(line_of "$TMP/broken-summary.txt" "→ run /bionic:setup")"
expect_match "broken: the setup action names the absences it would repair" "*absent*" "$SETUP_ACTION"
expect_match "broken: the setup action names the constraint violation it would repair" "*violation*" "$SETUP_ACTION"

# AC-4's report-never-police clause, measured where policing would show up. The
# broken machine HAS a locally modified role file; the summary is where doctor
# tells a user what to do, and a modified agent file is not something to do
# anything about. The line above already says how to undo it if they want to.
expect_not_contains "broken: the summary raises no action over a locally modified agent file" \
  "reinstall restores stock" "$B_SUM"
expect_not_contains "broken: the summary does not restate the integrity fact" \
  "agent files" "$B_SUM"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 7: doctor never prompts and never reaches the network ==="
# ---------------------------------------------------------------------------
#
# A read-only report that blocked on stdin would hang the command surface, and
# one that shelled out to the network would not be a diagnosis of THIS machine.
# stdin is closed for this run: a `read` would fail, and any consent-shaped pause
# would show up as a prompt string in the output.

NP_OUT="$TMP/noprompt.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" < /dev/null > "$NP_OUT" 2>&1
NP_RC=$?
NP="$(cat "$NP_OUT")"
expect_eq "doctor completes with stdin closed (it never prompts)" "0" "$NP_RC"
expect_not_contains "doctor emits no consent prompt" "[y/N]" "$NP"
expect_eq "doctor with stdin closed produces the same report as with stdin open" \
  "$(cat "$H_OUT")" "$NP"

# No network verbs in the source. The curl one-liner is TEXT doctor prints for
# the user to run, never a command doctor executes, so the check is that curl is
# only ever echoed.
CURL_EXECUTIONS="$(grep -nE '^[[:space:]]*(curl|wget)[[:space:]]' "$DOCTOR_SH" 2>/dev/null || true)"
expect_eq "doctor.sh executes no curl/wget (the one-liner is printed, not run)" "" "$CURL_EXECUTIONS"
# Two different questions, so two different checks. `brew`/`npm`/`claude` are
# things doctor may legitimately NAME in an action line and must never RUN, so
# they are searched for in command position only. The libraries' mutating
# functions are never legitimate anywhere, so they are searched for on any line
# that is not a comment — doctor.sh's header names them precisely in order to
# say it does not call them, and a check that could not tell a prohibition from
# a violation would forbid documenting the rule.
TREAT_COMMANDS="$(grep -nE '^[[:space:]]*(brew|npm|uv|claude|git|pnpm|npx)[[:space:]]' "$DOCTOR_SH" 2>/dev/null || true)"
expect_eq "doctor.sh runs no package manager or CLI in command position" "" "$TREAT_COMMANDS"
TREAT_FUNCTIONS="$(grep -vE '^[[:space:]]*#' "$DOCTOR_SH" \
  | grep -nE '(profile_apply|profile_strip|install_dep|remove_dep|_profile_write|_dep_install|_dep_consent)' || true)"
expect_eq "doctor.sh calls no mutating function from any library" "" "$TREAT_FUNCTIONS"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 8: doctor renders detect.sh's facts — it does not re-derive them ==="
# ---------------------------------------------------------------------------
#
# The ownership table makes detect.sh the SSoT for machine facts. A second
# implementation inside doctor is the defect the table exists to prevent, and it
# is invisible to every output assertion above: a hand-rolled probe can produce
# the identical string.

for fn in detect_plugin_integrity detect_agent_integrity detect_dep detect_env_todo_tools \
          detect_zshrc_legacy_block detect_legacy_channel_hooks \
          detect_half_uninstalled detect_profile_state profile_diff; do
  expect_true "doctor.sh calls ${fn} from the libraries" grep -q "${fn}" "$DOCTOR_SH"
done
# A `.` in command position naming the file — the source itself, not a mention
# of the path in prose.
expect_true "doctor.sh sources detect.sh rather than reimplementing it" \
  grep -qE '^[[:space:]]*\.[[:space:]].*detect\.sh' "$DOCTOR_SH"
expect_true "doctor.sh sources profile.sh rather than reimplementing it" \
  grep -qE '^[[:space:]]*\.[[:space:]].*profile\.sh' "$DOCTOR_SH"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 9: THE NO-MUTATION WALL — a doctor run changes nothing ==="
# ---------------------------------------------------------------------------
#
# The axis test. Every fixture file is checksummed and every path enumerated
# before and after a full run, on all three arms. Read-only is doctor's charter
# (design ownership table); if this wall is green nothing else in the file can
# be true by accident, and if it is red nothing else matters.

for arm in healthy broken nojq; do
  WALL="$TMP/wall-${arm}"
  case "$arm" in
    healthy) cp -R "$HEALTHY" "$WALL"; WALL_BIN="$FULL_BIN" ;;
    broken)  cp -R "$BROKEN"  "$WALL"; WALL_BIN="$BROKEN_BIN" ;;
    nojq)    cp -R "$HEALTHY" "$WALL"; WALL_BIN="$NOJQ_BIN" ;;
  esac
  WALL_BEFORE="$(fingerprint "$WALL")"
  doctor_run "$DOCTOR_SH" "$WALL_BIN" "$WALL" >/dev/null 2>&1
  WALL_AFTER="$(fingerprint "$WALL")"
  expect_eq "NO-MUTATION WALL (${arm}): every fixture file byte-identical, no path added or removed" \
    "$WALL_BEFORE" "$WALL_AFTER"
done

# The suite's own subject is untouched too — doctor must not rewrite the payload
# it is diagnosing.
PAYLOAD_CKSUM_BEFORE="$(shasum -a 256 "$DOCTOR_SH" "$TEMPLATE" 2>/dev/null)"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 10: mutation-and-restore ×3 — the assertions above discriminate ==="
# ---------------------------------------------------------------------------
#
# RED evidence dies at green (memory: red-evidence-is-perishable), so the proof
# that these checks can fail is taken here, against DOCTORED COPIES of the whole
# scripts tree. The shipped doctor.sh is never written to; its checksum is
# re-asserted at the end.

doctor_copy() {  # <name> -> path to a mutable copy of payload/scripts
  local dest="$TMP/mut-$1"
  rm -rf "$dest"; cp -R "${REPO}/payload/scripts" "$dest"
  echo "$dest/doctor.sh"
}

# ── Mutation 1: break read-only ──────────────────────────────────────────────
# A single appended byte to the settings file — the smallest possible violation
# of the charter. The wall must fire.
MUT1="$(doctor_copy readonly)"
{ head -1 "$DOCTOR_SH"; echo 'printf "\n" >> "${BIONIC_SETTINGS_FILE}"'; tail -n +2 "$DOCTOR_SH"; } > "$MUT1"
MUT1_TREE="$TMP/wall-mut1"; rm -rf "$MUT1_TREE"; cp -R "$HEALTHY" "$MUT1_TREE"
MUT1_BEFORE="$(fingerprint "$MUT1_TREE")"
doctor_run "$MUT1" "$FULL_BIN" "$MUT1_TREE" >/dev/null 2>&1
MUT1_AFTER="$(fingerprint "$MUT1_TREE")"
expect_ne "MUTATION 1 (a doctor that writes one byte): the no-mutation wall fires" \
  "$MUT1_BEFORE" "$MUT1_AFTER"

# ── Mutation 2: break a verdict rendering ────────────────────────────────────
# Every dependency reports `ok`. The broken machine's violation assertion must
# stop holding — otherwise it was passing on the string, not on the fact.
MUT2="$(doctor_copy verdict)"
python3 - "$DOCTOR_SH" "$MUT2" <<'PY'
import sys
src, dest = sys.argv[1], sys.argv[2]
lines = open(src).readlines()
# The last `. <something>/profile.sh` line: the override must land AFTER the
# library defines the function it replaces, or the source would simply undo it.
anchors = [i for i, l in enumerate(lines) if 'profile.sh' in l and l.lstrip().startswith('. ')]
if not anchors:
    raise SystemExit("mutation 2: no source-of-profile.sh line to anchor the override on")
lines.insert(anchors[-1] + 1,
             'detect_dep() { echo "dep:$1 lane=3b present=yes version=9.9.9 constraint=any verdict=ok"; }\n')
open(dest, 'w').writelines(lines)
PY
MUT2_OUT="$TMP/mut2.out"
doctor_run "$MUT2" "$BROKEN_BIN" "$BROKEN" > "$MUT2_OUT" 2>&1
MUT2_TEXT="$(cat "$MUT2_OUT")"
expect_not_contains "MUTATION 2 (verdicts forced to ok): the violation line disappears as expected" \
  "violates constraint ^6.3.0" "$MUT2_TEXT"
expect_not_match "MUTATION 2: the superpowers row no longer renders violation" \
  "*violation*" "$(line_of "$MUT2_OUT" "superpowers")"

# ── Mutation 3: break an action line ─────────────────────────────────────────
# The half-uninstalled fix is deleted. The broken machine still detects the
# state; what is lost is the one thing the user could act on.
MUT3="$(doctor_copy action)"
grep -v 'curl -fsSL' "$DOCTOR_SH" > "$MUT3"
MUT3_OUT="$TMP/mut3.out"
doctor_run "$MUT3" "$BROKEN_BIN" "$BROKEN" > "$MUT3_OUT" 2>&1
MUT3_TEXT="$(cat "$MUT3_OUT")"
expect_not_contains "MUTATION 3 (curl fallback deleted): the half-uninstalled action line is gone" \
  "curl -fsSL" "$MUT3_TEXT"
expect_match "MUTATION 3: the half-uninstalled STATE is still detected (only the fix was lost)" \
  "*yes*" "$(line_of "$MUT3_OUT" "half-uninstalled")"

# ── Restore proof ────────────────────────────────────────────────────────────
expect_eq "the shipped doctor.sh and profile template are byte-identical after all three mutations" \
  "$PAYLOAD_CKSUM_BEFORE" "$(shasum -a 256 "$DOCTOR_SH" "$TEMPLATE" 2>/dev/null)"

R_OUT="$TMP/restored.out"
doctor_run "$DOCTOR_SH" "$BROKEN_BIN" "$BROKEN" > "$R_OUT" 2>&1
R="$(cat "$R_OUT")"
expect_contains "restored: the production doctor still reports the constraint violation" \
  "violates constraint ^6.3.0" "$R"
expect_contains "restored: the production doctor still prints the curl fallback one-liner" \
  "curl -fsSL" "$R"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 11: the suite is registered in tests/run.sh by name ==="
# ---------------------------------------------------------------------------
#
# tests/*.test.sh is NOT globbed by the runner — an unregistered suite is a
# silent false green.

expect_true "tests/run.sh names doctor.test.sh" \
  grep -q 'run "doctor.test.sh" bash tests/doctor.test.sh' "${REPO}/tests/run.sh"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 12: the installed agent role files — the legacy drift line (AC-13) ==="
# ---------------------------------------------------------------------------
#
# WHAT THIS LINE IS FOR. Role files ship in the PAYLOAD; that is the plugin-era
# truth and it is the half of this line a reader most needs, because the other
# half is a directory that should not exist. The retired installer also copied
# the six rendered role files into the CLI's own agents directory, and a
# session that finds them there loads THOSE — so a machine can be running a
# build of its subagent instructions that no plugin update will ever touch, and
# nothing else on the machine says so.
#
# REPORTING, NOT POLICING — the same contract the agent-integrity line above it
# keeps. It names the state and stops: no exit-code effect, no repair, and no
# SUMMARY action line. Group 6's "action lines only" assertion and Group 3's
# "nothing to do" summary are the wall that keeps it that way.
#
# THREE FIXTURE STATES, and the drift arm is what makes the other two mean
# anything: a line that said "no drift" on a machine where two files differ
# would pass an absent-check and a match-check both.

# The healthy machine has no legacy agents directory at all — the cold, correct,
# post-cutover state.
H_LEGACY_AGENTS="$(line_of "$H_OUT" "installed agent role files")"
expect_match "absent: the line says there are no installed copies" "*none*" "$H_LEGACY_AGENTS"
expect_match "absent: and it states the plugin-era truth in the same breath" \
  "*payload*" "$H_LEGACY_AGENTS"

# A third machine, built only for this line, so the healthy and broken fixtures
# every other group reads keep their exact shape.
LEGACY="$TMP/machine-legacy"; plant_machine "$LEGACY" healthy
mkdir -p "$LEGACY/claude-home/agents"
for a in auditor critic implementor researcher senior-implementor test-runner; do
  cp "$LEGACY/plugin/agents/${a}.md" "$LEGACY/claude-home/agents/${a}.md"
done

L_OUT="$TMP/legacy-match.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEGACY" > "$L_OUT" 2>&1
L_MATCH="$(line_of "$L_OUT" "installed agent role files")"
expect_match "match: the line counts the six installed copies" "*6*" "$L_MATCH"
expect_match "match: none of them differs from the payload" "*none differ*" "$L_MATCH"
expect_match "match: the plugin-era truth is stated even when the copies agree" \
  "*payload*" "$L_MATCH"

# Now two of them drift — the shape of a machine whose plugin updated while the
# installed copies stayed at the build the installer left.
printf '\nA line only the installed copy carries.\n' >> "$LEGACY/claude-home/agents/critic.md"
printf '\nAnd another.\n' >> "$LEGACY/claude-home/agents/auditor.md"

D_OUT="$TMP/legacy-drift.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEGACY" > "$D_OUT" 2>&1
D_DRIFT="$(line_of "$D_OUT" "installed agent role files")"
expect_match "drift: the line counts the two that differ" "*2*" "$D_DRIFT"
expect_match "drift: and names them, so the reader can open the right file" \
  "*critic.md*" "$D_DRIFT"
expect_match "drift: both names, not just the first" "*auditor.md*" "$D_DRIFT"
expect_not_match "drift: a drifting machine is not reported as agreeing" \
  "*none differ*" "$D_DRIFT"

# THE NO-MUTATION CONTRACT HOLDS OVER THE NEW READ TOO. doctor is read-only,
# and a line that compares two trees is exactly the kind of line that grows a
# temp file or a repair. Fingerprint the whole legacy machine across a run.
L_FP_BEFORE="$(fingerprint "$LEGACY")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEGACY" >/dev/null 2>&1
expect_eq "the drift read changes nothing on the machine it reads" \
  "$L_FP_BEFORE" "$(fingerprint "$LEGACY")"

# AND IT STAYS OUT OF THE SUMMARY. Reporting a legacy directory is not the same
# as telling the user to delete it — /bionic:setup owns that offer, under
# consent. If this line ever grew an action line, the summary of a machine that
# is otherwise fine would stop saying so.
expect_contains "the drift line adds no action line — the summary still says nothing to do" \
  "nothing to do" "$(cat "$D_OUT")"

# The fact is detect.sh's, rendered here — doctor re-deriving it from the
# filesystem is the defect Group 8 exists to prevent, and this line is a new
# chance to commit it.
expect_true "doctor renders the library fact rather than listing the directory itself" \
  grep -q 'detect_installed_agent_copies' "$DOCTOR_SH"
expect_true "the fact function lives in detect.sh" \
  grep -q '^detect_installed_agent_copies()' "${REPO}/payload/scripts/lib/detect.sh"

# --- RV-7: the registry schema is read in ONE file, and it is not this one ---
#
# doctor.sh used to carry `_doctor_install_path`, its own jq program over the CLI's
# `installed_plugins.json`. Same schema as detect_plugin_root's, different expression, and
# neither side could notice the other drifting — a CLI field rename would be fixed in the
# pinned copy and left standing in this one, answering just as confidently. Worse, it meant
# detect_plugin_root had no production callsite at all: the parse the suite drove was not
# the parse that ran.
#
# So the arm is a DUPLICATION wall, not a behaviour one. The behaviour is already covered by
# the roster-footprint counts above (14 and 28, both read through the shared function now);
# what this stops is the second reading coming back.
expect_true "doctor resolves an install path through the shared library function" \
  grep -q 'detect_plugin_install_path' "$DOCTOR_SH"
expect_true "…and that function lives in detect.sh" \
  grep -q '^detect_plugin_install_path()' "${REPO}/payload/scripts/lib/detect.sh"
expect_true "the retired local parse is gone from doctor.sh" \
  bash -c '! grep -q "^_doctor_install_path()" "$1"' _ "$DOCTOR_SH"
# The schema itself, named as an absence — but the absence has to be of the PARSE, not of
# the word. doctor legitimately says "installPath" out loud in two report strings, because
# explaining where a count came from is its job; what it must never do again is run a
# program over that field. So the pin is `jq` and `installPath` on one line, which is what
# the retired copy was and what any re-fork would be.
expect_eq "no jq program in doctor.sh reads the registry's installPath field" "" \
  "$(grep -nE 'jq[^|]*installPath|installPath[^|]*jq' "$DOCTOR_SH" || true)"
# And the multi-line form the retired copy actually used, caught by its other half: doctor
# names the registry FILE nowhere except in prose. Selecting the file is detect.sh's job via
# _detect_installed_plugins_file, which is the one expression that decides which registry
# every answer in the payload comes from.
expect_eq "doctor.sh opens the plugin registry file nowhere in its own code" "" \
  "$(grep -n 'installed_plugins\.json' "$DOCTOR_SH" | grep -vE '^[0-9]+:[[:space:]]*(#|echo)' || true)"

# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
