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
# `~/.claude/CLAUDE.md` IS THE USER'S OWN FILE, AND SINCE wave-27 (D16) SETUP OFFERS
# ONE THING FOR IT: bionic's working principles, between markers, written only on
# a yes. Before that, AC-7 held that nothing the plugin does may create the file
# (bionic gave up managing memory on 2026-08-20). The all-yes run now does create
# it, so the manifest asserts it holds EXACTLY bionic's block and nothing else, and
# Group 5 asserts remove takes it back to no file at all. The negative that
# survives is `$HOME/CLAUDE.md`, a file no item names, beside the positive.
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
# REVIVED AND RAISED, epic-18 wave-03 (Chris D2, 2026-08-23). This suite was
# deleted with eighteen others on the reliability ruling — "if the tests cannot
# be made to fail, then the tests are no good" — and brought back on the
# condition that it be fixed in the same act. Three things changed. The rows that
# pinned a REPORT'S WORDING were rewritten to read a row's state marker, or
# deleted where the claim was already carried by a claim about bytes. Every
# negative now has a positive on the same extractor and the same fixture, and no
# extractor's empty return is read as an answer before that extractor has been
# seen to return something (.claude/rules/test-harness.md,
# "Anti-vacuity"). And the manifest grew the rc item — the
# `claude()` shell function wave-03 added to setup's roster — because a
# pristine-install manifest that does not carry setup's newest write target is
# describing last month's product.
#
# WHY THE FIXTURE $HOME IS NOT QUITE EMPTY ANY MORE. It starts empty, and that is
# still asserted; then exactly ONE file is planted, a `.zshrc` holding three lines
# that are not bionic's. An rc item cannot be measured on a machine with no rc,
# and a machine with no rc is not the pristine case anyway — a zsh user has a
# .zshrc before they have bionic. The plant is the USER'S file, and every rc
# assertion below is about what bionic did, and did not do, to it.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below
# (tests/assert-helper-race.test.sh): containment is bash `[[ == * ]]` in-process,
# and grep runs against FILE arguments only.
#
# Usage: bash tests/fresh-home.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
SETUP_SH="${PAYLOAD}/scripts/setup.sh"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"
REMOVE_SH="${PAYLOAD}/scripts/remove.sh"
LIB_DIR="${PAYLOAD}/scripts/lib"
CCSTATUSLINE_SHIPPED="${PAYLOAD}/ccstatusline/settings.json"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# HARD REQUIREMENTS, NOT ASSERTIONS. A machine without these cannot answer the
# suite's questions at all, and a red row would report a missing tool as a defect
# in the product. Same guard shape as tests/rc-item.test.sh, which needs zsh for
# the same reason: the rc rows ask the shell's own parser whether the file it
# would source is still a shell script.
command -v jq  >/dev/null 2>&1 || { echo "fresh-home.test.sh: jq is required"; exit 1; }
command -v zsh >/dev/null 2>&1 || { echo "fresh-home.test.sh: zsh is required — the rc rows run the shell's parser"; exit 1; }

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
            jq mktemp find xargs shasum uname date touch diff cmp printf true false sleep dirname; do
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
    # The `uv-project` kind (epic-18 T3's excalidraw-renderer row; VENV task,
    # AC-17, epic-20 wave-bionic-1.4.0): the argv is `uv sync --project <dir>`,
    # and what makes the row PRESENT is a real venv, because `_dep_check_uv_project`
    # is a filesystem test, not a call back into this binary. A recorder that only
    # logged the call would leave the row permanently absent no matter how many
    # times it "installed".
    #
    # WHERE THE VENV LANDS IS `$UV_PROJECT_ENVIRONMENT`, NOT `<dir>/.venv` (AC-17).
    # Real `uv sync` honours that env var when set, writing the venv there instead
    # of the project-relative default — that is the whole mechanism `deps.sh` now
    # relies on to keep the venv off the plugin's own (version-numbered, moving)
    # tree. This shim records the value it was called with so the RED test can see
    # whether `deps.sh` ever set it, and refuses to fall back to `<dir>/.venv` —
    # a fallback here would let a suite pass while the real export never happened.
    echo "UV_PROJECT_ENVIRONMENT=${UV_PROJECT_ENVIRONMENT:-<unset>}" >> "$BIONIC_TEST_CALLS"
    proj=""; prev=""
    for a in "$@"; do
      [ "$prev" = "--project" ] && proj="$a"
      prev="$a"
    done
    [ -n "$proj" ] || exit 0
    [ -f "${proj}/uv.lock" ] || exit 1
    if [ -n "${UV_PROJECT_ENVIRONMENT:-}" ]; then
      mkdir -p "${UV_PROJECT_ENVIRONMENT}/bin"
      printf '#!/bin/bash\nexit 0\n' > "${UV_PROJECT_ENVIRONMENT}/bin/python"
      chmod +x "${UV_PROJECT_ENVIRONMENT}/bin/python"
      printf 'version = 9.9.9\n' > "${UV_PROJECT_ENVIRONMENT}/pyvenv.cfg"
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
# CORRECTED 2026-08-22 (Step-6 critic F1). What this note used to say — that
# `_dep_check_pnpm_store` answers `unknown` by construction because a
# content-addressable cache has no installed-state — is exactly the premise the
# 2026-08-22 ruling reversed: the probe reads `pnpm store path` and then
# index.db, and answers a real yes/no like every other row.
#
# The true statement is narrower, and it is about THIS FIXTURE rather than about
# the product: the shim is a recorder, so `pnpm store path` prints nothing, the
# probe stops at its "no store to read" guard, and the `motion` row renders `–`.
# Group 4 expects `unknown` for that one row for this reason and no other. A
# shim that faked a store would be building an index.db, not a fake surface —
# worth doing when a wave wants `motion` measured; it is not this wave.
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
            # THE STATE THIS SHIM COULD NOT REPORT until 1.4.4's fixit: a plugin the CLI
            # KNOWS and refuses to LOAD. `enabled` and `failed to load` are different
            # answers to different questions, and setup's load-state arm reads the second.
            # A machine is put into it by naming the id in ${BIONIC_TEST_STATE}/load-broken;
            # the block printed is the one epic-17 W5 F12 measured, character for character
            # (tests/fixtures/plugin-list-dep-broken.txt carries the same text).
            broken=""
            [ -f "${BIONIC_TEST_STATE}/load-broken" ] && read -r broken < "${BIONIC_TEST_STATE}/load-broken"
            printf 'Installed plugins:\n\n'
            while read -r id en; do
              [ -n "$id" ] || continue
              if [ -n "$broken" ] && [ "$id" = "$broken" ]; then
                printf '  ❯ %s\n    Version: 1.0.0\n    Scope: user\n    Status: ✘ failed to load\n    Error: Dependency "superpowers@bionic" is not installed — run `claude plugin install superpowers@bionic`, …\n\n' "$id"
                continue
              fi
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
#
# `SHELL` IS SET AND `BIONIC_SHELL_RC` IS NOT. env.sh's `rc_file` and remove.sh's
# `_rm_shell_rc` each pick the rc file off `$SHELL`, and each takes a
# `BIONIC_SHELL_RC` override — which this suite refuses for the same reason it
# overrides no other root: pointing the door straight at a fixture path would
# test this env block instead of the resolution a real machine performs. `env -i`
# means the value below is the only one the payload can see, so `/bin/zsh` makes
# it resolve `$HOME_FIX/.zshrc` exactly the way a zsh user's machine resolves
# theirs.
run_payload() {  # <script> [args...] — stdin carries the answers
  local script="$1"; shift
  env -i \
    HOME="$HOME_FIX" \
    PATH="$BIN" \
    SHELL=/bin/zsh \
    TMPDIR="$TMPDIR_FIX" \
    BIONIC_TEST_CALLS="$CALLS" \
    BIONIC_TEST_STATE="$STATE" \
    BIONIC_TEST_BIN="$BIN" \
    BIONIC_TEST_SHIMSRC="$SHIMSRC" \
    BIONIC_TEST_PKG_MAP="$PKG_MAP" \
    BIONIC_PLUGIN_ROOT="${FH_PAYLOAD:-$PAYLOAD}" \
    CLAUDE_PLUGIN_ROOT="${FH_PAYLOAD:-$PAYLOAD}" \
    BIONIC_PLAYWRIGHT_CACHE="${HOME_FIX}/.cache/ms-playwright" \
    BIONIC_PNPM_STORE="${FH_PNPM_STORE:-}" \
    BIONIC_DOCTOR_PROBE_SECONDS=15 \
    bash "$script" "$@" 2>&1
}

YES="$(for _ in $(seq 1 80); do printf 'y\n'; done)"

SETTINGS="${HOME_FIX}/.claude/settings.json"
CCS_CONFIG="${HOME_FIX}/.config/ccstatusline/settings.json"
NB_SKILL="${HOME_FIX}/.claude/skills/notebooklm/SKILL.md"
GLOBAL_MEMORY="${HOME_FIX}/.claude/CLAUDE.md"
RC_FILE_FIX="${HOME_FIX}/.zshrc"

jqf() {  # <jq-program> — read one value out of the fixture settings.json
  [ -f "$SETTINGS" ] || { echo "<no settings.json>"; return 0; }
  jq -r "$1" "$SETTINGS" 2>/dev/null || echo "<unreadable>"
}

# One table/section out of a doctor report, by its flush-left heading (doctor
# no longer delimits sections with `=== NAME ===`; a heading is a line with no
# leading whitespace — "THIRD PARTY — tools and plugins bionic depends on",
# "ENVIRONMENT", "BIONIC NATIVE — ships inside the plugin" — and every row under
# it is indented).
# The heading itself is matched by PREFIX, since most of them carry an em-dash
# tagline after the name, and it is never printed back; capture runs until the
# blank line doctor always prints before the next heading.
doctor_section() {  # <file> <name>
  awk -v want="$2" '
    on && $0 == "" { on = 0 }
    on { print; next }
    index($0, want) == 1 { on = 1 }
  ' "$1"
}

# The `present` column of one THIRD PARTY row, read as yes/no/unknown off that
# row's own verdict symbol (✓/✗/–) — the table that replaced DEPENDENCIES still
# names each row by dependency name in column 2, so the same "find this name,
# report its state" claim holds, just against `_doctor_third_row`'s columns
# (symbol name version source state) instead of the deleted class-keyed table.
dep_present() {  # <report-file> <name>
  doctor_section "$1" "THIRD PARTY" | awk -v n="$2" '
    NF >= 4 && $2 == n {
      # NOT `$1 == "✓"`. macOS /usr/bin/awk (20200816) compares these multibyte
      # glyphs byte-blind: `$1 == "✓"` is true for ✗ and – as well, so the first
      # branch always fired and every row read "yes" — 23 assertions vacuous
      # (Step-6 critic F1). index(…)==1 discriminates all three.
      if (index($1, "✓") == 1)      print "yes";
      else if (index($1, "✗") == 1) print "no";
      else                          print "unknown";
      exit
    }'
}

# Does a path exist, as a word rather than as an exit status. Every "bionic did
# not write this" claim below goes through it, and so does at least one "bionic
# did write this" claim in the same group — which is the only thing that makes
# the first kind of claim mean anything (.claude/rules/test-harness.md, "Anti-vacuity").
path_exists() {  # <path> -> yes|no
  if [ -e "$1" ]; then printf 'yes'; else printf 'no'; fi
}

# Non-emptiness as a word, for the same reason.
yn() {  # <string> -> yes|no
  if [ -n "${1:-}" ]; then printf 'yes'; else printf 'no'; fi
}

# The permission rules a settings.json carries, joined. Read from a FILE argument
# so the same extractor can be pointed at a planted file that does carry rules —
# without which "setup wrote none" is a sentence about an extractor that might
# never return anything at all.
perm_allow_join() {  # <settings-file>
  [ -f "$1" ] || return 0
  jq -r '[.permissions.allow[]?] | join(" ")' "$1" 2>/dev/null
}

# The environment names bionic owns, as settings.json carries them.
settings_env_names() {  # <settings-file>
  [ -f "$1" ] || return 0
  jq -r '[.env // {} | keys[] | select(startswith("CLAUDE_CODE_") or startswith("BASH_MAX_"))] | join(" ")' \
    "$1" 2>/dev/null
}

# --- The verdict glyphs, read from doctor.sh rather than restated -----------
#
# A single-quoted shell constant's contents, in pure bash. These values are
# box-drawing and check glyphs, and neither awk nor sed may be asked to compare
# them: macOS /usr/bin/awk compares multibyte glyphs byte-blind, which is how 23
# rows of Group 4 came to be vacuous once already (Step-6 critic F1).
const_from() {  # <file> <name>
  local file="$1" name="$2" line v
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "${name}='"*)
        v="${line#${name}=\'}"; v="${v%\'}"
        printf '%s' "$v"; return 0 ;;
    esac
  done < "$file"
  return 1
}
DOCTOR_OK_GLYPH="$(const_from "$DOCTOR_SH" DOCTOR_OK)"   || DOCTOR_OK_GLYPH=""
DOCTOR_BAD_GLYPH="$(const_from "$DOCTOR_SH" DOCTOR_BAD)" || DOCTOR_BAD_GLYPH=""
DOCTOR_NIL_GLYPH="$(const_from "$DOCTOR_SH" DOCTOR_NIL)" || DOCTOR_NIL_GLYPH=""

# The STATE MARKER of one ENVIRONMENT row, found by the setting name in its
# second column. NOT the row's trailing sentence: doctor writes that sentence to
# be read by a person, and a suite that pinned it would go red the day somebody
# improved the wording and stay green the day the answer itself was wrong. The
# symbol is where the answer lives. Comparison is bash `case`, in-process.
env_row_state() {  # <report-file> <setting> -> yes|no|unknown|"" (no such row)
  local want="$2" line sym rest
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    sym="${line%%[[:space:]]*}"
    rest="${line#"$sym"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    case "$rest" in "$want"*) ;; *) continue ;; esac
    case "$sym" in
      "$DOCTOR_OK_GLYPH")  printf 'yes' ;;
      "$DOCTOR_BAD_GLYPH") printf 'no' ;;
      "$DOCTOR_NIL_GLYPH") printf 'unknown' ;;
      *)                   printf 'unrecognised-symbol' ;;
    esac
    return 0
  done <<< "$(doctor_section "$1" "ENVIRONMENT")"
  return 0
}

# The BIONIC NATIVE row whose component is `plugin`, if the report has one.
# doctor prints it only when the plugin is NOT loaded, so its absence is the
# positive proof of a healthy load — a claim that needs the row to be visible to
# this extractor when it IS printed, which Group 5 proves after the teardown.
# `$2` is an ASCII component name; the verdict glyph is `$1` and is not compared.
native_plugin_row() {  # <report-file>
  doctor_section "$1" "BIONIC NATIVE" | awk '$2 == "plugin" { print; exit }'
}

# --- The rc item's extractors ------------------------------------------------
#
# REUSED FROM tests/rc-item.test.sh, deliberately and without variation. That
# suite owns the rc item's BEHAVIOUR under a driven $HOME; this one owns whether
# an all-yes setup on a pristine machine leaves the block behind and a
# `remove --all` takes it back off. Same walk, same in-process comparisons, so a
# reader who knows one file knows the other.
#
# The marker literals are READ FROM env.sh, never restated here: rc-item.test.sh
# is where they are pinned to the spec's text, and this suite only needs to know
# what the payload will write.
env_sh() {  # <function> [args...] — one env.sh call against the fixture machine
  env -i HOME="$HOME_FIX" PATH="$BIN" SHELL=/bin/zsh \
    bash -c '. "$1"; shift; "$@"' _ "${LIB_DIR}/env.sh" "$@" 2>/dev/null
}
env_sh_var() {  # <name> — the value of one variable env.sh defines
  env -i HOME="$HOME_FIX" PATH="$BIN" SHELL=/bin/zsh \
    bash -c '. "$1"; n="$2"; printf "%s" "${!n}"' _ "${LIB_DIR}/env.sh" "$1" 2>/dev/null
}
RC_START_LIT="$(env_sh_var RC_START)"
RC_END_LIT="$(env_sh_var RC_END)"
RC_PROXY_LINE="$(env_sh rc_default claude-proxy)"

# The working-principles item's markers and text, likewise read from the payload:
# the block setup writes is the block the shipped file carries (wave-27 D16).
PRINCIPLES_START_LIT="$(env_sh_var PRINCIPLES_START)"
PRINCIPLES_END_LIT="$(env_sh_var PRINCIPLES_END)"
PRINCIPLES_SHIPPED="${PAYLOAD}/context/working-principles.md"

# The lines BETWEEN bionic's markers, in order. Not "does the file contain the
# proxy line": a proxy line outside the markers is a line bionic does not own.
rc_block_lines() {  # <file>
  local file="$1" line inside=0 out=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "1" ] && out="${out}${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

# Every line NOT between the markers, the markers themselves excluded: what the
# user's rc held before bionic touched it, and must still hold afterwards.
rc_nonblock_lines() {  # <file>
  local file="$1" line inside=0 out=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$RC_START_LIT" ]; then inside=1; continue; fi
    if [ "$line" = "$RC_END_LIT" ];   then inside=0; continue; fi
    [ "$inside" = "0" ] && out="${out}${line}"$'\n'
  done < "$file"
  printf '%s' "$out"
}

