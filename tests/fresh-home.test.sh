#!/bin/bash
# FRESH HOME — the pristine-install suite (epic-18 T6; spec AC-10, AC-7).
#
# WHAT THIS SUITE OWNS, AND WHY IT EXISTS. Every other suite here drives ONE
# script against a fixture built to exercise that script's own branches. None of
# them ever asked the whole-product question: take a machine with NOTHING on it,
# run `/bionic:setup` and answer yes to everything, and is the machine then in
# the state the plugin claims to leave it in? On 2026-08-22 the answer was no —
# ccstatusline's layout file was never copied and the notebooklm skill was never
# installed — and `/bionic:doctor` said "nothing to do" over both, because every
# probe asked "is this registered" rather than "is this in the state setup leaves
# it in". Nothing in the suite could see it, because nothing in the suite ever
# started from an empty $HOME.
#
# So this suite is the missing one: empty $HOME → `setup.sh --all` all-yes →
# `doctor.sh` → assert against a MANIFEST of files, not against a report's own
# summary line → `remove.sh --all` all-yes → assert the manifest is gone.
#
# THE MANIFEST IS THE POINT. A report that says "present" is the thing under
# test, so it cannot also be the evidence. Every claim below that matters is a
# claim about BYTES on the fixture filesystem — the ccstatusline layout is
# compared to the shipped file with `cmp`, the notebooklm SKILL.md is a file test,
# settings.json's three blocks are read back with jq. Doctor's own rows are
# asserted too, but as a SECOND question ("does the report agree with the
# machine"), never as the first.
#
# AND ONE ASSERTION IS NEGATIVE, DELIBERATELY BESIDE THE POSITIVE ONES (AC-7).
# `~/.claude/CLAUDE.md` is the user's own file: bionic gave up managing memory on
# 2026-08-20 and delegates it entirely to the harness. Nothing the plugin does may
# create it. An absence proves nothing on its own — an empty $HOME is full of
# absences, and a suite whose setup silently did nothing would pass such a check
# perfectly. It earns its keep only because it sits in the SAME run as the
# positive manifest above it: the run that proves setup wrote seven things is the
# run that proves it did not write this eighth.
#
# HERMETIC, AND WHAT THAT COSTS. `$HOME` is a fixture directory and PATH is
# REPLACED (not prefixed) by a bin dir this suite builds, so a real brew, npm, uv
# or claude on this machine can never be reached by accident. Nothing here
# touches the network and nothing here touches the real $HOME. The roots the
# payload reads are NOT overridden one by one — HOME is set and every default
# hangs off it, which is the whole point: the production path is what resolves
# `~/.claude/settings.json`, `~/.config/ccstatusline/settings.json` and
# `~/.claude/skills/`, and a suite that pointed each of them somewhere by hand
# would be testing its own env block instead of the product's path resolution.
#
# THE SHIMS ARE PACKAGE MANAGERS, NOT SEAMS. `brew`, `npm`, `uv`, `npx` and
# `claude` are faked, because installing nine Homebrew formulae is not what this
# suite is measuring and because a suite that reached the network would not be a
# suite. What is NOT faked is anything inside the payload: setup.sh, doctor.sh,
# remove.sh and every library run exactly as shipped, `check_dep` really probes
# the fixture machine, and the answers are read out of the fixture's own files.
# The fakes are STATEFUL — `brew install ripgrep` really puts an `rg` on the
# fixture PATH, `npm install -g` is visible to a later `npm list -g`, `claude
# plugin install` writes the registry a later `plugin list` renders — because a
# stateless stub would make every "then doctor reports it present" assertion
# vacuous.
#
# THE PACKAGE→BINARY MAP IS READ FROM THE DEPENDENCY TABLE, never restated. The
# table says `rg` installs from `brew:ripgrep` and `notebooklm` from
# `uv:notebooklm-py`; the shims resolve a target back to the name doctor will
# probe by reading that table. A row added to deps.sh therefore arrives here with
# no edit, as long as its KIND is one the shims below already speak. A row of a
# NEW kind (a github-skill, a marketplace plugin) needs a new arm in the shim
# block — that is the one place this suite has to be extended by hand.
#
# WHY IT IS NOT IN tests/run.sh YET. It is registered at T10, once the arms it
# exercises have merged. Until then it is RED on purpose: see the header of
# Group 3.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh): containment is bash `[[ == * ]]` in-process,
# and grep runs against FILE arguments only.
#
# Usage: bash tests/fresh-home.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
SETUP_SH="${PAYLOAD}/scripts/setup.sh"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"
REMOVE_SH="${PAYLOAD}/scripts/remove.sh"
LIB_DIR="${PAYLOAD}/scripts/lib"
CCSTATUSLINE_SHIPPED="${PAYLOAD}/ccstatusline/settings.json"

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

