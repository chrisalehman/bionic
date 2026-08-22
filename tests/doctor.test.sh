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
# `sleep` is on this list for wave-06 S6: doctor bounds every command that can
# hang (the plugin listing, brew, npm) and, with no `timeout` on a stock macOS,
# the bound is a poll loop that needs it. Without `sleep` on PATH doctor runs the
# probe unbounded, which is a different code path from the one under test.
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls tr head tail sort uniq wc jq python3 find shasum sleep diff; do
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
    cat > "$m/claude-home/plugins/installed_plugins.json" <<JSON
{ "plugins": {
    "bionic@bionic": [ { "scope": "user", "installPath": "${m}/plugin", "version": "0.1.0",
                         "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "superpowers@bionic": [ { "scope": "user", "installPath": "${m}/installs/superpowers", "version": "6.3.0",
                              "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "agent-skills@bionic": [ { "scope": "user", "installPath": "${m}/installs/agent-skills", "version": "0.6.1",
                               "installedAt": "2026-08-17T00:00:00.000Z" } ],
    "impeccable@bionic": [ { "scope": "user", "installPath": "${m}/installs/impeccable", "version": "4.1.1",
                             "installedAt": "2026-08-20T00:00:00.000Z" } ] } }
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
           "env": {"CLAUDE_CODE_ENABLE_TODO_TOOLS": "1", "BASH_MAX_TIMEOUT_MS": "1800000",
                   "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"},
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
    BIONIC_PROFILE_TEMPLATE="$TEMPLATE" \
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

H_OUT="$TMP/healthy.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" > "$H_OUT" 2>&1
H_RC=$?
H="$(cat "$H_OUT")"

expect_eq "doctor exits 0 on a healthy machine (a diagnosis is not a failure)" "0" "$H_RC"

# THE ROSTER IS AN ORDER, NOT A SET (AC-3, ratified D-A as corrected by D-D).
# Ten sections on every run, in this sequence, and UPDATES only after the closing
# question is answered yes. Asserted as one comparison of the whole ordered list
# rather than ten containment checks: a containment check passes on a report that
# renders every section in the wrong order, which is precisely the defect an
# ordering criterion exists to catch. LOAD STATE leads because a plugin that did
# not load makes every section under it a description of something the session is
# not running.
section_roster() {  # <doctor-output-file> -> one section name per line, in order
  sed -n 's/^=== \(.*\) ===$/\1/p' "$1"
}
EXPECTED_ROSTER="LOAD STATE
PLUGIN INTEGRITY
TIER STATE
DEPENDENCIES
DUPLICATES
ENVIRONMENT
PERMISSION PROFILE
ROSTER FOOTPRINT
DEGRADATION MAP
SUMMARY"
expect_eq "healthy: the section roster is exactly the ten instant sections, in the ratified order" \
  "$EXPECTED_ROSTER" "$(section_roster "$H_OUT")"

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
expect_match "healthy: core superpowers row carries class/present/version/constraint/verdict" \
  "*core*superpowers*yes*6.3.0*^6.3.0*ok*" "$(line_of "$H_OUT" "superpowers")"
expect_match "healthy: core agent-skills row satisfies the corrected ^0.6.0 constraint" \
  "*core*agent-skills*yes*0.6.1*^0.6.0*ok*" "$(line_of "$H_OUT" "agent-skills")"
expect_match "healthy: basic rg row renders present with its captured version" \
  "*basic*rg*yes*15.2.0*any*ok*" "$(line_of "$H_OUT" " rg ")"
expect_match "healthy: when-needed npm-global row renders the package version npm reported" \
  "*when-needed*@playwright/cli*yes*0.1.18*" "$(line_of "$H_OUT" "@playwright/cli")"
DEP_SECTION_H="$(awk '/=== DEPENDENCIES ===/,/=== DUPLICATES ===/' "$H_OUT")"
expect_match "healthy: the dependency table's own header names the class column" \
  "*class*name*present*version*constraint*verdict*" \
  "$(printf '%s\n' "$DEP_SECTION_H" | grep -E '^[[:space:]]+class[[:space:]]+name' || true)"
# The whole report, not just the table: the degradation map and the roster
# footprint each used to spell the lane codes out in prose.
LANE_TOKENS="$(grep -nE '(^|[^[:alnum:]])(lane|3a|3b)([^[:alnum:]]|$)' "$H_OUT" || true)"
expect_eq "healthy: no internal lane vocabulary reaches the report at all" "" "$LANE_TOKENS"
# The when-needed NATIVE row: same registry probe as the core rows, judged
# against its own ^4.1.0, and it belongs to neither legacy lane.
expect_match "healthy: when-needed impeccable row renders present at 4.1.1, verdict ok" \
  "*impeccable*yes*4.1.1*^4.1.0*ok*" "$(line_of "$H_OUT" "impeccable")"
expect_match "healthy: mcp-server row renders present" \
  "*extra*context7*yes*" "$(line_of "$H_OUT" "context7")"
expect_match "healthy: playwright browser cache row renders present" \
  "*when-needed*playwright-chromium*yes*" "$(line_of "$H_OUT" "playwright-chromium")"
# THE RENDERER GETS ITS OWN ROW (epic-18 T3, AC-6). The excalidraw skill is plugin-native
# now, so the skill itself is never a question — it arrives with bionic or bionic is not
# installed. What IS a question is whether its renderer has been synced, and this row is the
# probe-able half: present here because the healthy machine's plugin root carries the venv.
expect_match "healthy: the excalidraw renderer row renders present with the venv's python" \
  "*when-needed*excalidraw-renderer*yes*3.13.1*" "$(line_of "$H_OUT" "excalidraw-renderer")"

# Environment class.
# CONFIGURED AND LIVE ARE TWO FACTS. The healthy machine's settings.json
# carries both names; the process doctor ran in does not (doctor_run starts from
# `env -i`), so the honest report is "configured, not live in this session" —
# which is a restart, not a repair, and Group 21 below is where the pair is
# driven end to end.
expect_match "healthy: the task-list name reports its configured value" \
  "*1*" "$(line_of "$H_OUT" "CLAUDE_CODE_ENABLE_TODO_TOOLS")"
