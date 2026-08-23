#!/bin/bash
# DOCTOR — epic-17 wave-03 slice S7 (spec AC-3; design ownership table: doctor is
# the RENDERING SURFACE of detect.sh's facts and the dependency-constraint
# agreement surface).
#
# WHAT THIS SUITE OWNS. payload/scripts/doctor.sh and payload/commands/doctor.md
# — the read-only diagnosis and its thin wrapper. Not the facts themselves:
# detect.sh's and deps.sh's behaviour is tests/plugin-lib.test.sh's subject.
# What is proven HERE is that doctor
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
# HEALTHY machine and on a BROKEN one (absences, a constraint violation, a
# legacy rc block, legacy-channel hook entries, half-uninstalled). A
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

# THE SUITE'S OWN STDIN IS CLOSED, ONCE, HERE (wave-06 S6). doctor now ends with
# one question, and whether it is ASKED depends on what stdin is: a terminal or a
# pipe can answer, a closed stream cannot. Left inherited, this file would behave
# one way under `bash tests/run.sh` in a terminal (doctor asks, and blocks waiting
# for a human who is not reading the suite) and another way under a runner. So
# every arm below starts from the unattended shape, and the two arms that mean to
# answer the question pipe into `doctor_run` explicitly.
exec < /dev/null

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
DOCTOR_SH="${REPO}/payload/scripts/doctor.sh"
DOCTOR_MD="${REPO}/payload/commands/doctor.md"

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
# THE DETAIL ROW, NOT THE PROBLEM LINE (AC-15 rule 3). The verdict stands ABOVE
# every table that carries facts, and a verdict line names the same thing its row
# does — "the legacy .zshrc alias block is still there", "agent-skills is
# absent". An unscoped first-match would hand every assertion below the problem
# statement instead of the fact it is about, and pass or fail on the wrong line.
#
# THE ANCHOR IS THE FIRST TABLE HEADING. It used to be `=== LOAD STATE ===`, the
# first section of the report the verbose arm printed; that arm was deleted by
# owner order on 2026-08-22 and no `=== … ===` heading survives outside UPDATES,
# so the awk matched nothing and this helper returned the empty string for every
# arm in the file — the single cause behind most of this suite's stale failures.
# `BIONIC NATIVE` is the same boundary in the report doctor prints today: the
# header and the verdict are above it, and all four tables are below.
# The verdict has its own extractor (verdict_block).
line_of() {
  awk '/^BIONIC NATIVE/{f=1} f' "$1" 2>/dev/null | grep -F -m1 -- "$2" || true
}

# THE VERDICT, which is where the deleted SUMMARY and FIX sections went. Doctor
# prints a provenance header, then one `→` line per problem it cannot collapse
# (plus one collapsed `→ N problems. Run /bionic:setup to fix: …` line), then the
# tables. Everything between line 1 and the first table heading is the verdict.
verdict_block() {  # <doctor-output-file>
  awk 'NR == 1 { next } /^BIONIC NATIVE/ { exit } { print }' "$1" 2>/dev/null
}

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
# `sleep` is on this list for wave-06 S6: doctor bounds every command that can
# hang (the plugin listing, brew, npm) and, with no `timeout` on a stock macOS,
# the bound is a poll loop that needs it. Without `sleep` on PATH doctor runs the
# probe unbounded, which is a different code path from the one under test.
# `date` and `stat` joined the list for the Patrol section (T2): a stamp's age
# is `now` minus its mtime, and both spellings of `stat` are tried in turn.
# `dirname`/`basename` are here because hooks/session-poker.sh — which doctor
# asks for the Patrol interval, rather than keeping a second copy of that
# constant — resolves a project root with them, and reads its own machine
# lines with `cut`.
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls tr head tail sort uniq wc jq python3 find shasum sleep diff date stat dirname basename cut; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

# A machine with every binary-shaped dependency present, at its real version line.
FULL_BIN="$TMP/bin-full"; mkdir -p "$FULL_BIN"; cp -R "$BASE_BIN"/. "$FULL_BIN"/
make_version_stub "$FULL_BIN" git    "git version 2.50.1 (Apple Git-155)"
make_version_stub "$FULL_BIN" node   "v26.7.0"
make_version_stub "$FULL_BIN" pnpm   "11.22.0"
make_version_stub "$FULL_BIN" gh     "gh version 2.97.0 (2026-07-31)"
make_version_stub "$FULL_BIN" rg     "ripgrep 15.2.0"
make_version_stub "$FULL_BIN" uv     "uv 0.12.5 (Homebrew 2026-08-14 aarch64-apple-darwin)"
make_version_stub "$FULL_BIN" docker "Docker version 29.2.1, build a5c7197"
make_version_stub "$FULL_BIN" aws    "aws-cli/2.25.1 Python/3.12.9 Darwin/25.5.0 exe/x86_64"
make_version_stub "$FULL_BIN" notebooklm "notebooklm 0.9.3"

# `npm list -g --depth=0 <pkg>`, real shape — captured 2026-08-17:
#     /opt/homebrew/lib
#     └── @playwright/cli@0.1.18
#
# `npm outdated -g --json` shape (wave-06 S6) — captured from npm's documented
# JSON: one object per package carrying current/wanted/latest. The stub reports
# ONE managed package outdated (@playwright/cli) and one package bionic does not
# manage (typescript), which is what makes the intersection assertion mean
# something: a doctor that printed npm's whole answer would list typescript too.
cat > "$FULL_BIN/npm" <<'STUB'
#!/bin/bash
echo "npm $*" >> "${BIONIC_TEST_CALLS:-/dev/null}"
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
if [ "${1:-}" = "outdated" ]; then
  cat <<'JSON'
{
  "@playwright/cli": { "current": "0.1.18", "wanted": "0.2.0", "latest": "0.2.0", "location": "/opt/homebrew/lib" },
  "typescript": { "current": "5.4.0", "wanted": "5.9.2", "latest": "5.9.2", "location": "/opt/homebrew/lib" }
}
JSON
  # npm exits 1 when it finds anything outdated. Treating that as a failure is
  # the obvious bug this stub exists to catch.
  exit 1
fi
exit 0
STUB
chmod +x "$FULL_BIN/npm"

# `brew outdated --verbose` shape (wave-06 S6): `<formula> (<installed>) < <latest>`.
# ripgrep is a managed row (the table's `rg`), yq is not — bionic dropped it at
# S3 — so the second line is the one an unintersected renderer would leak.
cat > "$FULL_BIN/brew" <<'STUB'
#!/bin/bash
echo "brew $*" >> "${BIONIC_TEST_CALLS:-/dev/null}"
if [ "${1:-}" = "outdated" ]; then
  echo "ripgrep (15.2.0) < 15.3.0"
  echo "yq (4.44.1) < 4.45.0"
  exit 0
fi
exit 0
STUB
chmod +x "$FULL_BIN/brew"

# `claude mcp get <name>` — exit 0 for a registered server, non-zero otherwise.
cat > "$FULL_BIN/claude" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "mcp" ] && [ "${2:-}" = "get" ]; then
  case "${3:-}" in context7|chrome-devtools) exit 0 ;; *) exit 1 ;; esac
fi
exit 0
STUB
chmod +x "$FULL_BIN/claude"

# The broken machine's PATH: base plus four binaries. pnpm/gh/uv/docker/aws/
# notebooklm are ABSENT (present=no); npm and claude are absent too, which
# is a different fact — their mechanisms cannot answer at all (present=unknown).
BROKEN_BIN="$TMP/bin-broken"; mkdir -p "$BROKEN_BIN"; cp -R "$BASE_BIN"/. "$BROKEN_BIN"/
make_version_stub "$BROKEN_BIN" git  "git version 2.50.1 (Apple Git-155)"
make_version_stub "$BROKEN_BIN" node "v26.7.0"
make_version_stub "$BROKEN_BIN" rg   "ripgrep 15.2.0"

# The unknown machine's PATH: the healthy one with jq removed. jq is itself a row
# in the dependency table, and without it the plugin registry and settings.json
# are unreadable.
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

# A whole fixture machine. `flavor` is healthy | broken.
plant_machine() {  # <machine-root> <flavor>
  local m="$1" flavor="$2"
  mkdir -p "$m/home" "$m/plugin/.claude-plugin" "$m/plugin/hooks" \
           "$m/plugin/ccstatusline" "$m/claude-home/plugins" "$m/installs"

  # ── ccstatusline's second half (epic-18 T1, AC-2) ────────────────────────
  # The payload always ships the layout file, on both flavors — what differs
  # is whether THIS MACHINE's copy under ~/.config matches it. healthy: it
  # does, so the two-half check reads present. broken: it is simply absent
  # (the settings.json below never sets .statusLine either, so this machine
  # was never "installed" at all — the shape a fresh box is in before its
  # first /bionic:setup, not a partial-install shape).
  printf '{"version":3,"lines":[[{"id":"1","type":"model"}]]}' > "$m/plugin/ccstatusline/settings.json"
  if [ "$flavor" = "healthy" ]; then
    mkdir -p "$m/home/.config/ccstatusline"
    cp "$m/plugin/ccstatusline/settings.json" "$m/home/.config/ccstatusline/settings.json"
  fi

  # ── the payload tree doctor is diagnosing ────────────────────────────────
  printf '{ "name": "bionic", "version": "0.1.0" }\n' > "$m/plugin/.claude-plugin/plugin.json"

  # BIONIC NATIVE's other two rows, and they ship on BOTH flavors because they
  # are payload facts: `skills` counts `<root>/skills/*/SKILL.md` and `commands`
  # counts `<root>/commands/*.md`, so a fixture that plants neither renders
  # `✗ skills 0/1` and `✗ commands 0/0` on every arm — a machine the suite calls
  # healthy while doctor calls it broken. The skill directory below is the one
  # the excalidraw block plants further down; without its SKILL.md the loop
  # counts the directory and finds nothing in it.
  mkdir -p "$m/plugin/skills/excalidraw-diagram" "$m/plugin/commands"
  printf -- '---\nname: excalidraw-diagram\n---\nFixture payload skill.\n' \
    > "$m/plugin/skills/excalidraw-diagram/SKILL.md"
  printf -- '---\ndescription: fixture command\n---\nFixture payload command.\n' \
    > "$m/plugin/commands/doctor.md"
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
    # The when-needed native row is INSTALLED on the healthy machine: absent, it
    # would put a dependency action in a summary this file pins as "nothing to
    # do". One skill, no agents — impeccable's real shape.
    plant_installed_tree "$m/installs/impeccable"   1 0
    # THE `extra` NATIVE ROWS ADDED AT epic-18 T4 (`document-skills`,
    # `example-skills`) ARE INSTALLED HERE, and `humanizer`'s loose skill
    # directory below with them. A healthy machine that carried none of the three
    # rendered three ✗ rows and a "→ 3 problems" verdict, which is what a healthy
    # fixture must not do: every "nothing to do" arm in this file measures the
    # verdict line, and a verdict that is wrong for fixture reasons cannot
    # discriminate a product that stopped saying it.
    plant_installed_tree "$m/installs/document-skills" 4 0
    plant_installed_tree "$m/installs/example-skills"  9 0
    cat > "$m/claude-home/plugins/installed_plugins.json" <<JSON
{ "plugins": {
    "bionic@bionic": [ { "scope": "user", "installPath": "${m}/plugin", "version": "0.1.0",
                         "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "superpowers@bionic": [ { "scope": "user", "installPath": "${m}/installs/superpowers", "version": "6.3.0",
                              "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "agent-skills@bionic": [ { "scope": "user", "installPath": "${m}/installs/agent-skills", "version": "0.6.1",
                               "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "impeccable@bionic": [ { "scope": "user", "installPath": "${m}/installs/impeccable", "version": "4.1.1",
                             "installedAt": "2026-08-20T00:00:00.000Z" } ],
    "document-skills@anthropic-agent-skills": [ { "scope": "user", "installPath": "${m}/installs/document-skills",
                             "version": "0.3.0", "installedAt": "2026-08-22T00:00:00.000Z" } ],
    "example-skills@anthropic-agent-skills": [ { "scope": "user", "installPath": "${m}/installs/example-skills",
                             "version": "0.3.0", "installedAt": "2026-08-22T00:00:00.000Z" } ] } }
JSON
    # `humanizer` is a github-skill row: its presence surface is a SKILL.md in
    # the CLI's loose skills directory, which is the claude home this fixture
    # points BIONIC_CLAUDE_HOME at.
    mkdir -p "$m/claude-home/skills/humanizer"
    printf -- '---\nname: humanizer\n---\nFixture humanizer skill.\n' \
      > "$m/claude-home/skills/humanizer/SKILL.md"
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
    # The machine's OWN permission rules, which bionic neither writes nor reads
    # any more: they are here so a run that touched them would be visible.
    python3 -c '
import json, sys
json.dump({"statusLine": {"type": "command", "command": "npx ccstatusline@latest"},
           "env": {"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1", "BASH_MAX_TIMEOUT_MS": "1800000",
                   "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"},
           "permissions": {"allow": ["Bash(ls:*)", "Bash(git status:*)"]},
           "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
               {"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh"}]}]}},
          open(sys.argv[1], "w"), indent=2)
' "$m/claude-home/settings.json"
  else
    # Two legacy managed-hook entries, no statusline, and the machine's own
    # permission rules.
    python3 -c '
import json, sys
json.dump({"permissions": {"allow": ["Bash(ls:*)", "Bash(git status:*)", "Bash(make:*)"]},
           "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
               {"type": "command", "command": "~/.claude/hooks/protect-main.sh"},
               {"type": "command", "command": "~/.claude/hooks/protect-database.sh"}]}]}},
          open(sys.argv[1], "w"), indent=2)
' "$m/claude-home/settings.json"
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

  # ── notebooklm's second half ─────────────────────────────────────────────
  # _dep_check_uv_tool's two-half probe (deps.sh) treats notebooklm as present
  # only when the CLI is on PATH AND this skill file exists under the claude
  # home the fixture points BIONIC_CLAUDE_HOME at. The healthy machine's PATH
  # already stubs the CLI (FULL_BIN, above); without this file a healthy
  # machine now probes as needing setup.
  if [ "$flavor" = "healthy" ]; then
    mkdir -p "$m/claude-home/skills/notebooklm"
    printf -- '---\nname: notebooklm\n---\nFixture notebooklm skill.\n' \
      > "$m/claude-home/skills/notebooklm/SKILL.md"
  fi

  # ── the excalidraw renderer's venv (epic-18 T3, AC-6) ────────────────────
  #
  # The skill ships INSIDE the plugin now, so its uv project lives under the plugin root and
  # the venv `uv sync` leaves there is what the row's probe reads. The healthy machine has
  # rendered a diagram at some point; the broken one never has, which is the ordinary state
  # of a when-needed row rather than a defect.
  if [ "$flavor" = "healthy" ]; then
    mkdir -p "$m/plugin/skills/excalidraw-diagram/references/.venv/bin"
    : > "$m/plugin/skills/excalidraw-diagram/references/.venv/bin/python"
    chmod +x "$m/plugin/skills/excalidraw-diagram/references/.venv/bin/python"
    printf 'home = /opt/homebrew/bin\nversion = 3.13.1\n' \
      > "$m/plugin/skills/excalidraw-diagram/references/.venv/pyvenv.cfg"
  else
    mkdir -p "$m/plugin/skills/excalidraw-diagram/references"
  fi
}

# The CLI listing every arm reads unless it says otherwise (wave-06 S6). The
# plugin's load state is the CLI's own answer and the only way to ask is to run
# it, so the hermetic default is the captured listing of a machine where bionic
# loaded — `cat` on a fixture file, through the same seam production leaves unset.
# Arms that need another state pass their own BIONIC_PLUGIN_LIST_CMD; `env`
# applies assignments in order, so the later one wins.
# The one question doctor asks, verbatim (ratified D-D wording). Defined once: three
# groups assert on it, and a copy that drifted would let the wording change while every
# arm stayed green.
UPDATES_QUESTION="Check for tool updates? This asks Homebrew and npm and can take up to 30 seconds. [y/N]"

