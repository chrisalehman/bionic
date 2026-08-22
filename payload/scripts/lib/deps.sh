#!/bin/bash
# deps.sh — the dependency SSoT (epic-17 wave-03, spec AC-8).
#
# WHAT THIS FILE OWNS. The set of things bionic depends on, and everything that
# is true of a dependency *by declaration*: its class, the route that consumes
# it, where it comes from, what version range it must satisfy, how it is
# installed, and what happens to it when bionic is removed. One row per
# dependency. Nothing else in the repo may author that set — `plugin.json`'s
# `dependencies` array renders the `core` rows and `marketplace.json`'s
# url-sourced entries render the `native`-kind rows, both pinned by agreement
# tests that fail on drift.
#
# WHAT IT DOES NOT OWN. Machine facts. "Is superpowers installed on THIS box"
# is a question about a machine, not about the dependency set; `detect.sh` owns
# every such question and renders the fact lines. The one function here that
# touches a machine, `check_dep`, exists because the probe for a dependency is
# a property of the dependency's mechanism — it returns raw fields and does no
# formatting, and `detect.sh`'s `detect_dep` is its only formatter. There is no
# second implementation of either half.
#
# THE FOUR CLASSES (wave-06 D-B, ratified 2026-08-20). `class` answers WHEN
# bionic installs a tool, which is the question the old two-lane split could not
# express — it named the install MECHANISM and let the moment be implied.
#   core        — the two plugin dependencies the CLI's own mechanism resolves.
#                 bionic declares them; the harness installs them. Nothing else
#                 is ever core.
#   basic       — the substrate every machine needs. Asked once at setup, one
#                 consent each, and never removed by bionic: it ensured them, it
#                 does not own them.
#   when-needed — installed with ONE question the first time a route actually
#                 needs the tool. Setup never asks about these rows.
#   extra       — offered once at setup with a line of why, default No.
#
# `kind` is the orthogonal question — HOW a row installs — and it is what
# `install_dep` and `check_dep` dispatch on. `native` means the plugin harness
# does it, and `install_dep` REFUSES every native row whatever its class: a
# second installer for a natively-installed plugin is precisely the kludge D1
# rejected. Every non-native row has exactly one installer, the one below —
# the same function for the setup loop and for a just-in-time offer (AC-5).
#
# CLASS AND KIND ARE NOT THE SAME CUT, and impeccable is the row that proves it:
# it is `when-needed` (a route asks for it at the moment of use) and `native`
# (the harness installs it, from bionic's own marketplace). That is why the
# marketplace rendering rule is stated over `kind` and the plugin.json
# dependency rule over `class`.
#
# TRACEABILITY. Every row names its `consumer`: the repo-relative path of the
# doctrine file that uses it, or one of exactly two literals — `substrate` for
# the basics no single route owns, `extra` for the optional offers. A row with
# no consumer is a row nobody can justify, and the wave dropped two of them
# (`yq`, `gcloud`) on exactly that test. tests/plugin-lib.test.sh Group 3c
# resolves every path.
#
# CONSENT. `install_dep` and `remove_dep` are the only mutating entry points,
# and neither mutates before an explicit answer on stdin. No assume-yes knob
# exists: "consent per event, never silent, never unattended" is the ratified
# rule, and an env var that switches it off would be the hole in it.
#
# ROOTS ARE OVERRIDABLE. Every path this file reads comes from a variable with
# a live default, so the hermetic suite can point the whole library at a
# fixture tree without a seam that substitutes the value under test.
#
# Sourced, never executed:  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/deps.sh"

# ─── Roots ───────────────────────────────────────────────────────────────────
# Read at CALL time, not source time: a caller may source once and probe
# several roots (the suite does exactly that).

_dep_claude_home()      { echo "${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"; }
_dep_settings_file()    { echo "${BIONIC_SETTINGS_FILE:-$(_dep_claude_home)/settings.json}"; }
_dep_installed_json()   { echo "${BIONIC_INSTALLED_PLUGINS_FILE:-$(_dep_claude_home)/plugins/installed_plugins.json}"; }

# THE PAYLOAD ROOT, one more root this file now reads FROM rather than only
# writes to (epic-18 T1). Every other consumer of "where is the plugin"
# (detect.sh's `_detect_plugin_root`, profile.sh's `_profile_plugin_root`)
# carries its own byte-identical copy of this same three-step resolution for
# the reason `bionic_link_target` already gives above: each file is sourced on
# its own by something, so none may assume a sibling came first. No
# `dirname`/`basename` here either — the self-locator has to survive the
# half-broken machine it is most needed on.
_dep_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_dep_plugin_root() {
  if [ -n "${BIONIC_PLUGIN_ROOT:-}" ]; then echo "$BIONIC_PLUGIN_ROOT"; return; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then echo "$CLAUDE_PLUGIN_ROOT"; return; fi
  # lib -> scripts -> payload root
  ( cd "$(_dep_self_dir)/../.." && pwd -P )
}

# ccstatusline ships TWO halves (epic-18-w1 handoff §3.1): the `.statusLine`
# command that RENDERS the line, and the layout file that command reads. The
# source is always the payload's own copy; the target defaults to the bare
# path claude-bootstrap.sh always used, `~/.config/ccstatusline/settings.json`
# — overridable for the same reason every other root here is.
_dep_ccstatusline_config_source() { echo "$(_dep_plugin_root)/ccstatusline/settings.json"; }
_dep_ccstatusline_config_target() { echo "${BIONIC_CCSTATUSLINE_CONFIG:-$HOME/.config/ccstatusline/settings.json}"; }
_dep_ccstatusline_config_dir() {
  local t; t="$(_dep_ccstatusline_config_target)"
  echo "${t%/*}"
}

# Byte-identical, the same word AC-1 uses and the same tool
# claude-bootstrap.sh's ccstatusline-config step used (`diff -q`) — not `cmp`,
# so a hermetic suite need not add a second comparison binary to its curated
# PATH beside the one every writer path already needs.
_dep_files_match() { [ -f "${1:-}" ] && [ -f "${2:-}" ] && diff -q "$1" "$2" >/dev/null 2>&1; }
_dep_playwright_cache() {
  if [ -n "${BIONIC_PLAYWRIGHT_CACHE:-}" ]; then echo "$BIONIC_PLAYWRIGHT_CACHE"; return; fi
  case "$(uname -s 2>/dev/null || echo Darwin)" in
    Linux) echo "$HOME/.cache/ms-playwright" ;;
    *)     echo "$HOME/Library/Caches/ms-playwright" ;;
  esac
}

# The excalidraw skill's uv project, which lives INSIDE the plugin now (epic-18 T3, AC-6) —
# so the directory `uv sync` writes its `.venv` into is plugin-root-relative, not
# claude-home-relative. Empty when neither root is set, and that emptiness is deliberate: the
# probe below turns it into `unknown` with a named cause rather than into a confident `no`
# about a project directory nobody could locate. Same rule `_dep_check_pnpm_store` follows.
_dep_excalidraw_refs() {
  if [ -n "${BIONIC_EXCALIDRAW_REFS:-}" ]; then echo "$BIONIC_EXCALIDRAW_REFS"; return; fi
  local root="${BIONIC_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  [ -n "$root" ] || { echo ""; return; }
  echo "${root}/skills/excalidraw-diagram/references"
}

# ─── The settings values bionic offers ───────────────────────────────────────
#
# THE DEFAULT PERMISSION MODE, OWNED HERE BECAUSE TWO SCRIPTS MUST AGREE ON IT
# (six-axis review D-1). setup.sh offers to write it; remove.sh offers to reset
# it, and that offer is DEFINED as "the one value bionic knows it wrote" — it
# leaves any other value alone, because any other value is somebody else's
# choice. So the two are one decision, and they used to be two bare literals
# with nothing making them agree: a setup that started writing `acceptEdits`
# would have left both suites green while the teardown quietly stopped matching
# and the setting stayed behind on every machine.
#
# It is a plain variable rather than a function because remove.sh's standalone
# door has to be able to fall back to a copy of it — see the shared literals in
# that file, and the agreement arms in tests/remove.test.sh Group 19.
BIONIC_DEFAULT_PERMISSION_MODE="auto"

