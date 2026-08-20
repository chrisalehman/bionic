#!/bin/bash
# PERMISSION PROFILE — epic-17 wave-03 slice S5 (spec AC-6, design D2-final).
#
# WHAT THIS SUITE OWNS. The permission pipeline's two halves:
#
#   payload/permissions/profile.template.json   the shipped, versioned TEMPLATE
#   payload/scripts/lib/profile.sh              render / apply / strip / diff / detect
#
# THE MODEL IT PINS (wave-03 spec §Design, "Permission profile"). A shipped
# TEMPLATE carrying the placeholder token `__BIONIC_PLUGIN_ROOT__`; a RENDERED
# marker block written into the USER settings layer under explicit consent; and
# ACCRETION, meaning anything in `permissions.allow` outside that block. The
# invariant: render is deterministic from (template, install path), and diff is
# re-render + compare. Identity was refuted by measurement — permission rules
# take literal paths only, and the concrete plugin path is what the permission
# gate sees (record/epic-17-w3/probe-identity-match.md, D2-final) — so
# derivation is the mechanism and this suite is where its determinism is proven.
#
# HERMETIC. No live `~/.claude` is read or written by any assertion here. Every
# function runs in a `env -i` subshell whose HOME, PATH and BIONIC_SETTINGS_FILE
# point into a temp tree this suite owns. The one thing taken from the real
# machine is the SHAPE of a settings file, copied into the fixtures below with
# the capture command quoted beside it.
#
# BOTH ARMS, ALWAYS. Every fact is asserted present AND absent. An
# absence-only readback proves nothing: a `detect_profile_state` that always
# printed `applied=no` would pass a one-armed suite.
#
# MUTATION AND RESTORE. Four assertions here are only worth their line count if
# they would go red when the behavior they name disappears. RED evidence dies at
# green and cannot be audited afterwards, so the proof is taken HERE: a copy of
# the library (or of the template) is doctored, the assertion is re-run against
# the doctored copy, and the suite records that the doctored build failed. The
# production files are never touched.
#
# Usage: bash tests/profile.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PROFILE_SH="${REPO}/payload/scripts/lib/profile.sh"
TEMPLATE="${REPO}/payload/permissions/profile.template.json"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
HOOKS_JSON="${REPO}/hooks/hooks.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
# Pattern match without a pipe: `printf "$haystack" | grep -q` is a SIGPIPE race
# under pipefail that reports a present needle as missing
# (tests/assert-helper-race.test.sh pins that lesson).
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "'$actual' does not match '$pattern'"; fi
}
expect_nomatch() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "'$actual' unexpectedly matches '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"

# A bin dir carrying only what a hermetic run legitimately needs. PATH is
# REPLACED, never prefixed, so nothing on this machine's real PATH can be
# reached by accident.
BASE_BIN="$TMP/base-bin"; mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod stat ls tr head tail sort uniq wc diff jq python3; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done
# The same bin dir minus jq — the honest-degradation arms run against this one.
NOJQ_BIN="$TMP/nojq-bin"; mkdir -p "$NOJQ_BIN"
for f in "$BASE_BIN"/*; do
  case "${f##*/}" in jq) continue ;; esac
  ln -sf "$(readlink "$f")" "${NOJQ_BIN}/${f##*/}" 2>/dev/null
done

# prof_run_with <lib> <env-assignments...> -- <function> [args]
# One library function in a fresh bash with a controlled environment. The <lib>
# parameter is what lets the mutation arms drive a doctored COPY through the
# identical call path as the production file.
prof_run_with() {
  local lib="$1"; shift
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift  # drop --
  env -i HOME="$TMP/home" PATH="$BASE_BIN" "${envs[@]}" \
    bash -c '. "$1"; shift; "$@"' _ "$lib" "$@" 2>&1
}
prof_run() { prof_run_with "$PROFILE_SH" "$@"; }

# The same, with jq absent from PATH.
prof_run_nojq() {
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -i HOME="$TMP/home" PATH="$NOJQ_BIN" "${envs[@]}" \
    bash -c '. "$1"; shift; "$@"' _ "$PROFILE_SH" "$@" 2>&1
}

# A plugin root that looks like the real thing. Captured on this machine
# 2026-08-17 with `ls -la ~/.claude/plugins/cache/claude-plugins-official/superpowers/`:
# the CLI lays plugins out as <claude-home>/plugins/cache/<marketplace>/<plugin>/<version>,
# so the concrete root carries a VERSION SEGMENT — which is precisely why every
# plugin update stales the rendered block (wave-03 spec §Assumptions 3).
FAKE_ROOT="$TMP/home/.claude/plugins/cache/bionic/bionic/0.1.0"
FAKE_ROOT_V2="$TMP/home/.claude/plugins/cache/bionic/bionic/0.2.0"

# ---------------------------------------------------------------------------
# Settings fixtures
# ---------------------------------------------------------------------------
#
# FIXTURE FIDELITY. The shape below is this machine's real user settings file,
# captured 2026-08-17:
#
#   jq -S 'keys' ~/.claude/settings.json
#     -> ["agentPushNotifEnabled","effortLevel","enabledPlugins","env",
#         "extraKnownMarketplaces","hooks","mcpServers","model","permissions",
#         "skipDangerousModePermissionPrompt","statusLine","theme","tui"]
#   jq '.permissions' ~/.claude/settings.json
#     -> {"allow":["mcp__pencil"]}          (one pre-existing rule: real accretion)
#   jq . ~/.claude/settings.json | diff - ~/.claude/settings.json
#     -> differs ONLY by "\ No newline at end of file"
#
# That last line is the load-bearing one: the CLI writes jq-canonical JSON with
# NO trailing newline. Both shapes are fixtured below, because a round trip that
# is byte-exact on one and not the other is not byte-exact.
#
# THE CAPTURED LITERAL MOVED, AND THE FIXTURES DELIBERATELY DID NOT FOLLOW IT.
# Wave-06 S5 harvests that captured rule into the shipped block (AC-12) — it was
# precisely the prompt bionic's own offer of `@pencil.dev/cli` generates, which
# is what "harvest the gap" means. A fixture that kept the same literal as its
# stand-in for "a rule of the MACHINE's own" would stop discriminating the moment
# the block carries it: the `index(...) != null` assertions below would hold
# whether or not the user's own rule survived an apply. So the accretion rules
# use a DIFFERENT foreign server name. The capture above is left as measured —
# the shape it documents (one MCP rule, no trailing newline) is what the fixtures
# reproduce, and the shape is the part that was ever load-bearing.

# write_settings <path> — canonical JSON from stdin, no trailing newline.
write_settings() {
  local path="$1" body
  body="$(jq .)" || return 1
  printf '%s' "$body" > "$path"
}
# write_settings_nl <path> — the same, WITH a trailing newline.
write_settings_nl() {
  local path="$1" body
  body="$(jq .)" || return 1
  printf '%s\n' "$body" > "$path"
}

SET_REAL="$TMP/settings-real.json"
write_settings "$SET_REAL" <<'JSON'
{
  "model": "opusplan",
  "theme": "dark",
  "env": { "CLAUDE_CODE_ENABLE_TODO_TOOLS": "1" },
  "permissions": { "allow": ["mcp__notion"] },
  "enabledPlugins": { "bionic@bionic": true },
  "statusLine": { "type": "command", "command": "npx ccstatusline@latest" }
}
JSON