LISTING_HEALTHY="${REPO}/tests/fixtures/plugin-list-healthy.txt"
LISTING_DEPBROKEN="${REPO}/tests/fixtures/plugin-list-dep-broken.txt"

# Run a doctor script against a fixture machine with a controlled environment.
#
# Everything after the machine root is an ENV ASSIGNMENT until a bare `--`; everything
# after that is an ARGUMENT to doctor.sh itself. The separator was added at S6b, when
# doctor grew its first flag: without it `--updates` would have been handed to `env`,
# which would have read it as one of ITS options and failed in a way that looks nothing
# like the thing under test.
doctor_run() {  # <doctor.sh> <bin-dir> <machine-root> [env assignments...] [-- <script args...>]
  local sh="$1" bin="$2" m="$3"; shift 3
  local a seen=0
  local -a envs=() args=()
  for a in "$@"; do
    if [ "$seen" = "0" ] && [ "$a" = "--" ]; then seen=1; continue; fi
    if [ "$seen" = "1" ]; then args+=("$a"); else envs+=("$a"); fi
  done
  env -i \
    HOME="$m/home" \
    PATH="$bin" \
    BIONIC_PLUGIN_LIST_CMD="cat ${LISTING_HEALTHY}" \
    BIONIC_TEST_CALLS="$CALLS" \
    BIONIC_PLUGIN_ROOT="$m/plugin" \
    BIONIC_CLAUDE_HOME="$m/claude-home" \
    BIONIC_SETTINGS_FILE="$m/claude-home/settings.json" \
    BIONIC_INSTALLED_PLUGINS_FILE="$m/claude-home/plugins/installed_plugins.json" \
    BIONIC_SHELL_RC="$m/rc" \
    BIONIC_PLAYWRIGHT_CACHE="$m/playwright-cache" \
    ${envs[@]+"${envs[@]}"} \
    bash "$sh" ${args[@]+"${args[@]}"} 2>&1
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
  #
  # THE PIN IS REWRITTEN, NOT EXEMPTED (wave-06 S6b). It used to read "exactly one
  # ${CLAUDE_PLUGIN_ROOT} invocation", which was the strongest true statement while
  # doctor had one entry point. It has two now — the report, and the same script with
  # `--updates` when the user answers yes to the question the report ends with — and
  # counting them is no longer what the pin was protecting. What it was protecting is
  # that command prose runs NOTHING but this one read-only script: so every invocation
  # must name scripts/doctor.sh, and nothing else may appear.
  MD_INVOCATIONS="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}[^"'"'"'`]*' "$DOCTOR_MD" 2>/dev/null | sed 's/[[:space:]]*$//')"
  MD_FOREIGN="$(printf '%s\n' "$MD_INVOCATIONS" | grep -v '^\${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh' || true)"
  expect_eq "doctor.md: every invocation is the read-only doctor.sh, and nothing else" "" "$MD_FOREIGN"
  expect_true "doctor.md: at least one invocation exists" test -n "$MD_INVOCATIONS"
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

# ONE REPORT, ONE CAPTURE — and the second capture is kept as the proof of it.
# There used to be two audiences: a DEFAULT page of certified tables and a
# `verbose` arm that added back every section this report had ever printed. The
# verbose arm was deleted whole on 2026-08-22 by owner order — "the explainer
# prose is deleted, not parked", doctor.sh's own header says so — and both
# captures below now run doctor exactly the same way. They are retained because
# two identical invocations producing identical text is the cheapest available
# statement that there is no second mode left to drift.
H_OUT="$TMP/healthy.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY"  > "$H_OUT" 2>&1
H_RC=$?
H="$(cat "$H_OUT")"

H_DEF="$TMP/healthy-default.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" > "$H_DEF" 2>&1
H_DEF_RC=$?

expect_eq "doctor exits 0 on a healthy machine (a diagnosis is not a failure)" "0" "$H_RC"
expect_eq "the default report exits 0 too" "0" "$H_DEF_RC"

# THE `=== … ===` SECTIONS ARE GONE, ALL OF THEM BUT ONE. The ordered roster this
# helper served — LOAD STATE, PLUGIN INTEGRITY, TIER STATE, DEPENDENCIES,
# DUPLICATES, ENVIRONMENT, ROSTER FOOTPRINT — belonged to the verbose arm deleted
# on 2026-08-22, so the two ordering assertions and the two expected rosters they
# compared against are removed. `section_roster` itself stays: `UPDATES` is still
# printed in that shape, and Groups 19 and 20 read it that way.
section_roster() {  # <doctor-output-file> -> one section name per line, in order
  sed -n 's/^=== \(.*\) ===$/\1/p' "$1"
}
expect_eq "healthy: no FIX section on a machine with nothing to fix" \
  "" "$(grep -c '^=== FIX ===$' "$H_OUT" | grep -v '^0$' || true)"

# THE CERTIFIED DEFAULT PAGE: a header, a verdict, four tables. Asserted as the
# ordered list of its table titles for the same reason the roster above is — a
# containment check passes on a page that prints all four in the wrong order.
#
# PATROL JOINED THE PAGE 2026-08-22 (task T2, plan task-dispatch-wall-channel-loss),
# and it comes LAST on purpose: the three above it read files that exist, and it
# reads a reconstruction of something no file holds. A section whose answer is
# inferred belongs under the sections whose answers are read.
default_tables() {  # <doctor-output-file> -> one table title per line, in order
  sed -n 's/^\([A-Z][A-Z ]*[A-Z]\)\( — .*\)\{0,1\}$/\1/p' "$1"
}
EXPECTED_TABLES="BIONIC NATIVE
THIRD PARTY
ENVIRONMENT
PATROL"
expect_eq "healthy: the default report is the four certified tables, in order" \
  "$EXPECTED_TABLES" "$(default_tables "$H_DEF")"
expect_match "healthy: the header names the payload version and the commit it came from" \
  "Bionic Doctor — payload 0.1.0 @ *" "$(head -1 "$H_DEF")"
expect_eq "healthy: no detail section reaches the default report" \
  "" "$(section_roster "$H_DEF")"

# ── AC-15's width wall: no line this report composes may wrap ──────────────
#
# Chris's complaint was measured, not aesthetic: "doctor prints two lines for
# each thing. it's really hard to read!" A line over 100 columns becomes two
# lines on the terminal it is read in, which breaks rule 1 from the outside.
# Counted in COLUMNS, not bytes: ✓/✗/–/— are three bytes and one column each, so
# the continuation bytes (0x80–0xBF) are dropped before the length is taken.
# ONE EXEMPTION, AND IT IS NOT A LOOPHOLE: a line whose overflow is a single
# unbreakable token — a filesystem path, a raw URL, the CLI's own verbatim error.
# Truncating one of those makes it useless, and no wording doctor chooses can
# shorten it, so the rule this wall enforces is "nothing wraps because of what
# doctor CHOSE to put on the line". A line carrying no token over 40 columns has
# no such excuse. The fixture's own $TMPDIR path is why this is not theoretical.
over_100_cols() {  # <file> -> the offending lines, empty when there are none
  LC_ALL=C awk '
    { s=$0; gsub(/[\200-\277]/, "", s)
      if (length(s) <= 100) next
      longest = 0
      n = split(s, tok, /[ \t]+/)
      for (i = 1; i <= n; i++) if (length(tok[i]) > longest) longest = length(tok[i])
      if (longest <= 40) print length(s) ": " $0 }' "$1"
}

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 3: the healthy machine — the facts, not just the headings ==="
# ---------------------------------------------------------------------------


# AC-4, the STOCK arm. One line, in the integrity section, naming the state and
# how many files it covers — a "stock" with no count is a claim the reader
# cannot size.
# THE ROW LABEL IS `agents` NOW. The integrity fact used to have a line of its
# own in PLUGIN INTEGRITY headed "agent files"; it is BIONIC NATIVE's second row
# today — `✓ agents 6/6 stock` — so the needle moves and the claim does not. The
# surrounding spaces keep it off `agent-skills` in the table below.
H_AGENTS="$(line_of "$H_OUT" " agents ")"
expect_not_match "healthy: a stock machine is not called modified" "*modified*" "$H_AGENTS"
expect_not_contains "healthy: no reinstall nag when the files are stock" \
  "reinstall restores stock" "$H"

# Every class, presence AND version AND constraint AND verdict — the dep table
# is the sole constraint-agreement surface (AC-3, AC-8), so the verdict must be
# rendered per row, not inferred by the reader.
#
# THE COLUMN IS `class` NOW (wave-06 S6, AC-6). S3 replaced the lane column in
# the TABLE; the column doctor PRINTED was still the derived lane, which is
# exactly the internal vocabulary the voice contract bans from a display — Chris,
# 2026-08-20: "This concept of 'lane' and in particular references to '3b' are
# very confusing. Why are we exposing this to the user?" So the globs below name
# the four ratified classes, and the negative arm after them is what keeps the
# old codes from coming back anywhere in the report.
DEP_SECTION_H="$(awk '/=== DEPENDENCIES ===/,/=== DUPLICATES ===/' "$H_OUT")"
# The whole report, not just the table: the degradation map and the roster
# footprint each used to spell the lane codes out in prose.
LANE_TOKENS="$(grep -nE '(^|[^[:alnum:]])(lane|3a|3b)([^[:alnum:]]|$)' "$H_OUT" || true)"
expect_eq "healthy: no internal lane vocabulary reaches the report at all" "" "$LANE_TOKENS"
# The when-needed NATIVE row: same registry probe as the core rows, judged
# against its own ^4.1.0, and it belongs to neither legacy lane.

# Environment class.
# CONFIGURED AND LIVE ARE TWO FACTS. The healthy machine's settings.json
# carries both names; the process doctor ran in does not (doctor_run starts from
# `env -i`), so the honest report is "configured, not live in this session" —
# which is a restart, not a repair, and Group 21 below is where the pair is
# driven end to end.
# AC-15 rule 4. Six checks ask the same kind of question — did the retired
# installer leave something behind — and on a clean machine all six answer no.
# Six rows of "none" is the zero-value filler the rule names, so a CLEAN check is
# counted and a DIRTY one is printed with its own row. The count still appears,
# because "we looked at six things and they were fine" is a different claim from
# saying nothing; the broken-machine arms below prove the dirty half still prints.
expect_eq "healthy: a clean legacy check gets no row of its own" \
  "" "$(line_of "$H_OUT" "legacy .zshrc alias block")"

# THE PERMISSION-PROFILE ROW IS GONE (epic-18 T13). bionic ships no managed
# allow-list, so doctor has no block to diff and no staleness to name. What is
# pinned instead is the ABSENCE: a report that started mentioning one again would
# be reporting a feature the product does not have.
expect_not_contains "healthy: doctor names no permission profile at all" "permission profile" "$H"

# THE METHOD PARAGRAPH IS GONE FROM THE DEFAULT OUTPUT (AC-15 rule 2). Eight
# lines used to stand here explaining how a roster line is counted — a
# maintainer's paragraph printed at a user on every single run. It lives in
# doctor.sh's own comments now, which is where the person it is addressed to
# reads.
expect_not_contains "healthy: the counting-method paragraph is not printed at the user" \
  "method:" "$H"
# THE ROSTER FOOTPRINT SECTION WENT WITH THE VERBOSE ARM (2026-08-22, owner
# order). `ROSTER FOOTPRINT` survives in doctor.sh only as a comment; nothing
# prints it, so `roster_line_of` and the two count assertions it served read a
# section that does not exist. Removed rather than rewired: there is no
# replacement surface to point them at.

# Half-uninstalled. THE FACT MOVED INTO BIONIC NATIVE's `install` row when TIER
# STATE was deleted — one row, `✗ install — half-uninstalled — the CLI no longer
# knows bionic` — and the verdict above carries its action line. `line_of` already
# skips the verdict, so the old section-scoping this helper existed for is what
# `line_of` now does for every table.
tier_line_of() {  # <doctor-output-file> <label>
  line_of "$1" "$2"
}
expect_not_contains "healthy: no curl fallback one-liner on a registered machine" \
  "remove.sh | bash" "$H"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 3b: the permission mode line, and its Remote Control note (AC-10) ==="
# ---------------------------------------------------------------------------
#
# item 1 + O-3: doctor had no permission-mode line at all (a grep for
# `defaultMode`/`permission mode` came back empty). The fixture machine's
# settings.json carries no `.permissions.defaultMode` key, so the honest first
# reading is `unset` — never a bare blank, never a value doctor invented.

RC_NOTE='Remote Control sessions override this (Manual / Accept edits / Plan only).'

# THE CAVEAT RIDES ON THE ROW (AC-15 rule 1). The full sentence — which also
# names the three modes — was a second line under the value, the exact shape of
# the complaint this AC answers. Doctor prints the half that changes what a
# reader would do; /bionic:setup still prints the note whole, beside the
# question where there is room for it.

# A machine that HAS written a mode (the setup item's own effect) reports that
# value verbatim, with the same note beside it — the note is about what
# overrides the value, not about whether one happens to be set.
MODE_MACHINE="$TMP/machine-mode-auto"; rm -rf "$MODE_MACHINE"; cp -R "$HEALTHY" "$MODE_MACHINE"
jq '.permissions.defaultMode = "auto"' "$HEALTHY/claude-home/settings.json" \
  > "$MODE_MACHINE/claude-home/settings.json"
MODE_OUT="$TMP/mode-auto.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$MODE_MACHINE"  > "$MODE_OUT" 2>&1
MODE_RC=$?
expect_eq "mode set: doctor still exits 0" "0" "$MODE_RC"

# jq absent: the value cannot be read at all, so `unknown` — never coerced to
# `unset`, which would tell a machine that could not be read that it has
# nothing configured.
MODEQ_OUT="$TMP/mode-nojq.out"
doctor_run "$DOCTOR_SH" "$NOJQ_BIN" "$HEALTHY"  > "$MODEQ_OUT" 2>&1

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 4: the broken machine — every failure renders WITH its named fix ==="
# ---------------------------------------------------------------------------

B_OUT="$TMP/broken.out"
doctor_run "$DOCTOR_SH" "$BROKEN_BIN" "$BROKEN"  > "$B_OUT" 2>&1
B_RC=$?
B="$(cat "$B_OUT")"

B_DEF="$TMP/broken-default.out"
doctor_run "$DOCTOR_SH" "$BROKEN_BIN" "$BROKEN" > "$B_DEF" 2>&1

expect_eq "doctor exits 0 on a broken machine too (a diagnosis is not a failure)" "0" "$B_RC"

expect_eq "broken: the default report still renders the four certified tables" \
  "$EXPECTED_TABLES" "$(default_tables "$B_DEF")"


# W7 S11 (six-axis review axis 2). The SUMMARY's action line for degraded wiring
# used to read `re-converge with:` and then the hint in backticks — which on a
# directory-source machine handed a user with a genuinely broken tree the words
# "nothing to do" formatted as a command to run. The hint answers per state now,
# so this line gets a repair sentence instead of a re-converge fragment. This
# fixture carries no marketplace registry, so the feed kind is unknown and the
# git-source sentence is the one that renders — the documented default.
#
# THE ACTION IS A VERDICT LINE NOW. SUMMARY was deleted with the verbose arm; the
# problems doctor cannot collapse into the one /bionic:setup line are printed as
# `→ …` lines directly under the header, and the hook-wiring one is
# `→ hooks degraded → <hint>`. Same sentence, read from `verdict_block` instead
# of from a section that no longer prints.
B_HOOKFIX="$(verdict_block "$B_OUT" | grep -F -- "hooks degraded" || true)"
expect_contains "broken: the hook-wiring action names the copy the CLI reads" \
  "the installed copy is what the CLI reads" "$B_HOOKFIX"
expect_contains "broken: …and the command that re-converges it" \
  "claude plugin update bionic@bionic" "$B_HOOKFIX"
expect_not_contains "broken: …and never offers 'nothing to do' to a broken machine" \
  "nothing to do" "$B_HOOKFIX"
expect_not_contains "broken: …with no re-converge prefix in front of the sentence" \
  "re-converge with:" "$B_HOOKFIX"

# AC-4, the MODIFIED-LOCALLY arm. The framing is fixed by the AC and is the
# whole difference between a report and a scolding: an edited role file is a
# legitimate thing for a user to have done, and the line says so before it says
# how to undo it.
B_AGENTS="$(line_of "$B_OUT" " agents ")"
# THE WORD IS `edited locally` NOW, and the framing clause is the tail of the same
# row: `– agents 5/6 1 edited locally (critic.md) — reinstall restores stock`.
# AC-4's requirement is unchanged — say it is a legitimate thing to have done,
# then say how to undo it — and the row says both. The "may be intentional;"
# half of the old sentence is absent from doctor.sh (0 occurrences), so the pin
# is the half that survived.
expect_match "broken: the agent-integrity line reports the local modification" \
  "*edited locally*" "$B_AGENTS"
# The count is rendered as the row's `count` column — stock-over-shipped — rather
# than as the "1 of 6" prose the deleted line carried.
expect_match "broken: the modified line counts them against the shipped total" \
  "*5/6*" "$B_AGENTS"
expect_match "broken: the modified line NAMES the file that differs" "*critic.md*" "$B_AGENTS"
expect_contains "broken: the modified line carries the AC's exact framing" \
  "reinstall restores stock" "$B_AGENTS"
# REPORT-NEVER-POLICE. Exactly one line about integrity, and none of it in the
# verdict: the verdict is the action list, and a local edit is not a defect to
# be actioned. (Exit 0 is asserted at the top of this group for the whole run.)
B_AGENT_LINES="$(grep -c "edited locally" "$B_OUT" 2>/dev/null | tr -d ' ')"
expect_eq "broken: integrity is ONE line, not a section of nagging" "1" "$B_AGENT_LINES"

# The constraint violation — the whole point of carrying the dep table's
# constraint into the report.
# THE COLUMNS ARE `name / version / source / state` NOW (THIRD PARTY), and the
# class column is gone with the DEPENDENCIES table it lived in. The row still
# carries every fact this assertion was written for — which version is installed,
# which constraint it violates, what to type — so the glob is re-cut to the
# columns doctor prints rather than to the ones it used to.
expect_match "broken: superpowers 6.2.0 under ^6.3.0 renders verdict=violation" \
  "*superpowers*6.2.0*violates ^6.3.0*/bionic:setup*" "$(line_of "$B_OUT" "superpowers")"
expect_contains "broken: the violation appears in the degradation map with its constraint" \
  "violates constraint ^6.3.0" "$B"
expect_match "broken: the violation line names /bionic:setup as the fix" \
  "*/bionic:setup*" "$(grep -F -m1 -- "violates constraint" "$B_OUT" || true)"

# Absences, one per class that can have one, each with a named fix.
# `aws` carries the absent-basic case that `yq` used to: yq and gcloud were
# dropped from the table at wave-06 S3 (no consumer, no test, not universal),
# and the case they stood for — a substrate binary missing from PATH — is
# exactly what aws is on the broken machine.
# The state column's word for an absence is `not installed`, and it ends in the
# command that repairs it. The class column the old globs led with is gone.
expect_match "broken: absent core dependency renders present=no" \
  "*agent-skills*not installed*/bionic:setup*" "$(line_of "$B_OUT" "agent-skills")"
expect_match "broken: absent basic dependency renders present=no" \
  "*aws*not installed*/bionic:setup*" "$(line_of "$B_OUT" " aws ")"
# THE `=== FIX ===` SECTION IS GONE (0 occurrences in doctor.sh) and its two
# per-name assertions with it: the absences collapse into ONE verdict line whose
# name list is truncated at 99 columns, so no assertion can require a particular
# name to appear there. The claim each of them made — this dependency is reported
# absent with its repair command — is what the two row assertions above pin, on
# the surface that carries it now.
DEG="$(verdict_block "$B_OUT")"
# THE JIT WORDING NEVER REACHES THE VERDICT. Just-in-time install is what happens
# to a WHEN-NEEDED row, and the class is empty as of 41110bd — so the words
# cannot appear over any row, which is what this arm has always asserted.
expect_not_contains "broken: no FIX line offers to wait for a route (that class is not degraded)" \
  "just-in-time" "$DEG"
expect_contains "broken: the absent dependencies are offered the command that installs them" \
  "Run /bionic:setup to fix:" "$DEG"
expect_contains "broken: every FIX line ends in the command that repairs it" "→" "$DEG"

# Environment class, the other way round from healthy.
# ENVIRONMENT's third column is a STATE, and its word for an unset name is
# `not set → /bionic:setup` — the same fact the old `absent` said, said in the
# product's word and carrying its repair.
expect_match "broken: the task-list name reports absent" \
  "*not set*/bionic:setup*" "$(line_of "$B_OUT" "CLAUDE_CODE_ENABLE_TODO_TOOLS")"
expect_match "broken: so does the long-command ceiling" \
  "*not set*/bionic:setup*" "$(line_of "$B_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "broken: legacy .zshrc alias block reported present" \
  "*present*" "$(line_of "$B_OUT" "legacy .zshrc alias block")"
# The row's label lost the word `entries` when it moved into ENVIRONMENT; the
# count it carries is the assertion and is unchanged.
expect_match "broken: two legacy-channel managed-hook entries counted" \
  "*2*" "$(line_of "$B_OUT" "legacy-channel managed hooks")"
# ccstatusline is a THIRD PARTY row keyed on its own name — the `statusline`
# suffix belonged to the label the deleted ENVIRONMENT one-liner carried.
expect_match "broken: ccstatusline reported absent" \
  "*not installed*/bionic:setup*" "$(line_of "$B_OUT" " ccstatusline ")"

# The broken machine names no permission profile either — the absence holds on
# both arms, which is what keeps this from passing on a report that simply had
# nothing to say.
expect_not_contains "broken: doctor names no permission profile at all" "permission profile" "$B"

# Half-uninstalled — the curl fallback one-liner is its action line (D5a: the
# remover must not depend on the thing it removes).
expect_match "broken: half-uninstalled reported yes" \
  "*half-uninstalled*" "$(tier_line_of "$B_OUT" " install ")"
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
doctor_run "$DOCTOR_SH" "$NOJQ_BIN" "$HEALTHY"  > "$U_OUT" 2>&1
U_RC=$?
U="$(cat "$U_OUT")"

expect_eq "doctor exits 0 with jq absent" "0" "$U_RC"

# THE WORD `unknown` IS THE VERDICT'S, NOT THE ROW'S. A row whose presence could
# not be read renders `✗ <name> — <source> jq is not on PATH → /bionic:setup`;
# the three-valued answer itself — "this is unknown, and here is why" — is the
# verdict line above the tables. That is where the claim lives, so that is what
# is read.
verdict_line() {  # <doctor-output-file> <needle>
  verdict_block "$1" | grep -F -m1 -- "$2" || true
}
SP_LINE="$(verdict_line "$U_OUT" "superpowers")"
expect_match "no jq: a plugin-shaped dependency's presence renders unknown" "*unknown*" "$SP_LINE"
# The negative is written as ` absent ` with its surrounding spaces on purpose:
# a bare `no` is a substring of `unknown`, so the obvious spelling of this
# assertion would pass on the very value it is meant to reject.
expect_not_match "no jq: that presence is NOT coerced to no" "*superpowers* absent *" "$SP_LINE"

# THE LEGACY-HOOK COUNT HAS NO ROW TO READ WHEN IT IS UNKNOWN. doctor's
# ENVIRONMENT block prints that row for a count of 1 or more and stays silent on
# `unknown|0` alike (`case "$LEGACY_HOOK_COUNT" in unknown|0) ;;`), so with jq
# absent there is no line — neither an honest one nor a coerced one. Both arms
# that read it are removed rather than rewired: the surface is gone, and R2 puts
# adding one out of this wave's scope.

# THE ROSTER FOOTPRINT SECTION IS GONE (see Group 3), so its unknown-count arm
# goes with it.

# Every unknown carries a NAMED CAUSE — "unknown" alone is a shrug, not a
# diagnosis.
expect_contains "no jq: the cause of the unknowns is named" "jq is not on PATH" "$U"
expect_contains "no jq: FIX names installing jq as an action" "install jq" "$U"

# AC-4's third value. Two ways the integrity question cannot be answered — no
# digest tool, and no manifest to compare against — and both must read `unknown`
# with a named cause rather than the confident wrong answer in either direction.
# Calling an unreadable machine "stock" is the dangerous one: it is the state
# this line exists to detect, reported as the state it exists to reassure about.
NS_OUT="$TMP/nosha.out"
doctor_run "$DOCTOR_SH" "$NOSHA_BIN" "$HEALTHY"  > "$NS_OUT" 2>&1
NS_RC=$?
expect_eq "no sha tool: doctor still exits 0" "0" "$NS_RC"
NS_AGENTS="$(line_of "$NS_OUT" " agents ")"
expect_match "no sha tool: the integrity line renders unknown" "*unknown*" "$NS_AGENTS"
expect_not_match "no sha tool: an unreadable machine is NOT reported stock" "*stock*" "$NS_AGENTS"
expect_match "no sha tool: the unknown names its cause" "*sha*" "$NS_AGENTS"

NOMAN="$TMP/machine-nomanifest"; cp -R "$HEALTHY" "$NOMAN"; rm -rf "$NOMAN/plugin/integrity"
NM_OUT="$TMP/nomanifest.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$NOMAN"  > "$NM_OUT" 2>&1
NM_RC=$?
expect_eq "no manifest: doctor still exits 0" "0" "$NM_RC"
NM_AGENTS="$(line_of "$NM_OUT" " agents ")"
expect_match "no manifest: the integrity line renders unknown" "*unknown*" "$NM_AGENTS"
expect_not_match "no manifest: a payload with nothing to compare is NOT reported stock" \
  "*stock*" "$NM_AGENTS"
expect_match "no manifest: the unknown names the missing manifest as its cause" \
  "*manifest*" "$NM_AGENTS"

# The mechanism-level unknown, present on a fully healthy machine: the pnpm
# content-addressable store is a cache with no installed-state to read, so `no`
# would be a lie on a warm machine.
MOTION_LINE="$(line_of "$H_OUT" " motion ")"
# THE THREE-VALUED ANSWER IS THE SYMBOL IN COLUMN ONE. `–` is doctor's `unknown`
# in every table it prints — ✓ present, ✗ absent, – neither — and the row's own
# state column names the cause beside it. The word "unknown" was the DEPENDENCIES
# table's spelling of the same value, and that table is gone; what must still be
# true, and is what this arm was written for, is that a cache is not reported as
# an absence.
expect_match "healthy: the pnpm-store dependency renders present=unknown" "  – motion*" "$MOTION_LINE"
expect_contains "healthy: the pnpm-store unknown carries its named cause, on its own row" \
  "a cache, no presence surface" "$(line_of "$H_OUT" " motion ")"
expect_not_contains "healthy: a no-action unknown does not manufacture a setup reason" \
  "→ run /bionic:setup" "$H"
# SIX-AXIS REVIEW C-2, AMENDED 2026-08-22. The claim has moved twice and the pin
# tracks it both times. It first read "/bionic:setup re-warms the store either
# way" — true while setup walked every non-native row, false once AC-11 made a
# when-needed tool nobody's until a route asked. C-2 keyed it on the CLASS. Chris
# then promoted `motion` to `extra`, which makes /bionic:setup the installer again
# and would have sent a permanently-unreadable presence to "resolve the cause
# above, then re-run doctor" — a repair that does not exist for a cache. So the
# sentence is keyed on class AND mechanism now, and what it must not do in either
# case is manufacture a repair.
# THE DEGRADATION LINE FOR THIS ROW IS GONE, and its absence is now the whole
# claim. A `–` row is not a problem, so it earns no verdict line at all — which
# is the stronger form of what these three arms were protecting: the sentence
# could not "manufacture a repair" because there is no sentence. Neither
# "/bionic:setup offers motion either way" nor "resolve the cause above" occurs
# in doctor.sh (0 each). What replaces them is the pin two lines up: the row
# carries its own cause, and the healthy verdict below says there is nothing to
# do.
expect_not_contains "healthy: a cache with no presence surface raises no verdict line" \
  "motion" "$(verdict_block "$H_OUT")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 6: the SUMMARY block — action lines only ==="
# ---------------------------------------------------------------------------

# THE SUMMARY AND FIX SECTIONS BOTH BECAME THE VERDICT (2026-08-22, owner order).
# What used to be `=== SUMMARY ===` — one line saying how many problems there are
# — and `=== FIX ===` — one action line per problem — is a single block of `→`
# lines between the provenance header and the first table. The claims below are
# unchanged; every one of them is read from `verdict_block` now, and the two
# assertions that measured the SECTIONS rather than the claims are gone:
# "the FIX block is absent, not empty" (there is no block to be absent) and
# "a FIX line names the absences setup would repair" (the collapsed line's name
# list is truncated at 99 columns, so no name can be required to survive it —
# the constraint-violation arm below reads the untruncated half and keeps the
# claim that the action states its reason).
H_SUM="$(verdict_block "$H_OUT")"
B_SUM="$(verdict_block "$B_OUT")"

H_VERDICT="$H_SUM"
expect_contains "healthy: the SUMMARY line says there is nothing to do" "Nothing to do" "$H_VERDICT"
expect_eq "healthy: …and it is one line, not a second report" "1" \
  "$(printf '%s\n' "$H_VERDICT" | awk 'NF' | wc -l | tr -d ' ')"
B_VERDICT="$B_SUM"
# The count, and then what to type — the pointer at a FIX section became the
# command itself, which is the same sentence with one fewer indirection.
expect_match "broken: the SUMMARY line counts what is wrong and points at FIX" \
  "*problems.*to fix*" "$B_VERDICT"
expect_contains "broken: FIX names /bionic:setup" "/bionic:setup" "$B_SUM"
expect_contains "broken: FIX carries the curl fallback one-liner" "curl -fsSL" "$B_SUM"

# "Action lines only": every non-blank verdict line either starts an action
# (`→`) or is the indented continuation of one. No fact restatements. The one
# continuation the report has is the raw remove.sh one-liner, indented three
# columns under the half-uninstalled line it belongs to.
SUM_NON_ACTION="$(verdict_block "$B_OUT" | awk 'NF && $0 !~ /→/ && $0 !~ /^ {3}/ && $0 !~ /Finish with:$/')"
expect_eq "broken: FIX contains action lines only (no restated facts)" "" "$SUM_NON_ACTION"

expect_match "broken: another names the constraint violation it would repair" "*violates constraint*" \
  "$(grep -F -m1 -- "violates constraint" "$B_OUT" || true)"

# AC-4's report-never-police clause, measured where policing would show up. The
# broken machine HAS a locally modified role file; the verdict is where doctor
# tells a user what to do, and a modified agent file is not something to do
# anything about. The row above already says how to undo it if they want to.
expect_not_contains "broken: FIX raises no action over a locally modified agent file" \
  "reinstall restores stock" "$B_SUM"
expect_not_contains "broken: FIX does not restate the integrity fact" \
  "edited locally" "$B_SUM"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 7: doctor never prompts and never reaches the network ==="
# ---------------------------------------------------------------------------
#
# A read-only report that blocked on stdin would hang the command surface, and
# one that shelled out to the network would not be a diagnosis of THIS machine.
# stdin is closed for this run: a `read` would fail, and any consent-shaped pause
# would show up as a prompt string in the output.
#
# WAVE-06 S6 KEEPS THIS ARM AS WRITTEN AND IT MEANS MORE THAN IT DID. Doctor now
# has exactly one question, and this is the machine that cannot answer it: with
# stdin closed the report must come out identical to the one every other arm
# gets, with no question in it. Group 19 owns the other half — the answered
# question and the section it appends.

NP_OUT="$TMP/noprompt.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" < /dev/null  > "$NP_OUT" 2>&1
NP_RC=$?
NP="$(cat "$NP_OUT")"
expect_eq "doctor completes with stdin closed (it never blocks on an answer)" "0" "$NP_RC"
# THE QUESTION IS GONE (doctor.sh:1485, Chris 2026-08-22: "There's not much value
# of that"). Doctor asks nothing at all now, so the arm that required it to be
# printed here is removed and the arm below — that it asks nothing else — is what
# the whole claim has become: with stdin closed, the report comes out identical
# to every other arm's and carries no prompt of any kind.
expect_not_contains "…and asks nothing else" "Install " "$NP"
expect_not_contains "…nor the retired update question" "Check for tool updates" "$NP"
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
#
# NARROWED AT WAVE-06 S6, and narrowed deliberately rather than deleted. Doctor
# now asks two package managers ONE read-only question each — `brew outdated`,
# `npm outdated -g` — and only after the user says yes. So the prohibition moves
# from "runs a package manager" to "runs one that could change this machine": the
# mutating verbs stay banned in command position, and the two queries are named
# as the entire allowed set so a third shell-out cannot arrive unnoticed.
TREAT_COMMANDS="$(grep -nE '^[[:space:]]*(brew|npm|uv|claude|git|pnpm|npx)[[:space:]]' "$DOCTOR_SH" 2>/dev/null \
  | grep -vE '(brew|npm)[[:space:]]+outdated' || true)"
expect_eq "doctor.sh runs no package manager or CLI in command position, beyond the two update queries" \
  "" "$TREAT_COMMANDS"
MUTATING_VERBS="$(grep -nE '(brew|npm|uv|claude|pnpm|npx)[[:space:]]+(install|upgrade|update|uninstall|remove|add|enable|disable)' "$DOCTOR_SH" \
  | grep -vE '^[0-9]+:[[:space:]]*(#|echo|printf)' || true)"
expect_eq "doctor.sh never runs a mutating package-manager verb (the commands it prints are text)" \
  "" "$MUTATING_VERBS"
TREAT_FUNCTIONS="$(grep -vE '^[[:space:]]*#' "$DOCTOR_SH" \
  | grep -nE '(bionic_strip_permission_block|install_dep|remove_dep|_dep_install|_dep_consent)' || true)"
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
          detect_half_uninstalled; do
  expect_true "doctor.sh calls ${fn} from the libraries" grep -q "${fn}" "$DOCTOR_SH"
done
# A `.` in command position naming the file — the source itself, not a mention
# of the path in prose.
expect_true "doctor.sh sources detect.sh rather than reimplementing it" \
  grep -qE '^[[:space:]]*\.[[:space:]].*detect\.sh' "$DOCTOR_SH"

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
PAYLOAD_CKSUM_BEFORE="$(shasum -a 256 "$DOCTOR_SH" 2>/dev/null)"

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
# The last `. <something>/detect.sh` line: the override must land AFTER the
# library defines the function it replaces, or the source would simply undo it.
anchors = [i for i, l in enumerate(lines) if 'detect.sh' in l and l.lstrip().startswith('. ')]
if not anchors:
    raise SystemExit("mutation 2: no source-of-detect.sh line to anchor the override on")
lines.insert(anchors[-1] + 1,
             'detect_dep() { echo "dep:$1 lane=3b present=yes version=9.9.9 constraint=any verdict=ok"; }\n')
open(dest, 'w').writelines(lines)
PY
MUT2_OUT="$TMP/mut2.out"
doctor_run "$MUT2" "$BROKEN_BIN" "$BROKEN"  > "$MUT2_OUT" 2>&1
MUT2_TEXT="$(cat "$MUT2_OUT")"
expect_not_contains "MUTATION 2 (verdicts forced to ok): the violation line disappears as expected" \
  "violates constraint ^6.3.0" "$MUT2_TEXT"
expect_not_match "MUTATION 2: the superpowers row no longer renders violation" \
  "*violation*" "$(line_of "$MUT2_OUT" "superpowers")"

# ── Mutation 3: break an action line ─────────────────────────────────────────
# The half-uninstalled fix is deleted. The broken machine still detects the
# state; what is lost is the one thing the user could act on.
MUT3="$(doctor_copy action)"
# A LINE FILTER IS NOT ENOUGH ANY MORE, and the difference is what this mutation
# exists to avoid. The one-liner is emitted from a two-line statement now —
# `[ "$HALF_STATE" = "yes" ] && \` and the `echo` under it — so a plain
# `grep -v 'curl -fsSL'` leaves a dangling line continuation, and the doctored
# copy dies with a syntax error before printing anything. A mutation that
# produces NO report cannot show that the state assertion survives while the
# action assertion falls: both would fail, and for the same uninteresting reason.
# So the emitting lines go and the statements around them stay well-formed.
python3 - "$DOCTOR_SH" "$MUT3" <<'PY'
import sys, re
src, dest = sys.argv[1], sys.argv[2]
out = []
for line in open(src):
    if 'curl -fsSL' in line:
        # Drop the emitting line; if it was the tail of a `… && \` statement,
        # the head above it becomes a no-op rather than a dangling continuation.
        if out and out[-1].rstrip().endswith('&& \\'):
            indent = re.match(r'[ \t]*', out[-1]).group(0)
            out[-1] = indent + ':\n'
        continue
    out.append(line)
open(dest, 'w').writelines(out)
PY
expect_true "MUTATION 3: the doctored copy is still a valid script" bash -n "$MUT3"
MUT3_OUT="$TMP/mut3.out"
doctor_run "$MUT3" "$BROKEN_BIN" "$BROKEN"  > "$MUT3_OUT" 2>&1
MUT3_TEXT="$(cat "$MUT3_OUT")"
expect_not_contains "MUTATION 3 (curl fallback deleted): the half-uninstalled action line is gone" \
  "curl -fsSL" "$MUT3_TEXT"
expect_match "MUTATION 3: the half-uninstalled STATE is still detected (only the fix was lost)" \
  "*half-uninstalled*" "$(line_of "$MUT3_OUT" " install ")"

# ── Restore proof ────────────────────────────────────────────────────────────
expect_eq "the shipped doctor.sh is byte-identical after all three mutations" \
  "$PAYLOAD_CKSUM_BEFORE" "$(shasum -a 256 "$DOCTOR_SH" 2>/dev/null)"

R_OUT="$TMP/restored.out"
doctor_run "$DOCTOR_SH" "$BROKEN_BIN" "$BROKEN"  > "$R_OUT" 2>&1
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
echo "=== Group 12: the installed agent role files — the legacy drift read (AC-13) ==="
# ---------------------------------------------------------------------------
#
# THE LINE IS GONE; THE READ IS NOT. doctor still asks the library the question —
# `INST_AGENT_FACT="$(detect_installed_agent_copies)"` at doctor.sh:497, with the
# state, total, drift count, names and cause all parsed out of it — and then
# prints none of them: the verbose arm that carried "installed agent role files"
# was deleted by owner order on 2026-08-22, and nothing in the four certified
# tables took the line over. `/usr/bin/grep -c "installed agent role files"` over
# doctor.sh and over every fixture capture returns 0.
#
# So the seven arms that read that line are removed rather than rewired: there is
# no surface to point them at, and R2 keeps this wave from adding one. What
# survives is the half that is still measurable and still worth measuring — a
# comparison of two trees is exactly the kind of read that grows a temp file, and
# doctor performs it on every run whether or not it prints the answer.

# The machine that makes the read do work: six installed copies beside the
# payload, two of them drifted. Built on its own so the healthy and broken
# fixtures every other group reads keep their exact shape.
LEGACY="$TMP/machine-legacy"; plant_machine "$LEGACY" healthy
mkdir -p "$LEGACY/claude-home/agents"
for a in auditor critic implementor researcher senior-implementor test-runner; do
  cp "$LEGACY/plugin/agents/${a}.md" "$LEGACY/claude-home/agents/${a}.md"
done
printf '\nA line only the installed copy carries.\n' >> "$LEGACY/claude-home/agents/critic.md"
printf '\nAnd another.\n' >> "$LEGACY/claude-home/agents/auditor.md"

D_OUT="$TMP/legacy-drift.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEGACY"  > "$D_OUT" 2>&1

# THE NO-MUTATION CONTRACT HOLDS OVER THE READ. Fingerprint the whole legacy
# machine across a run.
L_FP_BEFORE="$(fingerprint "$LEGACY")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEGACY" >/dev/null 2>&1
expect_eq "the drift read changes nothing on the machine it reads" \
  "$L_FP_BEFORE" "$(fingerprint "$LEGACY")"

# AND IT RAISES NO ACTION. Reporting a legacy directory is not the same as
# telling the user to delete it — /bionic:setup owns that offer, under consent.
# A machine that is otherwise fine still says so.
expect_contains "the drift line adds no action line — the summary still says nothing to do" \
  "Nothing to do" "$(cat "$D_OUT")"

# The fact is detect.sh's, rendered here — doctor re-deriving it from the
# filesystem is the defect Group 8 exists to prevent, and this line is a new
# chance to commit it.
expect_true "doctor renders the library fact rather than listing the directory itself" \
  grep -q 'detect_installed_agent_copies' "$DOCTOR_SH"
expect_true "the fact function lives in detect.sh" \
  grep -q '^detect_installed_agent_copies()' "${REPO}/payload/scripts/lib/detect.sh"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 14: the two surfaces Step 9's referee needs — legacy skill copy, legacy hook files (W5 RV-5) ==="
# ---------------------------------------------------------------------------
#
# THE FINDING. detect.sh already knew about the legacy skill copy — the fact function was
# written in 4/6 and setup step 7 offers to remove it under consent — but doctor never
# RENDERED it. So `/bionic:doctor` could report a clean machine that was arming eleven hook
# registrations twice, through a channel the cutover was supposed to have retired. And
# nothing at all knew about the leftover hook FILES. Those are the two surfaces the wave's
# close-out has to referee, and the referee could not see either.
#
# THE TWO LINES ARE NOT THE SAME KIND OF LINE, and the split is deliberate:
#
#   skill copy   NOT INERT. It carries hook registrations in its own frontmatter, so a
#                session that loads it arms the same walls a second time. There is a remedy
#                under consent, so this one EARNS an ENVIRONMENT row and a verdict line.
#   hook files   INERT once the registrations are gone. Disk, not behaviour. It earned a
#                row that said so — and that row went with the verbose arm on 2026-08-22.
#
# ONLY ONE OF THE TWO STILL PRINTS. `legacy installed skill copy` is an ENVIRONMENT row
# today (`✗ legacy installed skill copy   arms the same walls twice → /bionic:setup`), so
# its arms are re-pointed at `line_of`. `legacy installed hook files` occurs zero times in
# doctor.sh and in every fixture capture: doctor still ASKS the library
# (`detect_legacy_hook_files`, pinned below) and prints nothing back, so the count arms,
# the user's-own-hook discriminator and the inert wording have no surface and are removed.
# The ASYMMETRY those arms existed to prove survives whole, because it is provable from the
# other side: a machine whose only leftover is hook files still reports nothing to do.
#
# The collapsed `legacy footprint … checks clean` line is gone with them.

# ---- both absent: the cold, correct, post-cutover machine ----
expect_eq "absent: the skill-copy check leaves no row of its own" \
  "" "$(line_of "$H_OUT" "legacy installed skill copy")"

# A machine carrying BOTH leftovers. Built on its own so the fixtures every other group
# reads keep their exact shape.
LEG2="$TMP/machine-leftovers"; plant_machine "$LEG2" healthy
mkdir -p "$LEG2/claude-home/skills/canonical-sdlc" "$LEG2/claude-home/hooks"
printf -- '---\nname: canonical-sdlc\nhooks:\n  PreToolUse: []\n---\nThe copy the installer rendered.\n' \
  > "$LEG2/claude-home/skills/canonical-sdlc/SKILL.md"
# Two of the payload's own hook names, plus one that is the user's and must NOT be counted.
printf '#!/bin/bash\nexit 0\n' > "$LEG2/claude-home/hooks/protect-main.sh"
printf '#!/bin/bash\nexit 0\n' > "$LEG2/plugin/hooks/landing-gate.sh"
printf '#!/bin/bash\nexit 0\n' > "$LEG2/claude-home/hooks/landing-gate.sh"
printf '#!/bin/bash\nexit 0\n' > "$LEG2/claude-home/hooks/my-own-hook.sh"

G14_OUT="$TMP/leftovers.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEG2"  > "$G14_OUT" 2>&1

G14_SKILL="$(line_of "$G14_OUT" "legacy installed skill copy")"
# THE PATH IS NO LONGER ON THE ROW. What the row carries instead is what the copy
# DOES — "arms the same walls twice" — and its command; the directory it names is
# fixed by the CLI, so the sentence is the half a reader could not reconstruct.
# The arm that required the path is removed rather than re-globbed at a substring
# of the sentence, which would be a different claim wearing the old label.
expect_not_match "present: and does not report it as absent" "*none*" "$G14_SKILL"

# ---- the action asymmetry, stated as its own pair of arms ----
expect_contains "present: the skill copy EARNS a setup action line (it is not inert)" \
  "/bionic:setup" "$(cat "$G14_OUT")"
expect_contains "…and the reason names the skill copy specifically" \
  "legacy skill copy" "$(verdict_block "$G14_OUT")"
# The hook files must not have added one. A machine whose ONLY leftover is hook files is
# the discriminating fixture: if that one grows an action line, the contract is broken.
LEG3="$TMP/machine-hookfiles-only"; plant_machine "$LEG3" healthy
mkdir -p "$LEG3/claude-home/hooks"
printf '#!/bin/bash\nexit 0\n' > "$LEG3/claude-home/hooks/protect-main.sh"
G14B_OUT="$TMP/hookfiles-only.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEG3"  > "$G14B_OUT" 2>&1
expect_contains "hook files alone: and the summary still says there is nothing to do" \
  "Nothing to do" "$(cat "$G14B_OUT")"

# ---- read-only over both new reads ----
LEG2_FP="$(fingerprint "$LEG2")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEG2" >/dev/null 2>&1
expect_eq "neither new read changes anything on the machine it reads" "$LEG2_FP" "$(fingerprint "$LEG2")"

# ---- the facts are the library's, not re-derived here ----
expect_true "doctor renders detect.sh's legacy-skill-copy fact rather than stat'ing the directory" \
  grep -q 'detect_legacy_skill_copy' "$DOCTOR_SH"
expect_true "doctor renders detect.sh's legacy-hook-files fact" \
  grep -q 'detect_legacy_hook_files' "$DOCTOR_SH"
expect_true "and the new fact function lives in detect.sh" \
  grep -q '^detect_legacy_hook_files()' "${REPO}/payload/scripts/lib/detect.sh"

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
echo "=== Group 15: the registry-sha divergence line (W5 critic C-6) ==="
# ---------------------------------------------------------------------------
#
# THE FACT IS detect.sh's (tests/plugin-lib.test.sh Group W owns its four states). What is
# proven HERE is that doctor RENDERS it: in PLUGIN INTEGRITY, one line, naming the state,
# both shas when it has them, and — on the one state a user can act on — the action, inline
# and not in the SUMMARY. That last part is the agent-files precedent applied deliberately:
# an install behind the tip is what every developer machine looks like between two commits,
# and a SUMMARY action line would nag on all of them.
#
# REAL GIT, REAL REPO. The two records this line compares are a registry file and a git
# tip; a stubbed git would substitute the value under test. The bin dir and the repo are
# both built by this suite, so nothing here leaves the fixture tree.
G15_BIN="$TMP/bin-git"; mkdir -p "$G15_BIN"; cp -R "$FULL_BIN"/. "$G15_BIN"/ 2>/dev/null
rm -f "$G15_BIN/git"
_g="$(command -v git 2>/dev/null)" && ln -sf "$_g" "$G15_BIN/git"

G15_REPO="$TMP/g15-repo"; mkdir -p "$G15_REPO"
( cd "$G15_REPO" && git init -q . && git config user.email t@t && git config user.name t \
  && echo one > f && git add f && git commit -qm one \
  && echo two > f && git commit -qam two ) >/dev/null 2>&1
G15_TIP=$( cd "$G15_REPO" && git rev-parse HEAD )
G15_PREV=$( cd "$G15_REPO" && git rev-parse HEAD~1 )

# The healthy fixture's registry, re-pointed at a commit of the fixture repo. `jq` is in the
# base bin dir, so this is the real file the real parse reads.
g15_set_sha() {  # <sha>
  jq --arg s "$1" '.plugins["bionic@bionic"][0].gitCommitSha = $s' \
    "$HEALTHY/claude-home/plugins/installed_plugins.json" > "$TMP/g15-reg.json" \
    && cp "$TMP/g15-reg.json" "$HEALTHY/claude-home/plugins/installed_plugins.json"
}

g15_run() {  # -> stdout, run FROM the fixture repo
  ( cd "$G15_REPO" && doctor_run "$DOCTOR_SH" "$G15_BIN" "$HEALTHY" )
}

# epic-17 W7 S2b (AC-3). Which re-converge command is TRUE differs by feed, so the lag
# arm below drives both: a git-source marketplace (the cache the registry names is what
# the CLI loads, so `update` really refreshes it) and a directory-source one (a local
# checkout registered as a feed — every dogfood install, and this fixture repo stands in
# for it — where the CLI never opens that cache, so `update` at an unchanged
# plugin.json version is a no-op). `known_marketplaces.json` is the file the CLI itself
# writes on `marketplace add`; this fixture is the real file the real parse
# (`detect_marketplace_feed_kind`) reads, not a stubbed answer.
g15_set_feed_kind() {  # <directory|git>
  case "$1" in
    directory)
      jq -n '{"bionic":{"source":{"source":"directory","path":"/tmp/g15-fixture-bionic"},"installLocation":"/tmp/g15-fixture-bionic"}}' ;;
    *)
      jq -n '{"bionic":{"source":{"source":"github","repo":"chrisalehman/bionic"},"installLocation":"/tmp/g15-fixture-cache"}}' ;;
  esac > "$HEALTHY/claude-home/plugins/known_marketplaces.json"
}