# ─── The table ───────────────────────────────────────────────────────────────
#
# FIELDS, in order:
#   name                  the probe identity — what `check_dep`/`dep_field` key on,
#                         and what doctor prints. For a binary that is the command
#                         name (`rg`), for a package-shaped dep the package
#                         (`@playwright/cli`), for an MCP server its server name.
#   class                 core | basic | when-needed | extra — WHEN bionic installs it.
#   consumer              the doctrine route that uses it: a repo-relative path
#                         that resolves, or the literal `substrate` / `extra`.
#                         Repo-relative, not payload-relative, because the
#                         traceability claim is about this repository's doctrine
#                         — which is why a route inside the payload spells its
#                         `payload/` prefix here rather than dropping it. Every
#                         route now ships in the payload: excalidraw-diagram was
#                         the last one outside it and moved in at epic-18 T3.
#   mechanism             the install target. `scheme:target` for the package
#                         managers (brew, brew-cask, npm, uv, pnpm, npx); a bare
#                         https git URL for a native row, whose renderings need
#                         it verbatim.
#   constraint            a semver range, or `any` where no range is declared.
#                         `any` is a real declaration — it says the dependency
#                         is unpinned — not a missing value.
#   kind                  HOW it installs. Names the `_dep_check_*` /
#                         `_dep_install_*` pair that knows how to probe and
#                         install this shape. `native` means the harness does it.
#   removal_behavior      native-uninstall-offer | remove-on-consent | keep-shared
#
# THE ONE FIELD THIS TABLE DOES NOT OWN is the commit `sha` on a native-kind
# marketplace entry. It is deliberately not a seventh column: a sha is a
# SUPPLY-CHAIN pin — "the code installed is the code that was reviewed" — and
# `constraint` above is a VERSION claim — "the installed version satisfies this
# range". Different questions, different lifetimes, different owners: the
# constraint is doctor's to judge on every run, the sha is the manifest's to
# state once and change only by review. So marketplace.json is the sha's author
# by written exception, and tests/plugin-lib.test.sh Group 18 requires EVERY
# url-sourced entry to carry one. Saying nothing here is what let one
# dependency ship pinned and the other tracking a moving branch head.
#
# PROVENANCE. Native rows: the wave-03 ratified D1 values (agent-skills is
# ^0.6.0 — the ^1.0.0 in today's plugin.json is stale and D3 ratified the
# correction), plus impeccable at wave-06 S3, whose `^4.1.0` was verified
# against the upstream tags rather than assumed: `git ls-remote --tags
# https://github.com/pbakaus/impeccable.git` puts skill-v4.1.1 at the top of the
# skill line, and that commit's `.claude-plugin/plugin.json` declares version
# 4.1.1. Everything else: ported from claude-bootstrap.sh, deleted at W5 and the
# authority on what actually got installed — claude-config.txt supplied the
# roster and the `do_install_*` / `verify_*` pairs the commands. Classes are
# D-B's ratified roster, verbatim.

BIONIC_DEP_TABLE="$(cat <<'TABLE'
superpowers|core|skills/canonical-sdlc/SKILL.md|https://github.com/obra/superpowers.git|^6.3.0|native|native-uninstall-offer
agent-skills|core|skills/canonical-sdlc/SKILL.md|https://github.com/addyosmani/agent-skills.git|^0.6.0|native|native-uninstall-offer
git|basic|substrate|brew:git|any|brew-dep|keep-shared
node|basic|substrate|brew:node|any|brew-dep|keep-shared
pnpm|basic|substrate|brew:pnpm|any|brew-dep|keep-shared
gh|basic|substrate|brew:gh|any|brew-dep|keep-shared
jq|basic|substrate|brew:jq|any|brew-dep|keep-shared
rg|basic|substrate|brew:ripgrep|any|brew-dep|keep-shared
uv|basic|substrate|brew:uv|any|brew-dep|keep-shared
docker|basic|substrate|brew:docker|any|brew-dep|keep-shared
aws|basic|substrate|brew:awscli|any|brew-dep|keep-shared
impeccable|when-needed|skills/canonical-sdlc/SKILL.md|https://github.com/pbakaus/impeccable.git|^4.1.0|native|native-uninstall-offer
@playwright/cli|when-needed|skills/browser-verify/SKILL.md|npm:@playwright/cli|any|npm-global|remove-on-consent
chrome-devtools|when-needed|skills/browser-verify/SKILL.md|npm:chrome-devtools-mcp@latest|any|mcp-server|remove-on-consent
playwright-chromium|when-needed|payload/skills/excalidraw-diagram/SKILL.md|npx:playwright@latest|any|playwright-browser|remove-on-consent
excalidraw-renderer|when-needed|payload/skills/excalidraw-diagram/SKILL.md|uv:sync|any|uv-project|remove-on-consent
motion|when-needed|skills/canonical-sdlc/SKILL.md|pnpm:motion|any|pnpm-store|remove-on-consent
ccstatusline|extra|extra|npx:ccstatusline@latest|any|statusline|remove-on-consent
notebooklm|extra|extra|uv:notebooklm-py|any|uv-tool|remove-on-consent
context7|extra|extra|npm:@upstash/context7-mcp@latest|any|mcp-server|remove-on-consent
@pencil.dev/cli|extra|extra|npm:@pencil.dev/cli|any|npm-global|remove-on-consent
TABLE
)"

# The nine brew rows are `keep-shared` deliberately, and that is now what the
# `basic` class MEANS rather than a coincidence of their removal policy: bionic
# ENSURED git/node/docker/... on this machine; it does not own them, and pulling
# `git` off a box because bionic is leaving is not a removal anyone asked for.
# The reset charter names shared binaries as the excluded class.
#
# TWO ROWS LEFT AT WAVE-06 S3. `yq` and `gcloud` had no consumer — no skill, no
# rule, no agent file, no test named either — and neither is universal enough to
# justify as substrate. D-B dropped them by name. They are not commented out
# here: a commented row is a row that comes back without a decision.
#
# `excalidraw-renderer` IS THE ROW THAT USED TO BE A README (epic-18 T3, AC-6). The skill's
# render loop needs two things bionic does not ship: a chromium build, which has been the
# `playwright-chromium` row all along, and a synced uv project, which was a "Renderer setup"
# code block the user was expected to find and paste. That made it the one piece of bionic's
# dependency surface with no probe, no consent prompt and no doctor line — invisible until a
# render failed. It is a row now, `when-needed` like its sibling: absent until a render asks,
# then ONE consented install.
#
# ITS `mechanism` IS `uv:sync` AND ITS TARGET IS NOT A PACKAGE. Every other row's locator
# names a thing to fetch; this one names an operation on a project directory the plugin
# already carries, and the directory comes from `_dep_excalidraw_refs` rather than from the
# table because it is a machine path, not a declaration. The `uv:` scheme is still the honest
# prefix — `uv` is what runs — and `_dep_locator_target` yields `sync`, which is exactly the
# subcommand the argv below uses.
#
# `motion` is the one when-needed row whose consumer file does not yet name the
# package (it is pre-warmed into the pnpm store for the design route). The class
# is D-B's ratified call; the gap is recorded as the single declared exemption
# in tests/plugin-lib.test.sh Group 3c, so it fails loudly the day it is fixed.

# ─── Table access ────────────────────────────────────────────────────────────

dep_names() { printf '%s\n' "$BIONIC_DEP_TABLE" | while IFS='|' read -r n _; do [ -n "$n" ] && echo "$n"; done; }

dep_names_class() {  # <core|basic|when-needed|extra>
  local want="${1:-}"
  printf '%s\n' "$BIONIC_DEP_TABLE" | while IFS='|' read -r n class _; do
    [ -n "$n" ] && [ "$class" = "$want" ] && echo "$n"
  done
  return 0
}

dep_names_kind() {  # <native|brew-dep|npm-global|…>
  local want="${1:-}"
  printf '%s\n' "$BIONIC_DEP_TABLE" | while IFS='|' read -r n _ _ _ _ kind _; do
    [ -n "$n" ] && [ "$kind" = "$want" ] && echo "$n"
  done
  return 0
}