HOME_FIX="$TMP/home"
BIN="$TMP/bin"
SHIMSRC="$TMP/shimsrc"
STATE="$TMP/state"          # OUTSIDE the fixture HOME: never part of the manifest
CALLS="$TMP/calls.log"
TMPDIR_FIX="$TMP/tmpdir"
mkdir -p "$BIN" "$SHIMSRC" "$STATE" "$TMPDIR_FIX"

# ---------------------------------------------------------------------------
# The bin dir: real tools the payload legitimately needs, then the fakes.
# ---------------------------------------------------------------------------
#
# PATH is REPLACED by this directory for every run below, so this list is the
# complete set of programs the payload can reach. `sleep` earns its place because
# `detect_bounded` degrades to an unbounded wait without it; `readlink` because
# every writer resolves a symlinked target before staging, and a PATH without it
# would measure the degradation rather than the behaviour.
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod stat readlink ls tr head tail sort uniq wc \
            jq mktemp find xargs shasum uname date touch diff cmp printf true false sleep; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BIN}/${real}" 2>/dev/null
done

# ─── The package→binary map, read from the dependency table ──────────────────
#
# One `<install-target> <probe-name>` line per installable row. `brew:ripgrep`
# installs the binary doctor probes as `rg`; `uv:notebooklm-py` installs the one
# probed as `notebooklm`. The shims resolve through this file rather than
# carrying a second copy of the roster.
PKG_MAP="$TMP/pkg-map"
build_pkg_map() {
  : > "$PKG_MAP"
  local n mech target
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    mech="$(dep_query dep_field "$n" mechanism)"
    case "$mech" in http*) continue ;; esac
    target="${mech#*:}"
    printf '%s %s\n' "$target" "$n" >> "$PKG_MAP"
  done <<< "$( { dep_query dep_names_class basic; dep_query dep_names_class extra; } )"
}

# Read one fact back out of the dependency table, with the fixture's own roots.
dep_query() {
  env -i HOME="$HOME_FIX" PATH="$BIN" \
    bash -c '. "$1"; shift; "$@"' _ "${LIB_DIR}/deps.sh" "$@" 2>/dev/null
}

# ─── The fake-binary factory ─────────────────────────────────────────────────
#
# `_mkfake <install-target>` materialises the binary that target installs, and
# `_rmfake <install-target>` takes it away. Both are on the fixture PATH because
# the package-manager shims call them; nothing in the payload can reach them by
# accident, since nothing in the payload knows the names.
#
# A target with a hand-written shim in $BIONIC_TEST_SHIMSRC gets that shim (the
# tools whose sub-commands matter: `uv`, `notebooklm`). Everything else gets a
# recorder that answers `--version` and exits 0, which is all `_dep_check_brew_dep`
# and `_dep_version_from_probe` ever ask of it.
cat > "${BIN}/_mkfake" <<'MKFAKE'
#!/bin/bash
target="${1:-}"; [ -n "$target" ] || exit 1
name="$(awk -v t="$target" '$1 == t { print $2; exit }' "$BIONIC_TEST_PKG_MAP")"
[ -n "$name" ] || name="$target"
if [ -f "${BIONIC_TEST_SHIMSRC}/${name}" ]; then
  cp "${BIONIC_TEST_SHIMSRC}/${name}" "${BIONIC_TEST_BIN}/${name}"
else
  { printf '#!/bin/bash\n'
    printf 'echo "%s $*" >> "$BIONIC_TEST_CALLS"\n' "$name"
    printf 'case "${1:-}" in --version|-V|-v|version) echo "%s 9.9.9" ;; esac\n' "$name"
    printf 'exit 0\n'
  } > "${BIONIC_TEST_BIN}/${name}"
fi
chmod +x "${BIONIC_TEST_BIN}/${name}"
exit 0
MKFAKE
chmod +x "${BIN}/_mkfake"

cat > "${BIN}/_rmfake" <<'RMFAKE'
#!/bin/bash
target="${1:-}"; [ -n "$target" ] || exit 1
name="$(awk -v t="$target" '$1 == t { print $2; exit }' "$BIONIC_TEST_PKG_MAP")"
[ -n "$name" ] || name="$target"
rm -f "${BIONIC_TEST_BIN}/${name}"
exit 0
RMFAKE
chmod +x "${BIN}/_rmfake"