# THE INSTALLED-COMMIT LINE IS GONE (2026-08-22, owner order — the verbose arm it
# lived in was deleted whole). `/usr/bin/grep -c "installed commit"` over doctor.sh
# returns 0, and so does a grep over every fixture capture in this file: the four
# states this group drove — at the tip, behind it on a git-source feed, nominal on
# a directory-source one, and a sha this repository has never seen — have no
# rendering left to assert against. All sixteen state arms are removed rather than
# rewired; nothing in the four certified tables compares a registry sha to a git
# tip.
#
# WHAT SURVIVED IS THE SHA ITSELF, in the provenance header — `Bionic Doctor —
# payload <version> @ <sha>` — which reads the same registry field through the same
# `detect_plugin_install_path` seam. So the two arms that asserted the SHA is named
# are re-pointed at the header, and the fixture repo below is what still makes them
# discriminate: the header follows the registry value across three different shas
# rather than printing a constant.

g15_set_sha "$G15_TIP"
G15_MATCH_OUT="$TMP/g15-match.out"; g15_run > "$G15_MATCH_OUT" 2>&1
expect_match "…naming the sha the two agreed on" \
  "Bionic Doctor*@ ${G15_TIP:0:8}*" "$(head -1 "$G15_MATCH_OUT")"
# The LABEL is product language, not registry vocabulary (epic-17 W6 S9a; walk finding W-3:
# "registry sha" reads as git internals to a user who never asked about a registry).
expect_not_contains "…and never under the old registry-internals label" \
  "registry sha" "$G15_MATCH_OUT"