SET_REAL_NL="$TMP/settings-real-nl.json"
write_settings_nl "$SET_REAL_NL" <<'JSON'
{
  "model": "opusplan",
  "permissions": { "allow": ["mcp__notion"] }
}
JSON

# No `permissions` key at all — the shape a fresh machine lands in.
SET_BARE="$TMP/settings-bare.json"
write_settings "$SET_BARE" <<'JSON'
{ "model": "opusplan", "theme": "dark" }
JSON

# Accretion fixture: several rules of the machine's own, none of them bionic's.
SET_ACCRETED="$TMP/settings-accreted.json"
write_settings "$SET_ACCRETED" <<'JSON'
{
  "model": "opusplan",
  "permissions": { "allow": ["mcp__notion", "Bash(gh pr view:*)", "Read(~/notes/*)"] }
}
JSON

echo "=== Group 1: the artifacts exist and are well-formed ==="

expect_true "profile.sh exists"                     test -f "$PROFILE_SH"
expect_true "profile.template.json exists"          test -f "$TEMPLATE"
expect_true "profile.sh passes bash -n"             bash -n "$PROFILE_SH"
expect_true "profile.sh sources without error"      bash -c '. "$1"' _ "$PROFILE_SH"
expect_true "the template is valid JSON"            jq -e . "$TEMPLATE"
expect_true "profile.sh defines render_profile"     bash -c '. "$1"; declare -F render_profile' _ "$PROFILE_SH"
expect_true "profile.sh defines profile_apply"      bash -c '. "$1"; declare -F profile_apply' _ "$PROFILE_SH"
expect_true "profile.sh defines profile_strip"      bash -c '. "$1"; declare -F profile_strip' _ "$PROFILE_SH"
expect_true "profile.sh defines profile_diff"       bash -c '. "$1"; declare -F profile_diff' _ "$PROFILE_SH"
expect_true "profile.sh defines detect_profile_state" bash -c '. "$1"; declare -F detect_profile_state' _ "$PROFILE_SH"

# The library is SOURCED on machines that may be missing coreutils entirely
# (a half-uninstalled box is the case doctor exists for). detect.sh's own header
# records the lesson; profile.sh inherits it.
expect_false "profile.sh calls no dirname/basename" \
  grep -qE '(^|[^a-z_])(dirname|basename)[[:space:]]' "$PROFILE_SH"

echo ""
echo "=== Group 2: the template is narrow — no broad grants, no unscoped rules ==="
#
# AC-6's own words: "briefs never emit broad grants". The point of shipping a
# profile at all is that a curated, enumerated set of rules replaces the reflex
# to widen permissions until the friction stops.

TPL_TEXT="$(cat "$TEMPLATE")"
ALLOW_JSON="$(jq -c '.permissions.allow' "$TEMPLATE" 2>/dev/null)"
ALLOW_N="$(jq '.permissions.allow | length' "$TEMPLATE" 2>/dev/null)"

expect_true "the template declares permissions.allow as an array" \
  jq -e '.permissions.allow | type == "array"' "$TEMPLATE"
expect_true "the template declares at least one rule" test "${ALLOW_N:-0}" -gt 0

expect_nomatch "no --dangerously-skip-permissions anywhere in the template" \
  "*dangerously-skip-permissions*" "$TPL_TEXT"
expect_nomatch "no bare Bash(*) grant"    '*"Bash(\*)"*'  "$TPL_TEXT"
expect_nomatch "no bare Bash(:*) grant"   '*"Bash(:\*)"*' "$TPL_TEXT"
expect_true "the template declares no deny list (allow-only profile)" \
  jq -e '.permissions | has("deny") | not' "$TEMPLATE"
expect_true "the template sets no defaultMode (it never widens the mode)" \
  jq -e '.permissions | has("defaultMode") | not' "$TEMPLATE"

# Every rule is Tool(pattern)-shaped, and no rule's pattern is a lone wildcard.
#
# TWO GRAMMARS, AND THE SECOND ONE HAS NO PARENTHESES TO CHECK. A Bash/Read rule
# is `Tool(pattern)`. An MCP permission is `mcp__<server>` or
# `mcp__<server>__<tool>` — the CLI's own spelling, which takes no pattern at
# all, so there is nothing for the first regex to match and a template carrying
# one would fail a check that only knows the parenthesised form. The two are
# judged separately rather than by loosening the first: an MCP rule is pinned to
# its own shape, so `mcp__` cannot become the hole through which an unshaped
# string enters the allow list.
# ONE backslash, not two: these reach jq through --arg, so they are regex source
# and never a jq string literal. The inline spelling above needed `\\(` because
# jq's own lexer ate one of them first.
RULE_SHAPE='^[A-Za-z_]+\(.+\)$'
MCP_SHAPE='^mcp__[A-Za-z0-9-]+(__[A-Za-z0-9-]+)?$'
BAD_SHAPE="$(jq -r --arg r "$RULE_SHAPE" --arg m "$MCP_SHAPE" \
  '.permissions.allow[] | select((test($r) or test($m)) | not)' "$TEMPLATE" 2>/dev/null)"
expect_eq "every rule is Tool(pattern)-shaped or an mcp__ server rule" "" "$BAD_SHAPE"
# Non-vacuous in both directions: the classifier must still reject a string that
# is neither, and must accept the MCP form it was widened for.
expect_eq "the shape check still rejects a bare unshaped string" "Bash" \
  "$(jq -rn --arg r "$RULE_SHAPE" --arg m "$MCP_SHAPE" '["Bash"] | .[] | select((test($r) or test($m)) | not)')"
expect_eq "the shape check accepts the mcp__ form" "" \
  "$(jq -rn --arg r "$RULE_SHAPE" --arg m "$MCP_SHAPE" '["mcp__pencil"] | .[] | select((test($r) or test($m)) | not)')"
BAD_WILD="$(jq -r '.permissions.allow[] | select(test("^[A-Za-z_]+\\(\\*?\\)$"))' "$TEMPLATE" 2>/dev/null)"
expect_eq "no rule grants a whole tool" "" "$BAD_WILD"

# F-S2 — THE ANCHORING WALL, and the reason it is a wall and not a fix.
#
# This profile is applied into the USER settings layer, which is machine-wide.
# A rule naming a RELATIVE path therefore fires in every repository on the
# machine, not only in bionic's: `Bash(bash tests/run.sh:*)` pre-approved the
# suite runner of any checkout that happened to have one — a repo cloned to
# review a PR, a colleague's tree. The two rules of that shape were moved out to
# bionic's own project-scope settings, where they belong by scope (Chris,
# 2026-08-17, F-S2 option 1). Moving them fixes the instance; this fixes the
# class, because nothing else stopped the next one being added.
#
# EVERY rule must fall in one of three anchored categories:
#   1. rooted at __BIONIC_PLUGIN_ROOT__ — an absolute path on this machine
#   2. scoped to bionic@bionic — the plugin's own plugin@marketplace pair
#   3. path-free, and enumerated BY LITERAL below
#
# Category 3 is pinned as an exact list rather than a predicate on purpose. It
# holds the two `:` marker rules (bash no-ops that authorise nothing and exist to
# bracket the block) and `claude plugin list`, which names no path in any
# repository and so cannot carry the F-S2 hazard. An exemption that could be
# EARNED by a predicate would be an exemption a future rule could earn by
# accident; this one has to be typed into this file, in front of whoever is
# adding it.
# The list is matched as PREFIXES so the begin marker's version suffix does not
# have to be restated here (Group 3 owns that pin); everything else is written
# whole.
# `mcp__pencil` joins the list at wave-06 S5 (AC-12) for the reason category 3
# exists: an MCP permission names a SERVER, not a path, so it cannot carry the
# F-S2 hazard of firing in a repository it was never meant for. It is typed in
# here, in front of whoever adds the next one, exactly as the paragraph above
# requires — and Group 5's MCP arm is the separate claim that it is EARNED.
ANCHOR_EXEMPT='Bash(: bionic-profile-begin version=
Bash(: bionic-profile-end)
Bash(claude plugin list:*)
mcp__pencil'