# ─── uv, and why it is hand-written ──────────────────────────────────────────
#
# `uv` is installed by brew (a `basic` row) AND is the mechanism the notebooklm
# extra installs through, so the binary brew materialises has to know `tool
# install`. It is written into the shim source rather than generated, and
# `_mkfake uv` copies it.
cat > "${SHIMSRC}/uv" <<'UVSHIM'
#!/bin/bash
echo "uv $*" >> "$BIONIC_TEST_CALLS"
case "${1:-}" in
  --version|version) echo "uv 9.9.9"; exit 0 ;;
  tool)
    case "${2:-}" in
      install)   _mkfake "${3:-}"; exit $? ;;
      uninstall) _rmfake "${3:-}"; exit $? ;;
    esac
    exit 1 ;;
  sync)
    # The `uv-project` kind (epic-18 T3's excalidraw-renderer row): the argv is
    # `uv sync --project <dir>`, and what makes the row PRESENT is a real venv at
    # `<dir>/.venv`, because `_dep_check_uv_project` is a filesystem test, not a
    # call back into this binary. A recorder that only logged the call would leave
    # the row permanently absent no matter how many times it "installed".
    proj=""; prev=""
    for a in "$@"; do
      [ "$prev" = "--project" ] && proj="$a"
      prev="$a"
    done
    if [ -n "$proj" ]; then
      mkdir -p "${proj}/.venv/bin"
      printf '#!/bin/bash\nexit 0\n' > "${proj}/.venv/bin/python"
      chmod +x "${proj}/.venv/bin/python"
      printf 'version = 9.9.9\n' > "${proj}/.venv/pyvenv.cfg"
    fi
    exit 0 ;;
esac
exit 0
UVSHIM
chmod +x "${SHIMSRC}/uv"

# TODO(T10 final regression, once T4 and T12 merge): two more dep `kind`s arrive with
# those merges — T4's roster rows add a `github-skill` kind and T12's notification
# channel row adds a `marketplace-plugin` kind. Neither has a shim arm yet. If this
# suite reds on a row of either kind, add its arm here the same way `sync` was added
# above — that is the one place this suite is extended by hand (see the file header).

# ─── notebooklm, and the one thing it does that matters here ─────────────────
#
# THE SECOND HALF OF THE INSTALL. `uv tool install notebooklm-py` puts a CLI on
# PATH; the old bootstrap then ran `notebooklm skill install`, which is what wrote
# `~/.claude/skills/notebooklm/SKILL.md`. That second command is the step the
# plugin port dropped. This shim implements it — writing a real file into the
# fixture HOME — so the assertion "the SKILL.md is there after setup" measures
# whether SETUP RAN THE COMMAND, and nothing else. It is the same reason the brew
# shim really creates binaries: a stub that wrote nothing would make the
# assertion unfalsifiable in the wrong direction.
cat > "${SHIMSRC}/notebooklm" <<'NBSHIM'
#!/bin/bash
echo "notebooklm $*" >> "$BIONIC_TEST_CALLS"
case "${1:-}" in
  --version|version) echo "notebooklm 9.9.9"; exit 0 ;;
  skill)
    case "${2:-}" in
      install)
        d="${HOME}/.claude/skills/notebooklm"
        mkdir -p "$d" || exit 1
        { printf -- '---\n'
          printf 'name: notebooklm\n'
          printf 'description: NotebookLM client — written by the notebooklm CLI shim.\n'
          printf -- '---\n'
        } > "${d}/SKILL.md" || exit 1
        echo "installed the notebooklm skill into ${d}"
        exit 0 ;;
    esac
    exit 1 ;;
esac
exit 0
NBSHIM
chmod +x "${SHIMSRC}/notebooklm"

# ─── brew ────────────────────────────────────────────────────────────────────
cat > "${BIN}/brew" <<'BREWSHIM'
#!/bin/bash
echo "brew $*" >> "$BIONIC_TEST_CALLS"
case "${1:-}" in
  install)
    for a in "$@"; do
      case "$a" in install|--cask|--quiet|-*) continue ;; esac
      _mkfake "$a"
    done
    exit 0 ;;
  outdated) exit 0 ;;
esac
exit 0
BREWSHIM
chmod +x "${BIN}/brew"