g15_set_feed_kind git
g15_set_sha "$G15_PREV"
G15_LAG_OUT="$TMP/g15-lag.out"; g15_run > "$G15_LAG_OUT" 2>&1
expect_match "…naming the installed sha" \
  "Bionic Doctor*@ ${G15_PREV:0:8}*" "$(head -1 "$G15_LAG_OUT")"
expect_eq "doctor still exits 0 with a lagging install (a diagnosis is not a failure)" "0" \
  "$( g15_run > /dev/null 2>&1; echo $? )"

# The same lagging sha on a DIRECTORY-SOURCE marketplace — a local checkout registered as
# a feed, which is what a dogfood install is. The feed kind no longer changes any rendering
# doctor prints, so what is left to assert is that reading it changes nothing else either.
g15_set_feed_kind directory
G15_DIRLAG_OUT="$TMP/g15-dirlag.out"; g15_run > "$G15_DIRLAG_OUT" 2>&1
expect_eq "doctor still exits 0 on a directory-source lag too" "0" \
  "$( g15_run > /dev/null 2>&1; echo $? )"

# A commit this checkout has never seen: the header still reports what the registry says,
# without inventing a state for it.
g15_set_sha "0123456789abcdef0123456789abcdef01234567"
G15_FOREIGN_OUT="$TMP/g15-foreign.out"; g15_run > "$G15_FOREIGN_OUT" 2>&1