expect_match "healthy: …and says whether this session has it" \
  "*live in this session*" "$(line_of "$H_OUT" "CLAUDE_CODE_ENABLE_TODO_TOOLS")"
expect_match "healthy: the long-command ceiling reports its configured value" \
  "*1800000*" "$(line_of "$H_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "healthy: legacy .zshrc alias block reported absent" \
  "*absent*" "$(line_of "$H_OUT" "legacy .zshrc alias block")"
expect_match "healthy: zero legacy-channel managed-hook entries" \
  "*0*" "$(line_of "$H_OUT" "legacy-channel managed-hook entries")"
expect_match "healthy: ccstatusline reported present" \
  "*present*" "$(line_of "$H_OUT" "ccstatusline statusline")"

# Permission profile — the three-way diff. The version is read from the shipped
# template, never pinned as a literal: plugin.json owns it and the template
# renders it (version-ssot arm (e)), so a release bump must not go red here.
TPL_VERSION="$(jq -r .version "$TEMPLATE")"
expect_match "healthy: shipped template version rendered" \
  "*${TPL_VERSION}*" "$(line_of "$H_OUT" "shipped template version")"
expect_match "healthy: applied block version rendered" \
  "*${TPL_VERSION}*" "$(line_of "$H_OUT" "applied block version")"
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
expect_match "healthy: a dependency that is not plugin-shaped contributes no roster lines" \
  "*0*" "$(roster_line_of "$H_OUT" " git ")"
# THE ROSTER BRANCH IS KEYED ON SHAPE, NOT ON CLASS (S3's hand-on, A-4.S3.7).
# impeccable is a plugin — it installs through the CLI and lands one skill in the
# session roster — and it is `when-needed`, not `core`. Keyed on the old lane
# code it fell into the "binaries and packages cost nothing" branch and an
# INSTALLED plugin was reported as contributing zero, which is the one number in
# this section a reader could act on being wrong.
expect_match "healthy: the installed when-needed plugin contributes its own skill to the roster" \
  "*1*1 skill *0 agents*" "$(roster_line_of "$H_OUT" "impeccable")"
expect_match "healthy: and the total counts it (14 + 28 + 1)" \
  "*43*" "$(roster_line_of "$H_OUT" "total")"

# Half-uninstalled and the summary.
expect_match "healthy: half-uninstalled reported no" \
  "*no*" "$(line_of "$H_OUT" "half-uninstalled")"
expect_not_contains "healthy: no curl fallback one-liner on a registered machine" \
  "remove.sh | bash" "$H"
expect_contains "healthy: summary says there is nothing to do" "nothing to do" "$H"

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

expect_match "healthy: permission mode reads unset when the machine has no key" \
  "*unset*" "$(line_of "$H_OUT" "permission mode")"
expect_contains "healthy: the permission mode line carries the Remote Control note" \
  "$RC_NOTE" "$H"

# A machine that HAS written a mode (the setup item's own effect) reports that
# value verbatim, with the same note beside it — the note is about what
# overrides the value, not about whether one happens to be set.
MODE_MACHINE="$TMP/machine-mode-auto"; rm -rf "$MODE_MACHINE"; cp -R "$HEALTHY" "$MODE_MACHINE"
jq '.permissions.defaultMode = "auto"' "$HEALTHY/claude-home/settings.json" \
  > "$MODE_MACHINE/claude-home/settings.json"
MODE_OUT="$TMP/mode-auto.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$MODE_MACHINE" > "$MODE_OUT" 2>&1
MODE_RC=$?
expect_eq "mode set: doctor still exits 0" "0" "$MODE_RC"
expect_match "mode set: permission mode reads the value on the machine" \
  "*auto*" "$(line_of "$MODE_OUT" "permission mode")"
expect_contains "mode set: the Remote Control note is still printed" \
  "$RC_NOTE" "$(cat "$MODE_OUT")"

# jq absent: the value cannot be read at all, so `unknown` — never coerced to
# `unset`, which would tell a machine that could not be read that it has
# nothing configured.
MODEQ_OUT="$TMP/mode-nojq.out"
doctor_run "$DOCTOR_SH" "$NOJQ_BIN" "$HEALTHY" > "$MODEQ_OUT" 2>&1
expect_match "no jq: permission mode renders unknown, not unset" \
  "*unknown*" "$(line_of "$MODEQ_OUT" "permission mode")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 4: the broken machine — every failure renders WITH its named fix ==="
# ---------------------------------------------------------------------------

B_OUT="$TMP/broken.out"
doctor_run "$DOCTOR_SH" "$BROKEN_BIN" "$BROKEN" > "$B_OUT" 2>&1
B_RC=$?
B="$(cat "$B_OUT")"

expect_eq "doctor exits 0 on a broken machine too (a diagnosis is not a failure)" "0" "$B_RC"

expect_eq "broken: the same ten sections still render, in the same order" \
  "$EXPECTED_ROSTER" "$(section_roster "$B_OUT")"

expect_match "broken: hooks.json naming a missing script renders degraded" \
  "*degraded*" "$(line_of "$B_OUT" "hooks ")"

# W7 S11 (six-axis review axis 2). The SUMMARY's action line for degraded wiring
# used to read `re-converge with:` and then the hint in backticks — which on a
# directory-source machine handed a user with a genuinely broken tree the words
# "nothing to do" formatted as a command to run. The hint answers per state now,
# so this line gets a repair sentence instead of a re-converge fragment. This
# fixture carries no marketplace registry, so the feed kind is unknown and the
# git-source sentence is the one that renders — the documented default.
B_HOOKFIX="$(awk '/=== SUMMARY ===/,0' "$B_OUT" | grep -A 1 "hook wiring")"
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
  "*core*superpowers*yes*6.2.0*^6.3.0*violation*" "$(line_of "$B_OUT" "superpowers")"
expect_contains "broken: the violation appears in the degradation map with its constraint" \
  "violates constraint ^6.3.0" "$B"
