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
_dep_playwright_cache() {
  if [ -n "${BIONIC_PLAYWRIGHT_CACHE:-}" ]; then echo "$BIONIC_PLAYWRIGHT_CACHE"; return; fi
  case "$(uname -s 2>/dev/null || echo Darwin)" in
    Linux) echo "$HOME/.cache/ms-playwright" ;;
    *)     echo "$HOME/Library/Caches/ms-playwright" ;;
  esac
}

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
#                         Repo-relative, not payload-relative: the traceability
#                         claim is about this repository's doctrine, and some
#                         routes (excalidraw-diagram) ship outside the payload.
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
playwright-chromium|when-needed|skills/excalidraw-diagram/SKILL.md|npx:playwright@latest|any|playwright-browser|remove-on-consent
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

# DEPRECATED — the pre-wave-06 view, kept because setup.sh and remove.sh still
# walk it and neither is this slice's to restructure (S4 and S7 retire the call
# sites). It is a VIEW over class and kind, never a stored field:
#   3a = the rows the harness installs  (class core)
#   3b = the rows bionic installs itself (kind != native)
# A native row outside `core` — impeccable — is in NEITHER list, and that is the
# point rather than an oversight. Putting it in 3b would have setup offer a
# when-needed tool it must not ask about (AC-11) and hand `install_dep` a row it
# is required to refuse; putting it in 3a would have setup tell the user to
# reinstall bionic so a dependency it never declares would resolve.
dep_names_lane() {  # <3a|3b>
  local want="${1:-}"
  case "$want" in
    3a) dep_names_class core ;;
    3b) printf '%s\n' "$BIONIC_DEP_TABLE" | while IFS='|' read -r n _ _ _ _ kind _; do
          [ -n "$n" ] && [ "$kind" != "native" ] && echo "$n"
        done ;;
  esac
  return 0
}

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
    # DEPRECATED, derived, and consistent with `dep_names_lane` by
    # construction — the same rule computed the same way, so the field and the
    # list can never disagree about a row. detect.sh is its only caller.
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
_dep_check_uv_tool()   { _dep_check_brew_dep "$@"; }

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

_dep_check_statusline() {
  local settings cmd
  settings="$(_dep_settings_file)"
  _dep_have jq || { echo "unknown|unknown"; return 0; }
  [ -f "$settings" ] || { echo "no|unknown"; return 0; }
  cmd="$(jq -r '.statusLine.command // ""' "$settings" 2>/dev/null)"
  case "$cmd" in
    *ccstatusline*) echo "yes|unknown" ;;
    *)              echo "no|unknown" ;;
  esac
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

# ─── Consent ─────────────────────────────────────────────────────────────────

_dep_consent() {  # <prompt> — non-zero unless the answer is an explicit yes
  local prompt="$1" answer=""
  printf '%s [y/N] ' "$prompt"
  IFS= read -r answer || { echo ""; return 1; }
  echo ""
  case "$answer" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
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
    statusline)         return 1 ;;  # not an argv — see _dep_install_statusline
    *)                  return 1 ;;
  esac
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
_dep_settings_write_jq() {  # <settings-file> <jq-program> [jq-arg...]
  local settings="${1:-}" program="${2:-}"
  shift 2 || return 1
  local tmp="${settings}.bionic.tmp" mode
  mode="$(stat -f '%Lp' "$settings" 2>/dev/null || stat -c '%a' "$settings" 2>/dev/null)"
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
_dep_install_statusline() {
  local settings cmd
  settings="$(_dep_settings_file)"
  cmd="npx $(_dep_locator_target "$(dep_field ccstatusline source_url)")"
  _dep_have jq || { echo "  jq is not installed — cannot edit ${settings}" >&2; return 1; }
  # Deliberately NOT under `umask 077`: the defect being fixed is widening a mode
  # the USER chose, and a file that does not exist yet carries no such choice.
  # bionic creating settings.json at 0600 where the CLI would have made it 0644
  # is a different decision, and not this fold's to make.
  [ -f "$settings" ] || echo '{}' > "$settings"
  _dep_settings_write_jq "$settings" \
    '.statusLine = {"type": "command", "command": $c}' --arg c "$cmd"
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
    plan="record 'npx $(_dep_locator_target "$(dep_field "$name" source_url)")' as the statusline in $(_dep_settings_file)"
  else
    while IFS= read -r line; do argv+=("$line"); done < <(_dep_install_argv "$name") || true
    [ "${#argv[@]}" -gt 0 ] || { echo "deps.sh: no install mechanism for ${name}" >&2; return 1; }
    plan="${argv[*]}"
  fi

  echo "  ${name} is not installed. bionic would run: ${plan}"
  _dep_consent "  Install ${name} now?" || { echo "  declined — ${name} stays absent."; return 1; }

  if [ "${#argv[@]}" -gt 0 ]; then "${argv[@]}"; else _dep_install_statusline; fi
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
  marketplace="${BIONIC_DEP_MARKETPLACE:-bionic}"
  id="${name}@${marketplace}"

  echo "  ${name} is not installed. bionic would run: claude plugin install ${id} --scope user --yes"
  _dep_consent "  Install ${name} now?" || { echo "  declined — ${name} stays absent."; return 1; }

  if claude plugin install "$id" --scope user --yes; then
    echo "  Takes effect after /reload-plugins or a new session."
    return 0
  fi
  return 1
}

# ─── Remove ──────────────────────────────────────────────────────────────────

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

remove_dep() {  # <name>
  local name="${1:-}" behavior plan line
  local -a argv=()
  behavior="$(dep_field "$name" removal_behavior)" || return 1

  case "$behavior" in
    keep-shared)
      echo "  ${name}: keep-shared — bionic ensured this binary but does not own it; leaving it in place."
      return 0
      ;;
    native-uninstall-offer)
      echo "  ${name}: removed by the plugin uninstall, not here."
      return 0
      ;;
  esac

  case "$(dep_field "$name" install_fn_or_check)" in
    playwright-browser)
      plan="rm -rf $(_dep_playwright_cache)"
      ;;
    pnpm-store)
      echo "  ${name}: lives in the shared pnpm store — removing it would evict a cache other projects hard-link from; leaving it."
      return 0
      ;;
    statusline)
      plan="clear .statusLine from $(_dep_settings_file)"
      ;;
    *)
      while IFS= read -r line; do argv+=("$line"); done < <(_dep_remove_argv "$name") || true
      [ "${#argv[@]}" -gt 0 ] || { echo "deps.sh: no removal mechanism for ${name}" >&2; return 1; }
      plan="${argv[*]}"
      ;;
  esac

  echo "  ${name}: bionic would run: ${plan}"
  _dep_consent "  Remove ${name} now?" || { echo "  declined — ${name} left in place."; return 1; }

  if [ "${#argv[@]}" -gt 0 ]; then
    "${argv[@]}"
  else
    case "$(dep_field "$name" install_fn_or_check)" in
      playwright-browser) rm -rf "$(_dep_playwright_cache)" ;;
      statusline)
        local settings
        settings="$(_dep_settings_file)"
        _dep_have jq || return 1
        [ -f "$settings" ] || return 0
        _dep_settings_write_jq "$settings" 'del(.statusLine)'
        ;;
    esac
  fi
}