# The minor from the same report: an assignment nothing reads is a fact the reader assumes
# is used. Pinned as an absence so it cannot come back with the next edit to that block.
expect_eq "doctor.sh carries no unread HOOK_FILES_NAMES assignment" "" \
  "$(grep -n 'HOOK_FILES_NAMES' "$DOCTOR_SH" || true)"

# NO DESIGN-DOC CITATION ON THE DISPLAY (epic-17 W6 S9a; walk finding W-3). ROSTER FOOTPRINT
# explained its counting method and then cited the design ledger by letter-number for it —
# a pointer into a document the user does not have, dropped into a read-only report. The
# explanation stays and the citation goes; the source comment above the code keeps it, which
# is where a reader who needs the provenance actually is. tests/script-vocabulary.test.sh
# guards the class from the source side; this measures the rendered output.
expect_not_contains "doctor's output cites no design document" "design-ledger" "$(cat "$H_OUT")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 16: an absent when-needed tool is not a degradation (wave-06 S6) ==="
# ---------------------------------------------------------------------------
#
# THE DEFECT S3 HANDED OVER (A-4.S3.7). Doctor treated EVERY absent row as a
# degradation with a matching SUMMARY action. That is right for a core plugin and
# wrong for a `when-needed` tool, whose absence is its NORMAL state: D-B's whole
# point is that these install at the moment a route needs them, so a fresh
# machine legitimately has none of them and doctor telling that user to run
# setup is telling them to fix something that is not broken.
#
# THE DISCRIMINATING PAIR. Same fixture, one row removed: the machine below has
# an absent when-needed plugin and must read clean, while the broken machine
# above has an absent CORE plugin and must still name it. A rule that silenced
# both would pass an "is not degradation" check on its own.

WN="$TMP/machine-when-needed-absent"; plant_machine "$WN" healthy
rm -rf "$WN/installs/impeccable"
jq 'del(.plugins["impeccable@bionic"])' "$WN/claude-home/plugins/installed_plugins.json" \
  > "$TMP/wn-reg.json" && cp "$TMP/wn-reg.json" "$WN/claude-home/plugins/installed_plugins.json"

WN_OUT="$TMP/when-needed-absent.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$WN"  > "$WN_OUT" 2>&1
WN_RC=$?
WN_TEXT="$(cat "$WN_OUT")"

expect_eq "when-needed absent: doctor still exits 0" "0" "$WN_RC"
# THE `when-needed` CLASS IS EMPTY as of 41110bd (Chris 2026-08-22, promoting
# impeccable and excalidraw-renderer to `extra`). doctor's when-needed branch —
# the `–` symbol and the "installs on first use" tail — is unreachable, and an
# absent impeccable is now an ordinary setup-repairable absence. So this machine
# no longer proves "an absence that is not a degradation": it proves the opposite
# case, and the two arms that asserted the old class's rendering
# ("…the row says on its face what installs it", "…the summary still says there
# is nothing to do") are removed rather than inverted, because inverting them
# would put a new claim under an old label. The honest-absence arm below survives,
# re-cut to the columns THIRD PARTY prints.
expect_match "when-needed absent: the dependency row reports it absent, honestly" \
  "*impeccable*not installed*/bionic:setup*" "$(line_of "$WN_OUT" " impeccable ")"
# The contrast arm: an absent row is a problem with an action, and the absences
# collapse onto ONE verdict line that counts them and ends in the command —
# eleven rows on a cold machine would otherwise be eleven copies of it.
expect_contains "core absent: still named in FIX" "agent-skills" "$B"
expect_match "core absent: …on a line that counts them and ends in the command" \
  "*problems.*Run /bionic:setup to fix:*" "$(verdict_block "$B_OUT" | head -1)"
expect_contains "core absent: and still carries a setup action" \
  "Run /bionic:setup to fix:" "$(verdict_block "$WN_OUT")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 17: the load state, from the CLI's own listing (AC-13) ==="
# ---------------------------------------------------------------------------
#
# WHY IT MATTERS. W5's F12 measured a plugin whose dependency was missing: the CLI
# refused to load it and every command silently did nothing. Doctor could not see
# that, because a payload tree on disk reads healthy whether or not the CLI ever
# loaded it — so every row describing that payload describes a machine that may
# not be running any of it.
#
# THE SECTION IS GONE; THE FACT AND ITS FOUR STATES ARE NOT. `=== LOAD STATE ===`
# was deleted with the verbose arm, and what replaced it is BIONIC NATIVE's
# `plugin` row — printed only when the state is something other than `loaded`,
# which is exactly the AC-15 rule that collapsed every other clean check — plus a
# verdict line on the two states a user can act on. So each arm below reads
# `line_of` for the row and `verdict_block` for the action, and the claims are
# untouched.
#
# The two ORDERING arms are removed with the ordered roster they measured: there
# are no `=== … ===` sections left to be first, and Group 2 already pins the
# ordered list of the four tables that replaced them.
#
# healthy: `loaded` prints NO row at all, which is the positive arm now — a clean
# load state says nothing, and the three broken states below are what print.
expect_eq "healthy: LOAD STATE reports the plugin loaded" \
  "" "$(line_of "$H_OUT" " plugin ")"

# ── failed: the dep-broken listing, the state F12 measured ──
DB_OUT="$TMP/loadstate-failed.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" "BIONIC_PLUGIN_LIST_CMD=cat ${LISTING_DEPBROKEN}"  > "$DB_OUT" 2>&1
DB_RC=$?
DB_TEXT="$(cat "$DB_OUT")"
expect_eq "dep-broken: doctor still exits 0" "0" "$DB_RC"
# The state's DISPLAY words are "the CLI refused to load it", on BIONIC NATIVE's
# `plugin` row; `failed` is the fact function's value and never reached the page.
DB_LOAD="$(line_of "$DB_OUT" " plugin ")"
expect_contains "dep-broken: the state is reported as failed, not loaded" "refused to load it" "$DB_LOAD"
expect_not_contains "dep-broken: and never as loaded" "loaded —" "$DB_LOAD"
# VERBATIM. The CLI's Error line is the one sentence that says WHICH dependency,
# and paraphrasing it is how a user ends up reinstalling the wrong thing.
expect_contains "dep-broken: the CLI's own Error line is rendered verbatim" \
  'Dependency "superpowers@bionic" is not installed' "$DB_LOAD"
expect_contains "dep-broken: and the fix rides in the same section" \
  "claude plugin install" "$DB_LOAD"
expect_contains "dep-broken: a plugin that did not load earns a SUMMARY action" \
  "→ " "$(verdict_block "$DB_OUT")"

# ── absent: a real listing that does not name bionic ──
ABSENT_LISTING="$TMP/plugin-list-absent.txt"
awk '/❯ bionic@bionic/{skip=1} /❯ superpowers@bionic/{skip=0} !skip' "$LISTING_HEALTHY" > "$ABSENT_LISTING"
AB_OUT="$TMP/loadstate-absent.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" "BIONIC_PLUGIN_LIST_CMD=cat ${ABSENT_LISTING}"  > "$AB_OUT" 2>&1
AB_LOAD="$(line_of "$AB_OUT" " plugin ")"
# The DISPLAY word is "not installed": `absent` is the fact function's value and
# a person reading a report about their own machine should meet the product word.
expect_contains "absent: the listing is real and does not name bionic — reported not installed" \
  "not installed" "$AB_LOAD"
expect_not_contains "absent: and certainly not as loaded" "loaded" "$AB_LOAD"
expect_contains "absent: with the install command as its fix, in FIX" \
  "claude plugin install bionic@bionic" \
  "$(verdict_block "$AB_OUT")"

# ── unknown: output that is not a listing at all ──
GARBAGE="$TMP/not-a-listing.txt"; printf 'command not found\n' > "$GARBAGE"
UK_OUT="$TMP/loadstate-unknown.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" "BIONIC_PLUGIN_LIST_CMD=cat ${GARBAGE}"  > "$UK_OUT" 2>&1
UK_LOAD="$(line_of "$UK_OUT" " plugin ")"
expect_contains "unreadable listing: the state is unknown" "unknown" "$UK_LOAD"
expect_contains "unreadable listing: and the unknown names its cause (A-4.S2.4)" \
  "not a plugin listing" "$UK_LOAD"
# An unknown is not an action: nobody can fix "I could not tell".
expect_contains "unreadable listing: the summary still says there is nothing to do" \
  "Nothing to do" "$(cat "$UK_OUT")"

# ── the bound: a listing command that never answers ──
#
# THE GAP S2 FLAGGED AND THIS SLICE OWNS. `claude plugin list` is the one fact
# function that shells out, and a CLI that hangs would hang the diagnosis — the
# command a user runs precisely when their machine is misbehaving.
HANGDIR="$TMP/bin-hang"; mkdir -p "$HANGDIR"
# `exec` so the stub IS the sleeping process: a wrapper that forked would leave
# the child holding the pipe after doctor killed its parent, and the bound would
# read as working while the run still waited for the grandchild.
printf '#!/bin/bash\nexec sleep 60\n' > "$HANGDIR/hanging-listing"; chmod +x "$HANGDIR/hanging-listing"

HANG_START=$SECONDS
HG_OUT="$TMP/loadstate-hang.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" \
  "BIONIC_PLUGIN_LIST_CMD=$HANGDIR/hanging-listing" "BIONIC_DOCTOR_PROBE_SECONDS=2"  > "$HG_OUT" 2>&1
HG_RC=$?
HANG_ELAPSED=$((SECONDS - HANG_START))
expect_eq "a hanging listing: doctor completes anyway, exit 0" "0" "$HG_RC"
expect_true "a hanging listing: doctor gave up near the bound rather than waiting" \
  test "$HANG_ELAPSED" -lt 10
HG_LOAD="$(line_of "$HG_OUT" " plugin ")"
expect_contains "a hanging listing: the state is unknown" "unknown" "$HG_LOAD"
expect_contains "a hanging listing: and the cause says it ran out of time" \
  "did not answer" "$HG_LOAD"

# THE SEAM-LESS ARM (memory: seam-blindness-class). Every timing arm above sets
# the cadence knob, so all of them would pass against a doctor that only honoured
# the knob and never bounded anything by default. This one sets nothing: the
# shipped 15-second default is what stops the run.
SEAMLESS_START=$SECONDS
SL_OUT="$TMP/loadstate-hang-default.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" \
  "BIONIC_PLUGIN_LIST_CMD=$HANGDIR/hanging-listing"  > "$SL_OUT" 2>&1
SL_RC=$?
SEAMLESS_ELAPSED=$((SECONDS - SEAMLESS_START))
expect_eq "the default bound (no knob set): doctor completes anyway, exit 0" "0" "$SL_RC"
expect_true "the default bound: it waited about fifteen seconds, not forever" \
  test "$SEAMLESS_ELAPSED" -ge 14 -a "$SEAMLESS_ELAPSED" -lt 40
expect_contains "the default bound: and reported unknown with its cause" \
  "did not answer" "$(line_of "$SL_OUT" " plugin ")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 18: DUPLICATES — two catalogs, one name (AC-9) ==="