expect_match "broken: the violation line names /bionic:setup as the fix" \
  "*/bionic:setup*" "$(line_of "$B_OUT" "violates constraint")"

# Absences, one per class that can have one, each with a named fix.
# `aws` carries the absent-basic case that `yq` used to: yq and gcloud were
# dropped from the table at wave-06 S3 (no consumer, no test, not universal),
# and the case they stood for — a substrate binary missing from PATH — is
# exactly what aws is on the broken machine.
expect_match "broken: absent core dependency renders present=no" \
  "*core*agent-skills*no*" "$(line_of "$B_OUT" "agent-skills")"
expect_match "broken: absent basic dependency renders present=no" \
  "*basic*aws*no*" "$(line_of "$B_OUT" " aws ")"
# A never-rendered machine: the plugin carries the skill, nothing has synced the venv, and
# that is the row's normal state rather than a fault. The degradation-map arm below is what
# holds it to that — a when-needed absence raises no action line.
expect_match "broken: the excalidraw renderer row renders absent on a machine that never rendered" \
  "*when-needed*excalidraw-renderer*no*" "$(line_of "$B_OUT" "excalidraw-renderer")"
DEG="$(awk '/=== DEGRADATION MAP ===/,/=== SUMMARY ===/' "$B_OUT")"
expect_contains "broken: the degradation map names the absent core dependency" "agent-skills" "$DEG"
expect_contains "broken: the degradation map names the absent basic dependency" "aws" "$DEG"
# THE JIT WORDING MOVED OUT OF THIS MAP AT WAVE-06 S6, and its absence here is
# the assertion. Just-in-time install is what happens to a WHEN-NEEDED row, and
# those are not degradations at all now (Group 16) — so a degradation line
# offering to wait for a route would be describing a row that cannot appear in
# this section. What an absent basic tool gets instead is the command that
# actually installs it.
expect_not_contains "broken: no degradation line offers to wait for a route (that class is not degraded)" \
  "just-in-time" "$DEG"
expect_contains "broken: an absent basic dependency is offered the command that installs it" \
  "run /bionic:setup" "$DEG"
expect_contains "broken: every degradation line names a fix (arrow-delimited)" "→" "$DEG"
# AC-2's own line: ccstatusline is the one dependency with two halves, and the
# generic "is absent" sentence does not say which one(s). Both are missing on
# this fixture (no .statusLine key, no config file), so the reason names both.
expect_contains "broken: the ccstatusline degradation line names which half is missing" \
  "ccstatusline is absent (neither the statusLine command nor its config file is set)" "$DEG"

# Environment class, the other way round from healthy.
expect_match "broken: the task-list name reports absent" \
  "*absent*" "$(line_of "$B_OUT" "CLAUDE_CODE_ENABLE_TODO_TOOLS")"
expect_match "broken: so does the long-command ceiling" \
  "*absent*" "$(line_of "$B_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "broken: legacy .zshrc alias block reported present" \
  "*present*" "$(line_of "$B_OUT" "legacy .zshrc alias block")"
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
expect_match "no jq: a plugin-shaped dependency's presence renders unknown" "*unknown*" "$SP_LINE"
# The negative is written as ` no ` with its surrounding column spaces on purpose:
# a bare `no` is a substring of `unknown`, so the obvious spelling of this
# assertion would pass on the very value it is meant to reject.
expect_not_match "no jq: that presence is NOT coerced to no" "*superpowers* no *" "$SP_LINE"

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
# SIX-AXIS REVIEW C-2. The second clause used to read "/bionic:setup re-warms the
# store either way". True at the wave base, where setup walked every non-native row;
# false at the tip, where setup asks about `core|basic|extra` only and AC-11 makes a
# when-needed tool nobody's to install until a route needs it. The string survived
# because the display lint judges vocabulary, not truth — so the pin is on the
# sentence, and it is keyed on the CLASS the claim is about rather than on the
# mechanism that happens to produce the unknown.
expect_not_contains "healthy: the unknown does not send the user to a command that no longer touches this row" \
  "re-warms the store" "$H"
expect_contains "healthy: it names what actually installs a when-needed row" \
  "motion is installed the first time a workflow needs it" "$H"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 6: the SUMMARY block — action lines only ==="
# ---------------------------------------------------------------------------

# THE SUMMARY BLOCK ENDS WHERE ITS INDENTATION DOES (widened at S6b). Every summary
# line is indented — an action line or the continuation of one — and the report now ends
# with one unindented line: the question doctor asks after the report is complete. That
# line is not a summary item, and an extractor that ran to EOF would read it as a fact
# restated in the action block, which is the one thing this group forbids.
summary_block() {  # <doctor-output-file>
  awk '/=== SUMMARY ===/{f=1; next} f && /^[^[:space:]]/{f=0} f' "$1"
}
H_SUM="$(summary_block "$H_OUT")"
B_SUM="$(summary_block "$B_OUT")"

H_SUM_SQUASHED="$(printf '%s' "$H_SUM" | tr -d '[:space:]')"
expect_true "healthy: the summary block is non-empty" test -n "$H_SUM_SQUASHED"
expect_contains "broken: the summary names /bionic:setup" "/bionic:setup" "$B_SUM"
expect_contains "broken: the summary carries the curl fallback one-liner" "curl -fsSL" "$B_SUM"

# "Action lines only": every non-blank summary line either starts an action
# (`→`) or is the indented continuation of one. No fact restatements.
SUM_NON_ACTION="$(summary_block "$B_OUT" | awk 'NF && $0 !~ /→/ && $0 !~ /^ {6}/')"
expect_eq "broken: the summary contains action lines only (no restated facts)" "" "$SUM_NON_ACTION"

# The setup action states WHY it is being recommended — a bare "run /bionic:setup"
# is not a diagnosis. Extracted from the SUMMARY SECTION, not the whole report:
# the degradation map names the same command per row, and grepping the file would
# return one of those rows instead.
summary_block "$B_OUT" > "$TMP/broken-summary.txt"
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
#
# WAVE-06 S6 KEEPS THIS ARM AS WRITTEN AND IT MEANS MORE THAN IT DID. Doctor now
# has exactly one question, and this is the machine that cannot answer it: with
# stdin closed the report must come out identical to the one every other arm
# gets, with no question in it. Group 19 owns the other half — the answered
# question and the section it appends.