rule_is_anchored() {  # <rule>
  local r="$1" ex
  case "$r" in
    *"__BIONIC_PLUGIN_ROOT__"*) return 0 ;;
    *"bionic@bionic"*)          return 0 ;;
  esac
  while IFS= read -r ex; do
    [ -n "$ex" ] || continue
    case "$r" in "$ex"*) return 0 ;; esac
  done <<< "$ANCHOR_EXEMPT"
  return 1
}

UNANCHORED=""
while IFS= read -r rule; do
  [ -n "$rule" ] || continue
  rule_is_anchored "$rule" || UNANCHORED="${UNANCHORED} ${rule}"
done < <(jq -r '.permissions.allow[]' "$TEMPLATE" 2>/dev/null)
expect_eq "every template rule is anchored to the plugin root, to bionic@bionic, or is a pinned path-free rule" \
  "" "$UNANCHORED"

# The wall is non-vacuous in both directions. Forward: the exact shape F-S2
# removed must still be REJECTED by the classifier, so the class cannot come
# back by someone re-adding it.
expect_false "the wall rejects the shape F-S2 removed (it is not vacuous)" \
  rule_is_anchored "Bash(bash tests/run.sh:*)"
expect_false "and its farm-out spelling" \
  rule_is_anchored "Bash(FARM_OUT_ALLOW=1 bash tests/run.sh:*)"
# ...while an anchored rule is accepted, so the classifier is not simply saying
# no to everything.
expect_true "the wall accepts a plugin-root-anchored rule" \
  rule_is_anchored "Bash(bash __BIONIC_PLUGIN_ROOT__/scripts/doctor.sh:*)"
# Backward: every exemption names a rule actually IN the template, so the list
# cannot rot into a licence for rules nobody ships any more.
STALE_EXEMPT=""
while IFS= read -r ex; do
  [ -n "$ex" ] || continue
  grep -qF "$ex" "$TEMPLATE" || STALE_EXEMPT="${STALE_EXEMPT} ${ex}"
done <<< "$ANCHOR_EXEMPT"
expect_eq "every path-free exemption names a rule the template actually ships" "" "$STALE_EXEMPT"

# And the rules that moved are asserted GONE, not merely un-walled: the fix and
# the wall are separate claims and a wall cannot prove a deletion happened.
expect_nomatch "the unanchored suite-runner rule is out of the template" \
  '*Bash(bash tests/run.sh:\**' "$TPL_TEXT"
expect_nomatch "so is its farm-out spelling" \
  '*FARM_OUT_ALLOW=1 bash tests/run.sh*' "$TPL_TEXT"

echo ""
echo "=== Group 3: the version pin — one manifest is the truth (ADR-002) ==="

PLUGIN_VERSION="$(jq -r '.version // ""' "$PLUGIN_JSON" 2>/dev/null)"
TPL_VERSION="$(jq -r '.version // ""' "$TEMPLATE" 2>/dev/null)"
# The begin sentinel carries the version literally, so the applied block can be
# version-identified on a machine long after the template moved on.
SENTINEL_VERSION="$(jq -r '.permissions.allow[] | select(startswith("Bash(: bionic-profile-begin version="))' "$TEMPLATE" 2>/dev/null \
                    | sed -e 's/.*version=//' -e 's/)$//')"

expect_true "plugin.json carries a version"  test -n "$PLUGIN_VERSION"
expect_eq "template version == plugin.json version"          "$PLUGIN_VERSION" "$TPL_VERSION"
expect_eq "begin-sentinel version == plugin.json version"    "$PLUGIN_VERSION" "$SENTINEL_VERSION"

echo ""
echo "=== Group 4: the marker block brackets the rules, and is inert ==="

FIRST_RULE="$(jq -r '.permissions.allow[0]' "$TEMPLATE" 2>/dev/null)"
LAST_RULE="$(jq -r '.permissions.allow[-1]' "$TEMPLATE" 2>/dev/null)"
expect_match "the first allow entry is the begin sentinel" \
  'Bash(: bionic-profile-begin version=*)' "$FIRST_RULE"
expect_eq "the last allow entry is the end sentinel" \
  'Bash(: bionic-profile-end)' "$LAST_RULE"
# Inertness is the whole reason the markers are shaped as rules rather than as a
# foreign key the CLI would not recognise: `:` is bash's no-op builtin, and both
# sentinels are EXACT-match rules (no `:*` suffix), so neither can authorize a
# command with anything appended to it.
expect_nomatch "the begin sentinel is exact-match (carries no :* suffix)" \
  '*:\*)' "$FIRST_RULE"
expect_nomatch "the end sentinel is exact-match (carries no :* suffix)" \
  '*:\*)' "$LAST_RULE"
expect_eq "exactly one begin sentinel" "1" \
  "$(jq '[.permissions.allow[] | select(startswith("Bash(: bionic-profile-begin version="))] | length' "$TEMPLATE")"
expect_eq "exactly one end sentinel" "1" \
  "$(jq '[.permissions.allow[] | select(. == "Bash(: bionic-profile-end)")] | length' "$TEMPLATE")"

echo ""
echo "=== Group 5: the rule list is DERIVED, not hand-waved ==="
#
# The template is a rendering of what bionic's machinery actually invokes. Two
# derivations are pinned here so the template cannot drift away from them:
# hooks/hooks.json's own commands, and the payload scripts the command surface
# calls. A rule with no invoker behind it is an unearned grant; an invoker with
# no rule is the friction the profile exists to remove.

# (a) every distinct script named in hooks/hooks.json has a rule
HOOK_SCRIPTS="$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/hooks/[A-Za-z0-9._-]+\.sh' "$HOOKS_JSON" 2>/dev/null \
                | sed 's|.*/hooks/||' | sort -u)"
expect_true "hooks.json names at least one hook script" test -n "$HOOK_SCRIPTS"
MISSING_HOOK_RULES=""
while IFS= read -r hs; do
  [ -n "$hs" ] || continue
  grep -qF "__BIONIC_PLUGIN_ROOT__/hooks/${hs}" "$TEMPLATE" || MISSING_HOOK_RULES="${MISSING_HOOK_RULES} ${hs}"
done <<< "$HOOK_SCRIPTS"
expect_eq "every hooks.json script has a template rule" "" "$MISSING_HOOK_RULES"

# The paired negative: no rule for a hook script hooks.json does NOT name.
STRAY_HOOK_RULES=""
while IFS= read -r rule; do
  [ -n "$rule" ] || continue
  case "$rule" in
    *"__BIONIC_PLUGIN_ROOT__/hooks/"*)
      hs="${rule##*/hooks/}"; hs="${hs%%:*}"; hs="${hs%%)*}"
      case "$HOOK_SCRIPTS" in
        *"$hs"*) ;;
        *) STRAY_HOOK_RULES="${STRAY_HOOK_RULES} ${hs}" ;;
      esac
      ;;
  esac