# ---------------------------------------------------------------------------
#
# Silent duplication is the defect: nothing stops a machine holding
# `superpowers@bionic` and `superpowers@claude-plugins-official` at once, and
# which copy a session loads is then a coin flip nobody saw tossed.
#
# THE SECTION IS GONE (2026-08-22, owner order). `=== DUPLICATES ===` went with
# the verbose arm and nothing in the four certified tables replaced it: a grep
# for `duplicate` over every fixture capture in this file returns nothing outside
# the Patrol section, which is a different subject. The six arms that read the
# section — the colliding name, both catalog ids, the consolidation command, and
# the no-jq unknown with its cause — have no rendering to assert against, so they
# are removed rather than rewired.
#
# WHAT STAYS is the fixture and the two claims that survive it: a machine holding
# two copies of one plugin is still diagnosed successfully, and the read that
# finds them changes nothing. Building the machine is what keeps the registry
# path exercised; the arms below are what can still be said about it.

DUP="$TMP/machine-duplicate"; plant_machine "$DUP" healthy
plant_installed_tree "$DUP/installs/superpowers-official" 14 0
jq --arg p "$DUP/installs/superpowers-official" \
   '.plugins["superpowers@claude-plugins-official"] = [ { "scope": "user", "installPath": $p, "version": "6.2.0" } ]' \
   "$DUP/claude-home/plugins/installed_plugins.json" > "$TMP/dup-reg.json" \
  && cp "$TMP/dup-reg.json" "$DUP/claude-home/plugins/installed_plugins.json"

DUP_OUT="$TMP/duplicate.out"
DUP_FP_BEFORE="$(fingerprint "$DUP")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$DUP"  > "$DUP_OUT" 2>&1
DUP_RC=$?
expect_eq "planted duplicate: doctor still exits 0" "0" "$DUP_RC"
expect_eq "planted duplicate: the registry read changes nothing" \
  "$DUP_FP_BEFORE" "$(fingerprint "$DUP")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 19: the closing question and UPDATES (AC-14) ==="
# ---------------------------------------------------------------------------
#
# D-D, Chris's own option: doctor prints its whole instant report, THEN asks one
# question. The rejected alternatives are what the shape has to keep out — an
# always-on check is a forced wait, an on-argument check is forgettable, and a
# cached one would make the read-only diagnosis write a file.
#
# THE QUESTION WAS DELETED ON 2026-08-22 (doctor.sh:1485, Chris: "There's not
# much value of that"). Doctor prints its report and stops; `--updates` is the
# only route to the check, and Group 20 owns it. So the arms that required the
# question to be printed — unattended, on a yes, on a no — are removed, and what
# is left of this group is the half that outlived it: nothing is appended unless
# the flag is passed, no package manager is asked without it, no narration is
# offered about a check that did not run, and the check's own rendering, which
# every arm below now reaches through the live route.
#
# UNATTENDED IS SILENT. Not "declined", not "skipped because there is no
# terminal" — silent. A report nobody is reading should not carry a question
# nobody can answer, nor an explanation of why it was not asked.

expect_not_contains "unattended: but nothing is appended" "=== UPDATES ===" "$H"
# NO NARRATION EITHER WAY. The line is the question and nothing else — not "declined",
# not "skipped", not an explanation of what could not be reached. A reader who wants the
# check answers it; a log that nobody reads carries one unanswered line.
for _narration in "no terminal" "declined" "skipped" "not asked" "unattended"; do
  expect_not_contains "unattended: nothing is said about why (${_narration})" "$_narration" "$H"
done
# And nothing was asked of the package managers either — the check is what costs
# thirty seconds, so a silent No must not have paid for it.
: > "$CALLS"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" >/dev/null 2>&1
expect_eq "unattended: neither Homebrew nor npm was asked about updates" "" \
  "$(grep -E '^(brew|npm) outdated' "$CALLS" || true)"

# ── the yes path — which is the flag path now ──
#
# THE ANSWER ARRIVES AS `--updates`, not on stdin. These arms were written when a
# piped `y` was how the check was reached; with the question gone the pipe answers
# nothing and every one of them passed vacuously against a report that had never
# run a probe. Routing them through the live flag is what makes them measure the
# thing they name again.
: > "$CALLS"
Y_OUT="$TMP/updates-yes.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" -- --updates > "$Y_OUT" 2>&1
Y_RC=$?
Y="$(cat "$Y_OUT")"
expect_eq "yes: doctor still exits 0" "0" "$Y_RC"
expect_contains "yes: UPDATES renders" "=== UPDATES ===" "$Y"
expect_eq "yes: UPDATES is the LAST section, after the whole report (D-D supersedes D-A)" \
  "UPDATES" "$(section_roster "$Y_OUT")"

Y_UPDATES="$(awk '/=== UPDATES ===/{f=1; next} f' "$Y_OUT")"
# The row shape: what it is now, what is available, and the exact command. A
# report that says "outdated" without the command has made the user go looking.
expect_match "yes: the outdated brew-managed row carries both versions" \
  "*rg*15.2.0*15.3.0*" "$Y_UPDATES"
expect_contains "yes: …and the exact upgrade command, naming the formula not the row" \
  "brew upgrade ripgrep" "$Y_UPDATES"
expect_match "yes: the outdated npm-global row carries both versions" \
  "*@playwright/cli*0.1.18*0.2.0*" "$Y_UPDATES"
expect_contains "yes: …and its exact upgrade command" \
  "npm install -g @playwright/cli@latest" "$Y_UPDATES"
# INTERSECTED WITH THE MANAGED ROWS. Both stubs report a package bionic does not
# manage; listing those would make doctor a report on the whole machine, and one
# of them (yq) is a tool this wave deliberately dropped.
expect_not_contains "yes: a formula bionic does not manage is not listed" "yq" "$Y_UPDATES"
expect_not_contains "yes: nor an npm global it does not manage" "typescript" "$Y_UPDATES"
# NEVER UPGRADES — the whole point of printing a command instead of running one.
expect_eq "yes: only the read-only `outdated` queries were run" "" \
  "$(grep -E '^(brew|npm) (install|upgrade|uninstall)' "$CALLS" || true)"
expect_true "yes: brew was asked exactly for outdated" grep -q '^brew outdated' "$CALLS"
expect_true "yes: npm was asked exactly for outdated" grep -q '^npm outdated' "$CALLS"

# ── the no path ──
N_OUT="$TMP/updates-no.out"
printf 'n\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY"  > "$N_OUT" 2>&1
N="$(cat "$N_OUT")"
# A piped answer reaches a report that asks nothing: it must not turn the check on.
expect_not_contains "no: and nothing was appended" "=== UPDATES ===" "$N"
# Default No: an empty answer is a No, which is what [y/N] promises.
E_OUT="$TMP/updates-empty.out"
printf '\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY"  > "$E_OUT" 2>&1
expect_not_contains "just enter: the default is No" "=== UPDATES ===" "$(cat "$E_OUT")"

# ── a manager that will not answer ──
#
# HONEST "NOT CHECKED". Homebrew hangs — offline, a slow mirror, an update of its
# own in flight — and the failure mode to avoid is a report that says nothing and
# lets the reader conclude everything is current.
SLOW_BIN="$TMP/bin-slowbrew"; mkdir -p "$SLOW_BIN"; cp -R "$FULL_BIN"/. "$SLOW_BIN"/
printf '#!/bin/bash\nexec sleep 60\n' > "$SLOW_BIN/brew"; chmod +x "$SLOW_BIN/brew"
SB_OUT="$TMP/updates-slowbrew.out"
doctor_run "$DOCTOR_SH" "$SLOW_BIN" "$HEALTHY" "BIONIC_DOCTOR_PROBE_SECONDS=2" -- --updates > "$SB_OUT" 2>&1
SB_RC=$?
SB_UPDATES="$(awk '/=== UPDATES ===/{f=1; next} f' "$SB_OUT")"
expect_eq "slow Homebrew: doctor still exits 0" "0" "$SB_RC"
expect_contains "slow Homebrew: the section says so rather than implying all-clear" \
  "not checked" "$SB_UPDATES"
expect_contains "slow Homebrew: and names which manager could not answer" \
  "Homebrew" "$SB_UPDATES"
# The other manager is INDEPENDENT: one timing out must not silence the other.
expect_contains "slow Homebrew: npm's answer still renders" "@playwright/cli" "$SB_UPDATES"

# ── a manager that FORKS: the bound has to release the CALLER, not just the child ──
#
# SIX-AXIS REVIEW C-1. The stub above `exec`s its sleep, so doctor's direct child
# IS the sleeping process and killing it ends the wait. The real managers are the
# other shape: `brew` is a shell script that runs Ruby, `npm` a shim that runs
# node. There the child forks a grandchild which inherits doctor's stdout, and a
# bound that kills only the child returns 124 on time while the caller's command
# substitution stays blocked on the still-open pipe until the grandchild exits —
# measured at 45 s against a 3 s bound before this arm existed. The honest "not
# checked" row was then true in VALUE and false in TIME, which is the half of
# AC-14 a user actually feels.
#
# THE MEASUREMENT IS THE ASSERTION. Nothing about the row's text discriminates
# this defect (the text was always right); only the clock does.
FORK_BIN="$TMP/bin-forkbrew"; mkdir -p "$FORK_BIN"; cp -R "$FULL_BIN"/. "$FORK_BIN"/
printf '#!/bin/bash\n/bin/sleep 45\n' > "$FORK_BIN/brew"; chmod +x "$FORK_BIN/brew"
FB_OUT="$TMP/updates-forkbrew.out"
FB_START="$(date +%s)"
doctor_run "$DOCTOR_SH" "$FORK_BIN" "$HEALTHY" "BIONIC_DOCTOR_PROBE_SECONDS=3" -- --updates > "$FB_OUT" 2>&1
FB_RC=$?
FB_ELAPSED=$(( $(date +%s) - FB_START ))
FB_UPDATES="$(awk '/=== UPDATES ===/{f=1; next} f' "$FB_OUT")"
expect_eq "forking Homebrew: doctor still exits 0" "0" "$FB_RC"
expect_true "forking Homebrew: the whole run returns near the bound, not near the grandchild's 45 s (elapsed=${FB_ELAPSED}s)" \
  test "$FB_ELAPSED" -le 10
expect_contains "forking Homebrew: and the row is still the honest one" "not checked" "$FB_UPDATES"
expect_contains "forking Homebrew: the other manager still answers" "@playwright/cli" "$FB_UPDATES"

# ── …and nothing is left running behind it ──
#
# The elapsed arm above passes on a bound that merely stops holding the pipe. This
# one is what pins the process-GROUP kill: the stub's grandchild would write the
# marker six seconds after doctor gave up on it, and a bound that signalled only
# the direct child would leave it alive to do exactly that.
LEAK_MARK="$TMP/forked-grandchild-survived"
LEAK_BIN="$TMP/bin-leakbrew"; mkdir -p "$LEAK_BIN"; cp -R "$FULL_BIN"/. "$LEAK_BIN"/
printf '#!/bin/bash\n/bin/sh -c "/bin/sleep 6; echo leaked > %s"\n' "$LEAK_MARK" > "$LEAK_BIN/brew"
chmod +x "$LEAK_BIN/brew"
doctor_run "$DOCTOR_SH" "$LEAK_BIN" "$HEALTHY" "BIONIC_DOCTOR_PROBE_SECONDS=2" -- --updates >/dev/null 2>&1
sleep 9
expect_true "forking Homebrew: the grandchild died with the group rather than outliving the run" \
  test ! -f "$LEAK_MARK"

# ── the wall still holds on the path that shells out ──
UP_WALL="$TMP/wall-updates"; rm -rf "$UP_WALL"; cp -R "$HEALTHY" "$UP_WALL"
UP_BEFORE="$(fingerprint "$UP_WALL")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$UP_WALL" -- --updates >/dev/null 2>&1
expect_eq "NO-MUTATION WALL (updates, answered yes): still byte-identical, no path added" \
  "$UP_BEFORE" "$(fingerprint "$UP_WALL")"

# ── and the source itself carries no upgrade ──
UPGRADE_CALLS="$(grep -nE '^[[:space:]]*(brew[[:space:]]+(install|upgrade)|npm[[:space:]]+(install|update))' "$DOCTOR_SH" || true)"
expect_eq "doctor.sh contains no upgrade invocation anywhere" "" "$UPGRADE_CALLS"
# ONE OWNER, AND IT IS NO LONGER THIS FILE (critic F-3). The bound moved into
# detect.sh at S11 so setup — which runs the same plugin listing through the same
# probe — is bounded by the same code rather than by a second copy of it. The
# shipped default is asserted where it now lives, and doctor is asserted to carry
# no bound of its own, which is what would make "one owner" a claim about the
# tree instead of about this line.
expect_true "the fifteen-second bound is the shipped default, not only the test's" \
  grep -q 'BIONIC_DOCTOR_PROBE_SECONDS:-15' "${REPO}/payload/scripts/lib/detect.sh"
expect_eq "doctor.sh implements no bound of its own" "" \
  "$(grep -n 'kill -TERM' "$DOCTOR_SH" || true)"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 20: --updates, the answer the model relays back (A-4.S6.F-RULING) ==="
# ---------------------------------------------------------------------------
#
# THE GAP THIS CLOSES. Doctor asks its question on stdout and reads the answer from
# stdin, which works for a person at a terminal and for a caller that pipes. It does not
# work for the path the product actually takes: the model runs the script from a tool
# whose stdin can carry nothing, sees the question, and has no way to answer it. Setup
# solved the same problem the same way — print the question, let the model relay it, act
# on the answer in a second run — and `--updates` IS that second run.
#
# NOT AN ASSUME-YES KNOB. The rule setup states in its own header ("an env var that
# switched consent off would be the hole in consent per event") guards MUTATIONS. This
# flag guards a read: two package managers asked what is outdated, with the upgrade
# command printed and never run. The user has already said yes by the time it is passed.

# ---- the flag runs the check without asking ----
: > "$CALLS"
F_OUT="$TMP/updates-flag.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" -- --updates > "$F_OUT" 2>&1
F_RC=$?
F="$(cat "$F_OUT")"
expect_eq "--updates: doctor still exits 0" "0" "$F_RC"
expect_contains "--updates: the UPDATES section renders" "=== UPDATES ===" "$F"
expect_not_contains "--updates: and the question is NOT asked again" "$UPDATES_QUESTION" "$F"
F_UPDATES="$(awk '/=== UPDATES ===/{f=1; next} f' "$F_OUT")"
expect_match "--updates: the outdated brew-managed row is there" "*rg*15.2.0*15.3.0*" "$F_UPDATES"
expect_contains "--updates: with its exact upgrade command" "brew upgrade ripgrep" "$F_UPDATES"
expect_match "--updates: and the npm-global row" "*@playwright/cli*0.1.18*0.2.0*" "$F_UPDATES"
expect_eq "--updates: UPDATES is still the last section, after SUMMARY" \
  "UPDATES" "$(section_roster "$F_OUT")"
expect_eq "--updates: still no mutating package-manager call" "" \
  "$(grep -E '^(brew|npm) (install|upgrade|uninstall)' "$CALLS" || true)"

# The whole point: it works where NOTHING can answer a question. This run's stdin is the
# suite's own closed stream — the shape the model's tool hands the script.
expect_contains "--updates: it worked with no answer channel at all" "brew upgrade ripgrep" "$F"

# It does not read stdin either — an answer piped at it is ignored, not consumed as a No.
P_OUT="$TMP/updates-flag-piped-no.out"
printf 'n\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" -- --updates > "$P_OUT" 2>&1
expect_contains "--updates: a piped answer cannot un-ask a question that was never asked" \
  "=== UPDATES ===" "$(cat "$P_OUT")"