# RETIRED — `dep_names_lane` (wave-06 S10, six-axis review A-1). S3 kept the
# pre-wave-06 lane list as a deprecated view because setup.sh and remove.sh still
# walked it; S4 retired setup's call and remove.sh now walks the CLASSES, so
# nothing enumerates by lane any more. The list was never a stored field — it was
# "class core" and "kind != native" under two old names — and keeping it meant a
# second live taxonomy over one table, which is how the teardown came to be
# computed as `kind != native` and silently miss the one native row outside core.
# tests/plugin-lib.test.sh Group 3b pins the removal and states the set that
# replaced it. The lane FIELD stays: see `dep_field` below.

dep_row() {  # <name> — the whole row, verbatim. Non-zero if there is no such row.
  local want="${1:-}" line
  while IFS= read -r line; do
    case "$line" in "${want}|"*) echo "$line"; return 0 ;; esac
  done <<< "$BIONIC_DEP_TABLE"
  return 1
}

dep_field() {  # <name> <field>
  local name="${1:-}" field="${2:-}" row
  local f_name f_class f_consumer f_mech f_con f_kind f_rem
  row="$(dep_row "$name")" || { echo "deps.sh: no such dependency: ${name}" >&2; return 1; }
  IFS='|' read -r f_name f_class f_consumer f_mech f_con f_kind f_rem <<< "$row"
  case "$field" in
    name)                printf '%s\n' "$f_name" ;;
    class)               printf '%s\n' "$f_class" ;;
    consumer)            printf '%s\n' "$f_consumer" ;;
    mechanism|source_url)          printf '%s\n' "$f_mech" ;;
    constraint)          printf '%s\n' "$f_con" ;;
    kind|install_fn_or_check)      printf '%s\n' "$f_kind" ;;
    removal_behavior)    printf '%s\n' "$f_rem" ;;
    # DEPRECATED and derived — never a stored column. detect.sh's fact line is
    # its one caller and renders it verbatim; the LIST that used to compute the
    # same rule is retired (see above), so this is now the only place the old
    # taxonomy is spoken at all.
    lane)
      if [ "$f_class" = "core" ]; then printf '3a\n'
      elif [ "$f_kind" != "native" ]; then printf '3b\n'
      else printf 'none\n'; fi ;;
    *) echo "deps.sh: no such field: ${field}" >&2; return 1 ;;
  esac
}

# Reports any row whose field count is not exactly 7. Silence means the table
# is well-formed; the suite asserts on the silence.
dep_table_field_count_report() {
  local line n
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')"
    [ "$n" = "6" ] || echo "${line} (has $((n + 1)) fields, want 7)"
  done <<< "$BIONIC_DEP_TABLE"
  return 0
}

# ─── Version comparison ──────────────────────────────────────────────────────
#
# Enough semver to judge the ranges the table actually declares. Deliberately
# NOT a general semver implementation: a range shape this does not recognise
# returns `unknown` rather than guessing, which keeps an unparsed constraint
# visible in doctor's output instead of silently reading as satisfied.

_dep_semver_cmp() {  # <a> <b> -> echoes -1 | 0 | 1  (prerelease tags ignored)
  local a="${1%%-*}" b="${2%%-*}" i av bv
  local -a A B
  IFS='.' read -r -a A <<< "$a"
  IFS='.' read -r -a B <<< "$b"
  for i in 0 1 2; do
    av="${A[i]:-0}"; bv="${B[i]:-0}"
    av="${av//[!0-9]/}"; bv="${bv//[!0-9]/}"
    av="${av:-0}"; bv="${bv:-0}"
    if [ "$av" -lt "$bv" ]; then echo -1; return 0; fi
    if [ "$av" -gt "$bv" ]; then echo 1; return 0; fi
  done
  echo 0
}

_dep_is_semver() { [[ "${1:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([-+].*)?$ ]]; }

dep_constraint_verdict() {  # <constraint> <version> -> ok | violation | unknown
  local c="${1:-}" v="${2:-}" base cmp upper
  # `any` is decided first, and deliberately: it declares that no range is
  # pinned, so it cannot be violated by any version — including one this
  # machine could not read. Making an unreadable version outrank it would
  # have doctor flag an unpinned dependency that is in fact fine.
  [ "$c" = "any" ] && { echo ok; return 0; }
  { [ -z "$v" ] || [ "$v" = "unknown" ]; } && { echo unknown; return 0; }
  _dep_is_semver "$v" || { echo unknown; return 0; }

  case "$c" in
    '^'*)
      base="${c#^}"; _dep_is_semver "$base" || { echo unknown; return 0; }
      [ "$(_dep_semver_cmp "$v" "$base")" = "-1" ] && { echo violation; return 0; }
      # npm's caret: the leftmost NON-ZERO component is what stays fixed, so
      # ^0.6.0 admits 0.6.x only. agent-skills is a 0.x dep — this branch is
      # its everyday case, not a corner.
      # One `local` per line on purpose: a later assignment in a chained
      # `local a=.. b=$a` does NOT see the earlier one.
      local maj min rest
      maj="${base%%.*}"; rest="${base#*.}"; min="${rest%%.*}"
      if [ "${maj//[!0-9]/}" = "0" ]; then upper="0.$((${min//[!0-9]/} + 1)).0"
      else upper="$((${maj//[!0-9]/} + 1)).0.0"; fi
      [ "$(_dep_semver_cmp "$v" "$upper")" = "-1" ] && echo ok || echo violation
      ;;
    '~'*)
      base="${c#\~}"; _dep_is_semver "$base" || { echo unknown; return 0; }
      [ "$(_dep_semver_cmp "$v" "$base")" = "-1" ] && { echo violation; return 0; }
      local tmaj tmin trest
      tmaj="${base%%.*}"; trest="${base#*.}"; tmin="${trest%%.*}"
      upper="${tmaj}.$((${tmin//[!0-9]/} + 1)).0"
      [ "$(_dep_semver_cmp "$v" "$upper")" = "-1" ] && echo ok || echo violation
      ;;
    '>='*)
      base="${c#>=}"; _dep_is_semver "$base" || { echo unknown; return 0; }
      cmp="$(_dep_semver_cmp "$v" "$base")"
      [ "$cmp" = "-1" ] && echo violation || echo ok
      ;;
    *)
      if _dep_is_semver "$c"; then
        [ "$(_dep_semver_cmp "$v" "$c")" = "0" ] && echo ok || echo violation
      else
        echo unknown
      fi
      ;;
  esac
  return 0
}

# ─── Locator helpers ─────────────────────────────────────────────────────────

_dep_locator_target() {  # brew:ripgrep -> ripgrep ; https://... -> unchanged
  local loc="${1:-}"
  case "$loc" in
    http://*|https://*) printf '%s\n' "$loc" ;;
    *:*)                printf '%s\n' "${loc#*:}" ;;
    *)                  printf '%s\n' "$loc" ;;
  esac
}

_dep_have() { command -v "${1:-}" >/dev/null 2>&1; }

# First semver-looking token in a `--version` line. Tools disagree about
# everything else in that line ("ripgrep 15.2.0", "jq-1.7.1", "v22.3.0"), so
# the token is what we take and nothing around it.
_dep_version_from_probe() {  # <argv...>
  local out
  out="$("$@" 2>/dev/null | head -3)" || true
  [ -n "$out" ] || { echo unknown; return 0; }
  local tok
  tok="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  echo "${tok:-unknown}"
}