NP_OUT="$TMP/noprompt.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" < /dev/null > "$NP_OUT" 2>&1
NP_RC=$?
NP="$(cat "$NP_OUT")"
expect_eq "doctor completes with stdin closed (it never blocks on an answer)" "0" "$NP_RC"
# THE QUESTION IS PRINTED EVEN HERE, and that is the corrected behaviour (A-4.S6.F-RULING,
# 2026-08-20): setup prints each consented question as it declines it so the model can relay
# it, and doctor's one question follows the same rule. What must never happen is a WAIT —
# the arm above is the proof, since this run has no answer to give.
expect_contains "doctor prints its one question even where nothing can answer it" \
  "$UPDATES_QUESTION" "$NP"
expect_not_contains "…and asks nothing else" "Install " "$NP"
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
#                under consent, so this one EARNS a summary action line.
#   hook files   INERT once the registrations are gone. Disk, not behaviour. Reported and
#                nothing more — the same read-only contract Group 12's line keeps, and for
#                the same reason: turning "this exists" into "you should delete it" on an
#                otherwise-fine machine is how a diagnosis becomes nagging.

# ---- both absent: the cold, correct, post-cutover machine ----
H_SKILL_COPY="$(line_of "$H_OUT" "legacy installed skill copy")"
expect_match "absent: the skill-copy line reports none" "*none*" "$H_SKILL_COPY"
expect_match "absent: and states the plugin-era truth in the same breath" \
  "*payload*" "$H_SKILL_COPY"
H_HOOK_FILES="$(line_of "$H_OUT" "legacy installed hook files")"
expect_match "absent: the hook-files line reports none" "*none*" "$H_HOOK_FILES"

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
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEG2" > "$G14_OUT" 2>&1

G14_SKILL="$(line_of "$G14_OUT" "legacy installed skill copy")"
expect_match "present: the skill-copy line names the path, so the reader can go look" \
  "*canonical-sdlc*" "$G14_SKILL"
expect_not_match "present: and does not report it as absent" "*none*" "$G14_SKILL"

G14_HOOKS="$(line_of "$G14_OUT" "legacy installed hook files")"
# The COUNT FIELD, extracted — not a glob over the whole line. The line ends in a path
# under $TMP, and $TMP is randomly named: a `*3*` match against the whole line passes or
# fails depending on whether mktemp happened to put a 3 in the directory name, which is a
# flake that reports as a real failure roughly one run in three. Pull the number out and
# compare it as a number.
hook_files_count_in() {  # <line> -> the count field alone
  printf '%s\n' "$1" | sed -E 's/^.*legacy installed hook files[[:space:]]+([^ ]+).*$/\1/'
}
expect_eq "present: the hook-files line counts the two payload-named leftovers" \
  "2" "$(hook_files_count_in "$G14_HOOKS")"
# The discriminating arm, and it is the reason the count is derived from payload names:
# THREE .sh files sit in that directory and only TWO are the payload's. A detector that
# counted the directory would say 3, and would be telling a person their own hook is
# bionic's litter — on a line they are reading in order to decide what to delete.
expect_ne "present: the user's own hook is not counted as bionic's leftover" \
  "3" "$(hook_files_count_in "$G14_HOOKS")"
expect_match "present: and says they are inert, so nobody reads a count as an emergency" \
  "*inert*" "$G14_HOOKS"

# ---- the action asymmetry, stated as its own pair of arms ----
expect_contains "present: the skill copy EARNS a setup action line (it is not inert)" \
  "/bionic:setup" "$(cat "$G14_OUT")"
expect_contains "…and the reason names the skill copy specifically" \
  "legacy skill copy" "$(cat "$G14_OUT")"
# The hook files must not have added one. A machine whose ONLY leftover is hook files is
# the discriminating fixture: if that one grows an action line, the contract is broken.
LEG3="$TMP/machine-hookfiles-only"; plant_machine "$LEG3" healthy
mkdir -p "$LEG3/claude-home/hooks"
printf '#!/bin/bash\nexit 0\n' > "$LEG3/claude-home/hooks/protect-main.sh"
G14B_OUT="$TMP/hookfiles-only.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$LEG3" > "$G14B_OUT" 2>&1
expect_eq "hook files alone: still counted" \
  "1" "$(hook_files_count_in "$(line_of "$G14B_OUT" "legacy installed hook files")")"
expect_contains "hook files alone: and the summary still says there is nothing to do" \
  "nothing to do" "$(cat "$G14B_OUT")"

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

g15_set_sha "$G15_TIP"
G15_MATCH_OUT="$TMP/g15-match.out"; g15_run > "$G15_MATCH_OUT" 2>&1
G15_MATCH="$(line_of "$G15_MATCH_OUT" "installed commit")"
expect_match "the installed-commit line renders when the install is at the tip" "*match*" "$G15_MATCH"
expect_match "…naming the sha the two agreed on" "*${G15_TIP:0:12}*" "$G15_MATCH"
expect_contains "…inside PLUGIN INTEGRITY, where the other install facts live" \
  "installed commit" "$(sed -n '/=== PLUGIN INTEGRITY ===/,/=== TIER STATE ===/p' "$G15_MATCH_OUT")"
# The LABEL is product language, not registry vocabulary (epic-17 W6 S9a; walk finding W-3:
# "registry sha" reads as git internals to a user who never asked about a registry). The
# fact is unchanged — which commit is installed — and only the word for it moved.
expect_not_contains "…and never under the old registry-internals label" \
  "registry sha" "$G15_MATCH_OUT"