# How many whole lines equal <literal>.
count_lines_equal() {  # <file> <literal>
  local file="$1" want="$2" line n=0
  [ -f "$file" ] || { printf '0'; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$want" ] && n=$((n + 1))
  done < "$file"
  printf '%s' "$n"
}

# Does the SHELL agree the file is still a shell script — `ok`, or the parser's
# own complaint. An rc that no longer parses is the failure mode that locks a
# user out of their login shell, and no assertion about bytes or blocks sees it.
# This runs the REAL zsh, outside the fixture PATH, because it is a question
# about the file rather than about the payload.
zsh_syntax_rc() {  # <file>
  local out
  if out="$(zsh -n "$1" 2>&1)"; then printf 'ok'; else printf '%s' "${out:-nonzero}"; fi
}

# The rc the fixture machine starts with: three lines that are not bionic's, the
# same shape tests/rc-item.test.sh plants, so a reader comparing the two suites
# is not also reconciling two fixtures.
plant_rc() {  # <file>
  cat > "$1" <<'RC'
# a line that was here before bionic
export EDITOR=vim
alias ll='ls -la'
RC
}

# ---------------------------------------------------------------------------
# Group 1 — the suite's own preconditions.
# ---------------------------------------------------------------------------

section "Group 1: preconditions"

expect_true "payload/scripts/setup.sh exists"  test -f "$SETUP_SH"
expect_true "payload/scripts/doctor.sh exists" test -f "$DOCTOR_SH"
expect_true "payload/scripts/remove.sh exists" test -f "$REMOVE_SH"
expect_true "the shipped ccstatusline layout exists" test -f "$CCSTATUSLINE_SHIPPED"
# DELETED AT THE REVIVE (epic-18 wave-03): a row asserting `command -v jq`. The
# hard guard above the fixture block now exits the suite when jq is missing, so
# this row is reached only on a machine that has it — it could not fail, which is
# the definition of the assertion this wave was told to delete. The four rows
# beside it stay because they still can: with those files removed from a copy of
# the checkout, each one goes red (captures/freshhome--payload-files-missing.txt).

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

# ...and then exactly ONE thing in it, read back through the same walk that just
# reported the directory empty — so "empty" is a reading this fixture can change
# rather than a fact about a `find` call that never returns anything.
plant_rc "$RC_FILE_FIX"
cp "$RC_FILE_FIX" "$TMP/rc-planted.zshrc"
expect_eq "the planted shell rc is the only thing in the fixture HOME" \
  "$RC_FILE_FIX" "$(find "$HOME_FIX" -mindepth 1 2>/dev/null)"

# The rc literals, taken from the payload rather than restated here, and proven
# non-empty before one assertion reads through them: an empty RC_START would make
# `rc_block_lines` walk straight past every marker and hand back an answer no
# later row could tell from the truth.
expect_ne "env.sh names a start marker" "" "$RC_START_LIT"
expect_ne "env.sh names an end marker"  "" "$RC_END_LIT"
expect_ne "env.sh names a body for the claude-proxy item" "" "$RC_PROXY_LINE"

# The verdict glyphs doctor's rows are read by, likewise: read out of doctor.sh,
# proven present, and proven to be different characters — an `env_row_state` whose
# three cases all held the same string would answer `yes` to every row, which is
# the exact shape of the defect that made 23 of Group 4's rows vacuous once.
expect_ne "doctor.sh's OK verdict glyph was read out of the script"  "" "$DOCTOR_OK_GLYPH"
expect_ne "doctor.sh's NIL verdict glyph was read out of the script" "" "$DOCTOR_NIL_GLYPH"
expect_ne "the OK and NIL verdict glyphs are different characters" \
  "$DOCTOR_OK_GLYPH" "$DOCTOR_NIL_GLYPH"

# And the shell's parser is proven to discriminate before the rc is handed to it:
# it calls the planted file well-formed and a deliberately broken one broken,
# through the same function.
printf '%s\n' 'if [ 1 = 1 ]' > "$TMP/broken.zshrc"
expect_eq "zsh -n calls the planted rc well-formed" "ok" \
  "$(zsh_syntax_rc "$TMP/rc-planted.zshrc")"
expect_ne "zsh -n calls a deliberately broken rc broken" "ok" \
  "$(zsh_syntax_rc "$TMP/broken.zshrc")"

# The rc's state before setup ever runs, captured through the extractors the
# manifest will use afterwards. These are the negative half of Group 3's rc rows,
# and they are read HERE so the positive half is measured against a fixture whose
# starting state was seen rather than assumed.
RC_BLOCK_BEFORE="$(rc_block_lines "$RC_FILE_FIX")"
RC_STARTS_BEFORE="$(count_lines_equal "$RC_FILE_FIX" "$RC_START_LIT")"

# ---------------------------------------------------------------------------
# Group 2 — setup --all against an empty $HOME.
# ---------------------------------------------------------------------------

section "Group 2: setup --all on a pristine machine"

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
# THE TWO ROWS THIS SUITE WAS WRITTEN FOR still carry their incident tags in
# their labels. Both were red the day it was written — `_dep_install_statusline`
# recorded the statusLine COMMAND and never copied the layout the payload ships,
# and the uv-tool arm installed the notebooklm CLI without ever running
# `notebooklm skill install` — and T1/T2 fixed both. The tags stay so that a
# future red on either is recognisable as the same defect coming back rather than
# as a new one.
#
# THE RC ITEM JOINED THE MANIFEST AT THE REVIVE (epic-18 wave-03). It is the
# newest thing setup writes and the only write target that is a file the USER
# already owned, which makes it two claims rather than one: bionic's block holds
# what env.sh says it holds, AND every byte that was not bionic's is still where
# the user left it.
# ---------------------------------------------------------------------------

section "Group 3: the manifest setup is supposed to leave"

# ── ccstatusline: both halves ──
#
# THE COMMAND IS THE INSTALLED BINARY, NEVER npx (epic-21 bug-ccstatusline-npx-per-render.md,
# Fix steps 1-2). `npx ccstatusline@latest` resolves a registry lookup on every render —
# this is the exact string an EXACT match pins, not a substring, so a regression back to
# the npx form (even wrapped, e.g. "npx ccstatusline") would fail this the same way a bare
# substring match on '*ccstatusline*' never could.
expect_true "manifest: settings.json exists" test -f "$SETTINGS"
expect_eq "manifest: settings.json records the installed-binary statusLine command, never npx" \
  "ccstatusline" "$(jqf '.statusLine.command // ""')"
expect_true "manifest: ~/.config/ccstatusline/settings.json exists [ccstatusline-config-missing]" \
  test -f "$CCS_CONFIG"
expect_true "manifest: ~/.config/ccstatusline/settings.json matches the shipped layout [ccstatusline-config-missing]" \
  cmp -s "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"
expect_match "manifest: the ccstatusline install reached npm, not npx (AC-3)" \
  '*npm install -g ccstatusline*' "$(cat "$CALLS")"
expect_no_match "manifest: the ccstatusline install never resolves a package over npx" \
  '*npx ccstatusline*' "$(cat "$CALLS")"

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

# ── the default permission mode, and the allow-list bionic does NOT write ──
#
# Setup writes the MODE and nothing else about permissions (epic-18 T13). The
# negative rides beside the positive on purpose: a pristine install that came
# back with rules in `permissions.allow` would be bionic exempting itself from
# the very mode it just asked about.
expect_eq "manifest: the default permission mode is auto" "auto" "$(jqf '.permissions.defaultMode // ""')"

# THE EXTRACTOR IS PROVEN TO SEE A RULE BEFORE ITS SILENCE IS READ AS "none".
# A planted settings.json that does carry one goes through the same function; an
# extractor that returned the empty string whatever it was handed would fail the
# line below and take the assertion after it down too.
printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"],"defaultMode":"auto"}}' \
  > "$TMP/settings-with-rules.json"
expect_eq "the permission-rule extractor reads a rule out of a settings.json that has one" \
  "Bash(ls:*)" "$(perm_allow_join "$TMP/settings-with-rules.json")"
expect_eq "manifest: setup wrote NO permission rules of its own" "" \
  "$(perm_allow_join "$SETTINGS")"

# ── AC-7: the negative, deliberately beside the positives above ──
#
# Absence proves nothing on its own; it proves something HERE because the same
# run just proved setup wrote the six things above it.
# The same extractor, in the same run, on the same fixture machine, says `yes` to
# a file setup did write — which is the only thing that makes the `no` below it
# mean anything at all.
expect_eq "the path extractor says yes to a file setup did write" "yes" \
  "$(path_exists "$SETTINGS")"
expect_eq "manifest: no CLAUDE.md was written at the top of \$HOME (AC-7)" \
  "no" "$(path_exists "${HOME_FIX}/CLAUDE.md")"

# ── the working principles: ~/.claude/CLAUDE.md holds bionic's block and only it ──
#
# The expected bytes are built from the SHIPPED file through env.sh's own reader,
# proven non-empty first, so an empty text could not make an empty file pass.
expect_ne "env.sh names the principles start marker" "" "$PRINCIPLES_START_LIT"
env_sh markers_get "$PRINCIPLES_SHIPPED" "$PRINCIPLES_START_LIT" "$PRINCIPLES_END_LIT" > "$TMP/principles-body"
expect_true "the shipped principles text reads back non-empty" test -s "$TMP/principles-body"
{ printf '%s\n' "$PRINCIPLES_START_LIT"; cat "$TMP/principles-body"; printf '%s\n' "$PRINCIPLES_END_LIT"; } \
  > "$TMP/principles-expected.md"
expect_eq "manifest: setup created ~/.claude/CLAUDE.md on the all-yes run" "yes" \
  "$(path_exists "$GLOBAL_MEMORY")"
expect_true "manifest: ~/.claude/CLAUDE.md is exactly bionic's marked principles block" \
  cmp -s "$TMP/principles-expected.md" "$GLOBAL_MEMORY"

# DELETED AT THE REVIVE (epic-18 wave-03): a third AC-7 row that grepped setup's
# PRINTED OUTPUT for the string `CLAUDE.md`. It pinned wording rather than
# behaviour in both directions — setup could name the file in a sentence and
# touch nothing, or touch it and say nothing — and the two file claims above
# carry the whole of AC-7 without it.

# ── the rc item: bionic's block, and the user's file around it ──
#
# THE POSITIVE AND THE NEGATIVE ARE THE SAME EXTRACTOR ON THE SAME FILE, one
# reading taken before setup ran (Group 1) and one after.
expect_eq "manifest: the rc carried no bionic block before setup" "" "$RC_BLOCK_BEFORE"
expect_ne "manifest: the rc carries a bionic block after setup" "" \
  "$(rc_block_lines "$RC_FILE_FIX")"
expect_eq "manifest: the block holds exactly env.sh's claude-proxy body" \
  "$RC_PROXY_LINE" "$(rc_block_lines "$RC_FILE_FIX")"
expect_eq "manifest: no start marker was in the rc before setup" "0" "$RC_STARTS_BEFORE"
RC_STARTS_AFTER_SETUP="$(count_lines_equal "$RC_FILE_FIX" "$RC_START_LIT")"
expect_eq "manifest: the start marker appears exactly once after setup" "1" \
  "$RC_STARTS_AFTER_SETUP"
# Each line of the body, once: a second copy of bionic's body anywhere in the rc is
# caught line by line (the body is two lines since wave-27 T75, A-orch-185).
RC_BODY_ONCE=yes; RC_BODY_N=0
while IFS= read -r rc_body_line; do
  RC_BODY_N=$((RC_BODY_N + 1))
  [ "$(count_lines_equal "$RC_FILE_FIX" "$rc_body_line")" = "1" ] || RC_BODY_ONCE="no: $rc_body_line"
done <<< "$RC_PROXY_LINE"
expect_true "manifest: the body's lines were read (the row below is not vacuous)" test "$RC_BODY_N" -ge 1
expect_eq "manifest: each line of the body appears exactly once in the whole rc" "yes" "$RC_BODY_ONCE"

# The user's own lines. First as a walk — both sides through the same extractor,
# and the extractor proven to return the planted file's lines rather than nothing
# — then as bytes, which is the claim that would catch a rewrite that reordered
# or re-spaced them.
expect_ne "the non-block extractor sees the planted rc's own lines" "" \
  "$(rc_nonblock_lines "$TMP/rc-planted.zshrc")"
expect_eq "manifest: every line outside the block is the planted rc, in order" \
  "$(rc_nonblock_lines "$TMP/rc-planted.zshrc")" "$(rc_nonblock_lines "$RC_FILE_FIX")"

{ cat "$TMP/rc-planted.zshrc"
  printf '%s\n' "$RC_START_LIT"
  printf '%s\n' "$RC_PROXY_LINE"
  printf '%s\n' "$RC_END_LIT"
} > "$TMP/rc-expected.zshrc"
expect_true "manifest: the rc is the planted file plus bionic's block, byte for byte" \
  cmp -s "$TMP/rc-expected.zshrc" "$RC_FILE_FIX"

# The claim no byte comparison can make: the file the login shell would source is
# still a file the login shell can parse.
expect_eq "manifest: the rc still parses as a shell script after setup wrote to it" \
  "ok" "$(zsh_syntax_rc "$RC_FILE_FIX")"

# ── the install record (wave-28 T40, D29) ──
# Every tool setup installed through `install_dep` has its line, written after the
# install's command exited 0; a native plugin, which the CLI's own registry proves,
# has none.
FH_RECORD="${HOME_FIX}/.claude/bionic/installed"
fh_record_kind() {  # <name> -> the kind on <name>'s newest record line, or nothing
  local n k rest out=""
  [ -f "$FH_RECORD" ] || return 0
  while IFS=$'\t' read -r n k rest; do [ "$n" = "$1" ] && out="$k"; done < "$FH_RECORD"
  printf '%s' "$out"
}
expect_true "manifest: setup wrote the install record" test -s "$FH_RECORD"
expect_eq "manifest: the record names ccstatusline, as kind statusline" "statusline" "$(fh_record_kind ccstatusline)"
expect_eq "manifest: …notebooklm, as kind uv-tool" "uv-tool" "$(fh_record_kind notebooklm)"
expect_eq "manifest: …the excalidraw renderer, as kind uv-project" "uv-project" "$(fh_record_kind excalidraw-renderer)"
expect_eq "manifest: …the Playwright browser, as kind playwright-browser" "playwright-browser" \
  "$(fh_record_kind playwright-chromium)"
expect_match "manifest: the native document-skills was installed through the CLI" \
  '*plugin install document-skills@*' "$(cat "$CALLS")"
expect_eq "manifest: …and has no record line" "" "$(fh_record_kind document-skills)"

# ---------------------------------------------------------------------------
# Group 4 — doctor agrees with the machine (AC-10a, AC-10c).
# ---------------------------------------------------------------------------

section "Group 4: doctor on the machine setup just built"

DOC1="$TMP/doctor-after-setup.txt"
run_payload "$DOCTOR_SH" < /dev/null > "$DOC1" 2>&1
DOC1_RC=$?
expect_eq "doctor exits 0" "0" "$DOC1_RC"

# Every basic and extra row, read from the table rather than restated here.
#
# PER-ROW TRUTH, NOT A BLANKET `yes` (Step-6 critic F1). This loop asserted
# `yes` for all 23 rows and got it from a parser that could not tell ✓ from ✗
# from – (see `dep_present` above): every one of those assertions was vacuous.
# Three of the rows are genuinely NOT present on this fixture, and in all three
# cases that is a property of how deep the SHIM goes, not of the product — each
# one still proves setup ISSUED the install, which is what Group 2 is about:
#
#   impeccable → no.      `claude plugin install impeccable@bionic` ran (it is in
#                         $BIONIC_TEST_CALLS), but the claude shim reports every
#                         installed plugin at version 1.0.0 and this row
#                         constrains `^4.1.0`, so doctor renders
#                         `✗ … violates ^4.1.0`. The row pins the version GATE
#                         on top of the install, and pins an absent `impeccable`
#                         — the one state the old blanket loop could not see.
#   motion → unknown.     `pnpm store add motion@latest` ran too. The pnpm shim
#                         is a recorder (see its note above), `pnpm store path`
#                         prints nothing, and `_dep_check_pnpm_store` stops at
#                         its "no store to read" guard. `unknown` was the right
#                         expectation all along; the wave briefly "corrected" it
#                         to `yes` on the strength of the vacuous parser.
#   humanizer → no.       `git clone … ~/.claude/skills/humanizer` ran; the
#                         fixture's git is a recorder, so no SKILL.md lands and
#                         `_dep_check_github_skill` answers no. This is the
#                         `github-skill` shim arm the TODO near the top of the
#                         shim block still names as unwritten.
#
# Every other row installs through a shim that really writes, so `yes` there is
# a measurement.
dep_expected_present() {  # <name> — the state THIS fixture can produce
  case "$1" in
    impeccable) echo no ;;
    motion)     echo unknown ;;
    humanizer)  echo no ;;
    *)          echo yes ;;
  esac
}

for cls in basic extra; do
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    WANT="$(dep_expected_present "$name")"
    expect_eq "doctor: ${cls} row ${name} reports present=${WANT}" \
      "$WANT" "$(dep_present "$DOC1" "$name")"
  done <<< "$(dep_query dep_names_class "$cls")"
done

# Doctor no longer prints a LOAD STATE section or the word "loaded" anywhere —
# `case "$LOAD_STATE" in loaded) ;; ...` is a deliberate no-op, so a healthy
# load leaves nothing to grep for directly. What IS still true, and testable:
# BIONIC NATIVE only grows a "plugin" row for the other three states (failed,
# absent, unknown — payload/scripts/doctor.sh:1232-1240), so the row's absence
# is the positive proof the CLI loaded bionic, by exhaustion over the same four
# states the deleted assertion named.
expect_ne "doctor: the BIONIC NATIVE table is present at all" "" \
  "$(doctor_section "$DOC1" "BIONIC NATIVE")"
expect_eq "doctor: the load state is loaded (no plugin-load row in BIONIC NATIVE)" "" \
  "$(native_plugin_row "$DOC1")"
# THE POSITIVE TWIN FOR THE LINE ABOVE IS IN GROUP 5, on the same extractor and
# the same fixture machine: once remove has uninstalled the plugin, doctor prints
# that row and `native_plugin_row` finds it. Without that assertion passing,
# "no row" here would be indistinguishable from an extractor that never returns.

# ── doctor agrees with the rc on disk ──
#
# READ AS A STATE MARKER, never as the row's sentence. The trailing text is prose
# for a person ("in <rc> — new shells pick it up"); the symbol is the answer, and
# the answer is what has to agree with the block Group 3 just found on disk. Its
# negative twin — the same extractor, same row name, `unknown` once the block is
# gone — is in Group 5.
expect_eq "doctor: the claude() shell proxy row agrees the block is on disk" \
  "yes" "$(env_row_state "$DOC1" "claude() shell proxy")"


# ---------------------------------------------------------------------------
# Group 4b — VENV task: a stable, plugin-version-independent venv path, and a
# stale uv.lock reads `stale`, not `absent` (AC-17, wave-bionic-1.4.0).
# ---------------------------------------------------------------------------
#
# THE WHOLE POINT OF AC-17. Group 2's real `uv sync` ran with `BIONIC_PLUGIN_ROOT`
# pointed at THIS repo's own payload — the same root every other row in this
# suite installs against. If the venv `deps.sh` builds still lived inside that
# tree (the pre-AC-17 shape: `<plugin-root>/skills/excalidraw-diagram/references/.venv`),
# an in-place plugin upgrade — a new version directory, same machine — would
# leave that venv behind and force a needless re-sync. So this group swaps
# `BIONIC_PLUGIN_ROOT` out from under the probe entirely, twice, and the venv
# must still read present: the path this checks is `$HOME`-anchored, never
# plugin-root-anchored.

section "Group 4b: VENV — stable venv path, version-independent, stale-lock state (AC-17)"

VENV_DIR="${HOME_FIX}/.local/share/bionic/excalidraw-venv"
VENV_LOCK_HASH="${VENV_DIR}.lock.sha256"

expect_true "VENV: the venv Group 2's sync built lives at the stable XDG path, not the plugin tree" \
  test -x "${VENV_DIR}/bin/python"