# ---- read-only holds on the flag path too ----
FLAG_WALL="$TMP/wall-updates-flag"; rm -rf "$FLAG_WALL"; cp -R "$HEALTHY" "$FLAG_WALL"
FLAG_BEFORE="$(fingerprint "$FLAG_WALL")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$FLAG_WALL" -- --updates >/dev/null 2>&1
expect_eq "NO-MUTATION WALL (--updates): every fixture file byte-identical, no path added" \
  "$FLAG_BEFORE" "$(fingerprint "$FLAG_WALL")"

# ---- an option doctor does not know is a CALLER error, not a diagnosis ----
#
# The always-exit-0 rule covers diagnoses: a machine with eleven absent dependencies has
# been diagnosed successfully. A misspelled flag has diagnosed nothing, and answering it
# with a clean report and status 0 would tell a caller that asked for updates, and did not
# get them, that everything went fine.
BAD_OUT="$TMP/updates-badflag.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" -- --uptades > "$BAD_OUT" 2>&1
BAD_RC=$?
expect_ne "an unknown option does not exit 0" "0" "$BAD_RC"
expect_contains "an unknown option says which option exists" "--updates" "$(cat "$BAD_OUT")"
expect_not_contains "an unknown option prints no report" "=== LOAD STATE ===" "$(cat "$BAD_OUT")"

# ---- the command file no longer carries a relay instruction ----
#
# THE RELAY WENT WITH THE QUESTION. `doctor.md` used to tell the model to ask the
# question and come back with `--updates`; with nothing to relay the command file
# says "Run … / Show the report as printed. Ask nothing afterwards." and the
# template says the same — `/usr/bin/grep -c -- '--updates'` over
# agents-src/templates/commands/doctor.md.tmpl returns 0. So the three relay pins
# and the template pin under them are removed; the flag itself is still doctor's
# own contract and is proven above, from doctor's own script.
#
# The render check stays: it is about this file agreeing with its sources, which
# is true of every line in it whether or not any one line survived.
if [ -f "$DOCTOR_MD" ]; then
  expect_true "render.sh --check is green (the rendered file matches its sources)" \
    bash "${REPO}/agents-src/render.sh" --check
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 21: ENVIRONMENT — configured is not live (W7 S4, spec AC-7) ==="
# ---------------------------------------------------------------------------
#
# THE DEFECT, VERBATIM. On 2026-08-21 a session ran with
# CLAUDE_CODE_ENABLE_TODO_TOOLS written to disk and absent from the process — the
# host had launched its shell with rc files disabled — and doctor could not say
# so: it had one line, sourced from the shell rc, that answered neither question
# well. A name in the file but not in the process is a RESTART; a name in
# neither is a setup gap. Reporting them as one state sends a user to repair
# something already repaired, or calls a session ready that is not.
#
# The three arms below plant each state independently: the file through the
# fixture machine, the process through doctor_run's env assignments. An
# implementation that answered one from the other fails at least one of them.

ENV_M="$TMP/machine-env-liveness"; plant_machine "$ENV_M" healthy

# (a) configured AND live — the session that will behave the way the file says.
ENV_LIVE_OUT="$TMP/env-live.txt"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_M" \
  BASH_MAX_TIMEOUT_MS=1800000 CLAUDE_CODE_ENABLE_TODO_TOOLS=1  > "$ENV_LIVE_OUT" 2>&1
expect_match "configured and live: the value is reported" \
  "*1800000*" "$(line_of "$ENV_LIVE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…and the session is reported as having it" \
  "*live in session*" "$(line_of "$ENV_LIVE_OUT" "BASH_MAX_TIMEOUT_MS")"

# (b) configured and NOT live — the state a restart fixes. The report has to say
# restart, because "absent" would send the user to run setup again and setup
# would find nothing to do.
ENV_STALE_OUT="$TMP/env-stale.txt"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_M"  > "$ENV_STALE_OUT" 2>&1
expect_match "configured and not live: the value is still reported" \
  "*1800000*" "$(line_of "$ENV_STALE_OUT" "BASH_MAX_TIMEOUT_MS")"
# The state column's two words for this pair are `written, restart to pick it up`
# and, on the live arm above, `live in session` — the same two facts the old
# "live in this session: yes/no" prose carried, in the column that carries them.
expect_match "…and the session is reported as not having it" \
  "*written, restart*" "$(line_of "$ENV_STALE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…named as a restart, not as a setup gap" \
  "*restart*" "$(line_of "$ENV_STALE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_not_contains "…and the summary does not ask for a setup run over it" \
  "environment settings" "$(verdict_block "$ENV_STALE_OUT")"

# (c) absent from the file — the real setup gap, and the one state that earns a
# setup line in the summary.
ENV_GAP_M="$TMP/machine-env-gap"; plant_machine "$ENV_GAP_M" healthy
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("env", None)
json.dump(d, open(sys.argv[1], "w"), indent=2)
' "$ENV_GAP_M/claude-home/settings.json"
ENV_GAP_OUT="$TMP/env-gap.txt"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_GAP_M"  > "$ENV_GAP_OUT" 2>&1
expect_match "absent: reported absent" \
  "*not set*/bionic:setup*" "$(line_of "$ENV_GAP_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_contains "absent: the summary names it as something setup would write" \
  "environment setting" "$(verdict_block "$ENV_GAP_OUT")"

# (d) absent from the file but live in the process — the state the retired shell
# export leaves behind. It must not read as configured: the value dies with this
# session, and the next one will not have it.
ENV_ORPHAN_OUT="$TMP/env-orphan.txt"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_GAP_M" BASH_MAX_TIMEOUT_MS=1800000  > "$ENV_ORPHAN_OUT" 2>&1
expect_match "live but not configured: reported absent from the file" \
  "*not written*/bionic:setup*" "$(line_of "$ENV_ORPHAN_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…and the session is still credited with having it" \
  "*live in session*" "$(line_of "$ENV_ORPHAN_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_contains "…and setup is still named, because the next session will not have it" \
  "environment setting" "$(verdict_block "$ENV_ORPHAN_OUT")"

# READ-ONLY STILL HOLDS over the new reads. env.sh's write path exists; doctor
# must never reach it.
FP_ENV_BEFORE="$(fingerprint "$ENV_M")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_M" > /dev/null 2>&1
expect_eq "the environment section mutates nothing" \
  "$FP_ENV_BEFORE" "$(fingerprint "$ENV_M")"


# ---------------------------------------------------------------------------
echo "=== Group 22: PATROL — the reconstruction, its duplicates, its stamp, its wall ==="
# ---------------------------------------------------------------------------
#
# WHAT THIS GROUP OWNS. The one section on the page with no file under it. The
# CLI keeps its cron table in process memory and writes none of it down, so
# doctor reconstructs it from two things that ARE on disk — the session files
# that name each live process, and those sessions' transcripts, where
# `CronCreate` and `CronDelete` are recorded tool_uses. Every fixture below is
# built from shapes captured off this machine on 2026-08-22; the capture
# commands are quoted at each builder.
#
# BEHAVIOUR, NOT PROSE. The output-text pins were purged from this suite on
# 2026-08-22 (b959b5e). What is asserted here is a VERDICT (`none armed`,
# `1 armed`, `DUPLICATE (n)`, `firing`, `NOT firing`) and a COUNT, plus one
# literal: the `CronDelete <id>` line, which is a command a reader pastes and
# is therefore load-bearing text rather than decoration.
#
# EVERY ARM IS A DIFFERENT MACHINE, because a live session is keyed by the pid
# of a process that must actually exist. The suite's own pid is used for the
# live one — `kill -0` is what doctor asks, and the suite is by definition
# alive while it asks.

# The transcript shapes, captured with:
#   jq -c 'select(.type=="assistant") | .message.content[]?
#          | select(.type=="tool_use" and (.name|test("^Cron")))' <transcript>
#   jq -c 'select(.type=="user") | .message.content[]?
#          | select(.type=="tool_result" and .tool_use_id=="toolu_…")' <transcript>
# The job id is NOT in the request — the platform mints it and names it in the
# result prose, in one of the two forms measured on this machine:
#   "Scheduled recurring job b63afd05 (13,43 * * * *). Session-only …"
#   "Scheduled one-shot task 1037a802 (46 10 18 8 *). Session-only …"
tx_create() {  # <transcript> <tool_use_id> <cron> <prompt> <recurring:true|false> <job-id> <kind-word>
  jq -nc --arg id "$2" --arg cron "$3" --arg prompt "$4" --argjson rec "$5" \
    '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[
       {type:"tool_use",id:$id,name:"CronCreate",input:{cron:$cron,prompt:$prompt,recurring:$rec}}]}}' >> "$1"
  jq -nc --arg id "$2" \
    --arg txt "Scheduled $7 $6 ($3). Session-only (not written to disk, dies when Claude exits)." \
    '{type:"user",isSidechain:false,message:{role:"user",content:[
       {type:"tool_result",tool_use_id:$id,content:$txt}]}}' >> "$1"
}
tx_delete() {  # <transcript> <tool_use_id> <job-id>
  jq -nc --arg id "$2" --arg jid "$3" \
    '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[
       {type:"tool_use",id:$id,name:"CronDelete",input:{id:$jid}}]}}' >> "$1"
  jq -nc --arg id "$2" --arg txt "Cancelled job $3." \
    '{type:"user",isSidechain:false,message:{role:"user",content:[
       {type:"tool_result",tool_use_id:$id,content:$txt}]}}' >> "$1"
}
# A main-thread dispatch. `isSidechain:false` is what makes it main-thread; a
# subagent's own turns carry `true` and are not dispatches this session made.
tx_agent() {  # <transcript> <tool_use_id> <agent-name>
  jq -nc --arg id "$2" --arg nm "$3" \
    '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[
       {type:"tool_use",id:$id,name:"Agent",input:{name:$nm,subagent_type:"bionic:implementor",prompt:"…"}}]}}' >> "$1"
}
# A SIDECHAIN dispatch — a subagent dispatching in its own turn. It is NOT a
# main-thread dispatch and must not be counted as one, which is the only thing
# keeping the wall-blindness number from drifting upward on every fan-out.
tx_agent_sidechain() {  # <transcript> <tool_use_id> <agent-name>
  jq -nc --arg id "$2" --arg nm "$3" \
    '{type:"assistant",isSidechain:true,message:{role:"assistant",content:[
       {type:"tool_use",id:$id,name:"Agent",input:{name:$nm,subagent_type:"bionic:implementor",prompt:"…"}}]}}' >> "$1"
}
# A dispatch the WALL REFUSED — the CLI still writes the Agent tool_use (the
# dispatch was attempted), but the wall's PreToolUse hook exits before
# dispatch-preflight.sh's roster append, so this tool_use has a tool_result
# carrying the CLI's own `PreToolUse:Agent hook error:` marker instead of a
# normal completion. It must be credited to the walled side, not counted as a
# gap — a refusal is the wall doing its job (session-poker.sh's
# `count_refused_dispatches`, mirrored here).
tx_agent_refused() {  # <transcript> <tool_use_id> <agent-name>
  jq -nc --arg id "$2" --arg nm "$3" \
    '{type:"assistant",isSidechain:false,message:{role:"assistant",content:[
       {type:"tool_use",id:$id,name:"Agent",input:{name:$nm,subagent_type:"bionic:implementor",prompt:"…"}}]}}' >> "$1"
  jq -nc --arg id "$2" \
    --arg txt "PreToolUse:Agent hook error: dispatch refused by dispatch-preflight.sh" \
    '{type:"user",isSidechain:false,message:{role:"user",content:[
       {type:"tool_result",tool_use_id:$id,content:$txt}]}}' >> "$1"
}

# THE PATROL PROMPT IS NOT MATCHED BY ITS WORDING. It is composed per session by
# a model, so its prose is not a fact anything may key on. What it must CONTAIN
# is fixed by skills/canonical-sdlc/SKILL.md §Dispatch, whose first of four
# reads is `session-poker.sh tick` — so that is the marker, and the arm below
# with a job carrying a different prompt proves a non-Patrol timer is not
# counted as one.
PATROL_PROMPT='PATROL TICK — run `bash /p/hooks/session-poker.sh tick` and act on its decision. Then continue.'
OTHER_PROMPT='One-shot: check the 529 backoff and resume the dead lineage if it is still dead.'

# machine + a project repo that is not this repository + the poker the interval
# comes from. `poker-interval: 60s` makes the staleness limit 120s, so an arm
# can plant a stamp past it without waiting (memory: accelerate-clocks-under-test).
plant_patrol_machine() {  # <machine-root>
  local m="$1"
  plant_machine "$m" healthy
  cp "${REPO}/payload/hooks/session-poker.sh" "$m/plugin/hooks/session-poker.sh"
  mkdir -p "$m/repo/.bionic/tmp" "$m/claude-home/sessions" "$m/claude-home/projects/-fixture-repo"
  printf 'poker-interval: 60s\n' > "$m/repo/.bionic/config.yaml"
}

plant_patrol_session() {  # <machine-root> <sid> <pid>
  jq -nc --argjson pid "$3" --arg sid "$2" --arg cwd "$1/repo" \
    '{pid:$pid,sessionId:$sid,cwd:$cwd,version:"2.1.240",kind:"interactive"}' \
    > "$1/claude-home/sessions/$3.json"
  : > "$1/claude-home/projects/-fixture-repo/$2.jsonl"
}

plant_patrol_stamp() {  # <machine-root> <sid> <age-seconds>
  local f="$1/repo/.bionic/tmp/patrol-$2.state"
  printf 'patrol-stamp/v1|at=2026-08-22T00:00:00Z|session=%s|verb=tick\n' "$2" > "$f"
  python3 -c 'import os,sys,time; p=sys.argv[1]; a=int(sys.argv[2]); os.utime(p,(time.time()-a,time.time()-a))' "$f" "$3"
}

# The roster, in the shape hooks/dispatch-preflight.sh writes it — captured with
#   head -3 .bionic/tmp/roster-<sid>.state
# The file is APPEND-ONLY and gains a row per status transition (`intended` at
# the wall, then `confirmed`, then `identified`), which is why the dispatch
# count is the number of `intended` rows and not the number of rows.
plant_patrol_roster() {  # <machine-root> <sid> <name>...
  local m="$1" sid="$2" nm; shift 2
  local f="$m/repo/.bionic/tmp/roster-$sid.state"
  printf '# bionic session roster — schema roster-state/v1 — machine-local, safe to delete\n' > "$f"
  for nm in "$@"; do
    printf 'roster-state/v1|status=intended|session=%s|name=%s|agent_id=|launched_at=2026-08-22T00:00:00Z|subagent_type=bionic:implementor|model=|deliverable=/tmp/%s.md|source=declared|duration=20 minutes.|progress=/tmp/p-%s.md|claims=|cadence=5m|absent=|waiver=|tool_use_id=toolu_%s\n' \
      "$sid" "$nm" "$nm" "$nm" "$nm" >> "$f"
    printf 'roster-state/v1|status=identified|session=%s|name=%s|agent_id=a%s-deadbeef|launched_at=2026-08-22T00:00:00Z|subagent_type=bionic:implementor|model=|deliverable=/tmp/%s.md|source=declared|duration=20 minutes.|progress=/tmp/p-%s.md|claims=|cadence=5m|absent=|waiver=|tool_use_id=toolu_%s\n' \
      "$sid" "$nm" "$nm" "$nm" "$nm" "$nm" >> "$f"
  done
}
# The one marker hooks/landing-gate.sh writes, and the only thing that closes a
# row for a reader that is not the sweeper.
plant_patrol_swept() {  # <machine-root> <sid> <name>
  printf 'landing-swept/v1|at=2026-08-22T00:10:00Z|session=%s|name=%s|agent_id=a%s-deadbeef|state=MET\n' \
    "$2" "$3" "$3" >> "$1/repo/.bionic/tmp/roster-$2.state"
}

# Doctor, run FROM the fixture project — `here` is decided by comparing the
# session's repo with doctor's own, so a run from anywhere else would report
# every fixture session as somebody else's.
doctor_run_at() {  # <cwd> <doctor.sh> <bin> <machine> [env…]
  local d="$1"; shift
  ( cd "$d" && doctor_run "$@" )
}