g15_set_feed_kind git
g15_set_sha "$G15_PREV"
G15_LAG_OUT="$TMP/g15-lag.out"; g15_run > "$G15_LAG_OUT" 2>&1
G15_LAG="$(line_of "$G15_LAG_OUT" "installed commit")"
expect_match "an install behind the tip renders as lag" "*behind*" "$G15_LAG"
expect_match "…naming the installed sha" "*${G15_PREV:0:12}*" "$G15_LAG"
expect_match "…and the tip it is behind" "*${G15_TIP:0:12}*" "$G15_LAG"
# AC-3: on a GIT-SOURCE feed the cache the registry names is what the CLI loads, so
# lagging is real staleness and `update` genuinely refreshes it — `install` on an
# already-registered id is a CLI no-op/"already installed", not a refresh.
# W7 S11 (six-axis review axis 2): the hint is a WHOLE SENTENCE now, and doctor
# prints it after the two shas rather than after a "re-converge with:" prefix that
# said the words the sentence already carried.
expect_contains "…the sentence names the state in its own words" "the installed copy is behind" "$G15_LAG"
expect_contains "…and the action, inline, is update — not install" "claude plugin update bionic@bionic" "$G15_LAG"
expect_contains "…and closes on the re-run that confirms it worked" "then re-run /bionic:doctor" "$G15_LAG"
expect_not_contains "…with no prefix repeating what the sentence already says" "re-converge with: " "$G15_LAG"
expect_not_contains "…never the install verb, which no-ops on an already-registered id" "plugin install bionic@bionic" "$G15_LAG"
expect_eq "…and exactly one such line, not one per state" "1" \
  "$(grep -c "installed commit" "$G15_LAG_OUT" | tr -d ' ')"
expect_eq "doctor still exits 0 with a lagging install (a diagnosis is not a failure)" "0" \
  "$( g15_run > /dev/null 2>&1; echo $? )"

# epic-17 W7 S2b (AC-3). Same lagging sha, but on a DIRECTORY-SOURCE marketplace — a
# local checkout registered as a feed, which is what a dogfood install is — the CLI
# never opens the cache the registry names, so `update` at an unchanged plugin.json
# version is a no-op ("already at the latest version") and refreshes nothing. Measured
# 2026-08-21, .bionic/docs/record/epic-17-w7/ac2-relay-drive.md. The false universal
# claim S2 shipped — one `update` sentence for every feed — must be gone from THIS
# state's rendering, replaced by the true one.
g15_set_feed_kind directory
G15_DIRLAG_OUT="$TMP/g15-dirlag.out"; g15_run > "$G15_DIRLAG_OUT" 2>&1
G15_DIRLAG="$(line_of "$G15_DIRLAG_OUT" "installed commit")"
expect_match "a directory-source lag still renders as lag" "*behind*" "$G15_DIRLAG"
expect_not_contains "…but the update command is never offered — it would no-op there" \
  "claude plugin update bionic@bionic" "$G15_DIRLAG"
# W7 S11: this used to read "re-converge with: nothing to do — the CLI runs this
# tree directly", spliced after a prefix that had ALREADY said "the cache copy is
# behind this tree, which the CLI runs" — the same clause twice, wrapped around a
# non-command offered where a command belongs. One sentence, said once.
expect_contains "…the state is called what it is: nominal" \
  "nominal:" "$G15_DIRLAG"
expect_contains "…naming why: the CLI already runs this tree" \
  "the CLI runs this tree" "$G15_DIRLAG"
expect_contains "…and when the copy does catch up" \
  "the next version bump or reinstall" "$G15_DIRLAG"
expect_not_contains "…never a bare 'nothing to do' handed over where a command belongs" \
  "nothing to do" "$G15_DIRLAG"
expect_not_contains "…and no prefix repeating the sentence's own words" \
  "re-converge with: " "$G15_DIRLAG"
expect_eq "…the clause naming what the CLI runs appears exactly once" "1" \
  "$(printf '%s\n' "$G15_DIRLAG" | /usr/bin/grep -o 'the CLI runs this tree' | wc -l | tr -d ' ')"
expect_not_contains "…never the install verb either" "plugin install bionic@bionic" "$G15_DIRLAG"
expect_eq "doctor still exits 0 on a directory-source lag too" "0" \
  "$( g15_run > /dev/null 2>&1; echo $? )"

# A commit this checkout has never seen is a DIFFERENT answer from lag, because reinstalling
# would change what is running rather than refresh it.
g15_set_sha "0123456789abcdef0123456789abcdef01234567"
G15_FOREIGN_OUT="$TMP/g15-foreign.out"; g15_run > "$G15_FOREIGN_OUT" 2>&1
G15_FOREIGN="$(line_of "$G15_FOREIGN_OUT" "installed commit")"
expect_match "a foreign sha is not reported as lag" "*not a commit in this repository*" "$G15_FOREIGN"
expect_not_match "…and is not confused with the lag wording" "*behind*" "$G15_FOREIGN"

# THE ORDINARY USER'S MACHINE: no repo under the cwd at all. `unknown` with a cause is the
# right answer, and the suite's other arms all run this way — so the healthy machine above
# has already rendered it, and this pins that it did rather than staying silent.
expect_match "off a repo the line still renders, as unknown with a cause" \
  "*unknown*" "$(line_of "$H_OUT" "installed commit")"