expect_true "VENV: a lock hash was written beside the venv at sync time" \
  test -s "$VENV_LOCK_HASH"
expect_eq "VENV: the sync argv carried UV_PROJECT_ENVIRONMENT set to the stable path (the fake uv recorded it)" \
  "UV_PROJECT_ENVIRONMENT=${VENV_DIR}" \
  "$(grep '^UV_PROJECT_ENVIRONMENT=' "$CALLS" | tail -1)"

# A second (simulated) plugin version directory: same uv.lock content, a
# completely different path. `$HOME` — and so the venv and its hash file —
# does not move; only `BIONIC_PLUGIN_ROOT` does.
V2_ROOT="$TMP/plugin-vnext"
mkdir -p "${V2_ROOT}/skills/excalidraw-diagram/references"
cp "${PAYLOAD}/skills/excalidraw-diagram/references/uv.lock" \
   "${V2_ROOT}/skills/excalidraw-diagram/references/uv.lock"
cp "${PAYLOAD}/skills/excalidraw-diagram/references/pyproject.toml" \
   "${V2_ROOT}/skills/excalidraw-diagram/references/pyproject.toml"

check_dep_root() {  # <plugin-root> — check_dep excalidraw-renderer under a chosen plugin root
  env -i HOME="$HOME_FIX" PATH="$BIN" BIONIC_PLUGIN_ROOT="$1" \
    bash -c '. "$1"; check_dep excalidraw-renderer' _ "${LIB_DIR}/deps.sh" 2>/dev/null
}

expect_match "VENV: the venv still reads present under a second (simulated) plugin version dir" \
  'present=yes*' "$(check_dep_root "$V2_ROOT")"

# A third version dir whose uv.lock changed since the venv was synced — the
# hash beside the venv no longer matches, so the row must read `stale`, a
# state distinct from both `yes` (nothing changed) and `no`/absent (never
# synced at all). AC-17: "re-synced, not re-offered" starts with this
# distinction existing at the probe.
V3_ROOT="$TMP/plugin-vstale"
mkdir -p "${V3_ROOT}/skills/excalidraw-diagram/references"
cp "${PAYLOAD}/skills/excalidraw-diagram/references/uv.lock" \
   "${V3_ROOT}/skills/excalidraw-diagram/references/uv.lock"
cp "${PAYLOAD}/skills/excalidraw-diagram/references/pyproject.toml" \
   "${V3_ROOT}/skills/excalidraw-diagram/references/pyproject.toml"
echo "# a lock changed after the venv was synced" >> "${V3_ROOT}/skills/excalidraw-diagram/references/uv.lock"

expect_match "VENV: a uv.lock that changed since sync reads present=stale, not absent" \
  'present=stale*' "$(check_dep_root "$V3_ROOT")"


# ---------------------------------------------------------------------------
# Group 4c — ccstatusline migrated its own layout file; doctor and setup must
# both still read that as installed (Chris 2026-09-03). ccstatusline rewrites
# ~/.config/ccstatusline/settings.json in place on first render, bumping the
# schema `version` and nothing else. Before this fix the byte-identical probe
# reported the row absent and the next setup --all re-copied the shipped file
# — a loop the status line's own migration re-entered every session.
# ---------------------------------------------------------------------------

section "Group 4c: a ccstatusline-migrated layout still reads as installed"

CCS_MIGRATED="$TMP/ccs-migrated.json"
jq '.version += 1' "$CCS_CONFIG" > "$CCS_MIGRATED" && cp "$CCS_MIGRATED" "$CCS_CONFIG"
expect_true "4c precondition: the migrated layout differs from the shipped one byte-for-byte" \
  test "$(cmp -s "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"; echo $?)" != 0

DOC1C="$TMP/doctor-after-migration.txt"
run_payload "$DOCTOR_SH" < /dev/null > "$DOC1C" 2>&1
expect_eq "4c doctor: ccstatusline row still reports present=yes after ccstatusline bumped the schema version" \
  "yes" "$(dep_present "$DOC1C" ccstatusline)"

SETUP_OUT_C="$TMP/setup-after-migration.txt"
printf '%s' "$YES" | run_payload "$SETUP_SH" --all > "$SETUP_OUT_C" 2>&1
expect_true "4c setup --all: leaves the migrated layout alone instead of re-copying the shipped file" \
  cmp -s "$CCS_MIGRATED" "$CCS_CONFIG"
expect_no_match "4c setup --all: does not offer to install ccstatusline again" \
  '*install ccstatusline*' "$(cat "$SETUP_OUT_C")"

# ---------------------------------------------------------------------------
# Group 4d — the principles span is bionic's: setup replaces an edited one without asking
# (wave-31 T10, AC-7.2; D8; rewritten by T34, A-orch-58). It was wave-27 D16's rule that an edited
# block is the user's and `--all` leaves it alone; D8 retired that. The span carries a marker line
# saying bionic replaces it on every setup and the user's own text belongs outside the markers, so
# `--all` and `--only` both bring it up to date, ask nothing about it, and say "updated" in the
# summary. Same machine as Group 5, which then removes a present block.
# ---------------------------------------------------------------------------

section "Group 4d: an edited principles span is bionic's — setup replaces it and asks nothing"

plant_edited_span() {
  { printf '%s\n' "$PRINCIPLES_START_LIT"; cat "$TMP/principles-body"; printf '%s\n' '- my own rule'
    printf '%s\n' "$PRINCIPLES_END_LIT"; } > "$GLOBAL_MEMORY"
}
plant_edited_span
cp "$GLOBAL_MEMORY" "$TMP/principles-edited.md"
expect_false "4d precondition: the edited block is not the shipped one" \
  cmp -s "$TMP/principles-expected.md" "$GLOBAL_MEMORY"
SETUP_OUT_D="$TMP/setup-edited-all.txt"
printf '%s' "$YES" | run_payload "$SETUP_SH" --all > "$SETUP_OUT_D" 2>&1
expect_true "4d: setup --all replaces the edited span with the shipped text" \
  cmp -s "$TMP/principles-expected.md" "$GLOBAL_MEMORY"
expect_match "4d: …and the summary says the span was updated" '*updated*' "$(cat "$SETUP_OUT_D")"
expect_no_match "4d: …and shows no difference for it" '*my own rule*' "$(cat "$SETUP_OUT_D")"
plant_edited_span
SETUP_OUT_DN="$TMP/setup-edited-only-no.txt"
printf 'n\n' | run_payload "$SETUP_SH" --only working-principles > "$SETUP_OUT_DN" 2>&1
expect_true "4d: asked for by name with an n on the input, the edit is replaced anyway" \
  cmp -s "$TMP/principles-expected.md" "$GLOBAL_MEMORY"
expect_match "4d: …and the run says the span was updated" '*updated*' "$(cat "$SETUP_OUT_DN")"
expect_no_match "4d: …and asked nothing about it" '*\[y/N\]*' "$(cat "$SETUP_OUT_DN")"
plant_edited_span
printf 'y\n' | run_payload "$SETUP_SH" --only working-principles > "$TMP/setup-edited-yes.txt" 2>&1
expect_true "4d: a y on the input replaces it with the same text" \
  cmp -s "$TMP/principles-expected.md" "$GLOBAL_MEMORY"

# ---------------------------------------------------------------------------
# Group 4e — a claude() block the user changed is theirs (wave-27 T77, review pass 64).
#
# On the machine setup built, a block holding bionic's earlier line and a line of the
# user's is not on `--all`'s page, even fed nothing but yes; the step names it by its
# lines, with bionic's lines for the user's hand, and no byte of the rc changes. The
# rc is put back for Group 5.
# ---------------------------------------------------------------------------

section "Group 4e: --all leaves a changed claude() block alone and names it"

cp "$RC_FILE_FIX" "$TMP/rc-before-4e"
T77_FN="${RC_PROXY_LINE#*$'\n'}"
T77_N="$(rc_nonblock_lines "$RC_FILE_FIX" | wc -l | tr -d ' ')"
{ rc_nonblock_lines "$RC_FILE_FIX"
  printf '%s\n' "$RC_START_LIT" "$T77_FN" 'export V9=9' "$RC_END_LIT"; } > "$TMP/rc-changed-4e"
cp "$TMP/rc-changed-4e" "$RC_FILE_FIX"
expect_ne "4e precondition: the earlier line is not the whole body" "$RC_PROXY_LINE" "$T77_FN"
SETUP_OUT_E="$TMP/setup-changed-all.txt"
printf '%s' "$YES" | run_payload "$SETUP_SH" --all > "$SETUP_OUT_E" 2>&1
expect_contains "4e: the changed block is named by its lines" \
  "lines $((T77_N + 1)) to $((T77_N + 4)) of" "$(cat "$SETUP_OUT_E")"
expect_contains "4e: …with bionic's lines for the user's hand" "     ${T77_FN}" "$(cat "$SETUP_OUT_E")"
expect_contains "4e: the page was printed (the row below is not vacuous)" "Do all of the above?" "$(cat "$SETUP_OUT_E")"
expect_absent "4e: …and does not offer the claude() function" "add bionic's claude() shell function" "$(cat "$SETUP_OUT_E")"
expect_absent "4e: …and the user's line is never printed" "V9=9" "$(cat "$SETUP_OUT_E")"
expect_true "4e: the rc is byte for byte as it was" cmp -s "$TMP/rc-changed-4e" "$RC_FILE_FIX"
cp "$TMP/rc-before-4e" "$RC_FILE_FIX"

# ---------------------------------------------------------------------------
# Group 4f — remove leaves a changed claude() block too (wave-27 T78).
#
# The same machine, its block holding bionic's two lines with a line of the user's
# between them. `remove --all`'s page, printed with every other item setup left, does
# not offer the block and names it by its lines after its items; the page is declined
# here, so Group 5 still finds the machine whole. Group 5b drives the yes.
# ---------------------------------------------------------------------------

section "Group 4f: remove --all keeps a changed claude() block off its page and names it"

T78_UNALIAS="${RC_PROXY_LINE%%$'\n'*}"
T78_N="$(rc_nonblock_lines "$RC_FILE_FIX" | wc -l | tr -d ' ')"
{ rc_nonblock_lines "$RC_FILE_FIX"
  printf '%s\n' "$RC_START_LIT" "$T78_UNALIAS" 'export V9=9' "$T77_FN" "$RC_END_LIT"; } > "$TMP/rc-changed-4f"
cp "$TMP/rc-changed-4f" "$RC_FILE_FIX"
expect_ne "4f precondition: the block's first line is not its second" "$T78_UNALIAS" "$T77_FN"
T78_NAMED="lines $((T78_N + 1)) to $((T78_N + 5)) of ~/.zshrc are bionic's claude() block, changed since bionic wrote it:"
REMOVE_OUT_F="$(printf 'n\n' | run_payload "$REMOVE_SH" --all 2>&1)"
REMOVE_PAGE_F="${REMOVE_OUT_F%%Do all of the above?*}"
expect_ne "4f: the page is on the output, ahead of its question" "$REMOVE_OUT_F" "$REMOVE_PAGE_F"
expect_contains "4f: …with setup's other items on it" "remove bionic's working principles" "$REMOVE_PAGE_F"
expect_absent "4f: …and not the claude() function" "remove bionic's claude() shell function" "$REMOVE_PAGE_F"
expect_contains "4f: the block is named by its lines after the page's items" "$T78_NAMED" "${REMOVE_PAGE_F##*  • }"
expect_absent "4f: …and the user's line is never printed" "V9=9" "$REMOVE_OUT_F"
expect_true "4f: the rc is byte for byte as it was" cmp -s "$TMP/rc-changed-4f" "$RC_FILE_FIX"
cp "$TMP/rc-before-4e" "$RC_FILE_FIX"


# ---------------------------------------------------------------------------
# Group 5 — remove --all undoes the manifest (AC-10, the second half).
# ---------------------------------------------------------------------------

section "Group 5: remove --all takes the manifest back off"

# Captured BEFORE the teardown, because the post-remove absence of a file that
# was never created proves nothing. Each removal claim below is the conjunction:
# it was there after setup, AND it is gone after remove.
CCS_WAS_THERE=no; [ -f "$CCS_CONFIG" ] && CCS_WAS_THERE=yes
NB_WAS_THERE=no;  [ -f "$NB_SKILL" ]   && NB_WAS_THERE=yes
VENV_WAS_THERE=no; [ -x "${VENV_DIR}/bin/python" ] && VENV_WAS_THERE=yes
RC_BLOCK_WAS="$(yn "$(rc_block_lines "$RC_FILE_FIX")")"
MEMORY_WAS="$(path_exists "$GLOBAL_MEMORY")"
SL_WAS="$(yn "$(jqf '.statusLine.command // ""')")"
ENV_NAMES_WAS="$(yn "$(settings_env_names "$SETTINGS")")"

REMOVE_OUT="$TMP/remove.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$REMOVE_OUT" 2>&1
REMOVE_RC=$?
expect_eq "remove exits 0" "0" "$REMOVE_RC"

CCS_GONE=no; [ -e "$CCS_CONFIG" ] || CCS_GONE=yes
NB_GONE=no;  [ -e "$NB_SKILL" ]   || NB_GONE=yes
VENV_GONE=no; [ -e "$VENV_DIR" ] || VENV_GONE=yes

# THE RECORDED TOOLS COME BACK OFF (wave-28 T40). Setup installed each of these
# through `install_dep`, which recorded it (Group 3), so the teardown's yes takes it
# off through the package-manager fakes. A tool with no record line is still named
# and never acted on — Group 7 and Group 16 pin that case, with no install behind
# them. Each row is still a conjunction — it was there after setup, AND it is gone now.
expect_eq "remove: the ccstatusline layout was installed and is gone again [ccstatusline-config-missing]" \
  "yes yes" "${CCS_WAS_THERE} ${CCS_GONE}"
expect_eq "remove: the notebooklm skill was installed and is gone again [notebooklm-skill-missing]" \
  "yes yes" "${NB_WAS_THERE} ${NB_GONE}"
expect_eq "remove: the excalidraw-renderer venv was installed at the stable path and is gone again [venv-path]" \
  "yes yes" "${VENV_WAS_THERE} ${VENV_GONE}"

# EACH OF THESE IS A CONJUNCTION, never a bare absence. "Was it there" was read
# before the teardown through the same extractor that reads "is it there" after
# it, so a run in which setup had quietly written nothing fails the first half
# instead of sailing through the second.
expect_eq "remove: settings.json carried a statusLine command and no longer does (a recorded tool row)" \
  "yes no" "${SL_WAS} $(yn "$(jqf '.statusLine.command // ""')")"
expect_eq "remove: settings.json carried bionic's environment names and no longer does" \
  "yes no" "${ENV_NAMES_WAS} $(yn "$(settings_env_names "$SETTINGS")")"

# The uninstall reached npm, beside setup's install on the same log.
expect_match "remove: the log holds setup's ccstatusline install" \
  '*npm install -g ccstatusline*' "$(cat "$CALLS")"
expect_match "remove: …and remove's uninstall of it reached npm" \
  '*npm uninstall -g ccstatusline*' "$(cat "$CALLS")"
expect_eq "remove: …and the record no longer names ccstatusline" "" "$(fh_record_kind ccstatusline)"
# The recorded shared cache is named and kept: bionic installed the browser, and
# the cache it lives in is every project's.
REMOVE_TOOLS_TEXT="$(cat "$REMOVE_OUT")"
expect_contains "remove: the summary has its by-hand heading" "  left for you to remove by hand:" "$REMOVE_TOOLS_TEXT"
expect_match "remove: …and names the recorded Playwright browser under it" \
  '*left for you to remove by hand:*• playwright-chromium*' "$REMOVE_TOOLS_TEXT"
expect_no_match "remove: …and not ccstatusline, which came off" \
  '*left for you to remove by hand:*• ccstatusline*' "$REMOVE_TOOLS_TEXT"
expect_eq "remove: …the browser's record line stays" "playwright-browser" "$(fh_record_kind playwright-chromium)"
expect_true "remove: …and so does the browser cache" \
  test -f "${HOME_FIX}/.cache/ms-playwright/chromium-1187/INSTALLATION_COMPLETE"

# DELETED AT THE REVIVE (epic-18 wave-03): a row asserting that no
# `bionic-profile-` permission rule survived the teardown. Group 3 asserts setup
# writes NO permission rules at all, so that extractor's input was empty by
# construction and the row could not have gone red for any defect in any door —
# the precise shape of assertion this wave was told to delete rather than keep.

# ── the rc item comes back off ──
RC_BLOCK_AFTER="$(rc_block_lines "$RC_FILE_FIX")"
expect_eq "remove: the rc carried bionic's block and no longer does" \
  "yes no" "${RC_BLOCK_WAS} $(yn "$RC_BLOCK_AFTER")"
expect_eq "remove: one start marker was there, and neither marker survives" \
  "1 0 0" "${RC_STARTS_AFTER_SETUP} $(count_lines_equal "$RC_FILE_FIX" "$RC_START_LIT") $(count_lines_equal "$RC_FILE_FIX" "$RC_END_LIT")"
expect_true "remove: the rc is byte-identical to the file the user planted" \
  cmp -s "$TMP/rc-planted.zshrc" "$RC_FILE_FIX"
expect_eq "remove: the rc still parses as a shell script after the teardown" \
  "ok" "$(zsh_syntax_rc "$RC_FILE_FIX")"

# ── doctor on the torn-down machine ──
#
# It runs again for two reasons, and both are the positive twins Group 4's
# negatives were promised. Its exit status is not asserted: a machine that has
# just had the plugin taken off it is a machine doctor is entitled to have
# findings about.
DOC2="$TMP/doctor-after-remove.txt"
run_payload "$DOCTOR_SH" < /dev/null > "$DOC2" 2>&1

expect_ne "doctor: the BIONIC NATIVE table is still rendered after the teardown" "" \
  "$(doctor_section "$DOC2" "BIONIC NATIVE")"
expect_ne "doctor: the plugin-load row IS visible to the extractor once bionic is uninstalled" \
  "" "$(native_plugin_row "$DOC2")"
expect_eq "doctor: the claude() shell proxy row follows the block back off the disk" \
  "unknown" "$(env_row_state "$DOC2" "claude() shell proxy")"

# AC-7 again, from the other direction: a teardown that deleted a file the plugin
# never wrote would be the 2026-08-20 mistake repeated. The positive twin is the
# line above it, on the same extractor — a file that IS still there afterwards.
# The CLAUDE.md row below is the other case: a file setup CREATED to hold only
# bionic's block, which remove takes back to no file (wave-27 D16).
expect_eq "remove: the user's own shell rc survives the teardown" "yes" \
  "$(path_exists "$RC_FILE_FIX")"
expect_eq "remove: ~/.claude/CLAUDE.md held only bionic's block, and is gone again with it" \
  "yes no" "${MEMORY_WAS} $(path_exists "$GLOBAL_MEMORY")"