done < <(jq -r '.permissions.allow[]' "$TEMPLATE" 2>/dev/null)
expect_eq "no hook rule without a hooks.json invoker" "" "$STRAY_HOOK_RULES"

# (b) the four payload scripts the wave's component boundaries name
for s in setup.sh doctor.sh remove.sh spawn-worktree.sh; do
  expect_true "the template covers scripts/${s}" \
    grep -qF "__BIONIC_PLUGIN_ROOT__/scripts/${s}" "$TEMPLATE"
done
# (c) WAS the suite runner CLAUDE.md makes every agent run. Removed 2026-08-17
# (F-S2, Chris's option 1): `bash tests/run.sh` is a relative path, and this
# profile lands in the machine-wide USER layer, so the rule pre-approved the
# suite runner of every repository on the machine. The two rules live in
# bionic's own project-scope settings now, where the scope matches the claim.
# Group 2's anchoring wall is this assertion's replacement, and it is the
# INVERSE: it asserts no rule of that shape is in the template at all.
# (d) plugin CLI operations, scoped to bionic's own plugin@marketplace pair
expect_true "the template covers claude plugin install, scoped to bionic@bionic" \
  grep -qF 'claude plugin install bionic@bionic' "$TEMPLATE"
expect_true "the template covers claude plugin uninstall, scoped to bionic@bionic" \
  grep -qF 'claude plugin uninstall bionic@bionic' "$TEMPLATE"
expect_false "no unscoped claude plugin install grant" \
  grep -qF '"Bash(claude plugin install:*)"' "$TEMPLATE"

# (e) the MCP rules, added at wave-06 S5 (AC-12). An MCP permission has no path
# and no command to derive it from, so the derivation it answers to is the
# dependency table: the server named by the rule must belong to a tool bionic
# itself offers to install. `mcp__pencil` is earned by the `@pencil.dev/cli`
# row — bionic offers that tool at setup, and the prompt its server raises is
# therefore bionic's own machinery asking, which is what AC-12 calls a gap to
# harvest. Drop the row from deps.sh and this arm turns red rather than leaving
# a grant standing with nothing behind it.
#
# The match is on the SERVER segment being a substring of some row's name, not
# on equality: an npm package name (`@pencil.dev/cli`) and the server it
# registers (`pencil`) are different strings by construction. Loose enough to
# admit a rule whose server is named after a row; strict enough that a rule for
# a server no row installs has nothing to point at.
MCP_RULES="$(jq -r '.permissions.allow[] | select(startswith("mcp__"))' "$TEMPLATE" 2>/dev/null)"
expect_true "the template carries at least one MCP rule (the arm is not vacuous)" \
  test -n "$MCP_RULES"
expect_true "the harvested pencil rule is in the template (AC-12)" \
  grep -qF '"mcp__pencil"' "$TEMPLATE"
DEP_NAMES="$(bash -c '. "$1"; dep_names' _ "${REPO}/payload/scripts/lib/deps.sh" 2>/dev/null)"
expect_true "the dependency table was readable (the arm is not vacuous)" test -n "$DEP_NAMES"
mcp_rule_earned() {  # <rule>
  local s="${1#mcp__}"; s="${s%%__*}"
  case "$DEP_NAMES" in *"$s"*) return 0 ;; *) return 1 ;; esac
}

UNEARNED_MCP=""
while IFS= read -r rule; do
  [ -n "$rule" ] || continue
  mcp_rule_earned "$rule" || UNEARNED_MCP="${UNEARNED_MCP} ${rule}"
done <<< "$MCP_RULES"
expect_eq "every MCP rule names a server a dependency-table row installs" "" "$UNEARNED_MCP"

# Both directions on the same classifier, so the arm above cannot be a function
# that says yes to everything.
expect_true  "the MCP derivation accepts the harvested pencil rule" mcp_rule_earned "mcp__pencil"
expect_false "the MCP derivation rejects a server no row installs"  mcp_rule_earned "mcp__unearned-server"

echo ""
echo "=== Group 6: render_profile — deterministic, total, and nothing else moved ==="

R1="$(prof_run -- render_profile "$TEMPLATE" "$FAKE_ROOT")"
R2="$(prof_run -- render_profile "$TEMPLATE" "$FAKE_ROOT")"
expect_eq "render is deterministic (same inputs -> byte-identical output)" "$R1" "$R2"
expect_true "the render is valid JSON" bash -c 'printf "%s" "$1" | jq -e . >/dev/null' _ "$R1"
expect_nomatch "no __BIONIC_PLUGIN_ROOT__ survives the render" '*__BIONIC_PLUGIN_ROOT__*' "$R1"
expect_match "the concrete plugin root appears in the render" "*${FAKE_ROOT}*" "$R1"

# NOTHING ELSE CHANGED. Substituting the token back must reproduce the template
# byte for byte — the strongest available statement of "token replaced, nothing
# else changed", and it fails for any render that reformats, reorders or drops.
UNRENDERED="${R1//${FAKE_ROOT}/__BIONIC_PLUGIN_ROOT__}"
expect_eq "un-substituting the render reproduces the template byte-exactly" \
  "$(cat "$TEMPLATE")" "$UNRENDERED"

# A different root renders differently — the paired positive to determinism.
R3="$(prof_run -- render_profile "$TEMPLATE" "$FAKE_ROOT_V2")"
expect_true "a different plugin root renders a different profile" test "$R1" != "$R3"
expect_match "the second root appears in its own render" "*${FAKE_ROOT_V2}*" "$R3"

expect_false "render_profile refuses a missing template" \
  bash -c '. "$1"; render_profile "$2" "$3"' _ "$PROFILE_SH" "$TMP/nope.json" "$FAKE_ROOT"
expect_false "render_profile refuses an empty plugin root" \
  bash -c '. "$1"; render_profile "$2" ""' _ "$PROFILE_SH" "$TEMPLATE"
expect_false "render_profile refuses a relative plugin root" \
  bash -c '. "$1"; render_profile "$2" "relative/path"' _ "$PROFILE_SH" "$TEMPLATE"

echo ""
echo "=== Group 7: profile_apply — the consent gate is the door, not a formality ==="

RENDERED="$TMP/rendered.json"
prof_run -- render_profile "$TEMPLATE" "$FAKE_ROOT" > "$RENDERED"

S_GATE="$TMP/s-gate.json"; cp "$SET_REAL" "$S_GATE"
BEFORE_GATE="$(cat "$S_GATE")"

expect_false "profile_apply refuses with no consent argument at all" \
  bash -c 'BIONIC_SETTINGS_FILE="$3" ; export BIONIC_SETTINGS_FILE; . "$1"; profile_apply "$2"' \
  _ "$PROFILE_SH" "$RENDERED" "$S_GATE"
expect_eq "the refused call left the settings file byte-identical" \
  "$BEFORE_GATE" "$(cat "$S_GATE")"

expect_false "profile_apply refuses a wrong consent token" \
  bash -c 'BIONIC_SETTINGS_FILE="$3"; export BIONIC_SETTINGS_FILE; . "$1"; profile_apply "$2" --yes' \
  _ "$PROFILE_SH" "$RENDERED" "$S_GATE"