PATROL_BLOCK="$TMP/patrol-block.txt"
patrol_block() {  # <doctor-output-file>
  awk '/^PATROL —/{f=1} f' "$1" > "$PATROL_BLOCK" 2>/dev/null
}
# First matching line of the section, read from a FILE — never `awk … | grep -m1`,
# which under `pipefail` kills the producer with SIGPIPE and answers 141
# (memory: grep-q-sigpipe-under-pipefail).
patrol_line() {  # <doctor-output-file> <needle>
  patrol_block "$1"
  grep -F -m1 -- "$2" "$PATROL_BLOCK" || true
}
patrol_count() {  # <doctor-output-file> <needle>
  local c
  patrol_block "$1"
  # `grep -c` PRINTS 0 and EXITS 1 on no match, so an `|| echo 0` fallback
  # prints a second zero and every count assertion compares against "0\n0".
  c="$(grep -c -F -- "$2" "$PATROL_BLOCK" 2>/dev/null || true)"
  printf '%s' "${c:-0}"
}

# ── (a) a machine with no live session at all ────────────────────────────────
PAT_NONE="$TMP/machine-patrol-none"; plant_patrol_machine "$PAT_NONE"
PAT_NONE_OUT="$TMP/patrol-none.txt"
doctor_run_at "$PAT_NONE/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_NONE" > "$PAT_NONE_OUT" 2>&1
expect_contains "no live session: the section is still printed" \
  "PATROL" "$(cat "$PAT_NONE_OUT")"
expect_match "no live session: it says there is nothing to reconstruct" \
  "*none*" "$(patrol_line "$PAT_NONE_OUT" "live sessions")"
expect_eq "no live session: no delete line is offered" \
  "0" "$(patrol_count "$PAT_NONE_OUT" "CronDelete")"

# ── (b) zero Patrol jobs, one timer that is not the Patrol ───────────────────
PAT_0="$TMP/machine-patrol-0"; plant_patrol_machine "$PAT_0"
SID_0="aaaaaaaa-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_0" "$SID_0" "$$"
TX0="$PAT_0/claude-home/projects/-fixture-repo/$SID_0.jsonl"
tx_create "$TX0" "toolu_o1" "46 10 18 8 *" "$OTHER_PROMPT" false "1037a802" "one-shot task"
PAT_0_OUT="$TMP/patrol-0.txt"
doctor_run_at "$PAT_0/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_0" > "$PAT_0_OUT" 2>&1
expect_match "0 patrol jobs: the verdict is none armed" \
  "*none armed*" "$(patrol_line "$PAT_0_OUT" "patrol jobs")"
expect_match "0 patrol jobs: the non-Patrol timer is still reported, as another job" \
  "*1*" "$(patrol_line "$PAT_0_OUT" "other jobs")"
expect_eq "0 patrol jobs: no delete line" \
  "0" "$(patrol_count "$PAT_0_OUT" "CronDelete")"
expect_not_contains "0 patrol jobs: an unarmed session is not a problem in the verdict" \
  "Patrol job" "$(head -3 "$PAT_0_OUT")"

# ── (c) one Patrol job, stamped fresh, roster clean ──────────────────────────
PAT_1="$TMP/machine-patrol-1"; plant_patrol_machine "$PAT_1"
SID_1="bbbbbbbb-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_1" "$SID_1" "$$"
TX1="$PAT_1/claude-home/projects/-fixture-repo/$SID_1.jsonl"
tx_create "$TX1" "toolu_p1" "7,37 * * * *" "$PATROL_PROMPT" true "6d3b6356" "recurring job"
tx_agent  "$TX1" "toolu_a1" "w1-alpha"
tx_agent  "$TX1" "toolu_a2" "w1-beta"
tx_agent_sidechain "$TX1" "toolu_a3" "w1-gamma-from-a-subagent"
plant_patrol_stamp  "$PAT_1" "$SID_1" 30
plant_patrol_roster "$PAT_1" "$SID_1" w1-alpha w1-beta
plant_patrol_swept  "$PAT_1" "$SID_1" w1-beta
PAT_1_OUT="$TMP/patrol-1.txt"
doctor_run_at "$PAT_1/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_1" > "$PAT_1_OUT" 2>&1
expect_match "1 patrol job: the verdict is 1 armed" \
  "*1 armed*" "$(patrol_line "$PAT_1_OUT" "patrol jobs")"
expect_contains "1 patrol job: its id and cron are on the page" \
  "6d3b6356" "$(cat "$PATROL_BLOCK")"
expect_contains "1 patrol job: …with the cron expression beside it" \
  "7,37 * * * *" "$(cat "$PATROL_BLOCK")"
expect_eq "1 patrol job: nothing to delete" \
  "0" "$(patrol_count "$PAT_1_OUT" "CronDelete")"
expect_match "a fresh stamp reads firing" \
  "*firing*" "$(patrol_line "$PAT_1_OUT" "patrol stamp")"
expect_not_match "…and not NOT-firing" \
  "*NOT firing*" "$(patrol_line "$PAT_1_OUT" "patrol stamp")"
expect_match "the roster is counted by dispatch, not by row" \
  "*2 dispatches*" "$(patrol_line "$PAT_1_OUT" "roster")"
expect_match "…split into the open ones and the swept ones" \
  "*1 open, 1 closed*" "$(patrol_line "$PAT_1_OUT" "roster")"
expect_match "the wall saw every main-thread dispatch" \
  "*2 dispatched, 2 rostered*" "$(patrol_line "$PAT_1_OUT" "dispatch wall")"
expect_not_contains "a sidechain dispatch is not counted against the wall" \
  "never reached it" "$(cat "$PATROL_BLOCK")"

# ── (d) two Patrol jobs live, a third created and deleted ────────────────────
PAT_2="$TMP/machine-patrol-2"; plant_patrol_machine "$PAT_2"
SID_2="cccccccc-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_2" "$SID_2" "$$"
TX2="$PAT_2/claude-home/projects/-fixture-repo/$SID_2.jsonl"
tx_create "$TX2" "toolu_q0" "13,43 * * * *" "$PATROL_PROMPT" true "b63afd05" "recurring job"
tx_delete "$TX2" "toolu_qd" "b63afd05"
tx_create "$TX2" "toolu_q1" "11,41 * * * *" "$PATROL_PROMPT" true "5f6fdf96" "recurring job"
tx_create "$TX2" "toolu_q2" "17,47 * * * *" "$PATROL_PROMPT" true "e34c715d" "recurring job"
plant_patrol_stamp "$PAT_2" "$SID_2" 30
PAT_2_OUT="$TMP/patrol-2.txt"
doctor_run_at "$PAT_2/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_2" > "$PAT_2_OUT" 2>&1
expect_match "two live Patrol jobs: the verdict names the duplication and its count" \
  "*DUPLICATE (2)*" "$(patrol_line "$PAT_2_OUT" "patrol jobs")"
expect_eq "…and exactly one delete line is offered, for the one extra" \
  "1" "$(patrol_count "$PAT_2_OUT" "CronDelete")"
expect_contains "…naming the OLDER live job" \
  "CronDelete 5f6fdf96" "$(cat "$PATROL_BLOCK")"
expect_not_contains "…never the newest, which is the one that stays" \
  "CronDelete e34c715d" "$(cat "$PATROL_BLOCK")"
expect_not_contains "…and never the job that was already deleted" \
  "b63afd05" "$(cat "$PATROL_BLOCK")"
expect_contains "the duplication reaches the verdict at the top of the report" \
  "CronDelete 5f6fdf96" "$(head -4 "$PAT_2_OUT")"

# ── (e) armed, then stopped firing ───────────────────────────────────────────
PAT_S="$TMP/machine-patrol-stale"; plant_patrol_machine "$PAT_S"
SID_S="dddddddd-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_S" "$SID_S" "$$"
TXS="$PAT_S/claude-home/projects/-fixture-repo/$SID_S.jsonl"
tx_create "$TXS" "toolu_s1" "7,37 * * * *" "$PATROL_PROMPT" true "6d3b6356" "recurring job"
# 600s against a 120s limit — 2x the 60s this project's config.yaml configures.
plant_patrol_stamp "$PAT_S" "$SID_S" 600
PAT_S_OUT="$TMP/patrol-stale.txt"
doctor_run_at "$PAT_S/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_S" > "$PAT_S_OUT" 2>&1
expect_match "a stale stamp reads NOT firing" \
  "*NOT firing*" "$(patrol_line "$PAT_S_OUT" "patrol stamp")"
expect_match "…measured against 2x the interval this project configures" \
  "*120s*" "$(patrol_line "$PAT_S_OUT" "patrol stamp")"
expect_contains "…and it reaches the verdict at the top" \
  "stopped firing" "$(head -5 "$PAT_S_OUT")"
# A job in the table and a stamp that is not landing are two facts, not one
# verdict: the section says the job is armed AND that nothing is firing.
expect_match "…while the job table still reports the job as armed" \
  "*1 armed*" "$(patrol_line "$PAT_S_OUT" "patrol jobs")"

# ── (f) never armed: a stamp that was never written ──────────────────────────
PAT_N="$TMP/machine-patrol-neverarmed"; plant_patrol_machine "$PAT_N"
SID_N="eeeeeeee-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_N" "$SID_N" "$$"
PAT_N_OUT="$TMP/patrol-neverarmed.txt"
doctor_run_at "$PAT_N/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_N" > "$PAT_N_OUT" 2>&1
expect_match "no stamp at all reads never armed" \
  "*never armed*" "$(patrol_line "$PAT_N_OUT" "patrol stamp")"
expect_match "…and an empty roster says so rather than reporting zero contracts" \
  "*none*" "$(patrol_line "$PAT_N_OUT" "roster")"

# ── (g) the blind wall: dispatches the roster never saw ──────────────────────
PAT_B="$TMP/machine-patrol-blind"; plant_patrol_machine "$PAT_B"
SID_B="ffffffff-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_B" "$SID_B" "$$"
TXB="$PAT_B/claude-home/projects/-fixture-repo/$SID_B.jsonl"
tx_create "$TXB" "toolu_b1" "7,37 * * * *" "$PATROL_PROMPT" true "6d3b6356" "recurring job"
tx_agent "$TXB" "toolu_b2" "w1-alpha"
tx_agent "$TXB" "toolu_b3" "w1-beta"
tx_agent "$TXB" "toolu_b4" "w1-gamma"
plant_patrol_stamp  "$PAT_B" "$SID_B" 30
plant_patrol_roster "$PAT_B" "$SID_B" w1-alpha
PAT_B_OUT="$TMP/patrol-blind.txt"
doctor_run_at "$PAT_B/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_B" > "$PAT_B_OUT" 2>&1
expect_match "three dispatches against one roster row: the wall is reported blind" \
  "*2 of 3*" "$(patrol_line "$PAT_B_OUT" "dispatch wall")"
expect_contains "…and the cure named in the verdict is the skill re-invocation" \
  "/bionic:canonical-sdlc" "$(head -5 "$PAT_B_OUT")"

# ── (h) a refused dispatch is not a blind wall ────────────────────────────────
# One dispatch the wall REFUSED (still a tool_use, but its tool_result carries
# the CLI's `PreToolUse:Agent hook error:` marker instead of a normal
# completion) plus two real dispatches that both reach the roster. The wall
# saw 3 tool_uses against 2 rostered rows, and the gap is fully explained by
# the refusal — this must NOT read as blind.
PAT_RF="$TMP/machine-patrol-refused-ok"; plant_patrol_machine "$PAT_RF"
SID_RF="11111111-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_RF" "$SID_RF" "$$"
TXRF="$PAT_RF/claude-home/projects/-fixture-repo/$SID_RF.jsonl"
tx_create "$TXRF" "toolu_rf1" "7,37 * * * *" "$PATROL_PROMPT" true "6d3b6356" "recurring job"
tx_agent_refused "$TXRF" "toolu_rf2" "w1-refused"
tx_agent         "$TXRF" "toolu_rf3" "w1-alpha"
tx_agent         "$TXRF" "toolu_rf4" "w1-beta"
plant_patrol_stamp  "$PAT_RF" "$SID_RF" 30
plant_patrol_roster "$PAT_RF" "$SID_RF" w1-alpha w1-beta
PAT_RF_OUT="$TMP/patrol-refused-ok.txt"
doctor_run_at "$PAT_RF/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_RF" > "$PAT_RF_OUT" 2>&1
expect_not_contains "a refused dispatch is credited to the wall, not read as a gap" \
  "never reached it" "$(patrol_line "$PAT_RF_OUT" "dispatch wall")"
expect_match "the wall line names the refusal explicitly" \
  "*1 refused*" "$(patrol_line "$PAT_RF_OUT" "dispatch wall")"

# ── (i) a refusal AND a genuinely missing dispatch, together ─────────────────
# Same one refused dispatch, but now a THIRD real dispatch never lands on the
# roster at all — a genuine gap the refusal does not explain. 4 tool_uses (1
# refused, 3 real) against 2 rostered rows: net of the refusal, exactly 1
# dispatch never reached the wall.
PAT_RB="$TMP/machine-patrol-refused-blind"; plant_patrol_machine "$PAT_RB"
SID_RB="22222222-0000-4000-8000-000000000000"
plant_patrol_session "$PAT_RB" "$SID_RB" "$$"
TXRB="$PAT_RB/claude-home/projects/-fixture-repo/$SID_RB.jsonl"
tx_create "$TXRB" "toolu_rb1" "7,37 * * * *" "$PATROL_PROMPT" true "6d3b6356" "recurring job"
tx_agent_refused "$TXRB" "toolu_rb2" "w1-refused"
tx_agent         "$TXRB" "toolu_rb3" "w1-alpha"
tx_agent         "$TXRB" "toolu_rb4" "w1-beta"
tx_agent         "$TXRB" "toolu_rb5" "w1-gamma"
plant_patrol_stamp  "$PAT_RB" "$SID_RB" 30
plant_patrol_roster "$PAT_RB" "$SID_RB" w1-alpha w1-beta
PAT_RB_OUT="$TMP/patrol-refused-blind.txt"
doctor_run_at "$PAT_RB/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_RB" > "$PAT_RB_OUT" 2>&1
expect_match "the genuinely missing dispatch is still reported, net of the refusal" \
  "*1 of 4*" "$(patrol_line "$PAT_RB_OUT" "dispatch wall")"
expect_match "…and the refusal is still named on that same line" \
  "*1 refused*" "$(patrol_line "$PAT_RB_OUT" "dispatch wall")"

# ── the format rules hold over the new section ───────────────────────────────
#
# AC-15's width wall, applied to every arm above rather than to one: the lines
# that can run long are exactly the ones carrying reconstructed values — a
# prompt head, a cwd, a list of ids — and each of those appears in only some
# arms.
PAT_ALL="$TMP/patrol-all-blocks.txt"; : > "$PAT_ALL"
for _po in "$PAT_NONE_OUT" "$PAT_0_OUT" "$PAT_1_OUT" "$PAT_2_OUT" "$PAT_S_OUT" "$PAT_N_OUT" "$PAT_B_OUT" "$PAT_RF_OUT" "$PAT_RB_OUT"; do
  awk '/^PATROL —/{f=1} f' "$_po" >> "$PAT_ALL"
done
PAT_WIDE=""
while IFS= read -r _pl; do
  [ "$(printf '%s' "$_pl" | wc -m | tr -d ' ')" -gt 100 ] && PAT_WIDE="${PAT_WIDE}${_pl}"$'\n'
done < "$PAT_ALL"
expect_eq "every Patrol line fits inside 100 columns" "" "$PAT_WIDE"

# ── READ-ONLY, over a machine with everything to read ────────────────────────
FP_PAT_BEFORE="$(fingerprint "$PAT_2")"
doctor_run_at "$PAT_2/repo" "$DOCTOR_SH" "$FULL_BIN" "$PAT_2" > /dev/null 2>&1
expect_eq "the Patrol section mutates nothing — not the transcript, not the state files" \
  "$FP_PAT_BEFORE" "$(fingerprint "$PAT_2")"

# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