# `--all` is the consent and adds no question, so the item's own lines carry the
# deletion (wave-27 T46, review pass 14 F1): said before the act, and after it.
REMOVE_TEXT="$(cat "$REMOVE_OUT")"
expect_contains "remove --all: before it acts, the principles item says the block and the file will be deleted" \
  "will delete the block and the file ${GLOBAL_MEMORY}" "$REMOVE_TEXT"
expect_contains "remove --all: …and its result line says the file was deleted" \
  "✓ deleted ${GLOBAL_MEMORY}" "$REMOVE_TEXT"
# The page that takes the consent says it too (wave-27 T51, review pass 21 F6):
# the line is read from the page alone, everything before its question.
REMOVE_PAGE="${REMOVE_TEXT%%Do all of the above?*}"
expect_ne "remove --all: the page is on the output, ahead of its question" "$REMOVE_TEXT" "$REMOVE_PAGE"
expect_contains "remove --all: the page line for the principles says the file will be deleted" \
  "remove bionic's working principles and delete the file ${GLOBAL_MEMORY}" "$REMOVE_PAGE"

# ---------------------------------------------------------------------------
# Group 5b — the yes, on the torn-down machine (wave-27 T78). A changed claude() block
# planted after the teardown is named and never offered by `remove --all` fed nothing
# but yes, and no byte of the rc changes.
# ---------------------------------------------------------------------------

section "Group 5b: remove --all fed yes leaves a changed claude() block byte for byte"

cp "$TMP/rc-changed-4f" "$RC_FILE_FIX"
REMOVE_OUT_5B="$(printf '%s' "$YES" | run_payload "$REMOVE_SH" --all 2>&1)"
expect_contains "5b: the changed block is named by its lines" "$T78_NAMED" "$REMOVE_OUT_5B"
expect_absent "5b: …never offered" "remove bionic's claude() shell function" "$REMOVE_OUT_5B"
expect_absent "5b: …the user's line never printed" "V9=9" "$REMOVE_OUT_5B"
expect_true "5b: the rc is byte for byte as it was" cmp -s "$TMP/rc-changed-4f" "$RC_FILE_FIX"
cp "$TMP/rc-planted.zshrc" "$RC_FILE_FIX"


# ---------------------------------------------------------------------------
# Group 6 — the statusLine WRITE itself: what it preserves, and what it records
# (1.4.4 T5; review-a C-3, review-b N-1).
#
# TWO CLAIMS ABOUT ONE jq LINE. `_dep_install_statusline` sets `.statusLine` in a
# settings.json the USER owns, and both defects live in that one assignment:
# replacing the whole object throws away any sibling key the user put beside
# `command`, and writing the locator target verbatim records `ccstatusline@2.2.29`
# — not an executable — the moment anyone adopts the pin the deps.sh docblock
# holds in reserve. Neither is reachable from the Group 2-5 sequence: that fixture
# starts with no settings.json and runs the unpinned locator, so both defects are
# invisible to it and stayed invisible through two reviews.
#
# THESE GROUPS OWN THEIR OWN FIXTURE. Each calls `fresh_home` first — which also
# clears the npm shim's global state and the call log — so the row is genuinely
# pending and setup genuinely runs the install arm rather than reporting
# "present" and writing nothing. Nothing after this group reads the fixture.
# ---------------------------------------------------------------------------

section "Group 6a: the statusLine write MERGES into the user's object"

fresh_home
mkdir -p "${HOME_FIX}/.claude"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "npx ccstatusline@latest",
    "padding": 0
  }
}
JSON
expect_eq "6a precondition: the planted settings.json carries a sibling field under .statusLine" \
  "0" "$(jqf '.statusLine.padding')"

G6A_OUT="$TMP/setup-statusline-merge.txt"
printf 'y\ny\ny\n' | run_payload "$SETUP_SH" --only tool:ccstatusline > "$G6A_OUT" 2>&1

# The anti-vacuity control: if the item had reported "present" and written nothing, the
# padding below would survive for the wrong reason entirely.
expect_eq "6a: setup rewrote the npx command to the installed binary" \
  "ccstatusline" "$(jqf '.statusLine.command // ""')"
expect_eq "6a: …and the user's own field beside it is still there" \
  "0" "$(jqf '.statusLine.padding')"
expect_eq "6a: …and so is the rest of the file" \
  "opus" "$(jqf '.model // ""')"

section "Group 6b: a PINNED locator still records an executable name"

# The pin the deps.sh docblock argues against adopting today, adopted here so the write can
# be measured under it. A copy of the whole payload — setup.sh refuses to run without its
# libraries beside it — with one locator changed and nothing else.
fresh_home
# The claude home exists on any machine that has the CLI, and bionic is a plugin of it —
# `_dep_install_statusline` writes settings.json into that directory and does not create it,
# so a fixture without it measures a machine shape that cannot happen.
mkdir -p "${HOME_FIX}/.claude"
G6B_PAYLOAD="$TMP/payload-pinned"
rm -rf "$G6B_PAYLOAD"
cp -R "$PAYLOAD" "$G6B_PAYLOAD"
LC_ALL=C sed 's#npm:ccstatusline|#npm:ccstatusline@2.2.29|#' \
  "$PAYLOAD/scripts/lib/deps.sh" > "$G6B_PAYLOAD/scripts/lib/deps.sh"
expect_eq "6b: the pinned payload differs from the shipped one by exactly the locator" \
  "1" "$(diff "$PAYLOAD/scripts/lib/deps.sh" "$G6B_PAYLOAD/scripts/lib/deps.sh" | grep -c '^< ')"

G6B_OUT="$TMP/setup-statusline-pinned.txt"
printf 'y\ny\ny\n' | FH_PAYLOAD="$G6B_PAYLOAD" \
  run_payload "$G6B_PAYLOAD/scripts/setup.sh" --only tool:ccstatusline > "$G6B_OUT" 2>&1

# The pin reached the installer — without this the row below could pass on a run where the
# locator change never took effect at all.
expect_match "6b: the install ran against the pinned package" \
  '*npm install -g ccstatusline@2.2.29*' "$(cat "$CALLS")"
expect_eq "6b: …and the command recorded in settings.json is the executable, not the pin" \
  "ccstatusline" "$(jqf '.statusLine.command // ""')"

# ---------------------------------------------------------------------------
# Group 7 — the teardown asks a DIFFERENT question from the report (1.4.4 T5,
# t5-report.md R-1).
#
# A teardown wants to know whether this machine carries anything bionic wrote.
# It used to ask `check_dep`, which answers whether the row is in the HEALTHY
# state setup leaves it in — a different question, and on the pre-1.4.4 machine
# the two answers point opposite ways. Once the presence check stopped calling
# `npx ccstatusline@latest` healthy, `/bionic:remove` started calling that same
# machine "already clean" and walking away from the command in the user's
# settings.json and the config directory bionic itself copied in. Every machine
# 1.4.4 exists for is in exactly that state.
# ---------------------------------------------------------------------------

section "Group 7: remove takes bionic's statusline state off a pre-1.4.4 machine"

fresh_home
mkdir -p "${HOME_FIX}/.claude" "${HOME_FIX}/.config/ccstatusline"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "npx ccstatusline@latest"
  }
}
JSON
cp "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"
expect_eq "7 precondition: the fixture is the pre-1.4.4 machine — npx command recorded" \
  "npx ccstatusline@latest" "$(jqf '.statusLine.command // ""')"
expect_true "7 precondition: …and the layout bionic copied is on disk" test -f "$CCS_CONFIG"

G7_OUT="$TMP/remove-statusline-pre144.txt"
printf 'y\ny\ny\n' | run_payload "$REMOVE_SH" --only tool:ccstatusline > "$G7_OUT" 2>&1

# LINE-SCOPED ON PURPOSE. A glob over the whole report would pair "ccstatusline" on one
# line with "already clean" on another and answer about neither, so the claim is made
# against the ccstatusline row itself.
g7_clean_rows() {  # <file> -> the ccstatusline rows that claim the machine is clean
  grep 'ccstatusline' "$1" 2>/dev/null | grep 'already clean' 2>/dev/null
  return 0
}
expect_eq "7: no ccstatusline row calls a machine carrying bionic's statusline state clean" \
  "" "$(g7_clean_rows "$G7_OUT")"
# Named, never acted on (wave-27 T82): the row is reported for the user to remove
# by hand, and both halves stay where they are.
expect_contains "7: …it names the row for the user to remove by hand" \
  "ccstatusline: present — bionic has no record that it installed it, so it is left in place." "$(cat "$G7_OUT")"
expect_eq "7: the statusLine is still in settings.json" \
  "npx ccstatusline@latest" "$(jqf '.statusLine.command // ""')"
expect_true "7: …and so is the config directory" \
  test -d "${HOME_FIX}/.config/ccstatusline"
# AC-7's rule, on this item too: what was not bionic's is still where the user left it.
expect_eq "7: …and the rest of the user's settings.json is untouched" \
  "opus" "$(jqf '.model // ""')"

# The other direction, so the rows above are a measurement and not a constant: a machine
# with no statusline state of bionic's IS clean, and the run says so.
fresh_home
mkdir -p "${HOME_FIX}/.claude"
echo '{"model":"opus"}' > "$SETTINGS"
G7_CLEAN_OUT="$TMP/remove-statusline-clean.txt"
printf 'y\ny\n' | run_payload "$REMOVE_SH" --only tool:ccstatusline > "$G7_CLEAN_OUT" 2>&1
expect_ne "7: a machine with none of it DOES read already clean, on the same extractor" \
  "" "$(g7_clean_rows "$G7_CLEAN_OUT")"

# ---------------------------------------------------------------------------
# Group 8 — /bionic:remove takes the leftovers /bionic:setup now removes
# (1.4.4 T5 extension, plan A-8).
#
# T1 gave setup two items for the pre-plugin hook files under ~/.claude/hooks and
# the drifted role copies under ~/.claude/agents. The teardown door had neither,
# so a full consented `/bionic:remove` left behind an older build of every wall
# bionic ships and a set of role files a dispatched agent still reads. Same
# detectors, same payload-side names discipline, same consent shape.
# ---------------------------------------------------------------------------

section "Group 8: remove takes the legacy hook files and drifted agent copies"

# The claude-home the field machine had, built the way cross-gate's `ds_plant` builds it:
# payload-named files two builds behind, plus ONE file in each directory that is not
# bionic's and must survive.
g8_plant() {
  local f n=0
  rm -rf "${HOME_FIX}/.claude/hooks" "${HOME_FIX}/.claude/agents"
  mkdir -p "${HOME_FIX}/.claude/hooks" "${HOME_FIX}/.claude/agents"
  for f in "$PAYLOAD"/hooks/*.sh; do
    [ -f "$f" ] || continue
    [ "$n" -lt 16 ] || break
    printf '#!/bin/bash\n# an older build of %s\n' "${f##*/}" > "${HOME_FIX}/.claude/hooks/${f##*/}"
    n=$((n + 1))
  done
  printf '#!/bin/bash\n# the machine owner wrote this one\n' > "${HOME_FIX}/.claude/hooks/not-bionics.sh"
  for f in "$PAYLOAD"/agents/*.md; do
    [ -f "$f" ] || continue
    printf -- '---\nname: %s\n---\nan older build of this role.\n' "${f##*/}" \
      > "${HOME_FIX}/.claude/agents/${f##*/}"
  done
  printf -- '---\nname: not-bionics\n---\nthe machine owner wrote this one.\n' \
    > "${HOME_FIX}/.claude/agents/not-bionics.md"
}

g8_count() {  # <dir> <glob>
  local n=0 f
  for f in "$1"/$2; do [ -e "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

fresh_home
mkdir -p "${HOME_FIX}/.claude"
g8_plant
# The expectation is DERIVED from the payload, not typed: g8_plant copies at most sixteen of the
# shipped hook files and adds one that is not bionic's. A literal here went stale the moment the
# hook roster changed (wave-11: 19 → 14 files), which is the drift a precondition exists to catch.
G8_SHIPPED="$(g8_count "$PAYLOAD/hooks" '*.sh')"; [ "$G8_SHIPPED" -gt 16 ] && G8_SHIPPED=16
expect_eq "8 precondition: every shipped hook file (capped at sixteen) plus one not bionic's in the hooks directory" \
  "$((G8_SHIPPED + 1))" "$(g8_count "${HOME_FIX}/.claude/hooks" '*.sh')"

G8_LIST="$(run_payload "$REMOVE_SH" --list 2>&1)"
expect_match "8: legacy-hook-files is a name the teardown takes" \
  '*legacy-hook-files*' "$G8_LIST"
expect_match "8: legacy-agent-copies is a name the teardown takes" \
  '*legacy-agent-copies*' "$G8_LIST"

G8_HOOKS="$(printf 'y\ny\n' | run_payload "$REMOVE_SH" --only legacy-hook-files 2>&1)"
expect_eq "8: the consented removal leaves exactly the machine's own hook behind" \
  "1" "$(g8_count "${HOME_FIX}/.claude/hooks" '*.sh')"
expect_true "8: …and that survivor is the one the payload does not ship" \
  test -f "${HOME_FIX}/.claude/hooks/not-bionics.sh"
expect_match "8: …and the run reports what it removed" '*✓*hook file*' "$G8_HOOKS"

G8_AGENTS="$(printf 'y\ny\n' | run_payload "$REMOVE_SH" --only legacy-agent-copies 2>&1)"
expect_eq "8: the consented removal leaves exactly the machine's own agent behind" \
  "1" "$(g8_count "${HOME_FIX}/.claude/agents" '*.md')"
expect_true "8: …and that survivor is the one the payload does not ship" \
  test -f "${HOME_FIX}/.claude/agents/not-bionics.md"
expect_match "8: …and the run reports what it removed" '*✓*agent*' "$G8_AGENTS"

# The negative twin on the same extractors: with the leftovers gone both items read clean,
# so the rows above measure the removal rather than restating the fixture.
expect_match "8: a second pass over the same machine reads already clean" \
  '*already clean*' "$(printf 'y\n' | run_payload "$REMOVE_SH" --only legacy-hook-files 2>&1)"

# ---------------------------------------------------------------------------
# Group 9 — the statusline teardown clears .statusLine ONLY when it names
# ccstatusline (1.4.4 T7, review-d D-1).
#
# `dep_teardown_state`'s presence predicate is a UNION over three facts — the
# recorded command names ccstatusline, OR the config directory exists, OR the
# global package is installed — because the config directory and the package
# are bionic's to remove even once the command has moved on. The removal body
# used to treat that same union as licence to delete all three, including a
# `.statusLine` the union only asked about because of the OTHER two facts. A
# machine where the user has since pointed the status line at their OWN
# renderer, but never cleaned up the config directory bionic copied in (or the
# package bionic installed), is a real, reachable machine: use bionic, adopt a
# different renderer, then run /bionic:remove. Two shapes below, matching
# review-d's matrix rows 6 and 7 — the "new harm" rows, run beside Group 7's
# existing positive twin so this is a measurement against the same extractor,
# not a new one.
#
# SINCE wave-27 (T82) remove clears none of the three: the row is named with the
# command to remove it by hand and left. The rows below now hold that the union
# still REPORTS the row, and that the user's key and everything else survives.
# ---------------------------------------------------------------------------

section "Group 9: remove clears .statusLine only when it names ccstatusline"

# Shape one (matrix row 6): the user's own renderer, PLUS the config directory
# bionic copied in and never cleaned up. The row is still pending — the config
# directory alone makes it so — and the run must still take the directory
# while leaving the key alone.
fresh_home
mkdir -p "${HOME_FIX}/.claude" "${HOME_FIX}/.config/ccstatusline"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "my-renderer"
  }
}
JSON
cp "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"
expect_eq "9a precondition: the fixture's statusLine names the user's own renderer" \
  "my-renderer" "$(jqf '.statusLine.command // ""')"

G9A_OUT="$TMP/remove-statusline-user-owned-cfgdir.txt"
printf 'y\ny\n' | run_payload "$REMOVE_SH" --only tool:ccstatusline > "$G9A_OUT" 2>&1

g9_clean_rows() {  # <file> -> the ccstatusline rows that claim the machine is clean
  grep 'ccstatusline' "$1" 2>/dev/null | grep 'already clean' 2>/dev/null
  return 0
}
expect_eq "9a: the row is still reported — the config directory alone makes it present" \
  "" "$(g9_clean_rows "$G9A_OUT")"
expect_eq "9a: the user's own .statusLine SURVIVES the teardown" \
  "my-renderer" "$(jqf '.statusLine.command // ""')"
expect_true "9a: …and the config directory is left in place too (named, never removed)" \
  test -d "${HOME_FIX}/.config/ccstatusline"
expect_eq "9a: …and the rest of the user's settings.json is untouched" \
  "opus" "$(jqf '.model // ""')"

# Shape two (matrix row 7): the user's own renderer, PLUS the global package
# bionic installed and never uninstalled — no config directory this time, so
# the package is the only other fact making the row pending.
fresh_home
mkdir -p "${HOME_FIX}/.claude"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "my-renderer"
  }
}
JSON
printf 'ccstatusline\n' > "${STATE}/npm-global"
expect_eq "9b precondition: the fixture's statusLine names the user's own renderer" \
  "my-renderer" "$(jqf '.statusLine.command // ""')"

G9B_OUT="$TMP/remove-statusline-user-owned-pkg.txt"
printf 'y\ny\n' | run_payload "$REMOVE_SH" --only tool:ccstatusline > "$G9B_OUT" 2>&1

expect_eq "9b: the row is still reported — the installed package alone makes it present" \
  "" "$(g9_clean_rows "$G9B_OUT")"
expect_eq "9b: the user's own .statusLine SURVIVES the teardown" \
  "my-renderer" "$(jqf '.statusLine.command // ""')"
# The presence probe's own `npm list` is the positive on this log; no uninstall follows it.
expect_match "9b: the teardown asked npm whether the package is there" \
  '*npm list*ccstatusline*' "$(cat "$CALLS")"
expect_no_match "9b: …and never asked npm to uninstall it" \
  '*npm uninstall*' "$(cat "$CALLS")"
expect_eq "9b: …and the rest of the user's settings.json is untouched" \
  "opus" "$(jqf '.model // ""')"

# The positive control, on the same two extractors: a command that DOES name
# ccstatusline is exactly what Group 7 already measures — not repeated here.