# ─── npm ─────────────────────────────────────────────────────────────────────
#
# Stateful, because `_dep_check_npm_global` reads `npm list -g`'s EXIT CODE as
# the presence answer: a recorder that exited 0 with no output would report every
# npm package as already installed and skip the arm that proves they install.
cat > "${BIN}/npm" <<'NPMSHIM'
#!/bin/bash
echo "npm $*" >> "$BIONIC_TEST_CALLS"
S="${BIONIC_TEST_STATE}/npm-global"
[ -f "$S" ] || : > "$S"
sub="${1:-}"; shift 2>/dev/null || true
pkgs=""
for a in "$@"; do
  case "$a" in -*) continue ;; esac
  pkgs="${pkgs}${a}"$'\n'
done
case "$sub" in
  list)
    p="${pkgs%%$'\n'*}"
    [ -n "$p" ] || exit 0
    if grep -qxF -- "$p" "$S"; then
      echo "/fixture/lib"
      echo "└── ${p}@1.0.0"
      exit 0
    fi
    exit 1 ;;
  install)
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      grep -qxF -- "$p" "$S" || printf '%s\n' "$p" >> "$S"
    done <<< "$pkgs"
    exit 0 ;;
  uninstall)
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      grep -vxF -- "$p" "$S" > "${S}.t" 2>/dev/null
      mv "${S}.t" "$S"
    done <<< "$pkgs"
    exit 0 ;;
  outdated) exit 0 ;;
esac
exit 0
NPMSHIM
chmod +x "${BIN}/npm"

# ─── pnpm: a plain recorder ──────────────────────────────────────────────────
#
# Nothing reads a pnpm store back: `_dep_check_pnpm_store` answers `unknown` by
# construction, because a content-addressable cache has no installed-state. A
# shim that faked one would be inventing a surface the payload does not have.
{ printf '#!/bin/bash\n'
  printf 'echo "pnpm $*" >> "$BIONIC_TEST_CALLS"\n'
  printf 'exit 0\n'
} > "${BIN}/pnpm"
chmod +x "${BIN}/pnpm"

# ─── npx, which has one machine effect the report reads back ─────────────────
#
# `npx --yes playwright@latest install chromium` is the `playwright-chromium`
# row's install, and its probe is a filesystem marker under the browser cache —
# so a pure recorder would leave that row absent after an all-yes setup and make
# "present" unprovable in the wrong direction. The marker this writes is the same
# one `_dep_check_playwright_browser` looks for, at the cache root the payload
# resolves (overridden below so the path does not depend on the runner's OS).
cat > "${BIN}/npx" <<'NPXSHIM'
#!/bin/bash
echo "npx $*" >> "$BIONIC_TEST_CALLS"
for a in "$@"; do
  if [ "$a" = "chromium" ]; then
    d="${BIONIC_PLAYWRIGHT_CACHE:?}/chromium-1187"
    mkdir -p "$d" && : > "${d}/INSTALLATION_COMPLETE"
  fi
done
exit 0
NPXSHIM
chmod +x "${BIN}/npx"

# ─── claude ──────────────────────────────────────────────────────────────────
#
# The stateful CLI fake. Three pieces of state, all outside the fixture HOME
# except the one the CLI genuinely owns there:
#
#   $BIONIC_TEST_STATE/plugins   one `<id> <enabled>` line per installed plugin —
#                                what `plugin list` renders, in both shapes
#   $BIONIC_TEST_STATE/mcp       one server name per line
#   ~/.claude/plugins/installed_plugins.json
#                                the registry the payload's own probes read. The
#                                real CLI writes it, so the fake writes it too —
#                                and it is inside HOME on purpose, because that
#                                is where `_dep_installed_json` looks.
#
# INSTALLING BIONIC BRINGS ITS DECLARED DEPENDENCIES, because that is what the
# harness does: the two `core` rows are resolved by the CLI, not by setup. The
# versions are chosen to satisfy the table's own constraints, so a `violation`
# verdict in the report would be a real finding rather than a fixture artefact.
cat > "${BIN}/claude" <<'CLAUDESHIM'
#!/bin/bash
echo "claude $*" >> "$BIONIC_TEST_CALLS"
STATE_FILE="${BIONIC_TEST_STATE}/plugins"
MCP_FILE="${BIONIC_TEST_STATE}/mcp"
REG="${HOME}/.claude/plugins/installed_plugins.json"
[ -f "$STATE_FILE" ] || : > "$STATE_FILE"
[ -f "$MCP_FILE" ] || : > "$MCP_FILE"