expect_eq "the wrong-token call left the settings file byte-identical" \
  "$BEFORE_GATE" "$(cat "$S_GATE")"

expect_false "profile_apply refuses a missing rendered file" \
  bash -c 'BIONIC_SETTINGS_FILE="$3"; export BIONIC_SETTINGS_FILE; . "$1"; profile_apply "$TMP/nope.json" --consented' \
  _ "$PROFILE_SH" "$RENDERED" "$S_GATE"

# An UNRENDERED template must never be applied: a permission rule carrying the
# literal token matches nothing (probe-identity-match.md), so applying one would
# quietly install a profile that grants nothing at all.
expect_false "profile_apply refuses a payload that still carries the token" \
  bash -c 'BIONIC_SETTINGS_FILE="$3"; export BIONIC_SETTINGS_FILE; . "$1"; profile_apply "$2" --consented' \
  _ "$PROFILE_SH" "$TEMPLATE" "$S_GATE"
expect_eq "the token-carrying payload left the settings file byte-identical" \
  "$BEFORE_GATE" "$(cat "$S_GATE")"

# The positive arm: with consent, it applies.
S_OK="$TMP/s-ok.json"; cp "$SET_REAL" "$S_OK"
expect_true "profile_apply applies with the consent token" \
  bash -c 'BIONIC_SETTINGS_FILE="$3"; export BIONIC_SETTINGS_FILE; . "$1"; profile_apply "$2" --consented' \
  _ "$PROFILE_SH" "$RENDERED" "$S_OK"
expect_true "the applied file is still valid JSON" jq -e . "$S_OK"
expect_eq "the pre-existing rule survived the apply" "true" \
  "$(jq '.permissions.allow | index("mcp__notion") != null' "$S_OK" 2>/dev/null)"
expect_eq "every template rule is now in the settings allow list" "true" \
  "$(jq -s '(.[0].permissions.allow - .[1].permissions.allow) | length == 0' "$RENDERED" "$S_OK" 2>/dev/null)"
expect_eq "unrelated settings keys are untouched" \
  "$(jq -S 'del(.permissions)' "$SET_REAL")" "$(jq -S 'del(.permissions)' "$S_OK")"

echo ""
echo "=== Group 8: apply/strip round-trip is byte-exact ==="
#
# Byte-exact, not merely equivalent. The user's settings file is a document they
# own; a teardown that returns it semantically-equal-but-reformatted has still
# edited every line of a file bionic was only ever a guest in.

roundtrip() {  # <fixture> -> "same" | "differs"
  local fixture="$1" work="$TMP/rt-$RANDOM.json"
  cp "$fixture" "$work"
  prof_run BIONIC_SETTINGS_FILE="$work" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
  prof_run BIONIC_SETTINGS_FILE="$work" -- profile_strip >/dev/null 2>&1
  if diff -q "$fixture" "$work" >/dev/null 2>&1; then echo same; else echo differs; fi
}

expect_eq "round trip on a real-shaped settings file (no trailing newline)" "same" "$(roundtrip "$SET_REAL")"
expect_eq "round trip on a settings file WITH a trailing newline"           "same" "$(roundtrip "$SET_REAL_NL")"
expect_eq "round trip on a file with no permissions key at all"             "same" "$(roundtrip "$SET_BARE")"
expect_eq "round trip on a file carrying unrelated accretion"               "same" "$(roundtrip "$SET_ACCRETED")"