# ---------------------------------------------------------------------------
# Group 10 — the four teardown removal loops are glob-safe against $PWD
# (1.4.4 T7, review-d D-2).
#
# `set -- $names` re-splits a detector's comma-separated list into positional
# parameters; unquoted, that is a pathname expansion, and two of the four
# call sites (setup's) ran it with no `set -f` guard. A payload shipping a
# hook literally named `n*.sh`, beside a machine owner's own file, with a
# decoy in the CALLING PROCESS's $PWD that happens to match that glob, turns
# the split's one "name" into whatever the decoy is — deleting the owner's
# file and leaving the payload's own leftover in place. This is the exact
# shape review-d's D-2 demonstrated against setup.sh; the same fixture proves
# remove.sh's twins were already safe and stay that way.
# ---------------------------------------------------------------------------

section "Group 10: the split loops do not glob against \$PWD"

# A fixture payload whose only shipped hook is literally named n*.sh — a
# filename no real commit would carry, chosen because it is the one the
# review's demonstration used: harmless as a literal, dangerous as a pattern.
G10_PAYLOAD="$TMP/payload-glob"
rm -rf "$G10_PAYLOAD"
cp -R "$PAYLOAD" "$G10_PAYLOAD"
# payload/hooks is a symlink to the repo's own hooks/ (`ls -la payload/`) — cp -R
# copies the LINK, not a directory, so it has to come off before this fixture can
# carry a hook roster of its own instead of the real one's.
rm -f "$G10_PAYLOAD/hooks"
mkdir -p "$G10_PAYLOAD/hooks"
printf '#!/bin/bash\n# the payload'"'"'s one hook, named to double as a glob\n' \
  > "$G10_PAYLOAD/hooks/n*.sh"

g10_plant() {  # -> builds the fixture home + a decoy $PWD, fresh each time
  fresh_home
  mkdir -p "${HOME_FIX}/.claude/hooks"
  cp "$G10_PAYLOAD/hooks/n*.sh" "${HOME_FIX}/.claude/hooks/n*.sh"
  printf '#!/bin/bash\n# the machine owner wrote this one\n' \
    > "${HOME_FIX}/.claude/hooks/not-bionics.sh"

  G10_PWD="$TMP/cwd-with-decoy"
  rm -rf "$G10_PWD"; mkdir -p "$G10_PWD"
  # The decoy: a file that has nothing to do with bionic, sitting in the
  # CALLER's cwd, whose name happens to glob-match the payload's one hook name.
  printf 'decoy\n' > "$G10_PWD/not-bionics.sh"
}

# <script-basename> <label> — runs that script's legacy-hook-files item with the
# CALLING PROCESS cd'd into the decoy directory, exactly the shape D-2 describes.
g10_run() {
  local script="$1" label="$2"
  G10_OUT="$TMP/${label}.txt"
  ( cd "$G10_PWD" && printf 'y\ny\n' | FH_PAYLOAD="$G10_PAYLOAD" \
      run_payload "$G10_PAYLOAD/scripts/${script}.sh" --only legacy-hook-files ) \
    > "$G10_OUT" 2>&1
}

g10_plant
g10_run setup setup-glob-guard-setup
expect_true "10 setup: the payload-named leftover is gone" \
  test ! -e "${HOME_FIX}/.claude/hooks/n*.sh"
expect_true "10 setup: the machine owner's file survives a glob-matching decoy in \$PWD" \
  test -f "${HOME_FIX}/.claude/hooks/not-bionics.sh"
expect_match "10 setup: the run reports the removal, not a leftover" \
  '*removed*' "$(cat "$G10_OUT")"

g10_plant
g10_run remove setup-glob-guard-remove
expect_true "10 remove: the payload-named leftover is gone" \
  test ! -e "${HOME_FIX}/.claude/hooks/n*.sh"
expect_true "10 remove: the machine owner's file survives a glob-matching decoy in \$PWD" \
  test -f "${HOME_FIX}/.claude/hooks/not-bionics.sh"

# ---------------------------------------------------------------------------
# Group 11 — the statusline teardown's jq predicate is TOTAL over
# `.statusLine`'s type (1.4.4 T8, review-e E-1).
#
# The T7 predicate, `(.statusLine.command // "") | test("ccstatusline")`, reads
# fine the moment `.statusLine` is an object and `.command` a string — every
# shape bionic itself ever writes — but a settings.json is not bionic's file,
# and `.statusLine` is a Claude Code key the CLI's own schema also accepts as a
# bare string. Indexing a string with `.command` is a jq TYPE error, not a
# missing-key null, so `// ""` never reaches it: jq exits non-zero,
# `_dep_settings_write_jq` turns that into `return 1`, and `remove_dep` returns
# from the statusline arm before the config-directory purge below it ever
# runs — on a machine carrying all three leftovers, a consented teardown then
# leaves the config directory in place, leaks a raw `jq:` line to the
# terminal, and reports the row `skipped by you` to a user who answered yes.
# The fix makes both the index and the value optional so a malformed key is
# read as "no match" instead of raised as an error.
#
# SINCE wave-27 (T82) remove runs no clear at all on this row; what stays measured
# is that a malformed key survives, no raw jq error reaches the user, and the row
# is counted neither removed nor skipped.
# ---------------------------------------------------------------------------

section "Group 11: the jq predicate is total over .statusLine's type"

fresh_home
mkdir -p "${HOME_FIX}/.claude" "${HOME_FIX}/.config/ccstatusline"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": "my-renderer"
}
JSON
cp "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"
printf 'ccstatusline\n' > "${STATE}/npm-global"

expect_eq "11 precondition: the fixture's .statusLine is a malformed (string) value" \
  "my-renderer" "$(jqf '.statusLine')"

G11_OUT="$TMP/remove-statusline-malformed-key.txt"
printf 'y\ny\n' | run_payload "$REMOVE_SH" --only tool:ccstatusline > "$G11_OUT" 2>&1

expect_eq "11: a malformed .statusLine value survives (not bionic's shape to touch)" \
  "my-renderer" "$(jqf '.statusLine')"
expect_true "11: …and the config directory is left in place (named, never removed)" \
  test -d "${HOME_FIX}/.config/ccstatusline"
expect_eq "11: …and the package is still installed (the npm recorder's state is as planted)" \
  "ccstatusline" "$(cat "${STATE}/npm-global")"
expect_no_match "11: …and no raw jq error reaches the output" \
  '*jq:*' "$(cat "$G11_OUT")"
expect_match "11: …and the run reports it neither removed nor skipped by you" \
  '*0 removed*0 already clean*0 skipped by you*' "$(cat "$G11_OUT")"

# The other two `.statusLine.command` readers (health probe, teardown-state
# union) already fail safe on this same malformed input — each swallows jq's
# stderr and never checks its exit code, so the raised type error was already
# invisible and the readers already answer "no match". Nothing here
# distinguishes their behaviour before and after aligning their jq totality,
# so — good-tests doctrine — nothing is pinned for them; the alignment is a
# robustness fix for the NEXT caller, not a behaviour change on this one.

# ---------------------------------------------------------------------------
# Group 12 — the consent-moment sentence matches what the clear actually does
# (1.4.4 T8, review-e E-2).
#
# `_rm_item_verb`'s `--all` page bullet already says the clear is conditional
# ("clears .statusLine only if it still names ccstatusline" — 1.4.4 T7,
# review-d D-1). The sentence printed immediately above the consent question
# itself, built in deps.sh's `remove_dep` and shown on BOTH the `--all` and
# `--only tool:ccstatusline` doors, still promised an unconditional clear.
# `--only` never renders the page bullet at all, so that door had no accurate
# sentence anywhere. One string, read from both doors here.
# ---------------------------------------------------------------------------

section "Group 12: the consent sentence says the clear is conditional"

fresh_home
mkdir -p "${HOME_FIX}/.claude"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "ccstatusline"
  }
}
JSON
printf 'ccstatusline\n' > "${STATE}/npm-global"

G12_ALL_OUT="$TMP/remove-statusline-consent-all.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$G12_ALL_OUT" 2>&1
expect_match "12 --all: the consent-moment sentence says the clear is conditional" \
  '*clear .statusLine*only if it still names ccstatusline*' "$(cat "$G12_ALL_OUT")"

fresh_home
mkdir -p "${HOME_FIX}/.claude"
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "statusLine": {
    "type": "command",
    "command": "ccstatusline"
  }
}
JSON
printf 'ccstatusline\n' > "${STATE}/npm-global"

G12_ONLY_OUT="$TMP/remove-statusline-consent-only.txt"
printf 'n\n' | run_payload "$REMOVE_SH" --only tool:ccstatusline > "$G12_ONLY_OUT" 2>&1
expect_match "12 --only: the (only) consent sentence this door shows says the clear is conditional" \
  '*clear .statusLine*only if it still names ccstatusline*' "$(cat "$G12_ONLY_OUT")"

# ---------------------------------------------------------------------------
# Group 13 — `_dep_rm_named_files` restores `set -f` to the CALLER's prior
# state, not unconditionally to off (1.4.4 T8, review-e E-3).
#
# Harmless at today's four call sites (every one reads the helper back through
# a command substitution, so the mutation dies in the subshell), but the
# consolidation moved the guard from two private script bodies into a public
# library function any future caller can invoke directly — exactly the moment
# an unconditional `set +f` stops being a detail nobody can observe.
# ---------------------------------------------------------------------------

section "Group 13: _dep_rm_named_files restores set -f to the caller's state"

e13_setf_after() {  # <on|off> -> the shell's OWN set -f state after a direct call
  env -i HOME="$HOME_FIX" PATH="$BIN" bash -c '
    . "$1"
    if [ "$2" = "on" ]; then set -f; else set +f; fi
    _dep_rm_named_files "'"$TMP"'/g13-nonexistent-dir" "a,b,c" >/dev/null
    case $- in *f*) echo on ;; *) echo off ;; esac
  ' _ "${LIB_DIR}/deps.sh" "$1"
}

expect_eq "13: caller's set -f ON survives a direct call" \
  "on" "$(e13_setf_after on)"
expect_eq "13: caller's set -f OFF survives a direct call" \
  "off" "$(e13_setf_after off)"

# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Group 14 — setup's LOAD-FAILURE arm names the repair route deps.sh owns
# (bionic 1.4.4 fixit T1, phase 2).
#
# THE FOURTH RENDERER. The fixit gave one owner — `dep_core_repair_route` — three
# renderers: doctor's THIRD PARTY row, doctor's headline core-absence line, and
# setup's absent-dependency action line. This arm was the fourth site naming the
# same repair and the last one still spelling it by hand, as "reinstall bionic
# with: claude plugin install <id> --scope user --yes". That wording is the one
# A-1 refutes: bionic is installed and registered, and a dependency is missing.
# The verb coincides; the description does not.
#
# THE CLI'S OWN WORDS STAY FIRST, which is this arm's older contract and is not
# what changed: the error is printed unedited, and the Fix line under it is what
# now defers to the library.
#
# WHY THIS SUITE. It is the only one that drives setup.sh against a stubbed
# listing on a fixture $HOME with PATH replaced, so the failed state can be put
# in front of the production path without touching a real CLI. The shim above
# gained the one status it could not previously report.
# ---------------------------------------------------------------------------

section "Group 14: setup's load-failure arm names the CLI's own repair route"

fresh_home
mkdir -p "${HOME_FIX}/.claude"

# THE POSITIVE ARM FIRST, on the same fixture and the same extractor: a listing
# that knows bionic and reports it healthy. Without it every assertion below
# would pass on a setup run that had crashed before step 1 printed anything.
printf 'bionic@bionic true\n' > "${STATE}/plugins"
G14_OK="$TMP/setup-load-loaded.txt"
run_payload "$SETUP_SH" < /dev/null > "$G14_OK" 2>&1
expect_match "14: a healthy listing renders the loaded row" \
  '*load state*loaded*' "$(cat "$G14_OK")"
expect_no_match "14: …and a loaded machine is told nothing about a repair" \
  '*did not load*' "$(cat "$G14_OK")"

# The same machine, with the CLI answering the way it answers when a declared
# dependency is missing (epic-17 W5 F12 §4.1).
printf 'bionic@bionic\n' > "${STATE}/load-broken"
G14_BAD="$TMP/setup-load-failed.txt"
run_payload "$SETUP_SH" < /dev/null > "$G14_BAD" 2>&1

expect_match "14: the failed arm reports the CLI's own error first, unedited" \
  '*did not load. The CLI reports:*Dependency "superpowers@bionic" is not installed*' \
  "$(cat "$G14_BAD")"
# THE FIX LINE ALONE, not the whole run. Step 2's absent-dependency action line — the
# third renderer, fixed in phase 1 — carries the same route further down the same output,
# so a glob over the whole run would match it and this row would pass on an unfixed step 1.
G14_FIX="$(grep -F 'Fix: install what the message names' "$G14_BAD" | head -1)"
expect_true "14: …the failed arm prints a Fix line at all (the two rows below are not vacuous)" \
  test -n "$G14_FIX"
expect_match "14: …and the Fix line names the route deps.sh owns" \
  "*reinstall bionic's dependencies: claude plugin install bionic@bionic*" "$G14_FIX"
# THE NEGATIVE SURVIVES THE WORDING CHANGE (1.4.4 fixit phase 4, review-c C-3). This line
# says "reinstall" now rather than "re-resolve" — plainer, and one column shorter — because
# what A-1 refutes is not the verb but the OBJECT. bionic is installed and registered; a
# dependency is missing. So the claim the row makes is that bionic is never the thing being
# reinstalled, and the bracket IS that claim: any character other than an apostrophe after
# the name makes bionic the object, which is exactly the shape of the two spellings this
# line has actually carried ("reinstall bionic with: …", "reinstall bionic so its
# dependencies resolve"). A glob of `*reinstall bionic*` cannot make this claim any more —
# it matches the correct line too.
expect_no_match "14: …and never asks for bionic ITSELF to be reinstalled, which misdescribes a machine whose only fault is a missing dependency" \
  "*reinstall bionic[!']*" "$G14_FIX"

# RENDERER 3, ON ITS OWN LINE (1.4.4 fixit phase 4, review-b B-9). Step 2's absent-core
# action line is the third site rendering `dep_core_repair_route`. This run drives it — the
# fixture home has neither core dependency, so step 2's absent arm fires twice — and until
# now nothing asserted it: the suite executed the renderer and measured nothing, so a
# regression there was invisible to the whole tree. Extracted rather than globbed over the
# whole run for the same reason the Fix line above is: both lines carry the same route, so a
# whole-run glob passes on either one alone.
G14_DEP="$(grep -F 'is missing)' "$G14_BAD" | head -1)"
expect_true "14: …step 2 prints an absent-core action line at all (the row below is not vacuous)" \
  test -n "$G14_DEP"
expect_match "14: …and it names the same route, with the dependency that is missing" \
  "*reinstall bionic's dependencies: claude plugin install bionic@bionic (superpowers is missing)*" \
  "$G14_DEP"


# ---------------------------------------------------------------------------
# Group 15 — the registry row that was dropped while the plugin's files stayed
# (REQ-S0, AC-S0.3; task-0 ruling §4 and §8).
#
# THE STATE, AND WHY IT NEEDED A NEW PROBE. `/bionic:remove` followed by a
# reinstall restores the two plugins bionic DECLARES and leaves the one it does
# not — `impeccable` is class `extra`, installed when a route asks for it, and no
# `plugin.json` dependency brings it back. What the machine is left with is a
# plugin whose files are all still in the CLI's cache and whose entry in
# `installed_plugins.json` is gone. Every probe bionic had read the registry
# alone, so that machine and a machine that never had the plugin were the same
# answer — `absent` — and setup re-downloaded bytes that were already correct
# (ruling §4: `CACHE VERDICT: CHANGED`).
#
# THREE MACHINES, ONE FIXTURE BUILDER, AND THE THIRD IS THE POINT. The arm that
# matters is the middle one — entry gone, cache present — but on its own an
# assertion that no download was attempted is a claim any broken run would
# satisfy, including one where setup crashed before it reached the row. So the
# same builder makes the two machines either side of it: one with the entry
# present, where nothing may happen at all, and one with neither the entry nor
# the cache, where a real `claude plugin install` MUST be attempted. The third is
# what makes the second's silence mean something: the same code path, the same
# fixture, the same extractor, and the opposite answer.
#
# WHY THE FIXTURE IS WRITTEN BY HAND RATHER THAN BY THE SHIM. The `claude` shim
# above records an install with an `installPath` under `$BIONIC_TEST_STATE`,
# because nothing until now cared where a plugin's files were. This group cares
# about exactly that: the cache directory under the fixture HOME is the fact
# being detected, so the registry and the cache are both written here, in the
# shape this machine's own registry carries (`"version": 2`, each key holding an
# ARRAY of entries — ruling §3).
# ---------------------------------------------------------------------------

section "Group 15: a dropped registry row is restored from the cache, not re-downloaded"

G15_REG="${HOME_FIX}/.claude/plugins/installed_plugins.json"
G15_CACHE="${HOME_FIX}/.claude/plugins/cache/bionic/impeccable"
G15_KNOWN="${HOME_FIX}/.claude/plugins/known_marketplaces.json"

# <row present: yes|no> <cache present: yes|no>
g15_plant() {
  local want_row="$1" want_cache="$2" extra=""
  fresh_home
  mkdir -p "${HOME_FIX}/.claude/plugins"
  printf '%s\n' '{}' > "${HOME_FIX}/.claude/settings.json"

  # THE CATALOG'S OWN CLONE, which is where the pinned commit is read from. A
  # `directory` feed's `installLocation` IS the checkout, so this points at the
  # tree under test and the sha the restore writes is the one this repo's
  # manifest declares — nothing is fetched to learn it.
  jq -n --arg p "$REPO" \
    '{bionic: {source: {source: "directory", path: $p}, installLocation: $p}}' > "$G15_KNOWN"

  [ "$want_row" = "yes" ] && extra=',
    "impeccable@bionic": [{"scope":"user","installPath":"'"${G15_CACHE}/4.1.1"'","version":"4.1.1"}]'
  cat > "$G15_REG" <<REG
{
  "version": 2,
  "plugins": {
    "bionic@bionic":       [{"scope":"user","installPath":"${STATE}/installed/bionic","version":"1.5.1"}],
    "superpowers@bionic":  [{"scope":"user","installPath":"${STATE}/installed/superpowers","version":"6.3.0","auto":true}],
    "agent-skills@bionic": [{"scope":"user","installPath":"${STATE}/installed/agent-skills","version":"0.6.7","auto":true}]${extra}
  }
}
REG

  if [ "$want_cache" = "yes" ]; then
    mkdir -p "${G15_CACHE}/4.1.1/.claude-plugin"
    printf '%s\n' '{"name":"impeccable","version":"4.1.1"}' \
      > "${G15_CACHE}/4.1.1/.claude-plugin/plugin.json"
  fi

  # The shim's own view, so steps 1 and 2 see a healthy machine and this group
  # measures the extras step alone.
  printf 'bionic@bionic true\nsuperpowers@bionic true\nagent-skills@bionic true\n' > "${STATE}/plugins"
  [ "$want_row" = "yes" ] && printf 'impeccable@bionic true\n' >> "${STATE}/plugins"
  return 0
}