_reg_init() {
  mkdir -p "${REG%/*}"
  [ -f "$REG" ] || printf '%s\n' '{"version":2,"plugins":{}}' > "$REG"
}
_dep_version_for() {
  case "${1:-}" in
    superpowers)  echo "6.3.0" ;;
    agent-skills) echo "0.6.0" ;;
    *)            echo "1.0.0" ;;
  esac
}
_reg_add() {  # <id>
  local id="$1" name="${1%%@*}" ver path tmp
  ver="$(_dep_version_for "$name")"
  path="${BIONIC_TEST_STATE}/installed/${name}"
  mkdir -p "$path"
  _reg_init
  tmp="${REG}.tmp"
  jq --arg k "$id" --arg v "$ver" --arg p "$path" \
    '.plugins[$k] = [{"scope":"user","installPath":$p,"version":$v}]' "$REG" > "$tmp" && mv "$tmp" "$REG"
}
_reg_del() {  # <id>
  local id="$1" tmp
  _reg_init
  tmp="${REG}.tmp"
  jq --arg k "$id" 'del(.plugins[$k])' "$REG" > "$tmp" && mv "$tmp" "$REG"
}
_state_add() {  # <id>
  grep -q "^$1 " "$STATE_FILE" 2>/dev/null || printf '%s true\n' "$1" >> "$STATE_FILE"
}
_state_del() {  # <id>
  grep -v "^$1 " "$STATE_FILE" > "${STATE_FILE}.t" 2>/dev/null
  mv "${STATE_FILE}.t" "$STATE_FILE"
}
_install_one() {  # <id>
  _state_add "$1"; _reg_add "$1"
}
# Whatever is installed and is not bionic, once bionic is gone: the CLI's own
# notion of an orphaned auto-installed dependency.
_orphans() {
  grep -q '^bionic@' "$STATE_FILE" 2>/dev/null && return 0
  awk '{ print $1 }' "$STATE_FILE"
}

case "${1:-}" in
  plugin|plugins)
    case "${2:-}" in
      list)
        case " $* " in
          *" --json "*)
            sep=""; printf '['
            while read -r id en; do
              [ -n "$id" ] || continue
              printf '%s{"id":"%s","version":"1.0.0","scope":"user","enabled":%s}' "$sep" "$id" "$en"
              sep=","
            done < "$STATE_FILE"
            printf ']\n'
            ;;
          *)
            printf 'Installed plugins:\n\n'
            while read -r id en; do
              [ -n "$id" ] || continue
              if [ "$en" = "true" ]; then st='✔ enabled'; else st='✘ not enabled'; fi
              printf '  ❯ %s\n    Version: 1.0.0\n    Scope: user\n    Status: %s\n\n' "$id" "$st"
            done < "$STATE_FILE"
            ;;
        esac
        exit 0 ;;
      install)
        id=""
        for a in "$@"; do case "$a" in *@*) id="$a"; break ;; esac; done
        [ -n "$id" ] || exit 1
        _install_one "$id"
        case "$id" in
          bionic@*)
            mk="${id#*@}"
            _install_one "superpowers@${mk}"
            _install_one "agent-skills@${mk}"
            ;;
        esac
        exit 0 ;;
      uninstall)
        id=""
        for a in "$@"; do case "$a" in *@*) id="$a"; break ;; esac; done
        [ -n "$id" ] || exit 1
        grep -q "^${id} " "$STATE_FILE" 2>/dev/null || exit 1
        _state_del "$id"; _reg_del "$id"
        exit 0 ;;
      enable)
        id=""
        for a in "$@"; do case "$a" in *@*) id="$a"; break ;; esac; done
        [ -n "$id" ] || exit 1
        awk -v id="$id" '{ if ($1 == id) print $1, "true"; else print }' "$STATE_FILE" > "${STATE_FILE}.t" \
          && mv "${STATE_FILE}.t" "$STATE_FILE"
        exit 0 ;;
      prune)
        case " $* " in
          *" --dry-run "*) _orphans; exit 0 ;;
        esac
        for id in $(_orphans); do _state_del "$id"; _reg_del "$id"; done
        exit 0 ;;
    esac
    exit 1 ;;
  mcp)
    case "${2:-}" in
      get)
        [ -n "${3:-}" ] || exit 1
        grep -qxF -- "$3" "$MCP_FILE" && exit 0
        exit 1 ;;
      add)
        [ -n "${3:-}" ] || exit 1
        grep -qxF -- "$3" "$MCP_FILE" || printf '%s\n' "$3" >> "$MCP_FILE"
        exit 0 ;;
      remove)
        [ -n "${3:-}" ] || exit 1
        grep -vxF -- "$3" "$MCP_FILE" > "${MCP_FILE}.t" 2>/dev/null
        mv "${MCP_FILE}.t" "$MCP_FILE"
        exit 0 ;;
    esac
    exit 0 ;;