# ─── Per-mechanism probes ────────────────────────────────────────────────────
#
# Each prints `<present>|<version>` where present is yes | no | unknown.
# `unknown` is used only where the mechanism genuinely has no presence surface
# — reporting `no` there would be a confident wrong answer, and doctor would
# nag about a dependency that is in fact fine.
#
# THE PROBE CONTRACT (epic-18 AC-9). A probe answers "is this dependency in
# the state setup leaves it in", not "is it registered". Those two questions
# only coincide where setup's own act of installing IS the registration
# (native, mcp-server below) — everywhere else, checking a registry as a
# stand-in for the state is a wrong-answer waiting to happen: the registry can
# say yes while the route that actually needs the dependency gets nothing.
# Audited against this at T5, one line per kind:
#   native              registration IS the installed state (a plugin's key in
#                        installed_plugins.json is not a proxy for anything
#                        else) — fine.
#   brew-dep/brew-cask   the binary on PATH is the state itself, not a lookup
#                        in some brew ledger — fine.
#   npm-global           `npm list -g` reads npm's own record of what its
#                        install left behind; for a global package that record
#                        IS the state, there is no second question to ask —
#                        fine.
#   mcp-server           registration via `claude mcp add` is genuinely the
#                        entire state a route consumes; no other installed
#                        surface exists to probe instead — fine.
#   pnpm-store           no presence surface exists at all (see
#                        _dep_check_pnpm_store below); `unknown` is the honest
#                        answer, never a registration stand-in — fine.
#   playwright-browser   a filesystem marker left by the actual install, not a
#                        network --dry-run check — fine.
#   statusline           being fixed in flight — see the note at
#                        _dep_check_statusline below (epic-18 T1, parallel).
#   uv-tool (notebooklm) being fixed in flight — see the note at
#                        _dep_check_uv_tool below (epic-18 T2, parallel).

_dep_check_native() {  # native kind: the harness's own install registry
  local name="$1" file ver
  file="$(_dep_installed_json)"
  _dep_have jq || { echo "unknown|unknown"; return 0; }
  [ -f "$file" ] || { echo "no|unknown"; return 0; }
  # Marketplace-agnostic on purpose: S3 re-points both deps at bionic's own
  # marketplace, which rewrites the right-hand side of the `name@marketplace`
  # key. Matching on the name half survives that.
  ver="$(jq -r --arg n "$name" '
      [ (.plugins // {}) | to_entries[]
        | select((.key | split("@")[0]) == $n)
        | .value[0].version // "unknown" ] | first // "absent"' "$file" 2>/dev/null)"
  case "$ver" in
    absent|null|"") echo "no|unknown" ;;
    *)              echo "yes|${ver}" ;;
  esac
}

_dep_check_brew_dep() {  # presence is the binary on PATH, exactly as bootstrap checks it
  local name="$1"
  if _dep_have "$name"; then echo "yes|$(_dep_version_from_probe "$name" --version)"; else echo "no|unknown"; fi
}
_dep_check_brew_cask() { _dep_check_brew_dep "$@"; }

# uv-tool's default probe is the brew-dep one — CLI on PATH — and that is
# right for the mechanism in general. notebooklm is the one row with a second
# half: `notebooklm skill install` (ported from claude-bootstrap.sh
# 1542-1550) writes ~/.claude/skills/notebooklm/SKILL.md, and the CLI being on
# PATH says nothing about whether that step ever ran — the ccstatusline bug
# this wave exists to fix, one row over (handoff §3.1 vs §3.2, AC-5). A new
# `kind` for one row would be the second-installer-shaped kludge the ownership
# table exists to prevent, so the name check lives here instead, the same way
# `_dep_install_statusline` is a whole dedicated function for its one row.
# (T5's probe audit deferred this row to T2's landing — satisfied here.)
_dep_check_uv_tool() {
  local name="$1" raw present version
  raw="$(_dep_check_brew_dep "$name")"
  present="${raw%%|*}"; version="${raw##*|}"
  if [ "$name" = "notebooklm" ] && [ "$present" = "yes" ]; then
    [ -f "$(_dep_claude_home)/skills/notebooklm/SKILL.md" ] || present=no
  fi
  printf '%s|%s\n' "$present" "$version"
}

_dep_check_npm_global() {  # the PACKAGE is the probe target, not a binary name
  local name="$1" pkg out
  pkg="$(_dep_locator_target "$(dep_field "$name" source_url)")"
  _dep_have npm || { echo "unknown|unknown"; return 0; }
  out="$(npm list -g --depth=0 "$pkg" 2>/dev/null)" || { echo "no|unknown"; return 0; }
  local ver
  ver="$(printf '%s\n' "$out" | grep -oE "@[0-9]+\.[0-9]+\.[0-9]+" | tail -1)"
  ver="${ver#@}"
  echo "yes|${ver:-unknown}"
}

_dep_check_mcp_server() {
  local name="$1"
  _dep_have claude || { echo "unknown|unknown"; return 0; }
  if claude mcp get "$name" >/dev/null 2>&1; then echo "yes|unknown"; else echo "no|unknown"; fi
}

# The pnpm content-addressable store is a cache, never an import path: there is
# no global "already installed" state to read, which is why bootstrap re-warms
# it unconditionally rather than checking. `no` would be a lie on a warm
# machine, so the honest answer is that presence is not knowable here.
_dep_check_pnpm_store() { echo "unknown|unknown"; }

# A filesystem probe rather than bootstrap's `--dry-run` walk: doctor is
# read-only and must not shell out to the network. Same caveat bootstrap's own
# comment makes about its glob — this proves SOME completed chromium build
# exists, not that a given project's pinned build does.
_dep_check_playwright_browser() {
  local cache marker
  cache="$(_dep_playwright_cache)"
  [ -d "$cache" ] || { echo "no|unknown"; return 0; }
  for marker in "$cache"/chromium-*/INSTALLATION_COMPLETE; do
    [ -f "$marker" ] || continue
    local dir="${marker%/INSTALLATION_COMPLETE}"
    echo "yes|${dir##*chromium-}"
    return 0
  done
  echo "no|unknown"
}

# THE VENV IS THE STATE `uv sync` LEAVES BEHIND, so the venv is what this asks about. Not
# whether `uv` is on PATH — that is the `uv` row's question, and answering this row with it
# would report a renderer as ready on a machine that has never synced the project.
#
# The version reported is the venv's own interpreter, read out of `pyvenv.cfg`, because that
# is the only version this mechanism HAS: there is no package and no release to name. The
# constraint is `any`, so nothing is judged on it — it is there so the report says something
# true rather than `unknown` about a directory it can plainly read.
#
# `unknown` when the project directory cannot be located at all (neither plugin-root name is
# set), with the cause doctor renders beside it. A `no` there would be a confident answer
# about a path nobody resolved.
_dep_check_uv_project() {
  local refs ver
  refs="$(_dep_excalidraw_refs)"
  [ -n "$refs" ] || { echo "unknown|unknown"; return 0; }
  [ -x "${refs}/.venv/bin/python" ] || { echo "no|unknown"; return 0; }
  ver="$(grep -E '^[[:space:]]*version[[:space:]]*=' "${refs}/.venv/pyvenv.cfg" 2>/dev/null \
         | head -1 | sed 's/.*=[[:space:]]*//' | tr -d '[:space:]')"
  echo "yes|${ver:-unknown}"
}

# TWO HALVES, ONE ANSWER (epic-18 T1, AC-2). `present=yes` used to mean only
# "the command is set" — the probe-contract violation that let a machine
# report healthy while ccstatusline rendered its own stock default (handoff
# §3.1). Now it means both: the command AND the layout file the command
# reads. The second field carries WHICH half is missing when it is not
# `yes`, so doctor's degradation line can name it rather than repeat the
# generic "is absent" sentence over a dependency that is half there.
# (T5's probe audit deferred this row to T1's landing — satisfied above.)
_dep_check_statusline() {
  local settings cmd cmd_ok=no cfg_ok=no
  settings="$(_dep_settings_file)"
  _dep_have jq || { echo "unknown|unknown"; return 0; }
  if [ -f "$settings" ]; then
    cmd="$(jq -r '.statusLine.command // ""' "$settings" 2>/dev/null)"
    case "$cmd" in *ccstatusline*) cmd_ok=yes ;; esac
  fi
  _dep_files_match "$(_dep_ccstatusline_config_source)" "$(_dep_ccstatusline_config_target)" \
    && cfg_ok=yes

  if [ "$cmd_ok" = "yes" ] && [ "$cfg_ok" = "yes" ]; then
    echo "yes|ok"
  elif [ "$cmd_ok" = "yes" ]; then
    echo "no|config-missing"
  elif [ "$cfg_ok" = "yes" ]; then
    echo "no|command-missing"
  else
    echo "no|both-missing"
  fi
}