# The library's own answer, asked in one process under the fixture's environment
# — the same way doctor and setup ask it.
g15_fires() {  # -> yes|no
  env -i HOME="$HOME_FIX" PATH="$BIN" SHELL=/bin/zsh TMPDIR="$TMPDIR_FIX" \
    BIONIC_PLUGIN_ROOT="${FH_PAYLOAD:-$PAYLOAD}" CLAUDE_PLUGIN_ROOT="${FH_PAYLOAD:-$PAYLOAD}" \
    bash -c '. "$1" >/dev/null 2>&1 || exit 1
             if bionic_check_registry_row_dropped "registry-row:impeccable" 2>/dev/null; then
               echo yes; else echo no; fi' _ "${FH_PAYLOAD:-$PAYLOAD}/scripts/lib/checks.sh" 2>/dev/null
}

# The lines of a doctor report that name this state. Counted, not matched: the
# claim AC-S0.3 makes is that there is exactly ONE, and a glob cannot say that.
g15_doctor_lines() {  # <report file> -> the count
  # NO `|| echo 0` FALLBACK. `grep -c` already prints `0` when it matches nothing
  # and merely exits 1 for it, so an `||` arm appends a SECOND zero and the value
  # becomes two lines — which reads as a failure against `0` and would have been
  # mistaken for a red row (it was, once, during this task's own red run).
  local n
  n="$(grep -c "impeccable lost its entry but its files are still on disk" "$1" 2>/dev/null)"
  printf '%s' "${n:-0}"
}

# The consent page's bullet for one item. `--all` prints the plan and then asks
# ONE question over it; with the answer channel closed the question goes
# unanswered, the run declines, and nothing on the fixture is written — which is
# how the page is read without consenting to anything.
g15_plan_bullet() {  # <report file> -> the bullet naming impeccable, or nothing
  grep -F '• ' "$1" 2>/dev/null | grep -F 'impeccable' | head -1
}

g15_row_in_registry() {  # -> the recorded version, or <absent>
  jq -r '.plugins["impeccable@bionic"][0].version // "<absent>"' "$G15_REG" 2>/dev/null \
    || echo "<unreadable>"
}

# ── Arm A: the entry is there. Nothing to detect, nothing to do. ─────────────
g15_plant yes yes
expect_eq "15A: with the entry present the dropped-row check does not fire" \
  "no" "$(g15_fires)"
G15A="$TMP/g15-present.txt"
printf 'y\ny\ny\n' | run_payload "$SETUP_SH" --only tool:impeccable > "$G15A" 2>&1
expect_no_match "15A: …and setup attempts no install for it" \
  '*plugin install impeccable@bionic*' "$(cat "$CALLS")"
expect_eq "15A: …and the entry is the one that was already there" \
  "4.1.1" "$(g15_row_in_registry)"
G15A_DOC="$TMP/g15-present-doctor.txt"
run_payload "$DOCTOR_SH" > "$G15A_DOC" 2>&1
expect_eq "15A: …and doctor says nothing about a lost entry" \
  "0" "$(g15_doctor_lines "$G15A_DOC")"

# ── Arm B: the entry is gone and the files are not. The state under test. ────
g15_plant no yes
expect_eq "15B: with the entry gone and the cache present the check fires" \
  "yes" "$(g15_fires)"
expect_eq "15B: …and the entry really is absent before the run (the rows below are not vacuous)" \
  "<absent>" "$(g15_row_in_registry)"

# DOCTOR FIRST, because a report is a diagnosis and the repair has not run yet.
# One line, and exactly one: the state is named once, with the plugin, with the
# fact that the files are still there, and with the route. Arm A above ran the
# same extractor over the same fixture with the entry present and counted zero,
# so a count of one here is the difference between two machines rather than a
# string that happens to be on every page.
G15B_DOC="$TMP/g15-restore-doctor.txt"
run_payload "$DOCTOR_SH" > "$G15B_DOC" 2>&1
expect_eq "15B: doctor names the lost entry and the files on disk, on exactly one line" \
  "1" "$(g15_doctor_lines "$G15B_DOC")"
# AND THE LINE IS WHOLE. It carries a problem and then a command, and doctor's
# first format rule is that the command survives the cut — a line that stated the
# problem and lost the route would pass the count above and help nobody.
expect_match "15B: …and that line ends with the route that clears it" \
  '*impeccable lost its entry but its files are still on disk → /bionic:setup restores it, no download' \
  "$(grep -F 'impeccable lost its entry' "$G15B_DOC" | head -1)"

# THE CONSENT PAGE, WHICH IS WHERE THE USER ACTUALLY DECIDES. A page offering to
# "install impeccable" over a machine that needs no download is asking consent
# for an act that is not the act about to be taken. Arm C below runs the same
# extractor on the machine where the install IS the act and gets the other
# sentence, so this row is a difference between machines and not a string that
# happens to be on every page.
G15B_PLAN="$TMP/g15-restore-plan.txt"
run_payload "$SETUP_SH" --all < /dev/null > "$G15B_PLAN" 2>&1
expect_eq "15B: the consent page offers a restore, not an install" \
  "  • restore impeccable's entry from the plugin cache, downloading nothing" \
  "$(g15_plan_bullet "$G15B_PLAN")"

G15B="$TMP/g15-restore.txt"
printf 'y\ny\ny\n' | run_payload "$SETUP_SH" --only tool:impeccable > "$G15B" 2>&1

expect_match "15B: setup says what it is about to do, and that it downloads nothing" \
  '*the plugin'"'"'s files are still on disk*download nothing*' "$(cat "$G15B")"
expect_eq "15B: …and the entry is back, naming the cached build's version" \
  "4.1.1" "$(g15_row_in_registry)"
expect_eq "15B: …pointing at the cache directory that was already on disk" \
  "${G15_CACHE}/4.1.1" \
  "$(jq -r '.plugins["impeccable@bionic"][0].installPath // "<absent>"' "$G15_REG")"
expect_eq "15B: …carrying the commit the catalog pins" \
  "5a149f3fdb1b5793f10567233b1dcab98fc305fd" \
  "$(jq -r '.plugins["impeccable@bionic"][0].gitCommitSha // "<absent>"' "$G15_REG")"
expect_eq "15B: …and the plugin is switched on in settings.json" \
  "true" \
  "$(jq -r '.enabledPlugins["impeccable@bionic"] // "<absent>"' "${HOME_FIX}/.claude/settings.json")"
# THE NEGATIVE, BESIDE ITS POSITIVE (arm C below runs the same extractor on the
# same fixture and comes out non-empty). Nothing was fetched: the CLI was never
# asked to install this plugin.
expect_no_match "15B: …and no install was ever attempted through the CLI" \
  '*plugin install impeccable@bionic*' "$(cat "$CALLS")"
# THE CACHE ITSELF IS NOT ASSERTED HERE, and the omission is deliberate. A stub
# `claude plugin install` does not rewrite a cache directory, so a row claiming
# the build was left alone would pass on this fixture whether the product
# downloaded or not — it could not fail, which makes it worth nothing. The
# rewrite is only visible to the real binary, so that half of AC-S0.3 is proved
# by the live rig's `CACHE VERDICT` line (tests/lib/registry-drop.sh, arm
# `setup-restores`) and reported with its before-picture beside it.
expect_eq "15B: …and the check stops firing once the entry is back" \
  "no" "$(g15_fires)"
G15B_DOC2="$TMP/g15-restored-doctor.txt"
run_payload "$DOCTOR_SH" > "$G15B_DOC2" 2>&1
expect_eq "15B: …and doctor stops naming it once the entry is back" \
  "0" "$(g15_doctor_lines "$G15B_DOC2")"

# ── Arm D: two builds in the cache, and the newer one is the CLI's leftover. ─
#
# THE CASE THE LIVE RIG FOUND, brought back here so it is asked on every run.
# `claude plugin install bionic@bionic` — setup's own first step — writes a
# bare-sha directory for every sha-pinned plugin in the catalog and registers
# none of them, so by the time the extras step reaches a dropped row the cache
# holds two builds and the NEWER one is the CLI's leftover rather than the build
# the machine was running. A restore that took the newest named a directory that
# had not existed ten seconds earlier; the version directory, whose name agrees
# with the version its own manifest declares, is the one the lost row named.
#
# THE LEFTOVER IS PLANTED WITH A MANIFEST, not as an empty directory, so the rule
# under test is the agreement between the name and the declared version and not
# merely "has a plugin.json".
g15_plant no yes
mkdir -p "${G15_CACHE}/5a149f3fdb1b/.claude-plugin"
printf '%s\n' '{"name":"impeccable","version":"4.1.1"}' \
  > "${G15_CACHE}/5a149f3fdb1b/.claude-plugin/plugin.json"
touch "${G15_CACHE}/5a149f3fdb1b"
expect_eq "15D: the planted leftover really is the newest build (the row below is not vacuous)" \
  "5a149f3fdb1b" "$(ls -1t "$G15_CACHE" | head -1)"
G15D="$TMP/g15-two-builds.txt"
printf 'y\ny\ny\n' | run_payload "$SETUP_SH" --only tool:impeccable > "$G15D" 2>&1
expect_eq "15D: the restore names the build whose name matches its own declared version" \
  "${G15_CACHE}/4.1.1" \
  "$(jq -r '.plugins["impeccable@bionic"][0].installPath // "<absent>"' "$G15_REG")"
expect_eq "15D: …and records that build's version, not the leftover's directory name" \
  "4.1.1" "$(g15_row_in_registry)"
expect_no_match "15D: …and still attempts no install" \
  '*plugin install impeccable@bionic*' "$(cat "$CALLS")"

# ── Arm C: neither entry nor cache. A real install, and it must be attempted. ─
#
# This is what makes 15B's silence a finding rather than an artefact: the same
# extractor over the same log, on the machine where a download IS the right act.
g15_plant no no
expect_eq "15C: with no cache either, the dropped-row check does not fire" \
  "no" "$(g15_fires)"
G15C_PLAN="$TMP/g15-install-plan.txt"
run_payload "$SETUP_SH" --all < /dev/null > "$G15C_PLAN" 2>&1
expect_eq "15C: …and the consent page offers an install, which is what this machine needs" \
  "  • install impeccable" "$(g15_plan_bullet "$G15C_PLAN")"

G15C="$TMP/g15-install.txt"
printf 'y\ny\ny\n' | run_payload "$SETUP_SH" --only tool:impeccable > "$G15C" 2>&1
expect_match "15C: …and setup installs it through the CLI, as it always did" \
  '*plugin install impeccable@bionic*' "$(cat "$CALLS")"

# ---------------------------------------------------------------------------
# Group 16 — remove names every tool it cannot prove it installed, and acts on
# none of them (wave-27 T82).
#
# PRESENCE IS NOT PROVENANCE. The tools item used to hand every `remove-on-consent`
# row it found PRESENT to `remove_dep`, which printed a plan, asked, and on a yes
# ran it: a package the user installed themselves came off exactly like one bionic
# installed. Nothing on a machine records which tools bionic put there, so every
# such row is now named, with the command that removes it by hand, and left —
# on every door and under `--all`. The one record the machine does keep is the
# native plugin registry's `<name>@bionic` id, and that row is still removed.
#
# The fixture carries one present row of each `remove-on-consent` kind:
# statusline, npm-global, uv-tool, uv-project, playwright-browser, pnpm-store,
# mcp-server, github-skill — plus the native `impeccable@bionic`. Every package
# manager on PATH is a recorder in $BIN, so a call is visible in the log and
# reaches nothing real. The pnpm store (T85) is an index.db at the path the
# doors are told through `BIONIC_PNPM_STORE`, so the probe never runs pnpm.
# ---------------------------------------------------------------------------

section "Group 16: remove names each declared tool it finds and removes none of them"

# The rows the fixture makes present, in the table's order (the order the item
# walks), each with its by-hand plan.
G16_NAMES="excalidraw-renderer @playwright/cli playwright-chromium motion ccstatusline notebooklm context7 humanizer"
G16_PW_CACHE="${HOME_FIX}/.cache/ms-playwright"
G16_PNPM_STORE="${HOME_FIX}/.local/share/pnpm/store/v10"
FH_PNPM_STORE="$G16_PNPM_STORE"

# A path as a door prints it: the fixture home written `~/`.
g16_home() { local tl='~/'; printf '%s' "${1//"$HOME_FIX"\//$tl}"; }

g16_plan() {  # <name> -> the command the by-hand line must carry
  case "$1" in
    excalidraw-renderer) printf 'rm -rf %s %s' "$(g16_home "$VENV_DIR")" "$(g16_home "${VENV_DIR}.lock.sha256")" ;;
    @playwright/cli)     printf 'npm uninstall -g @playwright/cli' ;;
    # T88: the cache is shared, so the line names Playwright's own uninstall, never the cache.
    playwright-chromium)
      printf 'npx --yes playwright@latest uninstall — its cache is shared with your other projects, so nothing here removes it whole' ;;
    motion)
      printf 'pnpm store prune — the store is shared with your other projects, so this removes only the packages none of them references' ;;
    ccstatusline)
      printf 'npm uninstall -g ccstatusline, clear .statusLine from %s only if it still names ccstatusline, and remove %s' \
        "$(g16_home "$SETTINGS")" "$(g16_home "${HOME_FIX}/.config/ccstatusline")" ;;
    notebooklm)          printf 'uv tool uninstall notebooklm-py && rm -rf %s' "$(g16_home "${HOME_FIX}/.claude/skills/notebooklm")" ;;
    context7)            printf 'claude mcp remove context7 -s user' ;;
    humanizer)           printf 'rm -rf %s' "$(g16_home "${HOME_FIX}/.claude/skills/humanizer")" ;;
  esac
}

g16_plant() {  # [native] — one present row of each kind; `native` adds impeccable@bionic
  fresh_home
  mkdir -p "${HOME_FIX}/.claude/skills/humanizer" "${HOME_FIX}/.claude/skills/notebooklm" \
           "${HOME_FIX}/.config/ccstatusline" "${G16_PW_CACHE}/chromium-1187" "${VENV_DIR}/bin" \
           "$G16_PNPM_STORE"
  printf 'some binary-ish preamble\nmotion@12.23.12\nmore\n' > "${G16_PNPM_STORE}/index.db"
  printf '%s\n' '{"model":"opus","statusLine":{"type":"command","command":"ccstatusline"}}' > "$SETTINGS"
  cp "$CCSTATUSLINE_SHIPPED" "$CCS_CONFIG"
  printf 'ccstatusline\n@playwright/cli\n' > "${STATE}/npm-global"
  printf 'context7\n' > "${STATE}/mcp"
  : > "${G16_PW_CACHE}/chromium-1187/INSTALLATION_COMPLETE"
  printf '#!/bin/bash\nexit 0\n' > "${VENV_DIR}/bin/python"; chmod +x "${VENV_DIR}/bin/python"
  printf -- '---\nname: humanizer\n---\n' > "${HOME_FIX}/.claude/skills/humanizer/SKILL.md"
  printf -- '---\nname: notebooklm\n---\n' > "${HOME_FIX}/.claude/skills/notebooklm/SKILL.md"
  printf '#!/bin/bash\necho "notebooklm $*" >> "$BIONIC_TEST_CALLS"\nexit 0\n' > "${BIN}/notebooklm"
  chmod +x "${BIN}/notebooklm"
  if [ "${1:-}" = "native" ]; then
    mkdir -p "${HOME_FIX}/.claude/plugins"
    printf '%s\n' '{"version":2,"plugins":{"impeccable@bionic":[{"scope":"user","installPath":"/x","version":"4.1.1"}]}}' \
      > "${HOME_FIX}/.claude/plugins/installed_plugins.json"
    printf 'impeccable@bionic true\n' > "${STATE}/plugins"
  fi
  : > "$CALLS"
}

# Every file and directory the tool rows stand on, with each file's bytes, plus
# the recorders' own state for the npm globals and the MCP servers. `g16_snap` is
# its digest, so a red row prints one line rather than the whole listing.
g16_snap_raw() {
  local p
  for p in "$SETTINGS" "${HOME_FIX}/.config" "${HOME_FIX}/.cache" "${HOME_FIX}/.local" \
           "${HOME_FIX}/.claude/skills" "${STATE}/npm-global" "${STATE}/mcp"; do
    [ -e "$p" ] || { echo "absent ${p}"; continue; }
    find "$p" -print | LC_ALL=C sort
    find "$p" -type f -exec shasum {} + | LC_ALL=C sort
  done
}
g16_snap() { g16_snap_raw | shasum | awk '{ print $1 }'; }

# The removal calls in the recorders' log: every way a package manager, the MCP
# list or a pip/brew could have been asked to take something off.
g16_acts() {
  grep -E '^(npm uninstall|npm remove|npm rm|uv tool uninstall|uv pip uninstall|pip3? uninstall|brew uninstall|pnpm (remove|rm|store prune)|claude mcp remove)' \
    "$CALLS" 2>/dev/null
  return 0
}

# yes when the item's two lines for <name> stand together, the second right under the first.
g16_pair() {  # <file> <name> <plan>
  local want1="  ${2}: present — bionic has no record that it installed it, so it is left in place."
  local want2="    remove it by hand with: ${3}" line prev=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$prev" = "$want1" ] && [ "$line" = "$want2" ] && { printf yes; return 0; }
    prev="$line"
  done < "$1"
  printf no
}

# How many lines ask to remove <name>.
g16_asks() {  # <file> <name>
  grep -cF "Remove ${2} now?" "$1" 2>/dev/null
  return 0
}

# The names under the summary's by-hand heading, space-joined, in order.
g16_byhand() {  # <file>
  local line on=0 out=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "  left for you to remove by hand:" ]; then on=1; continue; fi
    [ "$on" = "1" ] || continue
    [ -n "$line" ] || break
    out="${out:+${out} }${line#    • }"
  done < "$1"
  printf '%s' "$out"
}

g16_door_rows() {  # <label> <output file> <snapshot before>
  local label="$1" out="$2" before="$3" n
  for n in $G16_NAMES; do
    expect_eq "16 ${label}: ${n} is named, with the command to remove it by hand" \
      "yes" "$(g16_pair "$out" "$n" "$(g16_plan "$n")")"
    expect_eq "16 ${label}: …and nothing asks to remove ${n}" "0" "$(g16_asks "$out" "$n")"
    expect_absent "16 ${label}: …and no 'answer yes' route is printed for ${n}" "answer yes to tool:${n}" "$(cat "$out")"
  done
  expect_eq "16 ${label}: no package manager, MCP remove, pip or brew was asked to remove anything" "" "$(g16_acts)"
  expect_eq "16 ${label}: every file and directory the tool rows stand on is byte for byte as it was" \
    "$before" "$(g16_snap)"
}