esac
exit 0
CLAUDESHIM
chmod +x "${BIN}/claude"

# ---------------------------------------------------------------------------
# The fixture, and the one way anything is run against it.
# ---------------------------------------------------------------------------
#
# `fresh_home` is the whole premise: a directory with NOTHING in it. No
# `.claude`, no `.config`, no rc file, no CLAUDE.md. Every path the payload
# touches below is one it created itself.

fresh_home() {
  rm -rf "$HOME_FIX" "$STATE" "$TMPDIR_FIX"
  mkdir -p "$HOME_FIX" "$STATE" "$TMPDIR_FIX"
  : > "$CALLS"
}

# ONE ENV BLOCK FOR ALL THREE SCRIPTS, and it deliberately overrides no root.
# `HOME` is the fixture and everything else defaults off it — which is exactly
# the resolution the incident happened in. `CLAUDE_PLUGIN_ROOT` and its BIONIC_
# twin name the real payload, because that is what an installed plugin's scripts
# see and what the ccstatusline layout is copied FROM.
run_payload() {  # <script> [args...] — stdin carries the answers
  local script="$1"; shift
  env -i \
    HOME="$HOME_FIX" \
    PATH="$BIN" \
    TMPDIR="$TMPDIR_FIX" \
    BIONIC_TEST_CALLS="$CALLS" \
    BIONIC_TEST_STATE="$STATE" \
    BIONIC_TEST_BIN="$BIN" \
    BIONIC_TEST_SHIMSRC="$SHIMSRC" \
    BIONIC_TEST_PKG_MAP="$PKG_MAP" \
    BIONIC_PLUGIN_ROOT="$PAYLOAD" \
    CLAUDE_PLUGIN_ROOT="$PAYLOAD" \
    BIONIC_PLAYWRIGHT_CACHE="${HOME_FIX}/.cache/ms-playwright" \
    BIONIC_DOCTOR_PROBE_SECONDS=5 \
    bash "$script" "$@" 2>&1
}

YES="$(for _ in $(seq 1 80); do printf 'y\n'; done)"

SETTINGS="${HOME_FIX}/.claude/settings.json"
CCS_CONFIG="${HOME_FIX}/.config/ccstatusline/settings.json"
NB_SKILL="${HOME_FIX}/.claude/skills/notebooklm/SKILL.md"
GLOBAL_MEMORY="${HOME_FIX}/.claude/CLAUDE.md"

jqf() {  # <jq-program> — read one value out of the fixture settings.json
  [ -f "$SETTINGS" ] || { echo "<no settings.json>"; return 0; }
  jq -r "$1" "$SETTINGS" 2>/dev/null || echo "<unreadable>"
}

# One `=== SECTION ===` block out of a doctor report, by name.
doctor_section() {  # <file> <name>
  awk -v want="=== $2 ===" '
    $0 == want { on = 1; next }
    on && /^=== / { on = 0 }
    on { print }
  ' "$1"
}

# The `present` column of one DEPENDENCIES row. Read out of that section only,
# so a name appearing in the degradation map cannot answer for it.
dep_present() {  # <report-file> <name>
  doctor_section "$1" "DEPENDENCIES" | awk -v n="$2" 'NF >= 6 && $2 == n { print $3; exit }'
}

# ---------------------------------------------------------------------------
# Group 1 — the suite's own preconditions.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 1: preconditions ==="

expect_true "payload/scripts/setup.sh exists"  test -f "$SETUP_SH"
expect_true "payload/scripts/doctor.sh exists" test -f "$DOCTOR_SH"
expect_true "payload/scripts/remove.sh exists" test -f "$REMOVE_SH"
expect_true "the shipped ccstatusline layout exists" test -f "$CCSTATUSLINE_SHIPPED"
expect_true "jq is available to this suite" command -v jq

fresh_home
build_pkg_map
expect_true "the package→binary map was built from the dependency table" test -s "$PKG_MAP"
expect_eq "the map resolves brew:ripgrep to the name doctor probes" "rg" \
  "$(awk '$1 == "ripgrep" { print $2 }' "$PKG_MAP")"