# ─── check_dep ───────────────────────────────────────────────────────────────

check_dep() {  # <name> -> present=<yes|no|unknown>|version=<v|unknown>|verdict=<ok|violation|unknown>
  local name="${1:-}" mech constraint raw present version verdict
  mech="$(dep_field "$name" install_fn_or_check)" || return 1
  constraint="$(dep_field "$name" constraint)"

  case "$mech" in
    native)             raw="$(_dep_check_native "$name")" ;;
    brew-dep)           raw="$(_dep_check_brew_dep "$name")" ;;
    brew-cask)          raw="$(_dep_check_brew_cask "$name")" ;;
    npm-global)         raw="$(_dep_check_npm_global "$name")" ;;
    uv-tool)            raw="$(_dep_check_uv_tool "$name")" ;;
    pnpm-store)         raw="$(_dep_check_pnpm_store "$name")" ;;
    mcp-server)         raw="$(_dep_check_mcp_server "$name")" ;;
    playwright-browser) raw="$(_dep_check_playwright_browser "$name")" ;;
    uv-project)         raw="$(_dep_check_uv_project "$name")" ;;
    statusline)         raw="$(_dep_check_statusline "$name")" ;;
    *)                  raw="unknown|unknown" ;;
  esac

  present="${raw%%|*}"; version="${raw##*|}"

  # A constraint verdict is a judgement about an installed version. With
  # nothing installed there is nothing to judge — that is `unknown`, not `ok`.
  if [ "$present" != "yes" ]; then
    verdict=unknown
  else
    verdict="$(dep_constraint_verdict "$constraint" "$version")"
  fi
  echo "present=${present}|version=${version}|verdict=${verdict}"
}

# ─── Display indentation ─────────────────────────────────────────────────────
#
# THE CALLER OWNS THE DEPTH (six-axis review R-2). The prose this file prints
# lands inside somebody else's block — setup's numbered steps, which sit three
# spaces in, or remove's items, which sit two — and the indent used to be a bare
# literal here, so the seam between two files was visible on the user's screen:
# setup's own sentence three spaces in, the install prose beneath it two, down
# the whole step. The caller sets `BIONIC_DEP_INDENT` once; every line this file
# prints reads it. Two spaces is the default because that is what remove.sh and
# a route's just-in-time offer already use.
_dep_indent() { printf '%s' "${BIONIC_DEP_INDENT:-  }"; }

# ─── Consent ─────────────────────────────────────────────────────────────────

_dep_consent() {  # <prompt> -> 0 yes, 1 an explicit no, 2 EOF (nobody there to ask)
  local prompt="$1" answer=""
  # THE ANSWER IS ALREADY GIVEN. `setup --all` and `remove --all` print every
  # item their run would ask about — this one among them — and take a single
  # explicit `y` over that printed page before either sets its flag. Asking
  # again here would be asking a person to answer the same question twice.
  #
  # AND THE VALUE HERE IS ALWAYS THE SCRIPT'S OWN (epic-17 W7 S11, six-axis review
  # axis 4). An earlier version of this comment claimed neither name was settable
  # from outside those two scripts. That was FALSE, and it was the whole defect:
  # this function reads BOTH names, setup.sh zeroed only `SETUP_ALL` and remove.sh
  # only `RM_ALL`, so an exported `RM_ALL=1` answered every question in setup and
  # an exported `SETUP_ALL=1` answered every deps.sh-routed row in remove — with
  # the standard input closed and no page ever printed. What makes the claim true
  # now is not this comment: each script zeroes BOTH names before anything can ask
  # anything, so whatever the environment carries is overwritten by the script that
  # owns the question, and the only writer of a 1 is that script's own `--all` `y`.
  # The behavioural wall is one arm per suite (setup.test.sh / remove.test.sh, both
  # names exported, nothing on stdin, the machine byte-identical afterwards) — a
  # name grep cannot see this class, so the pin that could not see it is not the
  # pin that guards it.
  if [ "${SETUP_ALL:-0}" = "1" ] || [ "${RM_ALL:-0}" = "1" ]; then return 0; fi
  printf '%s [y/N] ' "$prompt"
  IFS= read -r answer || { echo ""; return 2; }
  echo ""
  case "$answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

# THE OTHER HALF OF A "NO" (AC-12). `_dep_consent` returning non-zero used to
# mean one thing — an explicit no — so every caller printed the same
# "declined —" sentence whether a person typed n or a non-interactive first
# pass hit EOF on the very first question. "declined" is a recorded choice;
# EOF means nobody was there to make one. This is the one sentence for that
# second case, so the transcript says so instead of putting a "no" in an
# absent user's mouth.
_dep_not_asked() {  # <name> — <name> stays absent, not asked
  printf '%snot asked — %s stays absent.\n' "$(_dep_indent)" "$1"
}

# The removal-side counterpart: a row left in place because nobody was there
# to answer, not because they said no. Same rule, opposite tail — every
# `_dep_consent` caller in this file (installers AND removers) gets to tell
# the two apart, not just `install_dep`.
_dep_not_asked_left() {  # <name> — <name> left in place, not asked
  printf '%snot asked — %s left in place.\n' "$(_dep_indent)" "$1"
}

# ─── Install ─────────────────────────────────────────────────────────────────
#
# One mutating entry point. The setup loop calls it once per row it installs; a
# route that hits an absent dependency calls it for that one row (AC-5). There
# is no third path and no silent path.

# The argv a mechanism would run. Printed to the user BEFORE the question and
# executed AFTER it, from the same source — the plan the user consented to is
# by construction the command that runs.
_dep_install_argv() {  # <name> — one token per line
  local name="$1" mech target
  mech="$(dep_field "$name" install_fn_or_check)" || return 1
  target="$(_dep_locator_target "$(dep_field "$name" source_url)")"
  case "$mech" in
    brew-dep)           printf '%s\n' brew install "$target" --quiet ;;
    brew-cask)          printf '%s\n' brew install --cask "$target" --quiet ;;
    npm-global)         printf '%s\n' npm install -g "$target" --silent ;;
    uv-tool)            printf '%s\n' uv tool install "$target" --quiet ;;
    pnpm-store)         printf '%s\n' pnpm store add "${target}@latest" ;;
    mcp-server)         printf '%s\n' claude mcp add "$name" -s user -- npx -y "$target" ;;
    playwright-browser) printf '%s\n' npx --yes "$target" install chromium ;;
    # `--project <dir>` rather than a `cd`: install_dep execs an argv, it does not run a
    # shell line, so the directory has to be an argument. An unresolvable project directory
    # yields no argv at all, which install_dep reports as "no install mechanism" instead of
    # syncing whatever the current directory happens to be.
    uv-project)
      local refs; refs="$(_dep_excalidraw_refs)"
      [ -n "$refs" ] || return 1
      printf '%s\n' uv "$target" --project "$refs" ;;
    statusline)         return 1 ;;  # not an argv — see _dep_install_statusline
    *)                  return 1 ;;
  esac
}