# The extractors, proven on real output before any row leans on them.
g16_plant native
G16_BEFORE="$(g16_snap)"
expect_ne "16 precondition: the snapshot digest reads (it is not empty)" "" "$G16_BEFORE"
expect_contains "16 precondition: …and the listing under it holds the planted ccstatusline layout" \
  ".config/ccstatusline/settings.json" "$(g16_snap_raw)"
for n in $G16_NAMES; do
  expect_eq "16 precondition: ${n} reads as present to the teardown" "yes" \
    "$(env -i HOME="$HOME_FIX" PATH="$BIN" BIONIC_TEST_CALLS="$CALLS" BIONIC_TEST_STATE="$STATE" \
         BIONIC_PLUGIN_ROOT="$PAYLOAD" CLAUDE_PLUGIN_ROOT="$PAYLOAD" BIONIC_PLAYWRIGHT_CACHE="$G16_PW_CACHE" \
         BIONIC_PNPM_STORE="$G16_PNPM_STORE" \
         bash -c '. "$1"; dep_teardown_state "$2"' _ "${LIB_DIR}/deps.sh" "$n" 2>/dev/null)"
done
: > "$CALLS"

# ── the interactive door, every question answered yes ──
G16_INT="$TMP/g16-interactive.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" > "$G16_INT" 2>&1
G16_INT_RC=$?
expect_eq "16 interactive: remove exits 0, as a run with these rows declined or absent does" "0" "$G16_INT_RC"
g16_door_rows "interactive" "$G16_INT" "$G16_BEFORE"
expect_eq "16 interactive: the one row the machine records as bionic's is still asked about (the question extractor reads)" \
  "1" "$(g16_asks "$G16_INT" impeccable)"
expect_match "16 interactive: …and still removed through the CLI's plugin uninstall" \
  '*claude plugin uninstall impeccable@bionic --yes*' "$(cat "$CALLS")"
expect_eq "16 interactive: the summary names every row left for the user to remove by hand" \
  "$G16_NAMES" "$(g16_byhand "$G16_INT")"

# ── the by-hand command runs as typed ──
# Each `~/` word of every by-hand line, handed to /bin/bash 3.2 and to zsh with the
# fixture's HOME, expands to the path the plan was composed with. The fixture home
# lives under the temp root, not /Users, so nothing here leans on a familiar prefix.
g16_tilde_check() {  # <file> <shell> -> "<checked> <mismatches>"
  local line w got n=0 bad=0
  while IFS= read -r line; do
    case "$line" in *"remove it by hand with: "*) ;; *) continue ;; esac
    for w in ${line#*remove it by hand with: }; do
      case "$w" in '~/'*) ;; *) continue ;; esac
      n=$((n + 1))
      got="$(env -i HOME="$HOME_FIX" "$2" -c "printf '%s' $w" 2>/dev/null)"
      [ "$got" = "${HOME_FIX}/${w#\~/}" ] || bad=$((bad + 1))
    done
  done < "$1"
  printf '%s %s' "$n" "$bad"
}
expect_no_match "16 by hand: the fixture home is not under /Users" '/Users/*' "$HOME_FIX"
# Six words: the playwright line names no path since T88.
expect_eq "16 by hand: every ~/ word of the by-hand lines expands to its path under /bin/bash (6 words, 0 wrong)" \
  "6 0" "$(g16_tilde_check "$G16_INT" /bin/bash)"
expect_eq "16 by hand: …and under zsh" "6 0" "$(g16_tilde_check "$G16_INT" "$(command -v zsh)")"
# A path that holds the home's spelling but does not start with it is printed as it is.
expect_eq "16 by hand: only a word that starts with the home is written ~/" \
  "rm -rf /elsewhere${HOME_FIX}/x ~/y" \
  "$(env -i HOME="$HOME_FIX" PATH="$BIN" bash -c '. "$1"; _dep_home_form "$2"' _ "${LIB_DIR}/deps.sh" \
       "rm -rf /elsewhere${HOME_FIX}/x ${HOME_FIX}/y")"

# ── --only tool:<name>, each row on its own ──
for n in $G16_NAMES; do
  g16_plant
  G16_ONLY="$TMP/g16-only.txt"
  printf 'y\ny\ny\n' | run_payload "$REMOVE_SH" --only "tool:${n}" > "$G16_ONLY" 2>&1
  expect_eq "16 --only tool:${n}: remove exits 0" "0" "$?"
  expect_eq "16 --only tool:${n}: the row is named, with the command to remove it by hand" \
    "yes" "$(g16_pair "$G16_ONLY" "$n" "$(g16_plan "$n")")"
  expect_eq "16 --only tool:${n}: …nothing asks to remove it" "0" "$(g16_asks "$G16_ONLY" "$n")"
  expect_eq "16 --only tool:${n}: …nothing was called" "" "$(g16_acts)"
  expect_eq "16 --only tool:${n}: …and the fixture is byte for byte as it was" "$G16_BEFORE" "$(g16_snap)"
done

# ── --all, the page answered yes ──
g16_plant native
G16_ALL="$TMP/g16-all.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$G16_ALL" 2>&1
expect_eq "16 --all: remove exits 0" "0" "$?"
G16_ALL_TEXT="$(cat "$G16_ALL")"
G16_PAGE="${G16_ALL_TEXT%%Do all of the above?*}"
expect_ne "16 --all: the page is on the output, ahead of its question" "$G16_ALL_TEXT" "$G16_PAGE"
expect_eq "16 --all: one question is put, the page's (the question counter reads)" \
  "1" "$(grep -c '\[y/N\]' "$G16_ALL")"
expect_contains "16 --all: the native row bionic's catalog installed is on the page" "• remove impeccable" "$G16_PAGE"
for n in $G16_NAMES; do
  expect_absent "16 --all: ${n} is not on the page" "• remove ${n}" "$G16_PAGE"
done
g16_door_rows "--all" "$G16_ALL" "$G16_BEFORE"
expect_match "16 --all: the native row is still removed through the CLI's plugin uninstall on the page's yes" \
  '*claude plugin uninstall impeccable@bionic --yes*' "$(cat "$CALLS")"
expect_eq "16 --all: the summary names every row left for the user to remove by hand" \
  "$G16_NAMES" "$(g16_byhand "$G16_ALL")"

# ── --all on a machine where the by-hand rows are all there is ──
# The page is empty, and the run must still name what it leaves rather than call
# the machine clean.
g16_plant
G16_ALL0="$TMP/g16-all-none-on-page.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$G16_ALL0" 2>&1
expect_eq "16 --all, nothing on the page: remove exits 0" "0" "$?"
expect_eq "16 --all, nothing on the page: ccstatusline is still named, with its by-hand command" \
  "yes" "$(g16_pair "$G16_ALL0" ccstatusline "$(g16_plan ccstatusline)")"
expect_absent "16 --all, nothing on the page: …and the run does not call the machine clean" \
  "this machine is already clean" "$(cat "$G16_ALL0")"
expect_eq "16 --all, nothing on the page: …and its summary names every row left for the user" \
  "$G16_NAMES" "$(g16_byhand "$G16_ALL0")"
expect_eq "16 --all, nothing on the page: …and no question was put to anyone" \
  "0" "$(grep -c '\[y/N\]' "$G16_ALL0")"
expect_eq "16 --all, nothing on the page: …and nothing was called" "" "$(g16_acts)"
expect_eq "16 --all, nothing on the page: …and the fixture is byte for byte as it was" "$G16_BEFORE" "$(g16_snap)"

# ── remove_dep called directly, with the page's consent already in force ──
g16_direct() {  # <name> — remove_dep under RM_ALL=1, yes on stdin; prints its output and rc=<n>
  printf 'y\ny\n' | env -i HOME="$HOME_FIX" PATH="$BIN" BIONIC_TEST_CALLS="$CALLS" BIONIC_TEST_STATE="$STATE" \
    BIONIC_TEST_BIN="$BIN" BIONIC_TEST_SHIMSRC="$SHIMSRC" BIONIC_TEST_PKG_MAP="$PKG_MAP" \
    BIONIC_PLUGIN_ROOT="$PAYLOAD" CLAUDE_PLUGIN_ROOT="$PAYLOAD" BIONIC_PLAYWRIGHT_CACHE="$G16_PW_CACHE" \
    BIONIC_PNPM_STORE="$G16_PNPM_STORE" \
    bash -c '. "$1"; RM_ALL=1; remove_dep "$2"; echo "rc=$?"' _ "${LIB_DIR}/deps.sh" "$1" 2>&1
}
g16_plant
G16_DIRECT="$TMP/g16-direct.txt"
for n in $G16_NAMES; do
  g16_direct "$n" > "$G16_DIRECT"
  expect_contains "16 remove_dep ${n}: returns 2, left in place by policy" "rc=2" "$(cat "$G16_DIRECT")"
  expect_eq "16 remove_dep ${n}: …prints the two lines" "yes" "$(g16_pair "$G16_DIRECT" "$n" "$(g16_plan "$n")")"
done
expect_eq "16 remove_dep: no row called anything, consent in force or not" "" "$(g16_acts)"
expect_eq "16 remove_dep: …and the fixture is byte for byte as it was" "$G16_BEFORE" "$(g16_snap)"

# ── the mutant: the act restored on top of the named row ──
# A doctored copy whose remove_dep, after naming a row, asks and runs the plan
# it named. The same extractors read it, so the rows above are a measurement: a
# remove that acts turns them red.
G16_MUT="$TMP/payload-g16-mutant"
rm -rf "$G16_MUT"; cp -R "$PAYLOAD" "$G16_MUT"
cat >> "$G16_MUT/scripts/lib/deps.sh" <<'MUT'
eval "_g16_named_$(declare -f remove_dep)"
remove_dep() {
  local rc
  _g16_named_remove_dep "$@"; rc=$?
  { [ "$rc" = 2 ] && [ "$(dep_field "$1" removal_behavior)" = remove-on-consent ]; } || return "$rc"
  _dep_consent "Remove ${1} now?" || return 1
  eval "$(_dep_remove_plan "$1")"
}
MUT
expect_true "16 mutant: the doctored library still parses" bash -n "$G16_MUT/scripts/lib/deps.sh"
g16_plant
G16_MUT_OUT="$TMP/g16-mutant.txt"
printf 'y\ny\ny\n' | FH_PAYLOAD="$G16_MUT" run_payload "$G16_MUT/scripts/remove.sh" --only tool:@playwright/cli \
  > "$G16_MUT_OUT" 2>&1
expect_eq "16 mutant: the mutant run reached the item (its question is on the output)" \
  "1" "$(g16_asks "$G16_MUT_OUT" @playwright/cli)"
expect_ne "16 mutant: …and the act-call extractor sees its uninstall" "" "$(g16_acts)"
expect_ne "16 mutant: …and the snapshot sees the machine change" "$G16_BEFORE" "$(g16_snap)"

# ── a declined native row still gets its route, so the absence above is a measurement ──
# The whole run, every question answered no: the summary's Skipped list carries the route.
g16_plant native
G16_NATIVE_N="$TMP/g16-native-declined.txt"
for _ in $(seq 1 80); do printf 'n\n'; done | run_payload "$REMOVE_SH" > "$G16_NATIVE_N" 2>&1
expect_contains "16: a declined native row is given its 'answer yes' route (the route extractor reads)" \
  "answer yes to tool:impeccable" "$(cat "$G16_NATIVE_N")"

# ── a run that named something never calls the machine clean (review pass 67 P2-1) ──
# A changed claude() block alone, the tools alone (the "nothing on the page" rows
# above), and both; the twin is a machine with nothing on it, which IS clean.
fresh_home; mkdir -p "${HOME_FIX}/.claude"
G16_CLEAN="$(printf 'y\n' | run_payload "$REMOVE_SH" --all 2>&1)"
expect_contains "16 named: a machine with nothing on it is called clean (the phrase extractor reads)" \
  "nothing to remove — this machine is already clean." "$G16_CLEAN"
fresh_home; mkdir -p "${HOME_FIX}/.claude"; cp "$TMP/rc-changed-4f" "$RC_FILE_FIX"
G16_BLK="$(printf 'y\n' | run_payload "$REMOVE_SH" --all 2>&1)"
expect_contains "16 named, a changed claude() block alone: it is named by its lines" "$T78_NAMED" "$G16_BLK"
expect_contains "16 named, a changed claude() block alone: …the run says bionic has nothing to remove" \
  "nothing for bionic to remove" "$G16_BLK"
expect_absent "16 named, a changed claude() block alone: …and never calls the machine clean" \
  "already clean" "$G16_BLK"
expect_true "16 named, a changed claude() block alone: …and the rc is byte for byte as it was" \
  cmp -s "$TMP/rc-changed-4f" "$RC_FILE_FIX"
g16_plant; cp "$TMP/rc-changed-4f" "$RC_FILE_FIX"
G16_BOTH="$TMP/g16-both.txt"
printf 'y\n' | run_payload "$REMOVE_SH" --all > "$G16_BOTH" 2>&1
expect_contains "16 named, block and tools: the block is named by its lines" "$T78_NAMED" "$(cat "$G16_BOTH")"
expect_eq "16 named, block and tools: …ccstatusline is named with its by-hand command" \
  "yes" "$(g16_pair "$G16_BOTH" ccstatusline "$(g16_plan ccstatusline)")"
expect_absent "16 named, block and tools: …and the run never calls the machine clean" \
  "this machine is already clean" "$(cat "$G16_BOTH")"
expect_eq "16 named, block and tools: …and nothing was called" "" "$(g16_acts)"

# ── T85: the pnpm store and the excalidraw venv, each alone on the machine ──
# The two kinds T82 held still (review pass 70): `motion` was counted removed
# while nothing was, and a venv stale against uv.lock read "not knowable" to the
# item and "already clean" to the `--all` page. Each fixture carries that one row
# and nothing else, so a row the item failed to name leaves nothing else to speak.
g16_alone() {  # motion | venv-fresh | venv-stale | venv-none
  fresh_home
  # The recorders' empty state, as their first probe would leave it.
  : > "${STATE}/npm-global"; : > "${STATE}/mcp"
  case "$1" in
    motion)
      mkdir -p "$G16_PNPM_STORE"
      printf 'some binary-ish preamble\nmotion@12.23.12\nmore\n' > "${G16_PNPM_STORE}/index.db" ;;
    venv-fresh|venv-stale)
      mkdir -p "${VENV_DIR}/bin"
      printf '#!/bin/bash\nexit 0\n' > "${VENV_DIR}/bin/python"; chmod +x "${VENV_DIR}/bin/python"
      if [ "$1" = venv-fresh ]; then
        shasum -a 256 "${PAYLOAD}/skills/excalidraw-diagram/references/uv.lock" | awk '{ print $1 }' \
          > "$VENV_LOCK_HASH"
      else
        printf '%s\n' "a-lock-this-venv-was-not-synced-against" > "$VENV_LOCK_HASH"
      fi ;;
  esac
  : > "$CALLS"
}
g16_lib() {  # <function> <name> — a deps.sh answer on the fixture machine
  env -i HOME="$HOME_FIX" PATH="$BIN" BIONIC_TEST_CALLS="$CALLS" BIONIC_TEST_STATE="$STATE" \
    BIONIC_PLUGIN_ROOT="$PAYLOAD" CLAUDE_PLUGIN_ROOT="$PAYLOAD" BIONIC_PNPM_STORE="$G16_PNPM_STORE" \
    BIONIC_PLAYWRIGHT_CACHE="$G16_PW_CACHE" \
    bash -c '. "$1"; "$2" "$3"' _ "${LIB_DIR}/deps.sh" "$1" "$2" 2>/dev/null
}
# The summary's removed and already-clean counts, "<removed> <clean>".
g16_tally() {  # <file>
  grep -F ' removed · ' "$1" | tail -1 | awk '{ print $1, $4 }'
}
# Every call the pnpm recorder logged.
g16_pnpm_calls() { grep '^pnpm ' "$CALLS" 2>/dev/null; return 0; }

g16_alone motion
G16_T85_BEFORE="$(g16_snap)"
expect_eq "16 motion alone: the pnpm store's index reads motion as present to the teardown" \
  "yes" "$(g16_lib dep_teardown_state motion)"
G16_M_ONLY="$TMP/g16-motion-only.txt"
printf 'y\ny\ny\n' | run_payload "$REMOVE_SH" --only tool:motion > "$G16_M_ONLY" 2>&1
expect_eq "16 motion --only: motion is named, with the store's by-hand command" \
  "yes" "$(g16_pair "$G16_M_ONLY" motion "$(g16_plan motion)")"
expect_eq "16 motion --only: …nothing asks to remove it" "0" "$(g16_asks "$G16_M_ONLY" motion)"
expect_eq "16 motion --only: …the summary counts it neither removed nor clean (the tally reads 0 0)" \
  "0 0" "$(g16_tally "$G16_M_ONLY")"
expect_eq "16 motion --only: …and the summary names it to remove by hand" "motion" "$(g16_byhand "$G16_M_ONLY")"
expect_eq "16 motion --only: …pnpm was never called" "" "$(g16_pnpm_calls)"
g16_alone motion
G16_M_ALL="$TMP/g16-motion-all.txt"
printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$G16_M_ALL" 2>&1
expect_eq "16 motion --all: motion is named, with the store's by-hand command" \
  "yes" "$(g16_pair "$G16_M_ALL" motion "$(g16_plan motion)")"
expect_absent "16 motion --all: …motion is not on the page" "• remove motion" "$(cat "$G16_M_ALL")"
expect_eq "16 motion --all: …no question was put to anyone" "0" "$(grep -c '\[y/N\]' "$G16_M_ALL")"
expect_eq "16 motion --all: …the summary says 0 removed" "0" "$(g16_tally "$G16_M_ALL" | awk '{ print $1 }')"
expect_eq "16 motion --all: …and names motion to remove by hand" "motion" "$(g16_byhand "$G16_M_ALL")"
expect_absent "16 motion --all: …and never calls the machine clean" "this machine is already clean" "$(cat "$G16_M_ALL")"
# The whole run probes the keep-shared `pnpm` row's version; motion asks pnpm nothing.
expect_eq "16 motion --all: …pnpm was asked nothing but the pnpm row's version" "" \
  "$(g16_pnpm_calls | grep -vx 'pnpm --version')"
expect_eq "16 motion --all: …nothing was asked to remove anything" "" "$(g16_acts)"
expect_eq "16 motion --all: …and the store is byte for byte as it was" "$G16_T85_BEFORE" "$(g16_snap)"
env -i PATH="$BIN" BIONIC_TEST_CALLS="$CALLS" pnpm store path >/dev/null 2>&1
expect_ne "16 motion: the pnpm call extractor, version probes set aside, reads a call the recorder logged" "" \
  "$(g16_pnpm_calls | grep -vx 'pnpm --version')"