expect_eq "the map resolves uv:notebooklm-py to the name doctor probes" "notebooklm" \
  "$(awk '$1 == "notebooklm-py" { print $2 }' "$PKG_MAP")"

# The premise, asserted rather than assumed: a $HOME with nothing in it.
expect_eq "the fixture HOME starts empty" "" \
  "$(find "$HOME_FIX" -mindepth 1 2>/dev/null)"

# ---------------------------------------------------------------------------
# Group 2 — setup --all against an empty $HOME.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 2: setup --all on a pristine machine ==="

SETUP_OUT="$TMP/setup.txt"
printf '%s' "$YES" | run_payload "$SETUP_SH" --all > "$SETUP_OUT" 2>&1
SETUP_RC=$?

expect_eq "setup exits 0" "0" "$SETUP_RC"

# The consented plan reached the package managers, which is what makes every
# "present" below a measurement rather than a fixture that was already true.
expect_match "the plugin install reached the CLI" \
  '*plugin install bionic@bionic*' "$(cat "$CALLS")"
expect_match "the substrate install reached brew" '*brew install*' "$(cat "$CALLS")"

# ---------------------------------------------------------------------------
# Group 3 — THE MANIFEST (AC-10b, AC-7).
#
# RED ON PURPOSE, TODAY, FOR TWO NAMED REASONS. Until T1 and T2 land, two of the
# assertions below fail and they are the whole reason this suite exists:
#
#   ccstatusline-config-missing  `_dep_install_statusline` records the statusLine
#                                COMMAND and never copies the layout file the
#                                payload ships, so ~/.config/ccstatusline/ does
#                                not exist on a machine setup just finished with.
#   notebooklm-skill-missing     the uv-tool arm installs the CLI and never runs
#                                `notebooklm skill install`, so
#                                ~/.claude/skills/notebooklm/SKILL.md is absent.
#
# Everything else in this group passes on the unfixed tree. A red here for any
# OTHER assertion is a fixture bug, not the repro.
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 3: the manifest setup is supposed to leave ==="

# ── ccstatusline: both halves ──
expect_true "manifest: settings.json exists" test -f "$SETTINGS"
expect_match "manifest: settings.json records the ccstatusline statusLine command" \
  '*ccstatusline*' "$(jqf '.statusLine.command // ""')"
expect_true "manifest: ~/.config/ccstatusline/settings.json exists [ccstatusline-config-missing]" \
  test -f "$CCS_CONFIG"
expect_true "manifest: ~/.config/ccstatusline/settings.json matches the shipped layout [ccstatusline-config-missing]" \
  cmp -s "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"

# ── notebooklm: both halves ──
expect_match "manifest: the notebooklm CLI install reached uv" \
  '*uv tool install notebooklm-py*' "$(cat "$CALLS")"
expect_true "manifest: ~/.claude/skills/notebooklm/SKILL.md exists [notebooklm-skill-missing]" \
  test -f "$NB_SKILL"

# ── the environment block ──
ENV_OK=yes; ENV_DETAIL=""
while IFS= read -r key; do
  [ -n "$key" ] || continue
  want="$(env -i HOME="$HOME_FIX" PATH="$BIN" bash -c '. "$1"; env_default "$2"' _ "${LIB_DIR}/env.sh" "$key" 2>/dev/null)"
  have="$(jqf ".env.\"${key}\" // \"\"")"
  [ "$have" = "$want" ] || { ENV_OK=no; ENV_DETAIL="${ENV_DETAIL}${key}: want '${want}', got '${have}'; "; }
done <<< "$(env -i HOME="$HOME_FIX" PATH="$BIN" bash -c '. "$1"; printf "%s\n" $ENV_KEYS' _ "${LIB_DIR}/env.sh" 2>/dev/null)"
expect_eq "manifest: settings.json carries every one of bionic's environment names" "yes" "$ENV_OK"
[ "$ENV_OK" = "yes" ] || echo "      $ENV_DETAIL"

# ── the permission block and the default mode ──
expect_match "manifest: settings.json carries bionic's permission marker block" \
  '*bionic-profile-begin*bionic-profile-end*' \
  "$(jqf '[.permissions.allow[]? | select(test("bionic-profile-"))] | join(" ")')"
expect_eq "manifest: the default permission mode is auto" "auto" "$(jqf '.permissions.defaultMode // ""')"

# ── AC-7: the negative, deliberately beside the positives above ──
#
# Absence proves nothing on its own; it proves something HERE because the same
# run just proved setup wrote the six things above it.
expect_false "manifest: ~/.claude/CLAUDE.md was NOT created — the plugin never touches it (AC-7)" \
  test -e "$GLOBAL_MEMORY"