# ─── Writing through a symlink ───────────────────────────────────────────────
#
# WHAT A DOTFILES USER GETS OTHERWISE (critic delta 2 N1). A `~/.zshrc` or a
# `~/.claude/settings.json` symlinked into a dotfiles repo is a regular way to
# manage those files. Every writer in this payload stages a `<file>.bionic.tmp`
# and `mv`s it into place, and `mv` REPLACES the link with a regular file: the
# rewrite lands in a fresh inode at the link's path, the dotfiles copy keeps the
# content bionic just reported removing, `git status` in that repo shows nothing,
# and the next `stow` puts the whole footprint back. The user is told the
# footprint is gone while it is sitting in the file they actually manage. So the
# writers resolve the path to the FINAL target of its symlink chain and publish
# onto THAT: the link survives, still points where it did, and the file it names
# is the one that changed.
#
# NO `realpath`, and no `readlink -f`. `realpath` is not on a bare macOS, and
# BSD `readlink` has no `-f`. The loop below is the portable spelling: one hop at
# a time, relative targets resolved against the LINK's own directory (that is
# what the kernel does), with a hop cap so a symlink loop terminates instead of
# spinning. Bash 3.2 — no `${var@…}`, no arrays, no `readarray`.
#
# HONEST DEGRADATION, the same contract `stat` already has here. If `readlink` is
# not on the machine the loop breaks on the first hop and the caller writes to the
# path as given, which is the behaviour every writer had before this existed — a
# degradation, never a refusal. The standalone door runs on the box with the bare
# /bin and must still write.
#
# THE ABSENT CASE IS NOT NEUTRAL (critic delta 3 F5). Absent `readlink`, the write
# lands on the link's path as given, which replaces a symlink with a regular
# file — the pre-S15 behaviour. `readlink` lives beside `stat` on both platforms
# this payload targets, so the risk is negligible; it is recorded here because the
# consequence, not just the mechanism, is what a reader of this comment needs.
#
# THREE OTHER FILES CARRY A BYTE-IDENTICAL COPY under the same name — hooks.sh,
# profile.sh and remove.sh. Each is sourced on its own by something (the suites
# load the two libraries directly; remove.sh's standalone door runs where
# scripts/lib/ no longer exists), so none of them may assume this file came
# first, and a `. deps.sh` inside a library also breaks every mutation arm that
# runs a doctored COPY of it from a scratch directory. setup.sh sources this file
# at load and uses this definition. tests/remove.test.sh pins all four against
# each other, the same wall the settings writer's two copies stand behind.
bionic_link_target() {  # <path> — the final target of a symlink chain, else <path>
  local p="${1:-}" link dir n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    link="$(readlink "$p" 2>/dev/null)" || break
    [ -n "$link" ] || break
    case "$link" in
      /*) p="$link" ;;
      *)  dir="${p%/*}"; [ "$dir" = "$p" ] && dir="."; p="${dir}/${link}" ;;
    esac
    n=$((n + 1))
  done
  printf '%s\n' "$p"
}

# THE ONE SETTINGS WRITER IN THIS FILE. Both statusline arms — recording the
# line on install and clearing it on removal — are jq rewrites of the same
# ~/.claude/settings.json, so they are one function rather than two copies of
# six lines. They were two copies once, and the drift that cost is exactly this:
# the mode repair that landed in the payload's other writers never reached
# either of them, and no test noticed. tests/remove.test.sh pins this body's
# shape alongside the other three and walls the payload against a fifth writer
# appearing beside them.
#
# THE FILE'S MODE SURVIVES THE REWRITE. `mv` replaces the inode, so without the
# capture-and-reapply below a settings.json the user deliberately kept at 0600 —
# it routinely holds an `env` block with tokens — would come back at whatever the
# umask says, as a side effect of recording a statusline. `stat` is spelled both
# ways because BSD and GNU take different flags and neither accepts the other's;
# an absent `stat` leaves `mode` empty and the rewrite still lands, which is the
# same honest degradation this file already practises for `jq`.
#
# AND IT IS THE TARGET'S MODE, NOT THE LINK'S (S14, closing the class the S13
# critic delta left standing here). A `~/.claude/settings.json` symlinked into a
# dotfiles repo is the commonest way people manage it, and a bare `stat` on a
# symlink reports the LINK's own mode — 755 — never the file's. Capturing that
# and handing it to `chmod` publishes the rewrite as `rwxr-xr-x`: WIDER than the
# file being replaced, which is the one outcome this capture exists to prevent.
# `-L` is what makes the capture mean the file; both flavours take it.
#
# THE ORDER IS THE FIX. `umask 077` and the `chmod` both come BEFORE the `mv`, so
# the rename publishes an already-correct inode. Repairing the mode afterwards —
# the obvious spelling — leaves the tmp holding the tokens at 0644 under a
# predictable name, and makes the widening PERMANENT if the process dies in the
# window between the two. Do not move either below the rename. The guard is
# spelled `-z … ||` rather than `-n … &&` because this is a single `&&` chain: on
# a machine with no `stat` the `-n` spelling would break the chain and skip the
# rename entirely, turning honest degradation into a silent refusal to write.
# hooks.sh's `hooks_strip_legacy_channel` carries the same shape for the same
# reasons.
#
# THE STALE TMP IS REMOVED, NOT TRUNCATED. `>` on an existing file keeps that
# file's mode, so a tmp left behind by an earlier interrupted run would carry
# ITS width through the write, exposed until the chmod line below catches up —
# the one hole S13's own header comment ("nothing ever exists at a mode wider
# than the file it is replacing") did not cover for this writer.
_dep_settings_write_jq() {  # <settings-file> <jq-program> [jq-arg...]
  local settings="${1:-}" program="${2:-}"
  shift 2 || return 1
  local tmp mode
  settings="$(bionic_link_target "$settings")"
  tmp="${settings}.bionic.tmp"
  mode="$(stat -L -f '%Lp' "$settings" 2>/dev/null || stat -L -c '%a' "$settings" 2>/dev/null)"
  [ -e "$settings" ] || mode=""
  rm -f "$tmp"
  if (umask 077; jq "$@" "$program" "$settings" > "$tmp") \
     && { [ -z "$mode" ] || chmod "$mode" "$tmp"; } \
     && mv "$tmp" "$settings"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# The statusline is a settings.json edit, not a package install: `npx
# ccstatusline@latest` is the command Claude Code runs to RENDER the line, and
# installing it means recording that command. Ported from
# claude-bootstrap.sh's do_set_statusline.
#
# BOTH HALVES (epic-18 T1, AC-1). Recording the command alone leaves
# ccstatusline rendering its own stock default — handoff §3.1's incident —
# because the LAYOUT (colors, field order) lives in a second file this
# function now also copies: the payload's own
# ${CLAUDE_PLUGIN_ROOT}/ccstatusline/settings.json, published to
# ~/.config/ccstatusline/settings.json exactly as claude-bootstrap.sh's
# ccstatusline-config step did. Skipped when already byte-identical, ported
# from that same step's `diff -q` short-circuit.
_dep_install_statusline() {
  local settings cmd source target
  settings="$(_dep_settings_file)"
  cmd="npx $(_dep_locator_target "$(dep_field ccstatusline source_url)")"
  _dep_have jq || { echo "$(_dep_indent)jq is not installed — cannot edit ${settings}" >&2; return 1; }
  # Deliberately NOT under `umask 077`: the defect being fixed is widening a mode
  # the USER chose, and a file that does not exist yet carries no such choice.
  # bionic creating settings.json at 0600 where the CLI would have made it 0644
  # is a different decision, and not this fold's to make.
  [ -f "$settings" ] || echo '{}' > "$settings"
  _dep_settings_write_jq "$settings" \
    '.statusLine = {"type": "command", "command": $c}' --arg c "$cmd" || return 1

  source="$(_dep_ccstatusline_config_source)"
  target="$(_dep_ccstatusline_config_target)"
  if [ ! -f "$source" ]; then
    echo "$(_dep_indent)shipped ccstatusline layout missing at ${source} — the statusline command is set but its config was not copied." >&2
    return 1
  fi
  _dep_files_match "$source" "$target" && return 0
  mkdir -p "$(_dep_ccstatusline_config_dir)" && cp "$source" "$target"
}

install_dep() {  # <name>
  local name="${1:-}" kind plan line
  local -a argv=()
  kind="$(dep_field "$name" kind)" || return 1

  # KIND, not class. Every native row is the harness's — the two core plugins
  # and the when-needed one alike — and a class-keyed guard would hand
  # impeccable to a mechanism that has no argv for it.
  if [ "$kind" = "native" ]; then
    echo "deps.sh: ${name} is installed by the plugin harness; there is no second installer." >&2
    return 1
  fi

  if [ "$(dep_field "$name" install_fn_or_check)" = "statusline" ]; then
    # BOTH HALVES, SURFACED BEFORE THE ONE QUESTION (AC-1: "never silently
    # overwritten"). This is a single-item row like every other — one
    # `_dep_consent` call below covers the whole plan — so a config file
    # already there that DIFFERS from the shipped layout is named in the
    # plan sentence itself rather than discovered only after a yes.
    local cfg_source cfg_target cfg_note=""
    cfg_source="$(_dep_ccstatusline_config_source)"
    cfg_target="$(_dep_ccstatusline_config_target)"
    if [ -f "$cfg_target" ] && ! _dep_files_match "$cfg_source" "$cfg_target"; then
      cfg_note=" (a config file already there differs from the shipped layout and would be overwritten)"
    fi
    plan="record 'npx $(_dep_locator_target "$(dep_field "$name" source_url)")' as the statusline in $(_dep_settings_file), and copy ${cfg_source} to ${cfg_target}${cfg_note}"
  else
    while IFS= read -r line; do argv+=("$line"); done < <(_dep_install_argv "$name") || true
    [ "${#argv[@]}" -gt 0 ] || { echo "deps.sh: no install mechanism for ${name}" >&2; return 1; }
    plan="${argv[*]}"
    # AC-5: notebooklm's second half, named in the plan the user consents to
    # rather than run silently behind it (see _dep_check_uv_tool above).
    [ "$name" = "notebooklm" ] && plan="${plan} && notebooklm skill install"
  fi

  echo "$(_dep_indent)${name} is not installed. bionic would run: ${plan}"
  _dep_consent "$(_dep_indent)Install ${name} now?"
  case $? in
    0) ;;
    2) _dep_not_asked "$name"; return 2 ;;
    *) echo "$(_dep_indent)declined — ${name} stays absent."; return 1 ;;
  esac

  # THE SUCCESS LINE (AC-11 — O-1). Every other item kind confirms what it did
  # ("added.", "applied.", "set."); a `tool:*` row used to run its mechanism and
  # say nothing at all, so a consented install and a silently-absent tool read
  # identically until the next `/bionic:doctor`. `install_dep`'s return value IS
  # the mechanism's own exit code — this only speaks on the zero.
  if [ "${#argv[@]}" -gt 0 ]; then
    if "${argv[@]}"; then
      if [ "$name" = "notebooklm" ]; then
        notebooklm skill install || {
          echo "$(_dep_indent)installed, but 'notebooklm skill install' failed." >&2
          return 1
        }
      fi
      echo "$(_dep_indent)installed."
      return 0
    fi
  else
    _dep_install_statusline && { echo "$(_dep_indent)installed."; return 0; }
  fi
  return 1
}

# ─── The OTHER installer, and why there are exactly two ──────────────────────
#
# `install_dep` refuses every native row above, and that refusal is right: there
# is no argv bionic could run to install a plugin, because installing a plugin
# is the CLI's own act. What the refusal did NOT do is give anybody a way to ASK
# for one. Setup's first step grew its own copy of the question, and when a
# when-needed row turned out to be native too (`impeccable`, the design route's
# dependency) the just-in-time offer had nothing to call and printed a command
# for the user to paste instead — an offer with no answer, for the one class of
# tool the ratified policy says to install at the moment of need (D-B, AC-11).
#
# So this is that missing entry point, and it is deliberately a SIBLING of
# install_dep rather than a branch inside it. The two differ in every part that
# matters — who executes the install, what the plan sentence is, and whether the
# result is usable in the session that asked — and folding them together would
# be the second-installer kludge the ownership table exists to prevent. What
# they share is the only thing that must not fork: the consent gate, which is
# `_dep_consent` here exactly as it is there.
#
# CONSENT, THEN THE CLI, THEN THE ONE THING THE USER HAS TO KNOW. The plan is
# printed before the question and run after it, from the same string. The `--yes`
# is not a consent bypass: it suppresses the CLI's own second prompt about a
# decision this function has already had with the user, and without it a
# consented install would sit waiting on a question nobody can see.
#
# THE CAVEAT IS THE POINT OF THE THIRD LINE. A plugin the CLI installs mid-run
# is not loaded into the session that asked for it until the plugins are re-read.
# Saying so is the one line that changes what the user does next, which is
# exactly the bar the voice contract sets for a caveat.
#
# Callers: setup.sh's first step (bionic itself) and jit.sh's `jit_offer` for a
# native `when-needed` row. Both reach the CLI through this function and nowhere
# else.
install_plugin_native() {  # <name>
  local name="${1:-}" marketplace id
  [ -n "$name" ] || { echo "deps.sh: install_plugin_native needs a plugin name" >&2; return 1; }
  # THE ONE EXTERNAL THIS FILE USED TO CALL UNGUARDED (critic F-5). `jq`, `npm`
  # and `brew` all pass through `_dep_have` first; these two did not, so a machine
  # without the CLI got `deps.sh: line 664: claude: command not found` — a library
  # filename and a line number on a user's terminal, which is the exact class of
  # display this wave exists to remove and the one class no source lint can see,
  # because bash writes the string at runtime. Guarded BEFORE the plan is printed:
  # an offer whose yes cannot be honoured is a worse thing to show than no offer.
  _dep_have claude || {
    echo "$(_dep_indent)the Claude Code CLI is not on PATH — bionic cannot install a plugin without it."
    return 1
  }
  marketplace="${BIONIC_DEP_MARKETPLACE:-bionic}"
  id="${name}@${marketplace}"

  echo "$(_dep_indent)${name} is not installed. bionic would run: claude plugin install ${id} --scope user --yes"
  _dep_consent "$(_dep_indent)Install ${name} now?"
  case $? in
    0) ;;
    2) _dep_not_asked "$name"; return 2 ;;
    *) echo "$(_dep_indent)declined — ${name} stays absent."; return 1 ;;
  esac

  if claude plugin install "$id" --scope user --yes; then
    echo "$(_dep_indent)Takes effect after /reload-plugins or a new session."
    return 0
  fi
  return 1
}

# ─── Remove ──────────────────────────────────────────────────────────────────

# THE COUNTERPART TO `install_plugin_native`, and it exists because the installer
# shipped without one (six-axis review A-2). Same shape, same rule, opposite
# direction: the plan is printed before the question and run after it, from the
# same string, and `--yes` suppresses the CLI's second prompt about a decision
# this function has already had with the user — never the first one.
#
# NO PRESENCE CHECK HERE. The caller establishes presence (remove.sh asks
# `check_dep` before it walks a row), exactly as it does for every other kind:
# a function that re-probed would be a second opinion about a fact the table
# already owns.
remove_plugin_native() {  # <name>
  local name="${1:-}" marketplace id
  [ -n "$name" ] || { echo "deps.sh: remove_plugin_native needs a plugin name" >&2; return 1; }
  # Same guard, same reason as install_plugin_native (critic F-5), and it matters
  # more here: remove.sh's standalone door exists for a machine where bionic's
  # world is partly gone, which is exactly where the CLI may already be missing.
  _dep_have claude || {
    echo "$(_dep_indent)the Claude Code CLI is not on PATH — bionic cannot uninstall a plugin without it."
    return 1
  }
  marketplace="${BIONIC_DEP_MARKETPLACE:-bionic}"
  id="${name}@${marketplace}"

  echo "$(_dep_indent)${name}: bionic would run: claude plugin uninstall ${id} --yes"
  _dep_consent "$(_dep_indent)Remove ${name} now?"
  case $? in
    0) ;;
    2) _dep_not_asked_left "$name"; return 2 ;;
    *) echo "$(_dep_indent)declined — ${name} left in place."; return 1 ;;
  esac

  claude plugin uninstall "$id" --yes || return 1
  return 0
}

# WHOSE COPY IS THIS? (critic F-4.) `_dep_check_native` matches on the NAME half
# across catalogs, deliberately — S3 re-points bionic's own marketplace and that
# match is what survives it — so "present" says nothing about who installed what
# is present. The teardown needs the other question, and only the teardown does:
# a `<name>@bionic` key is a plugin bionic's own route installed and nothing else
# will ever remove; a `<name>@somebody-else` key is the user's own, and removing
# it would be a mutation nobody asked for under an id that does not exist.
#
# Three states rather than a yes/no, because "not ours" and "not there at all"
# are different sentences to a reader and only one of them is about a catalog:
#
#   ours     `<name>@<bionic's marketplace>` is a key in the registry
#   other    the name is there, under somebody else's catalog
#   absent   no key of that name at all
#   unknown  the registry could not be read (no jq)
_dep_native_registry_state() {  # <name> -> ours|other|absent|unknown
  local name="${1:-}" id file out
  [ -n "$name" ] || { echo unknown; return 0; }
  id="${name}@${BIONIC_DEP_MARKETPLACE:-bionic}"
  _dep_have jq || { echo unknown; return 0; }
  file="$(_dep_installed_json)"
  [ -f "$file" ] || { echo absent; return 0; }
  out="$(jq -r --arg n "$name" --arg k "$id" '
      (.plugins // {}) as $p
      | if ($p | has($k)) then "ours"
        elif ([ $p | keys[] | select((split("@")[0]) == $n) ] | length) > 0 then "other"
        else "absent" end' "$file" 2>/dev/null)" || out=""
  case "$out" in ours|other|absent) echo "$out" ;; *) echo unknown ;; esac
}

_dep_remove_argv() {  # <name> — one token per line
  local name="$1" mech target
  mech="$(dep_field "$name" install_fn_or_check)"
  target="$(_dep_locator_target "$(dep_field "$name" source_url)")"
  case "$mech" in
    npm-global) printf '%s\n' npm uninstall -g "$target" ;;
    uv-tool)    printf '%s\n' uv tool uninstall "$target" ;;
    mcp-server) printf '%s\n' claude mcp remove "$name" -s user ;;
    *)          return 1 ;;
  esac
}

# THE ONE ENTRY POINT FOR "what happens to this dependency", and its answer is
# an exit code with three meanings, not two:
#
#   0  this row's policy was carried out — removed, or kept with the user told why
#   2  left in place by policy, nothing asked and nothing declined (critic F-4:
#      a same-named plugin from a catalog bionic never installed from)
#   1  not done — declined, or a mechanism that failed or could not be read
#
# The caller counts 0 and 2 as settled and 1 as outstanding; remove.sh's summary
# is built on that split.
remove_dep() {  # <name>
  local name="${1:-}" behavior plan line rc
  local -a argv=()
  behavior="$(dep_field "$name" removal_behavior)" || return 1

  case "$behavior" in
    keep-shared)
      # R-1: `keep-shared` is this table's word for the policy, not the user's.
      # What reaches the terminal is what was decided and why.
      echo "$(_dep_indent)${name}: kept — shared with other tools, bionic never removes it."
      return 0
      ;;
    native-uninstall-offer)
      # TWO NATIVE BEHAVIOURS, NOT ONE (six-axis review A-2). Both kinds of row
      # are plugins the CLI installed, and that is where the resemblance ends.
      #
      #   a row bionic DECLARES (class core, in plugin.json's dependencies):
      #     removing bionic removes it — the uninstall and prune at the end of
      #     the teardown are what take it, and asking here would be a second
      #     question about one decision.
      #
      #   a row bionic does NOT declare (impeccable, class when-needed):
      #     `install_plugin_native` can put it on a machine mid-session from a
      #     route's offer, and A-3.1 rules that the marketplace entry declares no
      #     dependency. Nothing else will ever remove it. This branch used to
      #     tell that user their plugin uninstall would take it, which was false
      #     by construction and left the plugin behind after a full, all-yes
      #     teardown.
      if [ "$(dep_field "$name" class)" = "core" ]; then
        echo "$(_dep_indent)${name}: bionic declares this plugin, so removing bionic removes it too."
        return 0
      fi
      # AND THE ID HAS TO BE THE ONE THE REGISTRY HOLDS (critic F-4). The presence
      # probe two functions up matches the bare name across catalogs, so a user's
      # own `impeccable` from another catalog read as present and was offered for
      # removal under `impeccable@bionic` — an id that does not exist. The CLI
      # answered "not installed", the non-zero landed in the skipped bucket, and a
      # user who said yes was reported as having skipped it.
      #
      # There is no question to ask about somebody else's copy, so none is asked:
      # exit 2 says "left in place by policy, nothing was declined", which is the
      # bucket the caller counts as clean rather than as a refusal.
      case "$(_dep_native_registry_state "$name")" in
        ours)
          remove_plugin_native "$name"; return $? ;;
        other)
          echo "$(_dep_indent)${name}: installed from another catalog — bionic did not install it and leaves it alone."
          return 2 ;;
        absent)
          echo "$(_dep_indent)${name}: bionic did not install this plugin, so there is nothing here to remove."
          return 2 ;;
        *)
          echo "$(_dep_indent)${name}: the list of installed plugins could not be read, so ${name} is left in place."
          return 1 ;;
      esac
      ;;
  esac

  case "$(dep_field "$name" install_fn_or_check)" in
    playwright-browser)
      plan="rm -rf $(_dep_playwright_cache)"
      ;;
    # THE VENV AND NOTHING ELSE. The skill's own files ship inside the plugin, so they leave
    # when the plugin does; what a teardown has to account for here is the tree `uv sync`
    # wrote into the plugin's copy, which no plugin uninstall knows about.
    uv-project)
      plan="rm -rf $(_dep_excalidraw_refs)/.venv"
      ;;
    pnpm-store)
      echo "$(_dep_indent)${name}: lives in the shared pnpm store — removing it would evict a cache other projects hard-link from; leaving it."
      return 0
      ;;
    statusline)
      plan="clear .statusLine from $(_dep_settings_file), and remove $(_dep_ccstatusline_config_dir)"
      ;;
    *)
      while IFS= read -r line; do argv+=("$line"); done < <(_dep_remove_argv "$name") || true
      [ "${#argv[@]}" -gt 0 ] || { echo "deps.sh: no removal mechanism for ${name}" >&2; return 1; }
      plan="${argv[*]}"
      # AC-5: notebooklm's skill dir, named in the plan alongside the uv-tool
      # uninstall — one consent covers both halves, same as the install arm.
      [ "$name" = "notebooklm" ] && plan="${plan} && rm -rf $(_dep_claude_home)/skills/notebooklm"
      ;;
  esac

  echo "$(_dep_indent)${name}: bionic would run: ${plan}"
  _dep_consent "$(_dep_indent)Remove ${name} now?"
  case $? in
    0) ;;
    2) _dep_not_asked_left "$name"; return 2 ;;
    *) echo "$(_dep_indent)declined — ${name} left in place."; return 1 ;;
  esac

  if [ "${#argv[@]}" -gt 0 ]; then
    "${argv[@]}"
    rc=$?
    [ "$name" = "notebooklm" ] && rm -rf "$(_dep_claude_home)/skills/notebooklm"
    return "$rc"
  else
    case "$(dep_field "$name" install_fn_or_check)" in
      playwright-browser) rm -rf "$(_dep_playwright_cache)" ;;
      uv-project)
        local _xr_refs
        _xr_refs="$(_dep_excalidraw_refs)"
        [ -n "$_xr_refs" ] && rm -rf "${_xr_refs}/.venv"
        ;;
      statusline)
        # BOTH HALVES (AC-3). The settings-clear used to `return 0` the
        # instant settings.json was absent, which skipped the config purge
        # below it entirely whenever the two halves came apart — exactly the
        # shape a machine with the config directory but no `.statusLine` key
        # is in. The two removals are independent now: an absent settings
        # file is nothing to clear, not a reason to stop.
        local settings dir
        settings="$(_dep_settings_file)"
        if [ -f "$settings" ]; then
          _dep_have jq || return 1
          _dep_settings_write_jq "$settings" 'del(.statusLine)' || return 1
        fi
        # THE SAME NEVER-LIST remove.sh's `_rm_purge_dir` enforces, its own
        # copy rather than a call across files — this library must stay
        # sourceable with no remove.sh in the process (tests/plugin-lib.test.sh
        # drives remove_dep directly), the same reason `bionic_link_target`
        # is duplicated rather than shared.
        dir="$(_dep_ccstatusline_config_dir)"
        case "$dir" in
          */.bionic|*/.bionic/*|""|/|"$HOME") ;;
          *) rm -rf "$dir" ;;
        esac
        ;;
    esac
  fi
}