for g16_v in venv-fresh venv-stale; do
  g16_alone "$g16_v"
  G16_V_BEFORE="$(g16_snap)"
  case "$g16_v" in venv-fresh) g16_want='present=yes*' ;; *) g16_want='present=stale*' ;; esac
  expect_match "16 ${g16_v}: doctor's and setup's probe still reads it ${g16_want%%\**}" \
    "$g16_want" "$(g16_lib check_dep excalidraw-renderer)"
  expect_eq "16 ${g16_v}: the teardown reads the venv on disk as present" \
    "yes" "$(g16_lib dep_teardown_state excalidraw-renderer)"
  G16_V_ONLY="$TMP/g16-${g16_v}-only.txt"
  printf 'y\ny\ny\n' | run_payload "$REMOVE_SH" --only tool:excalidraw-renderer > "$G16_V_ONLY" 2>&1
  expect_eq "16 ${g16_v} --only: the venv is named, with its rm -rf plan" \
    "yes" "$(g16_pair "$G16_V_ONLY" excalidraw-renderer "$(g16_plan excalidraw-renderer)")"
  expect_absent "16 ${g16_v} --only: …never 'not knowable'" "not knowable" "$(cat "$G16_V_ONLY")"
  expect_eq "16 ${g16_v} --only: …counted neither removed nor clean (the tally reads 0 0)" \
    "0 0" "$(g16_tally "$G16_V_ONLY")"
  expect_eq "16 ${g16_v} --only: …and named to remove by hand" "excalidraw-renderer" "$(g16_byhand "$G16_V_ONLY")"
  g16_alone "$g16_v"
  G16_V_ALL="$TMP/g16-${g16_v}-all.txt"
  printf '%s' "$YES" | run_payload "$REMOVE_SH" --all > "$G16_V_ALL" 2>&1
  expect_eq "16 ${g16_v} --all: the venv is named, with its rm -rf plan" \
    "yes" "$(g16_pair "$G16_V_ALL" excalidraw-renderer "$(g16_plan excalidraw-renderer)")"
  expect_absent "16 ${g16_v} --all: …never 'already clean'" "this machine is already clean" "$(cat "$G16_V_ALL")"
  expect_eq "16 ${g16_v} --all: …named to remove by hand" "excalidraw-renderer" "$(g16_byhand "$G16_V_ALL")"
  expect_eq "16 ${g16_v} --all: …nothing was called" "" "$(g16_acts)"
  expect_eq "16 ${g16_v} --all: …and the venv is byte for byte as it was" "$G16_V_BEFORE" "$(g16_snap)"
done

g16_alone venv-none
expect_eq "16 no venv: the teardown reads it absent" "no" "$(g16_lib dep_teardown_state excalidraw-renderer)"
G16_V_NONE="$TMP/g16-venv-none-only.txt"
printf 'y\ny\ny\n' | run_payload "$REMOVE_SH" --only tool:excalidraw-renderer > "$G16_V_NONE" 2>&1
expect_contains "16 no venv --only: the row reports not installed" \
  "excalidraw-renderer (not installed) — already clean" "$(cat "$G16_V_NONE")"
expect_eq "16 no venv --only: …and is not named" \
  "no" "$(g16_pair "$G16_V_NONE" excalidraw-renderer "$(g16_plan excalidraw-renderer)")"

# ── T85's mutants: the old `return 0` and the old `unknown`, each in a doctored copy ──
G16_M1="$TMP/payload-g16-t85-return0"
rm -rf "$G16_M1"; cp -R "$PAYLOAD" "$G16_M1"
cat >> "$G16_M1/scripts/lib/deps.sh" <<'MUT'
eval "_g16_t85_$(declare -f remove_dep)"
remove_dep() {
  if [ "$(dep_field "$1" install_fn_or_check)" = pnpm-store ]; then
    echo "$(_dep_indent)${1}: lives in the shared pnpm store — removing it would evict a cache other projects hard-link from; leaving it."
    return 0
  fi
  _g16_t85_remove_dep "$@"
}
MUT
expect_true "16 mutant return 0: the doctored library still parses" bash -n "$G16_M1/scripts/lib/deps.sh"
g16_alone motion
G16_M1_OUT="$TMP/g16-t85-return0.txt"
printf 'y\ny\ny\n' | FH_PAYLOAD="$G16_M1" run_payload "$G16_M1/scripts/remove.sh" --only tool:motion > "$G16_M1_OUT" 2>&1
expect_contains "16 mutant return 0: the mutant run reached the pnpm-store line" "lives in the shared pnpm store" \
  "$(cat "$G16_M1_OUT")"
expect_eq "16 mutant return 0: …and the tally extractor sees it counted removed" "1 0" "$(g16_tally "$G16_M1_OUT")"

G16_M2="$TMP/payload-g16-t85-unknown"
rm -rf "$G16_M2"; cp -R "$PAYLOAD" "$G16_M2"
cat >> "$G16_M2/scripts/lib/deps.sh" <<'MUT'
dep_teardown_state() {
  local name="${1:-}" raw
  if [ "$(dep_field "$name" install_fn_or_check)" = "statusline" ]; then
    if _dep_statusline_leftovers "$name"; then echo "yes"; else echo "no"; fi
    return 0
  fi
  raw="$(check_dep "$name")" || return 1
  raw="${raw#present=}"
  echo "${raw%%|*}"
}
MUT
expect_true "16 mutant unknown: the doctored library still parses" bash -n "$G16_M2/scripts/lib/deps.sh"
g16_alone venv-stale
G16_M2_OUT="$TMP/g16-t85-unknown.txt"
printf 'y\ny\ny\n' | FH_PAYLOAD="$G16_M2" run_payload "$G16_M2/scripts/remove.sh" --only tool:excalidraw-renderer \
  > "$G16_M2_OUT" 2>&1
expect_contains "16 mutant unknown: the mutant run reached the tools item and called the venv not knowable" \
  "excalidraw-renderer: presence is not knowable" "$(cat "$G16_M2_OUT")"
expect_eq "16 mutant unknown: …and the pair extractor sees it unnamed" \
  "no" "$(g16_pair "$G16_M2_OUT" excalidraw-renderer "$(g16_plan excalidraw-renderer)")"

# ── T88: the playwright browser, alone on the machine ──
# `ms-playwright` is one cache every project's Playwright shares, so the by-hand
# line names Playwright's own uninstall (the browsers of the version it runs) and
# says the cache is shared; no door prints `rm -rf` over it. Nothing here can
# answer yes: `--only` reads /dev/null and the `--all` page reads `n`.
g16_pw_alone() {
  fresh_home
  : > "${STATE}/npm-global"; : > "${STATE}/mcp"
  mkdir -p "${G16_PW_CACHE}/chromium-1187"
  : > "${G16_PW_CACHE}/chromium-1187/INSTALLATION_COMPLETE"
  : > "$CALLS"
}
# The line printed right under <name>'s "present" line, its lead-in taken off.
g16_byhand_line() {  # <file> <name>
  local want1="  ${2}: present — bionic has no record that it installed it, so it is left in place." line prev=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$prev" = "$want1" ] && { printf '%s' "${line#    remove it by hand with: }"; return 0; }
    prev="$line"
  done < "$1"
  return 0
}
g16_npx_calls() { grep '^npx ' "$CALLS" 2>/dev/null; return 0; }

expect_eq "16 playwright: the stub npx is the npx every door reaches" "${BIN}/npx" \
  "$(env -i PATH="$BIN" bash -c 'command -v npx')"
g16_pw_alone
G16_PW_BEFORE="$(g16_snap)"
expect_eq "16 playwright alone: the teardown reads the browser cache as present" \
  "yes" "$(g16_lib dep_teardown_state playwright-chromium)"
G16_PW_ONLY="$TMP/g16-pw-only.txt"
run_payload "$REMOVE_SH" --only tool:playwright-chromium < /dev/null > "$G16_PW_ONLY" 2>&1
expect_eq "16 playwright --only: remove exits 0" "0" "$?"
expect_eq "16 playwright --only: the two lines, the by-hand one byte for byte" \
  "yes" "$(g16_pair "$G16_PW_ONLY" playwright-chromium "$(g16_plan playwright-chromium)")"
G16_PW_LINE="$(g16_byhand_line "$G16_PW_ONLY" playwright-chromium)"
expect_contains "16 playwright --only: the by-hand line names Playwright's own uninstall" \
  "npx --yes playwright@latest uninstall" "$G16_PW_LINE"
expect_contains "16 playwright --only: …and says the cache is shared" "cache is shared" "$G16_PW_LINE"
expect_absent "16 playwright --only: …and never prints rm -rf" "rm -rf" "$G16_PW_LINE"
expect_absent "16 playwright --only: …nor the cache's name" "ms-playwright" "$G16_PW_LINE"
expect_absent "16 playwright --only: …and holds no quote a pasted line would leave open" "'" "$G16_PW_LINE"
expect_absent "16 playwright --only: no line of the door removes the cache whole" \
  "rm -rf $(g16_home "$G16_PW_CACHE")" "$(cat "$G16_PW_ONLY")"
expect_eq "16 playwright --only: …nothing asks to remove it" "0" "$(g16_asks "$G16_PW_ONLY" playwright-chromium)"
expect_eq "16 playwright --only: …counted neither removed nor clean (the tally reads 0 0)" \
  "0 0" "$(g16_tally "$G16_PW_ONLY")"
expect_eq "16 playwright --only: …named to remove by hand" "playwright-chromium" "$(g16_byhand "$G16_PW_ONLY")"
expect_eq "16 playwright --only: …npx was never called" "" "$(g16_npx_calls)"
expect_eq "16 playwright --only: …and the cache is byte for byte as it was" "$G16_PW_BEFORE" "$(g16_snap)"

g16_pw_alone
G16_PW_ALL="$TMP/g16-pw-all.txt"
printf 'n\n' | run_payload "$REMOVE_SH" --all > "$G16_PW_ALL" 2>&1
expect_eq "16 playwright --all: remove exits 0" "0" "$?"
expect_eq "16 playwright --all: the two lines, the by-hand one byte for byte" \
  "yes" "$(g16_pair "$G16_PW_ALL" playwright-chromium "$(g16_plan playwright-chromium)")"
expect_absent "16 playwright --all: …it is not on the page" "• remove playwright-chromium" "$(cat "$G16_PW_ALL")"
expect_absent "16 playwright --all: …no line of the door removes the cache whole" \
  "rm -rf $(g16_home "$G16_PW_CACHE")" "$(cat "$G16_PW_ALL")"
expect_eq "16 playwright --all: …named to remove by hand" "playwright-chromium" "$(g16_byhand "$G16_PW_ALL")"
expect_eq "16 playwright --all: …npx was never called" "" "$(g16_npx_calls)"
expect_eq "16 playwright --all: …nothing was asked to remove anything" "" "$(g16_acts)"
expect_eq "16 playwright --all: …and the cache is byte for byte as it was" "$G16_PW_BEFORE" "$(g16_snap)"
env -i PATH="$BIN" BIONIC_TEST_CALLS="$CALLS" BIONIC_PLAYWRIGHT_CACHE="$TMP/g16-pw-probe" npx --version >/dev/null 2>&1
expect_ne "16 playwright: the npx call extractor reads a call the recorder logged" "" "$(g16_npx_calls)"

# One line, no wider than the pnpm line it is modelled on (both from the interactive run).
G16_PW_INT="$(g16_byhand_line "$G16_INT" playwright-chromium)"
G16_PNPM_INT="$(g16_byhand_line "$G16_INT" motion)"
expect_ne "16 playwright width: the interactive run printed the pnpm line (the width extractor reads)" "" "$G16_PNPM_INT"
expect_true "16 playwright width: the playwright line is no wider than the pnpm line" \
  test "${#G16_PW_INT}" -gt 0 -a "${#G16_PW_INT}" -le "${#G16_PNPM_INT}"

# ── T88's mutant: the old arm, `rm -rf` over the whole cache, in a doctored copy ──
G16_M3="$TMP/payload-g16-t88-rmrf"
rm -rf "$G16_M3"; cp -R "$PAYLOAD" "$G16_M3"
cat >> "$G16_M3/scripts/lib/deps.sh" <<'MUT'
eval "_g16_t88_$(declare -f _dep_remove_plan)"
_dep_remove_plan() {
  if [ "$(dep_field "$1" install_fn_or_check)" = playwright-browser ]; then
    echo "rm -rf $(_dep_playwright_cache)"; return 0
  fi
  _g16_t88__dep_remove_plan "$@"
}
MUT
expect_true "16 mutant rm -rf: the doctored library still parses" bash -n "$G16_M3/scripts/lib/deps.sh"
g16_pw_alone
G16_M3_OUT="$TMP/g16-t88-rmrf.txt"
FH_PAYLOAD="$G16_M3" run_payload "$G16_M3/scripts/remove.sh" --only tool:playwright-chromium < /dev/null \
  > "$G16_M3_OUT" 2>&1
expect_eq "16 mutant rm -rf: the mutant run named the row with the old line" \
  "yes" "$(g16_pair "$G16_M3_OUT" playwright-chromium "rm -rf $(g16_home "$G16_PW_CACHE")")"
expect_eq "16 mutant rm -rf: …and the byte-for-byte row reads it red" \
  "no" "$(g16_pair "$G16_M3_OUT" playwright-chromium "$(g16_plan playwright-chromium)")"

# ── T88: a store entry is read where it begins, never as the tail of a longer name ──
# The v11 index holds `name@version` strings; `framer-motion@…` is not motion, and
# `undici-types@…` is not types. A scoped name matches by its whole `@scope/name`.
g16_store() {  # <entry>... — a fresh home whose pnpm store index holds exactly these entries
  fresh_home
  : > "${STATE}/npm-global"; : > "${STATE}/mcp"
  mkdir -p "$G16_PNPM_STORE"
  { printf 'some binary-ish preamble\n'; printf '%s\n' "$@"; printf 'more\n'; } > "${G16_PNPM_STORE}/index.db"
  : > "$CALLS"
}
g16_store framer-motion@12.0.0
expect_eq "16 store framer-motion only: motion reads absent" "no|unknown" "$(g16_lib _dep_check_pnpm_store motion)"
expect_eq "16 store framer-motion only: …the teardown reads it absent" "no" "$(g16_lib dep_teardown_state motion)"
G16_FR_DOC="$TMP/g16-framer-doctor.txt"
run_payload "$DOCTOR_SH" < /dev/null > "$G16_FR_DOC" 2>&1
expect_eq "16 store framer-motion only: …doctor reads motion not installed" "no" "$(dep_present "$G16_FR_DOC" motion)"
G16_FR_ONLY="$TMP/g16-framer-only.txt"
run_payload "$REMOVE_SH" --only tool:motion < /dev/null > "$G16_FR_ONLY" 2>&1
expect_contains "16 store framer-motion only: …remove reports motion not installed" \
  "motion (not installed) — already clean" "$(cat "$G16_FR_ONLY")"
expect_eq "16 store framer-motion only: …and does not name it" \
  "no" "$(g16_pair "$G16_FR_ONLY" motion "$(g16_plan motion)")"
g16_store motion@12.42.2
expect_eq "16 store motion: motion reads present, its version read" "yes|12.42.2" "$(g16_lib _dep_check_pnpm_store motion)"
G16_MO_DOC="$TMP/g16-motion-doctor.txt"
run_payload "$DOCTOR_SH" < /dev/null > "$G16_MO_DOC" 2>&1
expect_eq "16 store motion: …doctor reads it installed (the row extractor reads)" "yes" "$(dep_present "$G16_MO_DOC" motion)"
g16_store framer-motion@13.0.0 motion@12.42.2
expect_eq "16 store both: motion reads present with its own version, not framer-motion's" \
  "yes|12.42.2" "$(g16_lib _dep_check_pnpm_store motion)"
g16_store undici-types@7.18.2
expect_eq "16 store undici-types only: types reads absent" "no|unknown" "$(g16_lib _dep_check_pnpm_store types)"
g16_store @scope/pkg@1.2.3
expect_eq "16 store scoped: a scoped name reads present by its whole name" \
  "yes|1.2.3" "$(g16_lib _dep_check_pnpm_store @scope/pkg)"
expect_eq "16 store scoped: …and its bare name does not" "no|unknown" "$(g16_lib _dep_check_pnpm_store pkg)"
g16_store lodashxget@4.4.2
expect_eq "16 store dotted: a dot in the name is a dot, not any byte" \
  "no|unknown" "$(g16_lib _dep_check_pnpm_store lodash.get)"
g16_store lodash.get@4.4.2
expect_eq "16 store dotted: …and the dotted name itself reads present" \
  "yes|4.4.2" "$(g16_lib _dep_check_pnpm_store lodash.get)"

# ── T88's mutant: the anchor taken off the match, in a doctored copy ──
G16_M4="$TMP/payload-g16-t88-unanchored"
rm -rf "$G16_M4"; cp -R "$PAYLOAD" "$G16_M4"
G16_ANCHOR='(^|[^A-Za-z0-9@/_.-])'
G16_M4_SRC="$(cat "$G16_M4/scripts/lib/deps.sh")"
expect_contains "16 mutant unanchored: the library carries the anchor the mutant removes" "$G16_ANCHOR" "$G16_M4_SRC"
printf '%s\n' "${G16_M4_SRC//"$G16_ANCHOR"/}" > "$G16_M4/scripts/lib/deps.sh"
expect_absent "16 mutant unanchored: …and the doctored copy no longer does" "$G16_ANCHOR" \
  "$(cat "$G16_M4/scripts/lib/deps.sh")"
expect_true "16 mutant unanchored: the doctored library still parses" bash -n "$G16_M4/scripts/lib/deps.sh"
g16_store framer-motion@12.0.0
expect_eq "16 mutant unanchored: the framer-motion row reads motion present again" "yes|12.0.0" \
  "$(env -i HOME="$HOME_FIX" PATH="$BIN" BIONIC_PNPM_STORE="$G16_PNPM_STORE" \
       bash -c '. "$1"; _dep_check_pnpm_store motion' _ "$G16_M4/scripts/lib/deps.sh" 2>/dev/null)"

# ── standalone: unchanged ──
g16_plant
mkdir -p "$TMP/g16-standalone"; cp "$REMOVE_SH" "$TMP/g16-standalone/remove.sh"
G16_SA="$TMP/g16-standalone.txt"
printf 'n\n' | run_payload "$TMP/g16-standalone/remove.sh" > "$G16_SA" 2>&1
expect_contains "16 standalone: the tools item says the table ships with the payload" \
  "the dependency table ships with the payload — not available standalone." "$(cat "$G16_SA")"
expect_eq "16 standalone: …and nothing was called" "" "$(g16_acts)"
rm -f "${BIN}/notebooklm"

finish