expect_false "manifest: no CLAUDE.md was written at the top of \$HOME either (AC-7)" \
  test -e "${HOME_FIX}/CLAUDE.md"
expect_eq "manifest: nothing in the run even names the global memory file (AC-7)" "" \
  "$(grep -n 'CLAUDE\.md' "$SETUP_OUT" 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Group 4 — doctor agrees with the machine (AC-10a, AC-10c).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 4: doctor on the machine setup just built ==="

DOC1="$TMP/doctor-after-setup.txt"
run_payload "$DOCTOR_SH" < /dev/null > "$DOC1" 2>&1
DOC1_RC=$?
expect_eq "doctor exits 0" "0" "$DOC1_RC"

# Every basic and extra row, read from the table rather than restated here.
#
# ONE MECHANISM ANSWERS SOMETHING OTHER THAN `yes`, and it is not an exception
# made for a row that would not pass. `pnpm-store` has no presence surface at all
# — a content-addressable cache is not an install — so `_dep_check_pnpm_store`
# returns `unknown` on every machine, warm or cold. Asserting `yes` there would
# demand a lie from the probe; asserting nothing would let a genuinely broken row
# through. So the expectation is keyed on the KIND, read from the same table as
# the roster, and it is still an equality against a stated value.
for cls in basic extra; do
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ "$(dep_query dep_field "$name" kind)" = "pnpm-store" ]; then
      expect_eq "doctor: ${cls} row ${name} reports the honest unknown (a cache has no presence surface)" \
        "unknown" "$(dep_present "$DOC1" "$name")"
    else
      expect_eq "doctor: ${cls} row ${name} reports present" "yes" "$(dep_present "$DOC1" "$name")"
    fi
  done <<< "$(dep_query dep_names_class "$cls")"
done

expect_match "doctor: the load state is loaded" \
  '*loaded*' "$(doctor_section "$DOC1" "LOAD STATE")"
expect_match "doctor: the permission profile is applied and current" \
  '*identical*' "$(doctor_section "$DOC1" "PERMISSION PROFILE")"


# ---------------------------------------------------------------------------
# Group 5 — remove --all undoes the manifest (AC-10, the second half).
# ---------------------------------------------------------------------------

echo ""
echo "=== Group 5: remove --all takes the manifest back off ==="

# Captured BEFORE the teardown, because the post-remove absence of a file that
# was never created proves nothing. Each removal claim below is the conjunction:
# it was there after setup, AND it is gone after remove.
CCS_WAS_THERE=no; [ -f "$CCS_CONFIG" ] && CCS_WAS_THERE=yes
NB_WAS_THERE=no;  [ -f "$NB_SKILL" ]   && NB_WAS_THERE=yes

REMOVE_OUT="$TMP/remove.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$REMOVE_OUT" 2>&1
REMOVE_RC=$?
expect_eq "remove exits 0" "0" "$REMOVE_RC"

CCS_GONE=no; [ -e "$CCS_CONFIG" ] || CCS_GONE=yes
NB_GONE=no;  [ -e "$NB_SKILL" ]   || NB_GONE=yes

expect_eq "remove: the ccstatusline layout was installed and is now gone [ccstatusline-config-missing]" \
  "yes yes" "${CCS_WAS_THERE} ${CCS_GONE}"
expect_eq "remove: the notebooklm skill was installed and is now gone [notebooklm-skill-missing]" \
  "yes yes" "${NB_WAS_THERE} ${NB_GONE}"

expect_eq "remove: the statusLine record is gone from settings.json" "" \
  "$(jqf 'if has("statusLine") then "statusLine is still recorded" else "" end')"
expect_eq "remove: bionic's environment names are gone from settings.json" "" \
  "$(jqf '[.env // {} | keys[] | select(startswith("CLAUDE_CODE_") or startswith("BASH_MAX_"))] | join(" ")')"
expect_eq "remove: the permission marker block is gone from settings.json" "" \
  "$(jqf '[.permissions.allow[]? | select(test("bionic-profile-"))] | join(" ")')"

# AC-7 again, from the other direction: a teardown that removed a file the plugin
# never wrote would be the 2026-08-20 mistake repeated.
expect_false "remove: ~/.claude/CLAUDE.md is still not a file this plugin touches (AC-7)" \
  test -e "$GLOBAL_MEMORY"


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