# The cause is RENDERED, not the word "cause": doctor's contract is that every unknown it
# prints carries a named reason, so what is pinned is that something follows the dash.
G15_H_LINE="$(line_of "$H_OUT" "installed commit")"
expect_eq "…naming why it could not tell, rather than shrugging" "0" \
  "$([ -n "${G15_H_LINE##*unknown — }" ] && [ "${G15_H_LINE##*unknown — }" != "$G15_H_LINE" ] && echo 0 || echo 1)"

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
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$WN" > "$WN_OUT" 2>&1
WN_RC=$?
WN_TEXT="$(cat "$WN_OUT")"

expect_eq "when-needed absent: doctor still exits 0" "0" "$WN_RC"
expect_match "when-needed absent: the dependency row reports it absent, honestly" \
  "*when-needed*impeccable*no*" "$(line_of "$WN_OUT" "impeccable")"
WN_DEGRADATION="$(awk '/=== DEGRADATION MAP ===/,/=== SUMMARY ===/' "$WN_OUT")"
expect_not_contains "when-needed absent: it is NOT in the degradation map" \
  "impeccable" "$WN_DEGRADATION"
expect_contains "when-needed absent: and the summary still says there is nothing to do" \
  "nothing to do" "$WN_TEXT"
# The contrast arm: an absent CORE row is still a degradation with an action.
expect_contains "core absent: still named in the degradation map" "agent-skills is absent" "$B"
expect_contains "core absent: and still carries a setup action" "→ run /bionic:setup" "$B"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 17: LOAD STATE — the first section, from the CLI's own listing (AC-13) ==="
# ---------------------------------------------------------------------------
#
# WHY IT LEADS. W5's F12 measured a plugin whose dependency was missing: the CLI
# refused to load it and every command silently did nothing. Doctor could not see
# that, because a payload tree on disk reads healthy whether or not the CLI ever
# loaded it — so every section below LOAD STATE describes a machine that may not
# be running any of it.
#
# THE FACT IS detect.sh's (tests/plugin-lib.test.sh owns its six states). What is
# proven here is the RENDERING: the state, the CLI's own Error line verbatim when
# there is one, a fix on the states a user can act on, and the named cause on
# every unknown.

H_LOAD_SECTION="$(awk '/=== LOAD STATE ===/,/=== PLUGIN INTEGRITY ===/' "$H_OUT")"
expect_contains "healthy: LOAD STATE reports the plugin loaded" "loaded" "$H_LOAD_SECTION"
expect_eq "healthy: LOAD STATE is the FIRST section of the report" \
  "LOAD STATE" "$(section_roster "$H_OUT" | head -1)"

# ── failed: the dep-broken listing, the state F12 measured ──
DB_OUT="$TMP/loadstate-failed.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" "BIONIC_PLUGIN_LIST_CMD=cat ${LISTING_DEPBROKEN}" > "$DB_OUT" 2>&1
DB_RC=$?
DB_TEXT="$(cat "$DB_OUT")"
expect_eq "dep-broken: doctor still exits 0" "0" "$DB_RC"
DB_LOAD="$(awk '/=== LOAD STATE ===/,/=== PLUGIN INTEGRITY ===/' "$DB_OUT")"
expect_contains "dep-broken: the state is reported as failed, not loaded" "failed" "$DB_LOAD"
expect_not_contains "dep-broken: and never as loaded" "loaded —" "$DB_LOAD"
# VERBATIM. The CLI's Error line is the one sentence that says WHICH dependency,
# and paraphrasing it is how a user ends up reinstalling the wrong thing.
expect_contains "dep-broken: the CLI's own Error line is rendered verbatim" \
  'Dependency "superpowers@bionic" is not installed' "$DB_LOAD"
expect_contains "dep-broken: and the fix rides in the same section" \
  "claude plugin install" "$DB_LOAD"
expect_contains "dep-broken: a plugin that did not load earns a SUMMARY action" \
  "→ " "$(summary_block "$DB_OUT")"

# ── absent: a real listing that does not name bionic ──
ABSENT_LISTING="$TMP/plugin-list-absent.txt"
awk '/❯ bionic@bionic/{skip=1} /❯ superpowers@bionic/{skip=0} !skip' "$LISTING_HEALTHY" > "$ABSENT_LISTING"
AB_OUT="$TMP/loadstate-absent.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" "BIONIC_PLUGIN_LIST_CMD=cat ${ABSENT_LISTING}" > "$AB_OUT" 2>&1
AB_LOAD="$(awk '/=== LOAD STATE ===/,/=== PLUGIN INTEGRITY ===/' "$AB_OUT")"
# The DISPLAY word is "not installed": `absent` is the fact function's value and
# a person reading a report about their own machine should meet the product word.
expect_contains "absent: the listing is real and does not name bionic — reported not installed" \
  "not installed" "$AB_LOAD"
expect_not_contains "absent: and certainly not as loaded" "loaded" "$AB_LOAD"
expect_contains "absent: with the install command as its fix" \
  "claude plugin install bionic@bionic" "$AB_LOAD"

# ── unknown: output that is not a listing at all ──
GARBAGE="$TMP/not-a-listing.txt"; printf 'command not found\n' > "$GARBAGE"
UK_OUT="$TMP/loadstate-unknown.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" "BIONIC_PLUGIN_LIST_CMD=cat ${GARBAGE}" > "$UK_OUT" 2>&1
UK_LOAD="$(awk '/=== LOAD STATE ===/,/=== PLUGIN INTEGRITY ===/' "$UK_OUT")"
expect_contains "unreadable listing: the state is unknown" "unknown" "$UK_LOAD"
expect_contains "unreadable listing: and the unknown names its cause (A-4.S2.4)" \
  "not a plugin listing" "$UK_LOAD"
# An unknown is not an action: nobody can fix "I could not tell".
expect_contains "unreadable listing: the summary still says there is nothing to do" \
  "nothing to do" "$(cat "$UK_OUT")"

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
  "BIONIC_PLUGIN_LIST_CMD=$HANGDIR/hanging-listing" "BIONIC_DOCTOR_PROBE_SECONDS=2" > "$HG_OUT" 2>&1
HG_RC=$?
HANG_ELAPSED=$((SECONDS - HANG_START))
expect_eq "a hanging listing: doctor completes anyway, exit 0" "0" "$HG_RC"
expect_true "a hanging listing: doctor gave up near the bound rather than waiting" \
  test "$HANG_ELAPSED" -lt 10
HG_LOAD="$(awk '/=== LOAD STATE ===/,/=== PLUGIN INTEGRITY ===/' "$HG_OUT")"
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
  "BIONIC_PLUGIN_LIST_CMD=$HANGDIR/hanging-listing" > "$SL_OUT" 2>&1
SL_RC=$?
SEAMLESS_ELAPSED=$((SECONDS - SEAMLESS_START))
expect_eq "the default bound (no knob set): doctor completes anyway, exit 0" "0" "$SL_RC"
expect_true "the default bound: it waited about fifteen seconds, not forever" \
  test "$SEAMLESS_ELAPSED" -ge 14 -a "$SEAMLESS_ELAPSED" -lt 40
expect_contains "the default bound: and reported unknown with its cause" \
  "did not answer" "$(awk '/=== LOAD STATE ===/,/=== PLUGIN INTEGRITY ===/' "$SL_OUT")"

# ---------------------------------------------------------------------------
echo ""
echo "=== Group 18: DUPLICATES — two catalogs, one name (AC-9) ==="
# ---------------------------------------------------------------------------
#
# Silent duplication is the defect: nothing stops a machine holding
# `superpowers@bionic` and `superpowers@claude-plugins-official` at once, and
# which copy a session loads is then a coin flip nobody saw tossed. The registry
# knows; until now nobody asked it.

H_DUPS="$(awk '/=== DUPLICATES ===/,/=== ENVIRONMENT ===/' "$H_OUT")"
expect_contains "clean machine: the section says none" "none" "$H_DUPS"

DUP="$TMP/machine-duplicate"; plant_machine "$DUP" healthy
plant_installed_tree "$DUP/installs/superpowers-official" 14 0
jq --arg p "$DUP/installs/superpowers-official" \
   '.plugins["superpowers@claude-plugins-official"] = [ { "scope": "user", "installPath": $p, "version": "6.2.0" } ]' \
   "$DUP/claude-home/plugins/installed_plugins.json" > "$TMP/dup-reg.json" \
  && cp "$TMP/dup-reg.json" "$DUP/claude-home/plugins/installed_plugins.json"

DUP_OUT="$TMP/duplicate.out"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$DUP" > "$DUP_OUT" 2>&1
DUP_RC=$?
DUP_SECTION="$(awk '/=== DUPLICATES ===/,/=== ENVIRONMENT ===/' "$DUP_OUT")"
expect_eq "planted duplicate: doctor still exits 0" "0" "$DUP_RC"
expect_contains "planted duplicate: the colliding name is listed" "superpowers" "$DUP_SECTION"
expect_contains "planted duplicate: both catalogs are named, so the reader can tell them apart" \
  "superpowers@claude-plugins-official" "$DUP_SECTION"
# AC-9's substance: the row carries the CONSOLIDATION COMMAND, and it names the
# copy that is not bionic's — bionic's own catalog is the one this machine's
# install chose.
expect_contains "planted duplicate: the consolidation command is on the row" \
  "claude plugin uninstall superpowers@claude-plugins-official" "$DUP_SECTION"
expect_not_contains "planted duplicate: the section no longer claims none" "none" "$DUP_SECTION"

# `dup=unknown` IS A FAILURE TO LOOK, NOT A DUPLICATE (A-4.S2.8). Without jq the
# registry cannot be parsed, and silence there would be a claim of cleanliness
# that nobody earned.
U_DUPS="$(awk '/=== DUPLICATES ===/,/=== ENVIRONMENT ===/' "$U_OUT")"
expect_contains "no jq: the duplicates section reads unknown" "unknown" "$U_DUPS"
expect_contains "no jq: and names why it could not tell" "jq is not on PATH" "$U_DUPS"
expect_not_contains "no jq: an unreadable registry is not reported as clean" "none" "$U_DUPS"

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
# UNATTENDED IS SILENT. Not "declined", not "skipped because there is no
# terminal" — silent. A report nobody is reading should not carry a question
# nobody can answer, nor an explanation of why it was not asked.

QUESTION="Check for tool updates?"
expect_contains "unattended: the question is printed, verbatim and in full" \
  "$UPDATES_QUESTION" "$H"
expect_not_contains "unattended: but nothing is appended" "=== UPDATES ===" "$H"
# NO NARRATION EITHER WAY. The line is the question and nothing else — not "declined",
# not "skipped", not an explanation of what could not be reached. A reader who wants the
# check answers it; a log that nobody reads carries one unanswered line.
for _narration in "no terminal" "declined" "skipped" "not asked" "unattended"; do
  expect_not_contains "unattended: nothing is said about why (${_narration})" "$_narration" "$H"
done
# And it is the LAST thing the report says, after SUMMARY.
expect_contains "unattended: the question comes after the summary" "$UPDATES_QUESTION" \
  "$(awk '/=== SUMMARY ===/{f=1} f' "$H_OUT")"
# And nothing was asked of the package managers either — the check is what costs
# thirty seconds, so a silent No must not have paid for it.
: > "$CALLS"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" >/dev/null 2>&1
expect_eq "unattended: neither Homebrew nor npm was asked about updates" "" \
  "$(grep -E '^(brew|npm) outdated' "$CALLS" || true)"

# ── the yes path ──
: > "$CALLS"
Y_OUT="$TMP/updates-yes.out"
printf 'y\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" > "$Y_OUT" 2>&1
Y_RC=$?
Y="$(cat "$Y_OUT")"
expect_eq "yes: doctor still exits 0" "0" "$Y_RC"
expect_contains "yes: the question was asked, in the ratified words" "$QUESTION" "$Y"
expect_contains "yes: and it said what it costs, so the answer is informed" \
  "up to 30 seconds" "$Y"
expect_contains "yes: UPDATES renders" "=== UPDATES ===" "$Y"
expect_eq "yes: UPDATES is the LAST section, after SUMMARY (D-D supersedes D-A)" \
  "$(printf '%s\nUPDATES' "$EXPECTED_ROSTER")" "$(section_roster "$Y_OUT")"

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
printf 'n\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" > "$N_OUT" 2>&1
N="$(cat "$N_OUT")"
expect_contains "no: the question was still asked" "$QUESTION" "$N"
expect_not_contains "no: and nothing was appended" "=== UPDATES ===" "$N"
# Default No: an empty answer is a No, which is what [y/N] promises.
E_OUT="$TMP/updates-empty.out"
printf '\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$HEALTHY" > "$E_OUT" 2>&1
expect_not_contains "just enter: the default is No" "=== UPDATES ===" "$(cat "$E_OUT")"

# ── a manager that will not answer ──
#
# HONEST "NOT CHECKED". Homebrew hangs — offline, a slow mirror, an update of its
# own in flight — and the failure mode to avoid is a report that says nothing and
# lets the reader conclude everything is current.
SLOW_BIN="$TMP/bin-slowbrew"; mkdir -p "$SLOW_BIN"; cp -R "$FULL_BIN"/. "$SLOW_BIN"/
printf '#!/bin/bash\nexec sleep 60\n' > "$SLOW_BIN/brew"; chmod +x "$SLOW_BIN/brew"
SB_OUT="$TMP/updates-slowbrew.out"
printf 'y\n' | doctor_run "$DOCTOR_SH" "$SLOW_BIN" "$HEALTHY" "BIONIC_DOCTOR_PROBE_SECONDS=2" > "$SB_OUT" 2>&1
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
printf 'y\n' | doctor_run "$DOCTOR_SH" "$FORK_BIN" "$HEALTHY" "BIONIC_DOCTOR_PROBE_SECONDS=3" > "$FB_OUT" 2>&1
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
printf 'y\n' | doctor_run "$DOCTOR_SH" "$LEAK_BIN" "$HEALTHY" "BIONIC_DOCTOR_PROBE_SECONDS=2" >/dev/null 2>&1
sleep 9
expect_true "forking Homebrew: the grandchild died with the group rather than outliving the run" \
  test ! -f "$LEAK_MARK"

# ── the wall still holds on the path that shells out ──
UP_WALL="$TMP/wall-updates"; rm -rf "$UP_WALL"; cp -R "$HEALTHY" "$UP_WALL"
UP_BEFORE="$(fingerprint "$UP_WALL")"
printf 'y\n' | doctor_run "$DOCTOR_SH" "$FULL_BIN" "$UP_WALL" >/dev/null 2>&1
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
  "$(printf '%s\nUPDATES' "$EXPECTED_ROSTER")" "$(section_roster "$F_OUT")"
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

# ---- the command file carries the relay instruction ----
#
# The script half is useless without it: the model has to KNOW to ask the question and to
# come back with the flag. That instruction is a command-file line, and it is rendered
# from the template like every other line in that file.
if [ -f "$DOCTOR_MD" ]; then
  DMD="$(cat "$DOCTOR_MD")"
  expect_contains "doctor.md: tells the model to ask the question" "Ask the user that question" "$DMD"
  # UNQUOTED, and that is load-bearing rather than cosmetic (epic-17 W6 S9b, plan A-5.4):
  # a permission rule prefix-matches the literal command string, so the quoted spelling
  # this pin used to carry was the spelling that hit the approval wall. The agreement
  # between this line and the file's own `allowed-tools` rule is owned by
  # tests/command-permissions.test.sh; the pin here stays because the --updates relay is
  # doctor's own contract and must be provable from doctor's own suite.
  expect_contains "doctor.md: names the flag to run on a yes" \
    'bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh --updates' "$DMD"
  expect_contains "doctor.md: and to show what comes back" "UPDATES" "$DMD"
  # RENDERED, NOT HAND-EDITED — the file says so itself, and the template is where the
  # text lives. A hand edit here is what `render.sh --check` exists to catch.
  expect_true "the instruction lives in the template, not only in the rendered file" \
    grep -q -- '--updates' "${REPO}/agents-src/templates/commands/doctor.md.tmpl"
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
  BASH_MAX_TIMEOUT_MS=1800000 CLAUDE_CODE_ENABLE_TODO_TOOLS=1 > "$ENV_LIVE_OUT" 2>&1
expect_match "configured and live: the value is reported" \
  "*1800000*" "$(line_of "$ENV_LIVE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…and the session is reported as having it" \
  "*live in this session: yes*" "$(line_of "$ENV_LIVE_OUT" "BASH_MAX_TIMEOUT_MS")"

# (b) configured and NOT live — the state a restart fixes. The report has to say
# restart, because "absent" would send the user to run setup again and setup
# would find nothing to do.
ENV_STALE_OUT="$TMP/env-stale.txt"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_M" > "$ENV_STALE_OUT" 2>&1
expect_match "configured and not live: the value is still reported" \
  "*1800000*" "$(line_of "$ENV_STALE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…and the session is reported as not having it" \
  "*live in this session: no*" "$(line_of "$ENV_STALE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…named as a restart, not as a setup gap" \
  "*restart*" "$(line_of "$ENV_STALE_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_not_contains "…and the summary does not ask for a setup run over it" \
  "environment settings" "$(sed -n '/=== SUMMARY ===/,$p' "$ENV_STALE_OUT")"

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
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_GAP_M" > "$ENV_GAP_OUT" 2>&1
expect_match "absent: reported absent" \
  "*absent*" "$(line_of "$ENV_GAP_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_contains "absent: the summary names it as something setup would write" \
  "environment settings" "$(sed -n '/=== SUMMARY ===/,$p' "$ENV_GAP_OUT")"

# (d) absent from the file but live in the process — the state the retired shell
# export leaves behind. It must not read as configured: the value dies with this
# session, and the next one will not have it.
ENV_ORPHAN_OUT="$TMP/env-orphan.txt"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_GAP_M" BASH_MAX_TIMEOUT_MS=1800000 > "$ENV_ORPHAN_OUT" 2>&1
expect_match "live but not configured: reported absent from the file" \
  "*absent*" "$(line_of "$ENV_ORPHAN_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_match "…and the session is still credited with having it" \
  "*live in this session*" "$(line_of "$ENV_ORPHAN_OUT" "BASH_MAX_TIMEOUT_MS")"
expect_contains "…and setup is still named, because the next session will not have it" \
  "environment settings" "$(sed -n '/=== SUMMARY ===/,$p' "$ENV_ORPHAN_OUT")"

# READ-ONLY STILL HOLDS over the new reads. env.sh's write path exists; doctor
# must never reach it.
FP_ENV_BEFORE="$(fingerprint "$ENV_M")"
doctor_run "$DOCTOR_SH" "$FULL_BIN" "$ENV_M" > /dev/null 2>&1
expect_eq "the environment section mutates nothing" \
  "$FP_ENV_BEFORE" "$(fingerprint "$ENV_M")"

# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