# Applying twice must not stack two blocks — setup is idempotent (AC-2), and an
# apply that appended unconditionally would grow the file on every run.
S_TWICE="$TMP/s-twice.json"; cp "$SET_REAL" "$S_TWICE"
prof_run BIONIC_SETTINGS_FILE="$S_TWICE" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
ONCE="$(cat "$S_TWICE")"
prof_run BIONIC_SETTINGS_FILE="$S_TWICE" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
expect_eq "applying twice is idempotent (byte-identical to applying once)" "$ONCE" "$(cat "$S_TWICE")"
expect_eq "still exactly one begin sentinel after a second apply" "1" \
  "$(jq '[.permissions.allow[] | select(startswith("Bash(: bionic-profile-begin version="))] | length' "$S_TWICE")"

# Re-rendering at a NEW root and applying must replace, not accumulate.
RENDERED_V2="$TMP/rendered-v2.json"
prof_run -- render_profile "$TEMPLATE" "$FAKE_ROOT_V2" > "$RENDERED_V2"
prof_run BIONIC_SETTINGS_FILE="$S_TWICE" -- profile_apply "$RENDERED_V2" --consented >/dev/null 2>&1
expect_eq "re-applying at a new root leaves one block" "1" \
  "$(jq '[.permissions.allow[] | select(startswith("Bash(: bionic-profile-begin version="))] | length' "$S_TWICE")"
expect_eq "the new root is the one now applied" "true" \
  "$(jq --arg r "$FAKE_ROOT_V2" '[.permissions.allow[] | select(contains($r))] | length > 0' "$S_TWICE")"
expect_eq "no rule from the old root survives" "true" \
  "$(jq --arg r "$FAKE_ROOT" '[.permissions.allow[] | select(contains($r + "/"))] | length == 0' "$S_TWICE")"
expect_eq "the machine's own rule survived both applies" "true" \
  "$(jq '.permissions.allow | index("mcp__notion") != null' "$S_TWICE")"

echo ""
echo "=== Group 9: profile_strip — safe on a machine that never applied ==="

S_NEVER="$TMP/s-never.json"; cp "$SET_REAL" "$S_NEVER"
expect_true "profile_strip exits 0 with nothing applied" \
  bash -c 'BIONIC_SETTINGS_FILE="$2"; export BIONIC_SETTINGS_FILE; . "$1"; profile_strip' \
  _ "$PROFILE_SH" "$S_NEVER"
expect_eq "strip-without-apply left the file byte-identical" "$(cat "$SET_REAL")" "$(cat "$S_NEVER")"

expect_true "profile_strip exits 0 when the settings file does not exist" \
  bash -c 'BIONIC_SETTINGS_FILE="$2"; export BIONIC_SETTINGS_FILE; . "$1"; profile_strip' \
  _ "$PROFILE_SH" "$TMP/absent-settings.json"
expect_false "profile_strip did not create a settings file" test -e "$TMP/absent-settings.json"

# Strip removes EXACTLY the block: accretion added after the apply survives.
S_MIX="$TMP/s-mix.json"; cp "$SET_ACCRETED" "$S_MIX"
prof_run BIONIC_SETTINGS_FILE="$S_MIX" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
MIX_AFTER_APPLY="$(jq -c '.permissions.allow' "$S_MIX")"
# a rule the machine adds AFTER bionic's block — the hardest case for scoping
jq '.permissions.allow += ["Bash(docker ps:*)"]' "$S_MIX" > "$S_MIX.t" && mv "$S_MIX.t" "$S_MIX"
prof_run BIONIC_SETTINGS_FILE="$S_MIX" -- profile_strip >/dev/null 2>&1
expect_eq "strip kept every pre-existing rule" "true" \
  "$(jq -s '(.[0].permissions.allow - .[1].permissions.allow) | length == 0' "$SET_ACCRETED" "$S_MIX" 2>/dev/null)"
expect_eq "strip kept the rule added after the block" "true" \
  "$(jq '.permissions.allow | index("Bash(docker ps:*)") != null' "$S_MIX" 2>/dev/null)"
expect_eq "strip removed every bionic rule" "0" \
  "$(jq --arg r "$FAKE_ROOT" '[.permissions.allow[] | select(contains($r))] | length' "$S_MIX" 2>/dev/null)"
expect_true "the mixed fixture actually had a block to remove" \
  bash -c 'case "$1" in *bionic-profile-begin*) exit 0 ;; *) exit 1 ;; esac' _ "$MIX_AFTER_APPLY"

echo ""
echo "=== Group 10: profile_diff — three verdicts and an accretion count ==="

diff_verdict()   { prof_run BIONIC_SETTINGS_FILE="$1" -- profile_diff "$TEMPLATE" "$2" | sed -n 's/^profile:diff verdict=//p'; }
diff_accretion() { prof_run BIONIC_SETTINGS_FILE="$1" -- profile_diff "$TEMPLATE" "$2" | sed -n 's/^profile:diff accretion=//p'; }

# absent — nothing applied
S_ABSENT="$TMP/d-absent.json"; cp "$SET_REAL" "$S_ABSENT"
expect_eq "verdict absent when no block is applied" "absent" "$(diff_verdict "$S_ABSENT" "$FAKE_ROOT")"
expect_eq "accretion counts the machine's own rules when nothing is applied" "1" \
  "$(diff_accretion "$S_ABSENT" "$FAKE_ROOT")"

# identical — applied from the same template at the same root
S_IDENT="$TMP/d-ident.json"; cp "$SET_REAL" "$S_IDENT"
prof_run BIONIC_SETTINGS_FILE="$S_IDENT" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
expect_eq "verdict identical when the applied block re-renders to itself" "identical" \
  "$(diff_verdict "$S_IDENT" "$FAKE_ROOT")"
expect_eq "accretion counts only rules outside the block" "1" \
  "$(diff_accretion "$S_IDENT" "$FAKE_ROOT")"

# stale — same block, but the plugin has moved to a new root (the auto-update case)
expect_eq "verdict stale when the plugin root has moved (post-update staleness)" "stale" \
  "$(diff_verdict "$S_IDENT" "$FAKE_ROOT_V2")"

# stale — the machine edited a rule inside the block
S_EDITED="$TMP/d-edited.json"; cp "$S_IDENT" "$S_EDITED"
jq '.permissions.allow = (.permissions.allow | map(if test("scripts/doctor\\.sh") then "Bash(bash /tmp/hijack.sh:*)" else . end))' \
  "$S_EDITED" > "$S_EDITED.t" && mv "$S_EDITED.t" "$S_EDITED"
expect_eq "verdict stale when a rule inside the block was edited" "stale" \
  "$(diff_verdict "$S_EDITED" "$FAKE_ROOT")"

# accretion counting scales with real accretion
S_ACC="$TMP/d-acc.json"; cp "$SET_ACCRETED" "$S_ACC"
prof_run BIONIC_SETTINGS_FILE="$S_ACC" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
expect_eq "accretion counts three pre-existing rules" "3" "$(diff_accretion "$S_ACC" "$FAKE_ROOT")"
jq '.permissions.allow += ["Bash(docker ps:*)", "Read(/etc/hosts)"]' "$S_ACC" > "$S_ACC.t" && mv "$S_ACC.t" "$S_ACC"
expect_eq "accretion counts five after two more rules accrete" "5" "$(diff_accretion "$S_ACC" "$FAKE_ROOT")"
expect_eq "the block is still identical under accretion" "identical" "$(diff_verdict "$S_ACC" "$FAKE_ROOT")"

# a machine with no settings file at all
expect_eq "verdict absent when there is no settings file" "absent" \
  "$(diff_verdict "$TMP/never-existed.json" "$FAKE_ROOT")"
expect_eq "accretion is 0 when there is no settings file" "0" \
  "$(diff_accretion "$TMP/never-existed.json" "$FAKE_ROOT")"

echo ""
echo "=== Group 11: detect_profile_state — the fact line, both arms ==="
#
# S1-10, verbatim from record/epic-17-w3/s1-report.md: detect.sh's
# detect_half_uninstalled covers only the three facts detect.sh owns, and "the
# permission marker block is S5's fact and must join this disjunction there".
# This is the function that carries it — one line, detect.sh's conventions, so
# a joiner reads `applied=` the same way it reads `present=`.

state_of() { prof_run BIONIC_SETTINGS_FILE="$1" BIONIC_PLUGIN_ROOT="$2" -- detect_profile_state; }

ST_ABSENT="$(state_of "$S_ABSENT" "$FAKE_ROOT")"
expect_eq "state line, nothing applied" \
  "profile: applied=no version=none stale=no accretion=1" "$ST_ABSENT"

ST_APPLIED="$(state_of "$S_IDENT" "$FAKE_ROOT")"
expect_eq "state line, applied and current" \
  "profile: applied=yes version=${PLUGIN_VERSION} stale=no accretion=1" "$ST_APPLIED"

ST_STALE="$(state_of "$S_IDENT" "$FAKE_ROOT_V2")"
expect_eq "state line, applied but stale after a plugin update" \
  "profile: applied=yes version=${PLUGIN_VERSION} stale=yes accretion=1" "$ST_STALE"

expect_eq "detect_profile_state prints exactly one line" "1" "$(printf '%s\n' "$ST_APPLIED" | grep -c .)"
expect_true "detect_profile_state exits 0 with nothing applied" \
  bash -c 'BIONIC_SETTINGS_FILE="$2"; export BIONIC_SETTINGS_FILE; . "$1"; detect_profile_state >/dev/null' \
  _ "$PROFILE_SH" "$S_ABSENT"
expect_true "detect_profile_state exits 0 with no settings file at all" \
  bash -c 'BIONIC_SETTINGS_FILE="$2"; export BIONIC_SETTINGS_FILE; . "$1"; detect_profile_state >/dev/null' \
  _ "$PROFILE_SH" "$TMP/never-existed.json"

# The version is read from the APPLIED block, not from the shipped template —
# which is the whole reason the sentinel carries it. A machine still holding an
# older block must report the older number.
S_OLDVER="$TMP/s-oldver.json"; cp "$S_IDENT" "$S_OLDVER"
jq '.permissions.allow = (.permissions.allow | map(sub("bionic-profile-begin version=[0-9.]+"; "bionic-profile-begin version=0.0.9")))' \
  "$S_OLDVER" > "$S_OLDVER.t" && mv "$S_OLDVER.t" "$S_OLDVER"
expect_match "the state line reports the APPLIED version, not the shipped one" \
  "profile: applied=yes version=0.0.9 *" "$(state_of "$S_OLDVER" "$FAKE_ROOT")"

echo ""
echo "=== Group 12: honest degradation when jq is absent ==="
#
# jq is itself a row in the dependency table, so a machine can legitimately lack
# it. S1-3's rule applies unchanged: a confident wrong answer is worse than
# `unknown`, and the one direction this must never fail in is reporting a dirty
# machine as clean.

ST_NOJQ="$(prof_run_nojq BIONIC_SETTINGS_FILE="$S_IDENT" BIONIC_PLUGIN_ROOT="$FAKE_ROOT" -- detect_profile_state)"
expect_match "without jq the state line still reports applied=yes" "profile: applied=yes *" "$ST_NOJQ"
expect_match "without jq the applied version is still read" "*version=${PLUGIN_VERSION} *" "$ST_NOJQ"
expect_match "without jq staleness is unknown, never a confident no" "*stale=unknown*" "$ST_NOJQ"
expect_match "without jq accretion is unknown, never a confident 0" "*accretion=unknown" "$ST_NOJQ"
expect_eq "without jq the state line is still exactly one line" "1" "$(printf '%s\n' "$ST_NOJQ" | grep -c .)"

ST_NOJQ_ABS="$(prof_run_nojq BIONIC_SETTINGS_FILE="$S_ABSENT" BIONIC_PLUGIN_ROOT="$FAKE_ROOT" -- detect_profile_state)"
expect_match "without jq an unapplied machine still reports applied=no" "profile: applied=no version=none *" "$ST_NOJQ_ABS"

# Mutation is the one thing that must NOT degrade: an apply that cannot parse
# the file it is rewriting would corrupt it.
S_NOJQ="$TMP/s-nojq.json"; cp "$SET_REAL" "$S_NOJQ"
expect_false "profile_apply refuses outright when jq is absent" \
  env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_SETTINGS_FILE="$S_NOJQ" \
    bash -c '. "$1"; profile_apply "$2" --consented' _ "$PROFILE_SH" "$RENDERED"
expect_eq "the jq-less refusal left the settings file byte-identical" "$(cat "$SET_REAL")" "$(cat "$S_NOJQ")"
# render is pure text substitution and must work with nothing but bash.
R_NOJQ="$(prof_run_nojq -- render_profile "$TEMPLATE" "$FAKE_ROOT")"
expect_eq "render_profile needs no jq at all" "$R1" "$R_NOJQ"

echo ""
echo "=== Group 13: the read-only functions mutate nothing ==="

FP_DIR="$TMP/fp"; mkdir -p "$FP_DIR"
cp "$SET_ACCRETED" "$FP_DIR/settings.json"
fingerprint() { find "$FP_DIR" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $5, $9}' | sort; }
FP_BEFORE="$(fingerprint)"
prof_run BIONIC_SETTINGS_FILE="$FP_DIR/settings.json" -- profile_diff "$TEMPLATE" "$FAKE_ROOT" >/dev/null 2>&1
prof_run BIONIC_SETTINGS_FILE="$FP_DIR/settings.json" BIONIC_PLUGIN_ROOT="$FAKE_ROOT" -- detect_profile_state >/dev/null 2>&1
prof_run BIONIC_SETTINGS_FILE="$FP_DIR/settings.json" -- render_profile "$TEMPLATE" "$FAKE_ROOT" >/dev/null 2>&1
expect_eq "diff + detect + render leave the settings file byte-identical" "$FP_BEFORE" "$(fingerprint)"
expect_true "and none of them left a temp file behind" \
  bash -c '[ "$(ls -1 "$1" | wc -l | tr -d " ")" = "1" ]' _ "$FP_DIR"

echo ""
echo "=== Group 14: the write preserves the settings file's own mode ==="
#
# `mv` replaces the inode, so a tmp+mv writer hands the file whatever the
# umask says rather than the mode it had. ~/.claude/settings.json routinely
# carries an `env` block with tokens, so a machine that chose 0600 for it must
# still have 0600 after /bionic:setup applies the profile — silently widening
# it to 0644 is a machine side effect no other group here measures.
#
# Both mutating paths are asserted: apply and strip reach _profile_write
# independently, and a fix applied to one call site would not cover the other.

file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

S_MODE="$TMP/s-mode.json"; cp "$SET_REAL" "$S_MODE"; chmod 600 "$S_MODE"
expect_eq "the fixture really starts at 0600 (the arm is not vacuous)" "600" "$(file_mode "$S_MODE")"
prof_run BIONIC_SETTINGS_FILE="$S_MODE" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
expect_eq "profile_apply leaves a 0600 settings file at 0600" "600" "$(file_mode "$S_MODE")"
prof_run BIONIC_SETTINGS_FILE="$S_MODE" -- profile_strip >/dev/null 2>&1
expect_eq "profile_strip leaves it at 0600 too" "600" "$(file_mode "$S_MODE")"

# The other direction, so neither arm can pass by hard-coding one mode: a file
# the machine deliberately left world-readable keeps THAT mode, and a writer
# that narrowed every file to 0600 would fail here.
S_MODE_644="$TMP/s-mode-644.json"; cp "$SET_REAL" "$S_MODE_644"; chmod 644 "$S_MODE_644"
prof_run BIONIC_SETTINGS_FILE="$S_MODE_644" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
expect_eq "a 0644 settings file is not narrowed either" "644" "$(file_mode "$S_MODE_644")"

echo ""
echo "=== Group 14b: the mode is right AT the rename, not repaired after it (R-1) ==="
#
# Group 14 measures the mode when the dust settles. That is not the whole claim.
# A writer that renames a 0644 tmp into place and then chmods it back to 0600
# passes every assertion above while doing two things the finding above forbids:
#
#   (a) the tmp file — a PREDICTABLE name, "<settings>.bionic.tmp", in a
#       directory the user does not necessarily own exclusively — carries the
#       full settings content, tokens included, at the umask's mode for the
#       whole span between its creation and the rename; and
#   (b) if the process dies in the window between `mv` and `chmod`, the widening
#       is not a window at all, it is PERMANENT — the exact defect Group 14 was
#       written to close.
#
# So the property is not "the mode is correct afterwards", it is "the inode the
# rename PUBLISHES is already correct, and no repair is owed". Both arms below
# measure that instant. Neither stubs the value under test: the writer is the
# shipped `_profile_write`, doing its real work on a real file. The shim shadows
# only the two coreutils it calls, and only to observe and to stop the clock.

WRITE_SHIM="$TMP/write-instant-shim.sh"
cat > "$WRITE_SHIM" <<'SHIM'
# Shadows `mv` and `chmod` in the writer's OWN shell (both are called unqualified
# from the function body, so a shell function intercepts them).
#
# `mv` records the mode of its SOURCE — the tmp file, which is the inode about to
# become settings.json — and then does the real rename. From that moment the
# process is declared DEAD: every later `chmod` returns success without doing
# anything, which is what a crash immediately after the rename looks like from
# the filesystem's side. The kill is triggered by the rename EVENT, not by the
# chmod's target, so it cannot be tuned to spare one writer and not another.
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

# The same controlled environment as prof_run, with the shim sourced AFTER the
# library so its definitions win.
prof_run_shimmed() {  # <env-assignments...> -- <function> [args]
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -i HOME="$TMP/home" PATH="$BASE_BIN" "${envs[@]}" \
    bash -c '. "$1"; . "$2"; shift 2; "$@"' _ "$PROFILE_SH" "$WRITE_SHIM" "$@" 2>&1
}

S_INST="$TMP/s-instant.json"; cp "$SET_REAL" "$S_INST"; chmod 600 "$S_INST"
MODE_LOG="$TMP/instant-mode.log"; : > "$MODE_LOG"
expect_eq "instant arm fixture: settings.json really starts at 0600" "600" "$(file_mode "$S_INST")"

prof_run_shimmed BIONIC_SETTINGS_FILE="$S_INST" BIONIC_TEST_MODE_LOG="$MODE_LOG" \
  -- profile_apply "$RENDERED" --consented >/dev/null 2>&1

# The shim is only worth its lines if it actually ran — an arm that silently
# never reached `mv` would pass both assertions below by measuring nothing.
expect_true "instant arm: the shimmed rename really was reached (the arm is not vacuous)" \
  test -s "$MODE_LOG"

# (a) The tmp carried the settings content at the captured mode, not the umask's.
expect_eq "the tmp file already wears the settings file's mode when mv renames it" \
  "600" "$(head -1 "$MODE_LOG" | tr -d ' ')"

# (b) The rename published a correct inode, so a death right after it costs
# nothing. Every chmod after the rename was swallowed by the shim.
expect_eq "a process that dies the instant mv lands still leaves settings.json at 0600" \
  "600" "$(file_mode "$S_INST")"

# Both directions again, so neither arm can pass by hard-coding 600: the tmp for
# a 0644 file must be 0644 at the rename, not narrowed to 077's 0600.
S_INST_644="$TMP/s-instant-644.json"; cp "$SET_REAL" "$S_INST_644"; chmod 644 "$S_INST_644"
MODE_LOG_644="$TMP/instant-mode-644.log"; : > "$MODE_LOG_644"
prof_run_shimmed BIONIC_SETTINGS_FILE="$S_INST_644" BIONIC_TEST_MODE_LOG="$MODE_LOG_644" \
  -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
expect_eq "the tmp for a 0644 settings file is 0644 at the rename, not narrowed" \
  "644" "$(head -1 "$MODE_LOG_644" | tr -d ' ')"
expect_eq "and dying right after that rename leaves it at 0644" \
  "644" "$(file_mode "$S_INST_644")"

# The strip path reaches the writer independently of apply, and a fix applied to
# one call site would not cover the other — Group 14 makes that argument for the
# settled mode, and it holds identically for the instant.
S_INST_STRIP="$TMP/s-instant-strip.json"; cp "$SET_REAL" "$S_INST_STRIP"
prof_run BIONIC_SETTINGS_FILE="$S_INST_STRIP" -- profile_apply "$RENDERED" --consented >/dev/null 2>&1
chmod 600 "$S_INST_STRIP"
MODE_LOG_STRIP="$TMP/instant-mode-strip.log"; : > "$MODE_LOG_STRIP"
prof_run_shimmed BIONIC_SETTINGS_FILE="$S_INST_STRIP" BIONIC_TEST_MODE_LOG="$MODE_LOG_STRIP" \
  -- profile_strip >/dev/null 2>&1
expect_true "strip instant arm: the shimmed rename was reached" test -s "$MODE_LOG_STRIP"
expect_eq "profile_strip's tmp also wears 0600 at the rename" \
  "600" "$(head -1 "$MODE_LOG_STRIP" | tr -d ' ')"
expect_eq "and a death right after profile_strip's rename leaves 0600" \
  "600" "$(file_mode "$S_INST_STRIP")"

echo ""
echo "=== Group 15: mutation and restore — these assertions can go red ==="
#
# Each arm doctors a COPY, re-runs the assertion against the copy, and records
# that the doctored build failed. The production files are never touched.

MUT="$TMP/mut"; mkdir -p "$MUT"

# Mutation 1 — break the render substitution. A build that emits the template
# unchanged must fail the token check, or that check proves nothing.
M1="$MUT/profile-nosubst.sh"
sed 's|//__BIONIC_PLUGIN_ROOT__/|//__BIONIC_PLUGIN_ROOT_DISABLED__/|' "$PROFILE_SH" > "$M1"
M1_OUT="$(prof_run_with "$M1" -- render_profile "$TEMPLATE" "$FAKE_ROOT")"
expect_true "MUTATION 1: the doctored build really is a different file" \
  bash -c '! diff -q "$1" "$2" >/dev/null' _ "$PROFILE_SH" "$M1"
expect_match "MUTATION 1: a build with no substitution leaves the token in place (assertion discriminates)" \
  '*__BIONIC_PLUGIN_ROOT__*' "$M1_OUT"

# Mutation 2 — break marker scoping by one element. Renaming the sentinel on
# BOTH sides would only produce a differently-named but self-consistent build,
# which is why this arm doctors the strip span alone: an end index that stops
# one short leaves the end sentinel behind, and the round trip must catch it.
M2="$MUT/profile-badmarker.sh"
sed 's|\$a\[0:\$b\] + \$a\[\$e+1:\]|$a[0:$b] + $a[$e:]|' "$PROFILE_SH" > "$M2"
M2_WORK="$TMP/m2.json"; cp "$SET_REAL" "$M2_WORK"
env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_SETTINGS_FILE="$M2_WORK" \
  bash -c '. "$1"; profile_apply "$2" --consented' _ "$M2" "$RENDERED" >/dev/null 2>&1
env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_SETTINGS_FILE="$M2_WORK" \
  bash -c '. "$1"; profile_strip' _ "$M2" >/dev/null 2>&1
expect_true "MUTATION 2: the doctored build really is a different file" \
  bash -c '! diff -q "$1" "$2" >/dev/null' _ "$PROFILE_SH" "$M2"
expect_true "MUTATION 2: a build with a mis-scoped end marker fails the round trip (assertion discriminates)" \
  bash -c '! diff -q "$1" "$2" >/dev/null' _ "$SET_REAL" "$M2_WORK"

# Mutation 3 — desync the template version from plugin.json. The pin must catch
# it; a pin that reads the same file twice would not.
M3="$MUT/profile.template.json"
jq '.version = "9.9.9"' "$TEMPLATE" > "$M3"
M3_VER="$(jq -r '.version' "$M3")"
expect_true "MUTATION 3: a desynced template version fails the pin (assertion discriminates)" \
  bash -c '[ "$1" != "$2" ]' _ "$M3_VER" "$PLUGIN_VERSION"

# Mutation 4 — strip that removes the whole allow array. Marker scoping means
# "exactly what apply added"; a greedier strip must fail the accretion survival
# assertion.
M4="$MUT/profile-greedy.sh"
sed 's|\$a\[0:\$b\] + \$a\[\$e+1:\]|[]|' "$PROFILE_SH" > "$M4"
M4_WORK="$TMP/m4.json"; cp "$SET_ACCRETED" "$M4_WORK"
env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_SETTINGS_FILE="$M4_WORK" \
  bash -c '. "$1"; profile_apply "$2" --consented' _ "$M4" "$RENDERED" >/dev/null 2>&1
env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_SETTINGS_FILE="$M4_WORK" \
  bash -c '. "$1"; profile_strip' _ "$M4" >/dev/null 2>&1
M4_SURVIVORS="$(jq -r '[.permissions.allow[]?] | length' "$M4_WORK" 2>/dev/null)"
expect_true "MUTATION 4: the doctored build really is a different file" \
  bash -c '! diff -q "$1" "$2" >/dev/null' _ "$PROFILE_SH" "$M4"
expect_true "MUTATION 4: a greedy strip loses the machine's own rules (assertion discriminates)" \
  bash -c '[ "${1:-0}" != "3" ]' _ "$M4_SURVIVORS"

echo ""
echo "=== Group 16: the suite is registered in tests/run.sh by name ==="
#
# tests/*.test.sh is NOT globbed by the runner — an unregistered suite is a
# silent false green (tests/run.sh's own header records the last time that
# happened).

expect_true "tests/run.sh names profile.test.sh" \
  grep -q 'run "profile.test.sh" bash tests/profile.test.sh' "${REPO}/tests/run.sh"
expect_true "version-ssot.test.sh carries the template version pin" \
  grep -q 'profile.template.json' "${REPO}/tests/version-ssot.test.sh"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
