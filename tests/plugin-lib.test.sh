#!/bin/bash
# PLUGIN LIB — epic-17 wave-03 slice S1 (spec AC-8, AC-3, AC-5).
#
# WHAT THIS SUITE OWNS. The two payload libraries that every later command
# consumes:
#
#   payload/scripts/lib/deps.sh    the dependency SSoT table + per-dep functions
#   payload/scripts/lib/detect.sh  the machine-fact functions (read-only)
#
# WHY THEY ARE PINNED HERE AND NOT IN A COMMAND SUITE. The ownership table
# (wave-03 spec §Design) makes deps.sh the single owner of the dependency set
# and detect.sh the single owner of machine facts; plugin.json and
# marketplace.json are RENDERINGS of the table's rows (the `core` rows and the
# `native`-kind rows respectively, since wave-06 S3). A rendering can only be
# pinned against a table whose own shape is already proven, so the table's
# shape is proven first, here, and the two manifest-agreement pins land on top
# of it (slice S3).
#
# HERMETIC — AND THE MEANING OF THAT WORD HERE. No network, no `claude` CLI, no
# live ~/.claude, no brew/npm/uv. Every fact-reading function is driven against
# a FIXTURE root planted in a temp dir and handed over by env var; every
# presence probe is driven against a FIXTURE PATH holding recorder stubs. The
# stubs are not a seam that substitutes the value under test: they are the
# real `command -v` / `npm list` / `claude` lookups, resolved against a
# directory this suite controls. install_dep's mutation therefore reaches a
# real execution, and its consent gate is proven by whether the recorder file
# appears — not by a dry-run flag the production path would never set.
#
# BOTH ARMS, ALWAYS. Every detect function is asserted present AND absent. An
# absence-only readback proves nothing: a function that always prints
# `present=no` would pass it.
#
# FIXTURE FIDELITY. Version strings and JSON shapes are copied from real
# command output captured on this machine (2026-08-17); the capture command is
# quoted in a comment beside each fixture.
#
# Usage: bash tests/plugin-lib.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
DEPS_SH="${REPO}/payload/scripts/lib/deps.sh"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"
# profile.sh is tests/profile.test.sh's subject; it is named here only for the
# one arm that needs doctor's load-out — both libraries sourced together — to
# reach detect_half_uninstalled's fourth term (Group 14, R-2).
PROFILE_SH="${REPO}/payload/scripts/lib/profile.sh"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${REPO}/.claude-plugin/marketplace.json"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_false() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then no "$label" "expected non-zero exit"; else ok "$label"; fi; }
# Pattern match without a pipe: `printf | grep -q` is a SIGPIPE race under
# pipefail (tests/assert-helper-race.test.sh pins that lesson).
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "'$actual' does not match '$pattern'"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "'$actual' unexpectedly matches '$pattern'"; else ok "$label"; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# A recorder stub: an executable that appends its own argv to $TMP/calls.log
# and exits 0. Used both as a presence probe target (`command -v rg`) and as
# the proof that install_dep did or did not reach a mutation.
make_stub() {  # <bindir> <name> [exit-code]
  local bindir="$1" name="$2" rc="${3:-0}"
  mkdir -p "$bindir"
  cat > "${bindir}/${name}" <<STUB
#!/bin/bash
echo "${name} \$*" >> "\$BIONIC_TEST_CALLS"
exit ${rc}
STUB
  chmod +x "${bindir}/${name}"
}

# A bin dir carrying only what a hermetic run legitimately needs. PATH is
# replaced outright (not prefixed) so a real brew/npm on this machine can
# never be reached by accident.
BASE_BIN="$TMP/base-bin"
mkdir -p "$BASE_BIN"
for real in bash sh env cat grep sed awk mkdir rm cp mv chmod ls dirname basename tr head tail sort uniq wc jq python3; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${BASE_BIN}/${real}" 2>/dev/null
done

CALLS="$TMP/calls.log"; : > "$CALLS"

# lib_run <lib> <env-assignments...> -- <function> [args]
# Runs one library function in a fresh bash with a controlled environment.
lib_run() {
  local lib="$1"; shift
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift  # drop --
  env -i \
    HOME="$TMP/home" \
    PATH="$BASE_BIN" \
    BIONIC_TEST_CALLS="$CALLS" \
    "${envs[@]}" \
    bash -c '. "$1"; shift; "$@"' _ "$lib" "$@" 2>&1
}

deps_run()   { lib_run "$DEPS_SH" "$@"; }
detect_run() { lib_run "$DETECT_SH" "$@"; }

mkdir -p "$TMP/home"

echo "=== Group 1: the library files exist and source cleanly ==="

expect_true "deps.sh exists" test -f "$DEPS_SH"
expect_true "detect.sh exists" test -f "$DETECT_SH"
expect_true "deps.sh sources without error" bash -c '. "$1"' _ "$DEPS_SH"
expect_true "detect.sh sources without error" bash -c '. "$1"' _ "$DETECT_SH"
expect_true "deps.sh passes bash -n" bash -n "$DEPS_SH"
expect_true "detect.sh passes bash -n" bash -n "$DETECT_SH"

echo ""
echo "=== Group 2: table parse + field access ==="

NAMES="$(deps_run -- dep_names)"
NAME_COUNT="$(printf '%s\n' "$NAMES" | grep -c .)"
expect_true "dep_names returns at least 20 rows (got ${NAME_COUNT})" test "$NAME_COUNT" -ge 20
expect_true "dep_names has no duplicates" \
  bash -c 'test "$(printf "%s\n" "$1" | sort | uniq -d | wc -l | tr -d " ")" = 0' _ "$NAMES"

# Every row carries exactly the seven declared fields, in order (wave-06 S3:
# `class` and `consumer` joined the schema; nothing else moved).
FIELD_REPORT="$(deps_run -- dep_table_field_count_report)"
expect_eq "every table row has exactly 7 pipe-separated fields" "" "$FIELD_REPORT"

# …and the report can SEE a wrong-width row. Silence from a function that
# reports nothing under any input is not evidence — and this exact assertion sat
# green through the six-to-seven field change until the width it checks was
# updated with it.
# The table is assigned at SOURCE time, so the mutation has to land after the
# source — an env override would simply be overwritten and the arm would prove
# nothing.
WIDTH_MUTANT="$(bash -c '. "$1"; BIONIC_DEP_TABLE="rg|basic|substrate|brew:ripgrep|any|brew-dep"; dep_table_field_count_report' _ "$DEPS_SH")"
expect_match "the field-count report catches a row that lost a field" \
  "*has 6 fields, want 7*" "$WIDTH_MUTANT"

expect_eq "dep_field superpowers class" "core" "$(deps_run -- dep_field superpowers class)"
expect_eq "dep_field superpowers consumer" "skills/canonical-sdlc/SKILL.md" \
  "$(deps_run -- dep_field superpowers consumer)"
expect_eq "dep_field superpowers mechanism" "https://github.com/obra/superpowers.git" \
  "$(deps_run -- dep_field superpowers mechanism)"
expect_eq "dep_field superpowers constraint" "^6.3.0" "$(deps_run -- dep_field superpowers constraint)"
expect_eq "dep_field superpowers kind" "native" "$(deps_run -- dep_field superpowers kind)"
expect_eq "dep_field superpowers removal_behavior" "native-uninstall-offer" \
  "$(deps_run -- dep_field superpowers removal_behavior)"
expect_eq "dep_field rg mechanism" "brew:ripgrep" "$(deps_run -- dep_field rg mechanism)"
expect_eq "dep_field rg kind" "brew-dep" "$(deps_run -- dep_field rg kind)"
expect_eq "dep_field rg class" "basic" "$(deps_run -- dep_field rg class)"
expect_eq "dep_field rg consumer" "substrate" "$(deps_run -- dep_field rg consumer)"

# The pre-S3 field names stay readable so the callers this slice does not own
# (detect.sh, setup.sh, remove.sh, jit.sh, doctor.sh) compile unchanged. They
# are aliases of the columns above, not a second authority.
expect_eq "deprecated alias: dep_field <n> source_url == mechanism" \
  "$(deps_run -- dep_field rg mechanism)" "$(deps_run -- dep_field rg source_url)"
expect_eq "deprecated alias: dep_field <n> install_fn_or_check == kind" \
  "$(deps_run -- dep_field rg kind)" "$(deps_run -- dep_field rg install_fn_or_check)"
expect_eq "deprecated alias: a core row still reads lane=3a" "3a" \
  "$(deps_run -- dep_field superpowers lane)"
expect_eq "deprecated alias: a bionic-installed row still reads lane=3b" "3b" \
  "$(deps_run -- dep_field rg lane)"
# A native-kind row outside `core` is installed by neither pathway the lane
# taxonomy could name — the harness does not carry it (it is not a plugin.json
# dependency) and bionic has no installer for it (the JIT offer hands the user
# one command). `none` is the honest legacy answer, and it is what keeps the
# deprecated FIELD and the deprecated LIST saying the same thing.
expect_eq "deprecated alias: a when-needed native row belongs to neither lane" "none" \
  "$(deps_run -- dep_field impeccable lane)"

expect_false "dep_field on an unknown dep exits non-zero" \
  bash -c '. "$1"; dep_field no-such-dep class' _ "$DEPS_SH"
expect_false "dep_field with an unknown field name exits non-zero" \
  bash -c '. "$1"; dep_field superpowers no_such_field' _ "$DEPS_SH"

echo ""
echo "=== Group 2b: the four classes (wave-06 D-B, AC-10) ==="
#
# `class` is the wave's answer to WHEN bionic installs a tool: core = the two
# plugin dependencies the harness resolves; basic = the substrate asked for at
# setup and never removed; when-needed = installed with one question the first
# time a route needs it, never offered by setup; extra = offered once at setup,
# default No. The roster below is D-B's, ratified 2026-08-20.

# LC_ALL=C so the roster literals below do not depend on the runner's locale
# (`@playwright/cli` sorts before `aws` only under the C collation).
class_names() { deps_run -- dep_names_class "$1" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }

expect_eq "dep_names_class core is exactly the two plugin dependencies" \
  "agent-skills superpowers" "$(class_names core)"
expect_eq "dep_names_class basic is the substrate roster" \
  "aws docker gh git jq node pnpm rg uv" "$(class_names basic)"
expect_eq "dep_names_class when-needed is the JIT roster" \
  "@playwright/cli chrome-devtools impeccable motion playwright-chromium" "$(class_names when-needed)"
expect_eq "dep_names_class extra is the optional roster" \
  "@pencil.dev/cli ccstatusline context7 notebooklm" "$(class_names extra)"
expect_eq "an unknown class returns nothing (and exits 0)" "" "$(class_names no-such-class)"

# Every row lands in exactly one of the four. A fifth class value would leave
# rows the setup loop and the JIT route both skip.
CLASS_SUM=0
for c in core basic when-needed extra; do
  CLASS_SUM=$((CLASS_SUM + $(deps_run -- dep_names_class "$c" | grep -c .)))
done
expect_eq "the four classes partition the table (no row is unclassed)" \
  "$NAME_COUNT" "$CLASS_SUM"

# The two rows the traceability rule dropped: no route consumed them and no
# test covered them (D-B: "DROP: yq, gcloud").
expect_false "yq has no row (dropped, wave-06 D-B)" \
  bash -c '. "$1"; dep_row yq' _ "$DEPS_SH"
expect_false "gcloud has no row (dropped, wave-06 D-B)" \
  bash -c '. "$1"; dep_row gcloud' _ "$DEPS_SH"

echo ""
echo "=== Group 3: native-kind rows are byte-exact (the manifest renderings pin here) ==="
#
# superpowers and agent-skills carry the wave-03 ratified D1 values —
# agent-skills is ^0.6.0, the ^1.0.0 plugin.json once carried is stale.
# impeccable joins them at wave-06 S3: `^4.1.0` is the range, verified live
# against the upstream tags (`git ls-remote --tags` → skill-v4.1.1 is the
# newest; that commit's .claude-plugin/plugin.json declares version 4.1.1).
# marketplace.json is rendered FROM these three rows and plugin.json's
# `dependencies` from the two `core` ones, so a silent edit here moves a
# manifest.

expect_eq "native row: superpowers (byte-exact)" \
  "superpowers|core|skills/canonical-sdlc/SKILL.md|https://github.com/obra/superpowers.git|^6.3.0|native|native-uninstall-offer" \
  "$(deps_run -- dep_row superpowers)"
expect_eq "native row: agent-skills (byte-exact, ^0.6.0 not ^1.0.0)" \
  "agent-skills|core|skills/canonical-sdlc/SKILL.md|https://github.com/addyosmani/agent-skills.git|^0.6.0|native|native-uninstall-offer" \
  "$(deps_run -- dep_row agent-skills)"
expect_eq "native row: impeccable (byte-exact, when-needed — never a third core dep)" \
  "impeccable|when-needed|skills/canonical-sdlc/SKILL.md|https://github.com/pbakaus/impeccable.git|^4.1.0|native|native-uninstall-offer" \
  "$(deps_run -- dep_row impeccable)"

echo ""
echo "=== Group 3b: the deprecated lane lists still answer for the callers S3 does not own ==="
#
# setup.sh and remove.sh still walk `dep_names_lane`; S4/S6/S7 retire those call
# sites. Until then the alias has to mean exactly what it meant before: 3a = the
# rows the harness installs (class core), 3b = the rows bionic's own installers
# handle (kind != native). impeccable is native and NOT core, so it is in
# neither list — putting it in 3b would have setup offer a when-needed tool
# (AC-11) and hand install_dep a row it must refuse.

lane_names() { deps_run -- dep_names_lane "$1" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }

expect_eq "dep_names_lane 3a == dep_names_class core" \
  "$(class_names core)" "$(lane_names 3a)"
expect_eq "dep_names_lane 3b is every row bionic installs itself" \
  "@pencil.dev/cli @playwright/cli aws ccstatusline chrome-devtools context7 docker gh git jq motion node notebooklm playwright-chromium pnpm rg uv" \
  "$(lane_names 3b)"
expect_no_match "dep_names_lane 3b never yields the when-needed native row" \
  "*impeccable*" "$(lane_names 3b)"

echo ""
echo "=== Group 3c: consumer agreement — every row names something real (AC-10) ==="
#
# The traceability rule the wave ratified: "every dependency-table row names the
# doctrine route that consumes it, or gets dropped". A `consumer` is therefore
# either a repo-relative path that RESOLVES, or one of exactly two literals —
# `substrate` (the basics bionic ensures for every machine, which no single
# route owns) and `extra` (offered once, wanted by the user rather than by a
# route). Anything else is a row whose justification has gone stale.

CONSUMER_REPORT=""
while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  c="$(deps_run -- dep_field "$dep_name" consumer)"
  case "$c" in
    substrate|extra) continue ;;
    "") CONSUMER_REPORT="${CONSUMER_REPORT}${dep_name}: empty consumer"$'\n'; continue ;;
  esac
  [ -e "${REPO}/${c}" ] || CONSUMER_REPORT="${CONSUMER_REPORT}${dep_name}: consumer does not resolve: ${c}"$'\n'
done <<< "$NAMES"
expect_eq "every consumer resolves under the repo, or is substrate/extra" "" "$CONSUMER_REPORT"

# The literals are only legitimate for the classes that earned them: a
# when-needed row IS a route's dependency, so `substrate`/`extra` there would be
# the traceability gap wearing a permitted value.
LITERAL_REPORT=""
while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  c="$(deps_run -- dep_field "$dep_name" consumer)"
  k="$(deps_run -- dep_field "$dep_name" class)"
  case "${k}/${c}" in
    basic/substrate|extra/extra) ;;
    basic/*|extra/*) LITERAL_REPORT="${LITERAL_REPORT}${dep_name}: class ${k} wants its own literal, got ${c}"$'\n' ;;
    */substrate|*/extra) LITERAL_REPORT="${LITERAL_REPORT}${dep_name}: class ${k} must name a route, got the literal ${c}"$'\n' ;;
  esac
done <<< "$NAMES"
expect_eq "substrate/extra are used only by the basic/extra classes" "" "$LITERAL_REPORT"

# Naming a path is not the same as that path knowing about the dependency. The
# route file has to actually mention it, which is what makes the column a
# traceability claim rather than a plausible-looking string.
#
# ONE declared exemption, and it is a finding rather than a convenience:
# `motion` is a when-needed row by D-B's ratified roster, but no skill, rule or
# agent file in this repo names the package today — it is pre-warmed into the
# pnpm store for the design route and nothing writes that down. Either the
# design route names it or it is an `extra`; that is a design call, not this
# slice's, so the row keeps its class and the gap is visible here instead of
# being hidden by dropping the pin.
MENTION_EXEMPT=" motion "
MENTION_REPORT=""
while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  case "$MENTION_EXEMPT" in *" ${dep_name} "*) continue ;; esac
  c="$(deps_run -- dep_field "$dep_name" consumer)"
  case "$c" in substrate|extra) continue ;; esac
  grep -qF -- "$dep_name" "${REPO}/${c}" 2>/dev/null \
    || MENTION_REPORT="${MENTION_REPORT}${dep_name}: named consumer ${c} never mentions it"$'\n'
done <<< "$NAMES"
expect_eq "every named consumer route mentions the dependency it consumes" "" "$MENTION_REPORT"

# The exemption is itself pinned: if a later wave gives motion a route that
# names it, this fails and the exemption comes out. Vendored trees (.venv,
# node_modules) are excluded: they exist on a developer checkout and never in a
# worktree, and a pin that flips with the machine is not an absence claim.
# /usr/bin/grep, not the PATH one: this shell's `grep` is ugrep with
# --ignore-files, and it reports zero hits inside .claude/ even when the
# directory is named explicitly — an absence claim built on it would be a
# guaranteed pass (memory: grep-skips-hidden-dirs).
GREP_ABS="$(command -v /usr/bin/grep || echo grep)"
expect_false "the one mention exemption (motion) is still needed — no repo file names the package" \
  bash -c '"$2" -rIlw --include="*.md" --exclude-dir=.venv --exclude-dir=node_modules motion "$1/skills" "$1/agents-src" "$1/.claude/rules" 2>/dev/null | "$2" -q .' \
  _ "$REPO" "$GREP_ABS"

# Mutation-and-restore: the pin has to be able to SEE a bad consumer, or it is
# three loops that always print nothing. A row pointing at a path that does not
# exist is the failure the column exists to catch.
MUT_TABLE="$(printf '%s\n' "$(deps_run -- dep_row rg)" | sed 's#|substrate|#|skills/no-such-route/SKILL.md|#')"
MUT_C="$(printf '%s' "$MUT_TABLE" | cut -d'|' -f3)"
expect_eq "mutation: the fixture row really carries the broken consumer" \
  "skills/no-such-route/SKILL.md" "$MUT_C"
expect_false "mutation: a consumer path that does not resolve is detectable" \
  test -e "${REPO}/${MUT_C}"

echo ""
echo "=== Group 4: constraint-verdict logic (pure, fixture versions) ==="
#
# Fixture versions are real: 6.3.0 is superpowers' installed version on this
# machine — captured with
#   jq -r '.plugins["superpowers@claude-plugins-official"][0].version' \
#      ~/.claude/plugins/installed_plugins.json   ->  6.3.0

v() { deps_run -- dep_constraint_verdict "$1" "$2"; }

expect_eq "^6.3.0 vs 6.3.0 -> ok"        "ok"        "$(v '^6.3.0' 6.3.0)"
expect_eq "^6.3.0 vs 6.4.1 -> ok"        "ok"        "$(v '^6.3.0' 6.4.1)"
expect_eq "^6.3.0 vs 6.2.9 -> violation" "violation" "$(v '^6.3.0' 6.2.9)"
expect_eq "^6.3.0 vs 7.0.0 -> violation" "violation" "$(v '^6.3.0' 7.0.0)"
# The 0.x caret rule is not a corner case here — agent-skills IS a 0.x dep.
expect_eq "^0.6.0 vs 0.6.0 -> ok"        "ok"        "$(v '^0.6.0' 0.6.0)"
expect_eq "^0.6.0 vs 0.6.9 -> ok"        "ok"        "$(v '^0.6.0' 0.6.9)"
expect_eq "^0.6.0 vs 0.7.0 -> violation" "violation" "$(v '^0.6.0' 0.7.0)"
expect_eq "^0.6.0 vs 0.5.9 -> violation" "violation" "$(v '^0.6.0' 0.5.9)"
expect_eq "^0.6.0 vs 1.0.0 -> violation" "violation" "$(v '^0.6.0' 1.0.0)"
expect_eq "~1.2.3 vs 1.2.9 -> ok"        "ok"        "$(v '~1.2.3' 1.2.9)"
expect_eq "~1.2.3 vs 1.3.0 -> violation" "violation" "$(v '~1.2.3' 1.3.0)"
expect_eq ">=1.0.0 vs 2.0.0 -> ok"       "ok"        "$(v '>=1.0.0' 2.0.0)"
expect_eq ">=1.0.0 vs 0.9.0 -> violation" "violation" "$(v '>=1.0.0' 0.9.0)"
expect_eq "6.3.0 (exact) vs 6.3.0 -> ok" "ok"        "$(v '6.3.0' 6.3.0)"
expect_eq "6.3.0 (exact) vs 6.3.1 -> violation" "violation" "$(v '6.3.0' 6.3.1)"
expect_eq "any vs 0.0.1 -> ok"           "ok"        "$(v any 0.0.1)"
# `any` is a declaration that nothing is pinned, so it survives an unreadable
# version: there is no range left for that version to violate.
expect_eq "any vs unknown -> ok"         "ok"        "$(v any unknown)"
expect_eq "^6.3.0 vs unknown -> unknown" "unknown"   "$(v '^6.3.0' unknown)"
expect_eq "prerelease tag tolerated: ^6.3.0 vs 6.4.0-beta.1 -> ok" "ok" "$(v '^6.3.0' 6.4.0-beta.1)"
expect_eq "unparseable constraint -> unknown" "unknown" "$(v 'not-a-range' 1.0.0)"

echo ""
echo "=== Group 5: check_dep, native kind, against a fixture installed_plugins.json ==="
#
# Fixture shape copied from the real file, trimmed to one entry — captured with
#   jq '.plugins["superpowers@claude-plugins-official"]' \
#      ~/.claude/plugins/installed_plugins.json

plant_installed_plugins() {  # <dir> <key> <version>
  local dir="$1" key="$2" ver="$3"
  mkdir -p "${dir}/plugins"
  cat > "${dir}/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "${key}": [
      {
        "scope": "user",
        "installPath": "/fixture/plugins/cache/${key}/${ver}",
        "version": "${ver}",
        "installedAt": "2026-07-25T23:09:41.851Z",
        "lastUpdated": "2026-08-15T03:09:39.671Z",
        "gitCommitSha": "3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9"
      }
    ]
  }
}
JSON
}

CH_OK="$TMP/ch-ok"; plant_installed_plugins "$CH_OK" "superpowers@claude-plugins-official" "6.3.0"
CH_BAD="$TMP/ch-bad"; plant_installed_plugins "$CH_BAD" "superpowers@claude-plugins-official" "5.0.0"
CH_EMPTY="$TMP/ch-empty"; mkdir -p "$CH_EMPTY/plugins"
echo '{"version":2,"plugins":{}}' > "$CH_EMPTY/plugins/installed_plugins.json"

expect_eq "check_dep superpowers, installed at 6.3.0 -> present/ok" \
  "present=yes|version=6.3.0|verdict=ok" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_OK" -- check_dep superpowers)"
expect_eq "check_dep superpowers, installed at 5.0.0 -> present/violation" \
  "present=yes|version=5.0.0|verdict=violation" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_BAD" -- check_dep superpowers)"
expect_eq "check_dep superpowers, not installed -> absent/unknown" \
  "present=no|version=unknown|verdict=unknown" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- check_dep superpowers)"

# The native-kind probe must be marketplace-agnostic: slice S3 re-points both deps
# at bionic's own marketplace, which rewrites the key's right-hand side.
CH_REPOINTED="$TMP/ch-repointed"; plant_installed_plugins "$CH_REPOINTED" "superpowers@bionic" "6.3.0"
expect_eq "check_dep superpowers finds it under a DIFFERENT marketplace key" \
  "present=yes|version=6.3.0|verdict=ok" \
  "$(deps_run BIONIC_CLAUDE_HOME="$CH_REPOINTED" -- check_dep superpowers)"

# jq is itself a table row, so a machine can legitimately lack it. The fact
# must degrade to `unknown`, never to a confident wrong answer.
NOJQ_BIN="$TMP/nojq-bin"; mkdir -p "$NOJQ_BIN"
for real in bash sh env cat grep sed awk head tr; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${NOJQ_BIN}/${real}" 2>/dev/null
done
expect_eq "check_dep superpowers with no jq on PATH -> version unknown, verdict unknown" \
  "present=unknown|version=unknown|verdict=unknown" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_CLAUDE_HOME="$CH_OK" \
      bash -c '. "$1"; check_dep superpowers' _ "$DEPS_SH" 2>&1)"

echo ""
echo "=== Group 6: check_dep, lane-3b, against a fixture PATH ==="

PRESENT_BIN="$TMP/present-bin"
cp -R "$BASE_BIN/." "$PRESENT_BIN/" 2>/dev/null || { mkdir -p "$PRESENT_BIN"; cp -R "$BASE_BIN/." "$PRESENT_BIN/"; }
make_stub "$PRESENT_BIN" rg
make_stub "$PRESENT_BIN" npm
make_stub "$PRESENT_BIN" claude
make_stub "$PRESENT_BIN" brew
make_stub "$PRESENT_BIN" uv

expect_eq "check_dep rg with rg on PATH -> present, constraint 'any' -> ok" \
  "present=yes|version=unknown|verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
      bash -c '. "$1"; check_dep rg' _ "$DEPS_SH" 2>&1)"
expect_eq "check_dep rg with rg absent from PATH -> absent" \
  "present=no|version=unknown|verdict=unknown" \
  "$(deps_run -- check_dep rg)"

# A version-bearing probe: the brew-dep mechanism parses `<binary> --version`.
# Fixture output copied from the real `rg --version` on this machine:
#   ripgrep 15.2.0
VER_BIN="$TMP/ver-bin"; mkdir -p "$VER_BIN"; cp -R "$BASE_BIN/." "$VER_BIN/"
cat > "${VER_BIN}/rg" <<'STUB'
#!/bin/bash
echo "ripgrep 15.2.0"
STUB
chmod +x "${VER_BIN}/rg"
expect_eq "check_dep rg reads a version out of the probe's --version output" \
  "present=yes|version=15.2.0|verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$VER_BIN" bash -c '. "$1"; check_dep rg' _ "$DEPS_SH" 2>&1)"

# The npm-global mechanism probes the PACKAGE, not a binary name.
expect_eq "check_dep @playwright/cli with a succeeding npm -> present" \
  "present=yes|version=unknown|verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
      bash -c '. "$1"; check_dep @playwright/cli' _ "$DEPS_SH" 2>&1)"

# The pnpm-store mechanism has NO presence surface (bootstrap never checks it,
# it re-warms unconditionally). Saying `no` on a warm machine would be a lie;
# the honest value is `unknown`.
expect_eq "check_dep motion (pnpm store) -> presence honestly unknown" \
  "present=unknown|version=unknown|verdict=unknown" \
  "$(deps_run -- check_dep motion)"

expect_false "check_dep on an unknown dep exits non-zero" \
  bash -c '. "$1"; check_dep no-such-dep' _ "$DEPS_SH"

echo ""
echo "=== Group 7: install_dep — consent gates every mutation ==="
#
# No dry-run seam: the stub `brew` on the fixture PATH is what install_dep
# really invokes, and the recorder file is the only evidence considered.

: > "$CALLS"
DECLINE_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; install_dep rg </dev/null' _ "$DEPS_SH" 2>&1)"
DECLINE_RC=$?
expect_true "install_dep with no answer on stdin exits non-zero (declined)" test "$DECLINE_RC" -ne 0
expect_eq "install_dep with no answer ran NOTHING (recorder empty)" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"
expect_match "install_dep names what it would run before asking" "*brew install ripgrep*" "$DECLINE_OUT"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; install_dep rg; }' _ "$DEPS_SH" >/dev/null 2>&1
expect_match "install_dep with an explicit y DOES invoke brew" "*brew install ripgrep*" "$(cat "$CALLS")"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo n | { . "$1"; install_dep rg; }' _ "$DEPS_SH" >/dev/null 2>&1
expect_eq "install_dep with an explicit n ran nothing" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

# A native-KIND row is the plugin harness's job — install_dep must refuse to
# grow a second installer for it (that is exactly the D1 kludge the wave
# rejected). The refusal keys on `kind`, not on the class: impeccable is
# when-needed and equally native, and a class-keyed guard would have handed it
# to a mechanism that has no argv for it.
: > "$CALLS"
expect_false "install_dep refuses a core native row (the harness owns it)" \
  bash -c 'echo y | { . "$1"; install_dep superpowers; }' _ "$DEPS_SH"
expect_false "install_dep refuses the when-needed native row too" \
  bash -c 'echo y | { . "$1"; install_dep impeccable; }' _ "$DEPS_SH"
expect_eq "…and neither refusal ran anything" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

expect_false "install_dep on an unknown dep exits non-zero" \
  bash -c 'echo y | { . "$1"; install_dep no-such-dep; }' _ "$DEPS_SH"

echo ""
echo "=== Group 8: remove_dep — consent-wrapped, policy-bounded ==="

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c '. "$1"; remove_dep @playwright/cli </dev/null' _ "$DEPS_SH" >/dev/null 2>&1
expect_eq "remove_dep with no answer removed nothing" "0" "$(grep -c . "$CALLS" | tr -d ' ')"

: > "$CALLS"
env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; remove_dep @playwright/cli; }' _ "$DEPS_SH" >/dev/null 2>&1
expect_match "remove_dep with consent uninstalls an own-install row" "*npm uninstall -g @playwright/cli*" "$(cat "$CALLS")"

# Shared foundation binaries are the reset charter's named exclusion: bionic
# ensured them, it does not own them, and pulling `git` off a machine because
# bionic is leaving is not a removal anyone consented to.
: > "$CALLS"
KEEP_OUT="$(env -i HOME="$TMP/home" PATH="$PRESENT_BIN" BIONIC_TEST_CALLS="$CALLS" \
  bash -c 'echo y | { . "$1"; remove_dep git; }' _ "$DEPS_SH" 2>&1)"
expect_eq "remove_dep git (keep-shared) removes nothing even with consent" "0" \
  "$(grep -c . "$CALLS" | tr -d ' ')"
expect_match "remove_dep git says why it is keeping the binary" "*keep-shared*" "$KEEP_OUT"

echo ""
echo "=== Group 8b: the statusline writers preserve settings.json's MODE ==="
#
# C-1 and R-1, on the two settings writers in this file. `~/.claude/settings.json`
# routinely carries an `env` block with tokens, so a machine that chose 0600 for
# it must still have 0600 after bionic records or clears the statusline —
# widening a credential-bearing file to 0644 is a machine side effect, not a
# formatting detail. Neither writer captured the mode at all before this group
# existed, so the widening here was UNCONDITIONAL rather than a crash window:
# every install, every removal, no race required.
#
# Both writers are driven through their LIVE entry points — `install_dep`'s
# statusline branch and `remove_dep ccstatusline` — not through the helper they
# share, so what is measured is the path the setup loop actually walks.
#
# Both directions are asserted for each, so no arm can pass by pinning one
# constant: a writer that narrowed every file to 0600 fails the 0644 arm.

file_mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

# BASE_BIN deliberately carries no `stat` — the payload's mode capture degrades
# honestly without it (A18), and the last arm in this group proves that. The
# repair itself can only be measured on a machine that HAS `stat`, so this group
# gets a bin dir that is BASE_BIN plus that one binary and nothing else.
STL_BIN="$TMP/statusline-bin"; mkdir -p "$STL_BIN"
for _stl_real in "$BASE_BIN"/*; do ln -sf "$_stl_real" "$STL_BIN/" 2>/dev/null; done
_stl_stat="$(command -v stat 2>/dev/null)" && ln -sf "$_stl_stat" "$STL_BIN/stat" 2>/dev/null
expect_true "the statusline arms have a stat on PATH (the repair is reachable)" \
  test -x "$STL_BIN/stat"

# A settings.json carrying a token, so every arm below also witnesses that the
# rewrite preserved the content it was not asked to touch.
STL_TOKEN='sk-fixture-not-a-real-token'
plant_settings() {  # <path> <mode> [extra-json-object]
  local path="$1" mode="$2" extra="${3:-{\}}"
  printf '{"env":{"ANTHROPIC_AUTH_TOKEN":"%s"},"model":"opus"}' "$STL_TOKEN" \
    | jq --argjson extra "$extra" '. + $extra' > "$path"
  chmod "$mode" "$path"
}

# One library function, one controlled environment, one settings file. `answer`
# is fed on stdin because the live entry points are consent-gated.
stl_run() {  # <settings-file> <answer|-> [shim] -- <fn> [args]
  local settings="$1" answer="$2" shim="$3"; shift 4
  local prog='. "$1"; shift; "$@"'
  [ "$shim" = "-" ] || prog='. "$1"; . "$BIONIC_TEST_SHIM"; shift; "$@"'
  if [ "$answer" = "-" ]; then
    env -i HOME="$TMP/home" PATH="$STL_BIN" BIONIC_TEST_CALLS="$CALLS" \
      BIONIC_SETTINGS_FILE="$settings" BIONIC_TEST_SHIM="$shim" \
      BIONIC_TEST_MODE_LOG="${STL_LOG:-/dev/null}" \
      bash -c "$prog" _ "$DEPS_SH" "$@" 2>&1
  else
    echo "$answer" | env -i HOME="$TMP/home" PATH="$STL_BIN" BIONIC_TEST_CALLS="$CALLS" \
      BIONIC_SETTINGS_FILE="$settings" BIONIC_TEST_SHIM="$shim" \
      BIONIC_TEST_MODE_LOG="${STL_LOG:-/dev/null}" \
      bash -c "$prog" _ "$DEPS_SH" "$@" 2>&1
  fi
}

STL_DIR="$TMP/statusline-arms"; mkdir -p "$STL_DIR"
STL_LINE='{"statusLine":{"type":"command","command":"npx ccstatusline@latest"}}'

# --- install, through install_dep's consent gate, on a 0600 file -------------
STL_S="$STL_DIR/install-600.json"
plant_settings "$STL_S" 600
expect_eq "install fixture: settings.json really starts at 0600 (not vacuous)" \
  "600" "$(file_mode "$STL_S")"
STL_OUT="$(stl_run "$STL_S" y - -- install_dep ccstatusline)"
expect_match "install_dep really recorded the statusline (the arm is not vacuous)" \
  '*ccstatusline*' "$(cat "$STL_S")"
expect_match "and the token already in the file survived the rewrite" \
  "*${STL_TOKEN}*" "$(cat "$STL_S")"
expect_eq "recording the statusline leaves a 0600 settings.json at 0600" \
  "600" "$(file_mode "$STL_S")"

# --- and the other direction, so 0600 cannot be hard-coded ------------------
STL_S644="$STL_DIR/install-644.json"
plant_settings "$STL_S644" 644
STL_OUT="$(stl_run "$STL_S644" y - -- install_dep ccstatusline)"
expect_match "install_dep recorded the statusline on the 0644 fixture too" \
  '*ccstatusline*' "$(cat "$STL_S644")"
expect_eq "recording the statusline does not narrow a 0644 settings.json" \
  "644" "$(file_mode "$STL_S644")"

# --- removal, through remove_dep's consent gate, on a 0600 file -------------
STL_R="$STL_DIR/remove-600.json"
plant_settings "$STL_R" 600 "$STL_LINE"
expect_eq "removal fixture: settings.json really starts at 0600 (not vacuous)" \
  "600" "$(file_mode "$STL_R")"
STL_OUT="$(stl_run "$STL_R" y - -- remove_dep ccstatusline)"
expect_true "remove_dep ccstatusline really cleared .statusLine (not vacuous)" \
  jq -e '.statusLine == null' "$STL_R"
expect_match "and the removal left the token it was not asked to touch" \
  "*${STL_TOKEN}*" "$(cat "$STL_R")"
expect_eq "clearing the statusline leaves a 0600 settings.json at 0600" \
  "600" "$(file_mode "$STL_R")"

STL_R644="$STL_DIR/remove-644.json"
plant_settings "$STL_R644" 644 "$STL_LINE"
STL_OUT="$(stl_run "$STL_R644" y - -- remove_dep ccstatusline)"
expect_true "remove_dep cleared .statusLine on the 0644 fixture too" \
  jq -e '.statusLine == null' "$STL_R644"
expect_eq "clearing the statusline does not narrow a 0644 settings.json" \
  "644" "$(file_mode "$STL_R644")"

# --- R-1: the mode must be right AT THE RENAME, not repaired after it -------
#
# The arms above measure the mode once the writer has returned, which a writer
# that publishes a 0644 inode and then chmods it back would also satisfy — while
# leaving the tmp (predictable name, whole settings content, tokens included)
# world-readable for the span before the rename, and leaving the widening
# PERMANENT if the process dies in that window. The shim shadows only `mv` and
# `chmod`, and only to observe and to stop the clock: it stats the RENAME'S
# SOURCE — the inode about to become settings.json — logs that mode, does the
# real rename, and then declares the process dead so every later `chmod` returns
# success without acting. The kill is triggered by the rename EVENT, so it cannot
# be tuned to spare one writer's spelling. Same mechanism as
# tests/remove.test.sh's instant arms, on this file's two writers.
STL_SHIM="$TMP/statusline-write-shim.sh"
cat > "$STL_SHIM" <<'SHIM'
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

STL_I="$STL_DIR/install-instant.json"
plant_settings "$STL_I" 600
STL_LOG="$TMP/statusline-instant-install.log"; : > "$STL_LOG"
STL_OUT="$(stl_run "$STL_I" y "$STL_SHIM" -- install_dep ccstatusline)"
expect_true "install instant arm: the shimmed rename really was reached (not vacuous)" \
  test -s "$STL_LOG"
expect_eq "the install writer's tmp already wears 0600 when mv renames it" \
  "600" "$(head -1 "$STL_LOG" | tr -d ' ')"
expect_eq "a process that dies the instant that mv lands still leaves it at 0600" \
  "600" "$(file_mode "$STL_I")"

STL_I644="$STL_DIR/install-instant-644.json"
plant_settings "$STL_I644" 644
STL_LOG="$TMP/statusline-instant-install-644.log"; : > "$STL_LOG"
STL_OUT="$(stl_run "$STL_I644" y "$STL_SHIM" -- install_dep ccstatusline)"
expect_eq "the install writer's tmp for a 0644 file is 0644 at the rename, not narrowed" \
  "644" "$(head -1 "$STL_LOG" | tr -d ' ')"

STL_RI="$STL_DIR/remove-instant.json"
plant_settings "$STL_RI" 600 "$STL_LINE"
STL_LOG="$TMP/statusline-instant-remove.log"; : > "$STL_LOG"
STL_OUT="$(stl_run "$STL_RI" y "$STL_SHIM" -- remove_dep ccstatusline)"
expect_true "removal instant arm: the shimmed rename really was reached (not vacuous)" \
  test -s "$STL_LOG"
expect_eq "the removal writer's tmp already wears 0600 when mv renames it" \
  "600" "$(head -1 "$STL_LOG" | tr -d ' ')"
expect_eq "and a death right after THAT rename leaves 0600 too" \
  "600" "$(file_mode "$STL_RI")"

STL_RI644="$STL_DIR/remove-instant-644.json"
plant_settings "$STL_RI644" 644 "$STL_LINE"
STL_LOG="$TMP/statusline-instant-remove-644.log"; : > "$STL_LOG"
STL_OUT="$(stl_run "$STL_RI644" y "$STL_SHIM" -- remove_dep ccstatusline)"
expect_eq "the removal writer's tmp for a 0644 file is 0644 at the rename" \
  "644" "$(head -1 "$STL_LOG" | tr -d ' ')"
unset STL_LOG

# --- A18's honest degradation, on a machine with no `stat` ------------------
#
# BASE_BIN has no `stat`, so the mode cannot be captured. The write must still
# land: an absent coreutil turns the repair off, it does not turn the writer
# into a refusal. This is the same degradation the payload already practises for
# `jq`, and the consequence A18 recorded deliberately — on such a machine the
# pre-fold widening persists, silently.
STL_NS="$STL_DIR/no-stat.json"
plant_settings "$STL_NS" 600
STL_OUT="$(echo y | env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_TEST_CALLS="$CALLS" \
  BIONIC_SETTINGS_FILE="$STL_NS" \
  bash -c '. "$1"; install_dep ccstatusline' _ "$DEPS_SH" 2>&1)"
expect_match "with no stat on PATH the statusline is still recorded (write, don't chmod)" \
  '*ccstatusline*' "$(cat "$STL_NS")"
expect_true "and the file is still valid JSON after that degraded write" \
  jq -e . "$STL_NS"

echo ""
echo "=== Group 9: detect_plugin_integrity — all three hook states ==="

plant_hook_scripts() {  # <root> <name>...
  local root="$1"; shift
  local name
  for name in "$@"; do
    printf '#!/bin/bash\nexit 0\n' > "${root}/hooks/${name}"
    chmod +x "${root}/hooks/${name}"
  done
}

plant_plugin() {  # <root> <version|-> <hooks: ok|degraded|chained-gap|absent>
  local root="$1" ver="$2" hooks="$3"
  mkdir -p "${root}/.claude-plugin" "${root}/hooks"
  if [ "$ver" != "-" ]; then
    cat > "${root}/.claude-plugin/plugin.json" <<JSON
{ "name": "bionic", "version": "${ver}" }
JSON
  fi
  case "$hooks" in
    absent) rm -f "${root}/hooks/hooks.json" ;;
    *)
      # Fixture-faithful to the shipped payload/hooks/hooks.json that S4
      # re-derived in this same wave: one plain entry plus a CHAINED one
      # ("agent-context-guard.sh <inner>"). Four of the six shipped entries
      # chain, so a fixture carrying only the plain shape cannot reach the
      # state that matters most — a payload where the OUTER script is there
      # and an inner one is not. That is the `chained-gap` arm below.
      cat > "${root}/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh", "timeout": 10 } ] }
    ],
    "PreCompact": [
      { "matcher": "",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/agent-context-guard.sh ${CLAUDE_PLUGIN_ROOT}/hooks/dispatch-preflight.sh", "timeout": 10 } ] }
    ]
  }
}
JSON
      case "$hooks" in
        ok)          plant_hook_scripts "$root" protect-main.sh agent-context-guard.sh dispatch-preflight.sh ;;
        chained-gap) plant_hook_scripts "$root" protect-main.sh agent-context-guard.sh ;;
        degraded)    : ;;   # nothing planted — even the FIRST token is missing
      esac
      ;;
  esac
}

PL_OK="$TMP/pl-ok";        plant_plugin "$PL_OK" 0.1.0 ok
PL_DEG="$TMP/pl-degraded"; plant_plugin "$PL_DEG" 0.1.0 degraded
PL_CHAIN="$TMP/pl-chain";  plant_plugin "$PL_CHAIN" 0.1.0 chained-gap
PL_ABS="$TMP/pl-absent";   plant_plugin "$PL_ABS" 0.1.0 absent
PL_NOVER="$TMP/pl-nover";  plant_plugin "$PL_NOVER" - ok

expect_eq "detect_plugin_integrity: intact payload" "plugin: version=0.1.0 hooks=ok" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_OK" -- detect_plugin_integrity)"
expect_eq "detect_plugin_integrity: hooks.json references a missing script" \
  "plugin: version=0.1.0 hooks=degraded" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_DEG" -- detect_plugin_integrity)"
# R-1. The outer script of a chained command is present, the INNER one is not.
# Reading only the first whitespace token calls this payload healthy while half
# its hooks are missing files — a half-copied install that lost the evidence
# gate, the governing-skill gate and the landing gate reports clean.
expect_eq "detect_plugin_integrity: a CHAINED command's second script is missing" \
  "plugin: version=0.1.0 hooks=degraded" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_CHAIN" -- detect_plugin_integrity)"
expect_eq "detect_plugin_integrity: no hooks.json at all" "plugin: version=0.1.0 hooks=absent" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_ABS" -- detect_plugin_integrity)"
expect_eq "detect_plugin_integrity: unreadable plugin.json -> version=unknown" \
  "plugin: version=unknown hooks=ok" \
  "$(detect_run BIONIC_PLUGIN_ROOT="$PL_NOVER" -- detect_plugin_integrity)"

echo ""
echo "=== Group 10: detect_dep renders one line per dep, both arms ==="

expect_eq "detect_dep superpowers (present)" \
  "dep:superpowers lane=3a present=yes version=6.3.0 constraint=^6.3.0 verdict=ok" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_OK" -- detect_dep superpowers)"
expect_eq "detect_dep superpowers (absent)" \
  "dep:superpowers lane=3a present=no version=unknown constraint=^6.3.0 verdict=unknown" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- detect_dep superpowers)"
expect_eq "detect_dep rg (present, lane 3b)" \
  "dep:rg lane=3b present=yes version=15.2.0 constraint=any verdict=ok" \
  "$(env -i HOME="$TMP/home" PATH="$VER_BIN" bash -c '. "$1"; detect_dep rg' _ "$DETECT_SH" 2>&1)"
expect_eq "detect_dep rg (absent, lane 3b)" \
  "dep:rg lane=3b present=no version=unknown constraint=any verdict=unknown" \
  "$(detect_run -- detect_dep rg)"
expect_false "detect_dep on an unknown dep exits non-zero" \
  bash -c '. "$1"; detect_dep no-such-dep' _ "$DETECT_SH"

echo ""
echo "=== Group 11: detect_env_todo_tools — both arms ==="

RC_WITH="$TMP/rc-with";  printf 'export PATH="$HOME/bin:$PATH"\nexport CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n' > "$RC_WITH"
RC_WITHOUT="$TMP/rc-without"; printf 'export PATH="$HOME/bin:$PATH"\n' > "$RC_WITHOUT"
RC_COMMENTED="$TMP/rc-commented"; printf '# export CLAUDE_CODE_ENABLE_TODO_TOOLS=1\n' > "$RC_COMMENTED"

expect_eq "detect_env_todo_tools: export present" "env:todo-tools present=yes" \
  "$(detect_run BIONIC_SHELL_RC="$RC_WITH" -- detect_env_todo_tools)"
expect_eq "detect_env_todo_tools: export absent" "env:todo-tools present=no" \
  "$(detect_run BIONIC_SHELL_RC="$RC_WITHOUT" -- detect_env_todo_tools)"
expect_eq "detect_env_todo_tools: a COMMENTED export does not count" "env:todo-tools present=no" \
  "$(detect_run BIONIC_SHELL_RC="$RC_COMMENTED" -- detect_env_todo_tools)"
expect_eq "detect_env_todo_tools: rc file missing entirely" "env:todo-tools present=no" \
  "$(detect_run BIONIC_SHELL_RC="$TMP/rc-nonexistent" -- detect_env_todo_tools)"

echo ""
echo "=== Group 12: detect_zshrc_legacy_block — both arms ==="
#
# Marker literals copied verbatim from claude-bootstrap.sh's ALIAS_START /
# ALIAS_END (the box-drawing dashes are part of the marker).

RC_LEGACY="$TMP/rc-legacy"
cat > "$RC_LEGACY" <<'RC'
export PATH="$HOME/bin:$PATH"
# ─── bionic:start ───
alias claude='claude --dangerously-skip-permissions'
# ─── bionic:end ───
RC

expect_eq "detect_zshrc_legacy_block: block present" "env:zshrc-legacy present=yes" \
  "$(detect_run BIONIC_SHELL_RC="$RC_LEGACY" -- detect_zshrc_legacy_block)"
expect_eq "detect_zshrc_legacy_block: block absent" "env:zshrc-legacy present=no" \
  "$(detect_run BIONIC_SHELL_RC="$RC_WITHOUT" -- detect_zshrc_legacy_block)"
expect_eq "detect_zshrc_legacy_block: rc file missing entirely" "env:zshrc-legacy present=no" \
  "$(detect_run BIONIC_SHELL_RC="$TMP/rc-nonexistent" -- detect_zshrc_legacy_block)"

echo ""
echo "=== Group 13: detect_legacy_channel_hooks — counts, both arms ==="
#
# Fixture shape copied from the real user settings.json hook block written by
# claude-bootstrap.sh's wire_managed_hooks (MANAGED_HOOKS, :1772-1779).

SET_STALE="$TMP/settings-stale.json"
cat > "$SET_STALE" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "~/.claude/hooks/protect-main.sh" },
                   { "type": "command", "command": "~/.claude/hooks/protect-database.sh" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/landing-gate.sh" } ] }
    ]
  }
}
JSON

SET_CLEAN="$TMP/settings-clean.json"
cat > "$SET_CLEAN" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-main.sh" } ] }
    ]
  }
}
JSON

SET_NOHOOKS="$TMP/settings-nohooks.json"; echo '{"model":"opus"}' > "$SET_NOHOOKS"

expect_eq "detect_legacy_channel_hooks: two legacy entries counted, plugin entry not" \
  "env:legacy-channel-hooks count=2" \
  "$(detect_run BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: a clean plugin-channel settings file counts 0" \
  "env:legacy-channel-hooks count=0" \
  "$(detect_run BIONIC_SETTINGS_FILE="$SET_CLEAN" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: settings with no hooks key counts 0" \
  "env:legacy-channel-hooks count=0" \
  "$(detect_run BIONIC_SETTINGS_FILE="$SET_NOHOOKS" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: missing settings file counts 0" \
  "env:legacy-channel-hooks count=0" \
  "$(detect_run BIONIC_SETTINGS_FILE="$TMP/settings-nonexistent.json" -- detect_legacy_channel_hooks)"
expect_eq "detect_legacy_channel_hooks: no jq on PATH -> count=unknown, never a false 0" \
  "env:legacy-channel-hooks count=unknown" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_SETTINGS_FILE="$SET_STALE" \
      bash -c '. "$1"; detect_legacy_channel_hooks' _ "$DETECT_SH" 2>&1)"

echo ""
echo "=== Group 14: detect_half_uninstalled — both arms ==="
#
# Half-uninstalled = the plugin is no longer registered, but bionic's machine
# footprint is still there. It is the fact the standalone remove.sh door (AC-4)
# exists to serve, so it must NOT be answered by asking whether this file's own
# payload tree exists — that tree is gone in exactly the case being detected.

expect_eq "detect_half_uninstalled: plugin gone + legacy .zshrc block left behind" \
  "state:half-uninstalled=yes" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_LEGACY" \
      BIONIC_SETTINGS_FILE="$SET_CLEAN" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: plugin gone + stale settings entries left behind" \
  "state:half-uninstalled=yes" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: plugin gone and no footprint at all -> no" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_CLEAN" -- detect_half_uninstalled)"
# The discriminating arm: identical footprint, only the registration differs.
# Without it the function could return `yes` on the footprint alone and still
# pass every case above.
CH_BIONIC="$TMP/ch-bionic"; plant_installed_plugins "$CH_BIONIC" "bionic@bionic" "0.1.0"
expect_eq "detect_half_uninstalled: plugin still installed, same footprint -> no" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_BIONIC" BIONIC_SHELL_RC="$RC_LEGACY" \
      BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_half_uninstalled)"

# R-2 — the FOURTH term. detect.sh owns three pieces of footprint; the applied
# permission block is profile.sh's, and it is reachable on its own: a user who
# runs /bionic:remove, declines the permission-block question and accepts the
# uninstall lands with the block as the only leftover. Both files' headers said
# the disjunction joined there and neither joined it, so doctor read
# half-uninstalled=no and withheld the one fix that machine has.
#
# The consult is SOFT — `declare -F` — because detect.sh must stay sourceable
# alone. That is not a nicety here: the standalone remove.sh door exists for
# exactly the machine where the payload (and so profile.sh) is gone. Hence two
# arms on one machine state, differing only in which libraries are loaded.
SET_PROFILE_ONLY="$TMP/settings-profile-only.json"
cat > "$SET_PROFILE_ONLY" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(: bionic-profile-begin version=0.1.0)",
      "Bash(bash /Users/nobody/.claude/plugins/bionic/scripts/doctor.sh:*)",
      "Bash(: bionic-profile-end)"
    ]
  }
}
JSON

detect_and_profile_run() {  # <env-assignments...> -- <function> [args]
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -i HOME="$TMP/home" PATH="$BASE_BIN" BIONIC_TEST_CALLS="$CALLS" "${envs[@]}" \
    bash -c '. "$1"; . "$2"; shift 2; "$@"' _ "$DETECT_SH" "$PROFILE_SH" "$@" 2>&1
}

expect_eq "detect_half_uninstalled: doctor's load-out (detect+profile) sees the permission block as footprint" \
  "state:half-uninstalled=yes" \
  "$(detect_and_profile_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_PROFILE_ONLY" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: detect.sh ALONE degrades to its own three terms, same machine" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_PROFILE_ONLY" -- detect_half_uninstalled)"
expect_eq "detect_half_uninstalled: detect+profile, plugin still registered -> still no" \
  "state:half-uninstalled=no" \
  "$(detect_and_profile_run BIONIC_CLAUDE_HOME="$CH_BIONIC" BIONIC_SHELL_RC="$RC_WITHOUT" \
      BIONIC_SETTINGS_FILE="$SET_PROFILE_ONLY" -- detect_half_uninstalled)"

# C-2 — REGISTRATION AS A FACT OF ITS OWN. The registration probe above was
# computed inside detect_half_uninstalled and reachable nowhere else, so setup's
# step 6 could not consult it and told every user the plugin registers a
# replacement for the hooks it was about to delete — false on every machine
# before the W5 cutover. A machine fact that only one caller can see is a fact
# with one caller by accident, not by design; this exposes it the way every
# other line here is exposed, and detect_half_uninstalled now reads it rather
# than recomputing it.

expect_eq "detect_plugin_registered: bionic in installed_plugins.json -> yes" \
  "plugin:registered=yes" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_BIONIC" -- detect_plugin_registered)"
expect_eq "detect_plugin_registered: a registry with no bionic entry -> no" \
  "plugin:registered=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- detect_plugin_registered)"
expect_eq "detect_plugin_registered: another marketplace's plugin is not bionic" \
  "plugin:registered=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_OK" -- detect_plugin_registered)"
expect_eq "detect_plugin_registered: no registry file at all -> no (nothing is installed)" \
  "plugin:registered=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$TMP/ch-absent" -- detect_plugin_registered)"

# The honest unknown, in the one case where guessing would be a lie: the file is
# there and jq cannot parse it. Answering `no` would tell setup to promise the
# user nothing replaces their hooks; answering `yes` would promise that
# something does. Neither is known.
CH_MALFORMED="$TMP/ch-malformed"; mkdir -p "$CH_MALFORMED/plugins"
printf '%s' '{"plugins": {' > "$CH_MALFORMED/plugins/installed_plugins.json"
expect_eq "detect_plugin_registered: unparseable registry -> unknown, never a guess" \
  "plugin:registered=unknown" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_MALFORMED" -- detect_plugin_registered)"

# No jq: the grep fallback the half-uninstalled probe already carried. It is a
# real answer, not an unknown — the key is a literal string in the file.
expect_eq "detect_plugin_registered: no jq on PATH still reads the registry -> yes" \
  "plugin:registered=yes" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_CLAUDE_HOME="$CH_BIONIC" \
      bash -c '. "$1"; detect_plugin_registered' _ "$DETECT_SH" 2>&1)"
expect_eq "detect_plugin_registered: no jq, no bionic entry -> no" \
  "plugin:registered=no" \
  "$(env -i HOME="$TMP/home" PATH="$NOJQ_BIN" BIONIC_CLAUDE_HOME="$CH_EMPTY" \
      bash -c '. "$1"; detect_plugin_registered' _ "$DETECT_SH" 2>&1)"

# The extraction did not move the half-uninstalled verdict. An `unknown`
# registration must not be reported as half-uninstalled: that verdict tells the
# user their machine is broken and points them at the standalone remove door.
expect_eq "detect_half_uninstalled: an unparseable registry is not a half-uninstall claim" \
  "state:half-uninstalled=no" \
  "$(detect_run BIONIC_CLAUDE_HOME="$CH_MALFORMED" BIONIC_SHELL_RC="$RC_LEGACY" \
      BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_half_uninstalled)"

echo ""
echo "=== Group 15: read-only contract — no detect function mutates ==="
#
# The design's own words: doctor mutates nothing, and every doctor line comes
# from detect.sh. A fingerprint of the whole fixture tree taken before and
# after a full detect sweep is the cheapest honest proof of that.

FP_ROOT="$TMP/fp"; mkdir -p "$FP_ROOT"
cp "$RC_LEGACY" "$FP_ROOT/rc"; cp "$SET_STALE" "$FP_ROOT/settings.json"
cp -R "$PL_OK" "$FP_ROOT/plugin"; cp -R "$CH_OK" "$FP_ROOT/claude-home"
fingerprint() { find "$FP_ROOT" -type f -exec ls -l {} \; 2>/dev/null | awk '{print $5, $9}' | sort; }
FP_BEFORE="$(fingerprint)"
: > "$CALLS"
detect_run BIONIC_PLUGIN_ROOT="$FP_ROOT/plugin" BIONIC_CLAUDE_HOME="$FP_ROOT/claude-home" \
  BIONIC_SHELL_RC="$FP_ROOT/rc" BIONIC_SETTINGS_FILE="$FP_ROOT/settings.json" \
  -- detect_all >/dev/null 2>&1
FP_AFTER="$(fingerprint)"
expect_eq "a full detect_all sweep leaves every fixture file byte-identical" "$FP_BEFORE" "$FP_AFTER"

DETECT_ALL="$(detect_run BIONIC_PLUGIN_ROOT="$PL_OK" BIONIC_CLAUDE_HOME="$CH_OK" \
  BIONIC_SHELL_RC="$RC_LEGACY" BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_all)"
expect_match "detect_all emits the plugin line"        "*plugin: version=*"          "$DETECT_ALL"
expect_match "detect_all emits the todo-tools line"    "*env:todo-tools present=*"   "$DETECT_ALL"
expect_match "detect_all emits the zshrc-legacy line"  "*env:zshrc-legacy present=*" "$DETECT_ALL"
expect_match "detect_all emits the stale-hooks line"   "*env:legacy-channel-hooks count=*" "$DETECT_ALL"
expect_match "detect_all emits the registration line"  "*plugin:registered=*"        "$DETECT_ALL"
expect_match "detect_all emits the half-uninstalled line" "*state:half-uninstalled=*" "$DETECT_ALL"
expect_match "detect_all emits a dep line per row"     "*dep:superpowers lane=3a*"   "$DETECT_ALL"

echo ""
echo "=== Group 16: every detect function prints exactly one line and exits 0 ==="

# detect_registry_sha_lag is in this list deliberately, driven with NO git on PATH: this
# group's contract is the shape of the answer, not the answer, and the unknown path is the
# one an ordinary user's machine takes.
for fn in detect_plugin_integrity detect_env_todo_tools detect_zshrc_legacy_block \
          detect_legacy_channel_hooks detect_plugin_registered detect_half_uninstalled \
          detect_registry_sha_lag; do
  out="$(detect_run BIONIC_PLUGIN_ROOT="$PL_OK" BIONIC_CLAUDE_HOME="$CH_OK" \
    BIONIC_SHELL_RC="$RC_LEGACY" BIONIC_SETTINGS_FILE="$SET_STALE" -- "$fn")"
  rc=$?
  expect_eq "${fn} exits 0" "0" "$rc"
  expect_eq "${fn} prints exactly one line" "1" "$(printf '%s\n' "$out" | grep -c .)"
done
out="$(detect_run BIONIC_CLAUDE_HOME="$CH_OK" -- detect_dep superpowers)"; rc=$?
expect_eq "detect_dep exits 0" "0" "$rc"
expect_eq "detect_dep prints exactly one line" "1" "$(printf '%s\n' "$out" | grep -c .)"

echo ""
echo "=== Group 18: manifest agreement — deps.sh table <-> plugin.json <-> marketplace.json (AC-8) ==="
#
# The dep table is the SSoT. plugin.json's `dependencies` array renders the
# `core` rows and marketplace.json's url-sourced entries render the
# `native`-KIND rows — two different sets since wave-06 S3, because impeccable
# is installable as `impeccable@bionic` (so it needs a marketplace entry) while
# declaring it a plugin.json dependency would make it a third mandatory core
# dep, which D-B ruled out. Neither manifest is an independent authority
# (ownership table, wave-03 spec §Design). Version constraints are deliberately ABSENT from
# plugin.json: the CLI cannot resolve a same-marketplace, version-constrained
# dependency — reproduced on a fresh scratch config with a confirmed-existing
# matching upstream tag (record/epic-17-w3/probe-ac6-marketplace-entry.md) — so
# the constraint lives ONLY in this table; a version key reappearing in
# plugin.json is a silent regression to the broken shape, not a harmless
# duplicate.
#
# manifest_agreement_report prints one problem line per disagreement, either
# direction, or nothing when the three parties agree. It is driven against the
# real manifests for the golden case and against a mutated TMP copy for the
# mutation-and-restore proof below — the real files are never written to.

MANIFEST_JSON_HELPER="$TMP/manifest_agreement.py"
cat > "$MANIFEST_JSON_HELPER" <<'PYEOF'
import json, sys

plugin_path, marketplace_path = sys.argv[1], sys.argv[2]
core_json, native_json = sys.argv[3], sys.argv[4]
core = json.loads(core_json)      # {name: mechanism}  class == core
table = json.loads(native_json)   # {name: mechanism}  kind  == native (superset of core)
plugin = json.load(open(plugin_path))
mkt = json.load(open(marketplace_path))

problems = []

deps = {d.get('name'): d for d in plugin.get('dependencies', []) if isinstance(d, dict)}
for name in core:
    if name not in deps:
        problems.append("plugin.json missing dependency: %s" % name)
for name, d in deps.items():
    if name not in core:
        problems.append("plugin.json has dependency with no core row: %s" % name)
        continue
    if d.get('marketplace') != 'bionic':
        problems.append("plugin.json %s marketplace != bionic: %r" % (name, d.get('marketplace')))
    if 'version' in d:
        problems.append("plugin.json %s carries a version key: %r" % (name, d.get('version')))

entries = {p.get('name'): p for p in mkt.get('plugins', [])}
for name, url in table.items():
    if name not in entries:
        problems.append("marketplace.json missing entry: %s" % name)
        continue
    src = entries[name].get('source', {})
    entry_url = src.get('url', '') if isinstance(src, dict) else ''
    if entry_url != url:
        problems.append("marketplace.json %s source_url mismatch: table=%r entry=%r" % (name, url, entry_url))
    # Every url-sourced entry carries a commit pin. This is the supply-chain
    # claim — "the code installed is the code that was reviewed" — and it is
    # NOT the version constraint the table owns; an unpinned entry tracks
    # whatever HEAD the default branch is at install time, and these
    # dependencies ship skills and agents whose text Claude reads and acts on.
    # Pinning one and not the other is the shape this asserts away.
    if not str(src.get('sha', '') if isinstance(src, dict) else '').strip():
        problems.append("marketplace.json %s is url-sourced with no sha pin" % name)
for name, p in entries.items():
    if name != 'bionic' and name not in table and isinstance(p.get('source'), dict):
        problems.append("marketplace.json has url-sourced entry with no table row: %s" % name)

print('\n'.join(problems))
PYEOF

names_to_json() {  # <newline-separated names> — {name: mechanism}
  local names="$1"
  python3 -c "
import json, sys
names = sys.argv[1].split()
print(json.dumps({n: sys.argv[2 + i] for i, n in enumerate(names)}))
" "$names" $(while IFS= read -r n; do [ -n "$n" ] && deps_run -- dep_field "$n" mechanism; done <<< "$names")
}

CORE_NAMES="$(deps_run -- dep_names_class core | LC_ALL=C sort)"
NATIVE_NAMES="$(deps_run -- dep_names_kind native | LC_ALL=C sort)"
CORE_JSON="$(names_to_json "$CORE_NAMES")"
NATIVE_JSON="$(names_to_json "$NATIVE_NAMES")"

# The two sets are not the same set, and the difference is exactly impeccable.
expect_eq "the marketplace-rendered set is the native-kind set, core plus impeccable" \
  "agent-skills impeccable superpowers" "$(printf '%s' "$NATIVE_NAMES" | tr '\n' ' ' | sed 's/ $//')"

manifest_agreement_report() {  # <plugin.json path> <marketplace.json path>
  python3 "$MANIFEST_JSON_HELPER" "$1" "$2" "$CORE_JSON" "$NATIVE_JSON"
}

expect_eq "table, plugin.json, and marketplace.json agree in both directions (golden case)" \
  "" "$(manifest_agreement_report "$PLUGIN_JSON" "$MARKETPLACE_JSON")"

echo ""
echo "=== Group 19: mutation-and-restore — both agreement pins actually discriminate ==="
#
# A pin that stays green on a mutated copy proves nothing (fixtures-can-pin-
# away-the-test). Mutations are applied to TMP copies; the shipped manifests
# are checksummed before and after and asserted byte-identical at the end.

MANIFEST_CKSUM_BEFORE="$(shasum "$PLUGIN_JSON" "$MARKETPLACE_JSON" 2>/dev/null)"

# Mutation 1: break a source_url in a marketplace.json copy.
MUT_MKT="$TMP/marketplace.mutant.json"
python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
for p in d['plugins']:
    if p.get('name') == 'superpowers':
        p['source']['url'] = 'https://example.invalid/not-superpowers.git'
json.dump(d, open('$MUT_MKT', 'w'))
"
MUT1_REPORT="$(manifest_agreement_report "$PLUGIN_JSON" "$MUT_MKT")"
expect_true "mutation 1 (broken source_url) makes the agreement pin non-empty" test -n "$MUT1_REPORT"
expect_match "mutation 1 is reported as a source_url mismatch on superpowers" \
  "*superpowers source_url mismatch*" "$MUT1_REPORT"

# Mutation 2: re-add a version key in a plugin.json copy.
MUT_PLUGIN="$TMP/plugin.mutant.json"
python3 -c "
import json
d = json.load(open('$PLUGIN_JSON'))
for dep in d['dependencies']:
    if dep.get('name') == 'superpowers':
        dep['version'] = '^6.3.0'
json.dump(d, open('$MUT_PLUGIN', 'w'))
"
MUT2_REPORT="$(manifest_agreement_report "$MUT_PLUGIN" "$MARKETPLACE_JSON")"
expect_true "mutation 2 (reintroduced version key) makes the agreement pin non-empty" test -n "$MUT2_REPORT"
expect_match "mutation 2 is reported as a version key on superpowers" \
  "*superpowers carries a version key*" "$MUT2_REPORT"

# Mutation 3: drop a sha pin in a marketplace.json copy. The asymmetry this
# catches is the one that actually shipped — superpowers pinned, agent-skills
# tracking the default branch's HEAD — so the pin has to be proven able to see
# an ABSENT sha, not merely a wrong one.
MUT_MKT_NOSHA="$TMP/marketplace.nosha.json"
python3 -c "
import json
d = json.load(open('$MARKETPLACE_JSON'))
for p in d['plugins']:
    if p.get('name') == 'agent-skills':
        p['source'].pop('sha', None)
json.dump(d, open('$MUT_MKT_NOSHA', 'w'))
"
MUT3_REPORT="$(manifest_agreement_report "$PLUGIN_JSON" "$MUT_MKT_NOSHA")"
expect_true "mutation 3 (sha pin removed) makes the agreement pin non-empty" test -n "$MUT3_REPORT"
expect_match "mutation 3 is reported as a missing sha pin on agent-skills" \
  "*agent-skills is url-sourced with no sha pin*" "$MUT3_REPORT"

expect_eq "the shipped plugin.json and marketplace.json are byte-identical to before the mutations" \
  "$MANIFEST_CKSUM_BEFORE" "$(shasum "$PLUGIN_JSON" "$MARKETPLACE_JSON" 2>/dev/null)"

echo ""
echo "=== Group 20: the sha ACTUATES the version the constraint JUDGES (C-4) ==="
#
# marketplace.json's `sha` and the table's version constraint were treated as
# answering different questions on different clocks. They do not. The sha is
# HONOURED by the CLI — measured, not assumed: an isolated-config install of a
# marketplace entry pinned to superpowers v6.2.0 (3dcbd5c…) landed 6.2.0 and not
# HEAD's 6.3.0 (record/epic-17-w3/critic-report.md, C-3). So the sha DETERMINES
# the version that arrives through bionic's marketplace, and the table's
# constraint JUDGES that same version, and doctor renders the verdict. They are
# an actuator and a judge on one quantity, and nothing joined them: a future sha
# bump could ship a dependency that bionic's own doctor immediately reports as
# violating bionic's own constraint, with this suite green.
#
# WHAT THIS PIN IS, HONESTLY. It is a TRIPWIRE, not a resolver. Resolving a sha
# to a version means reaching the network, which this suite must not do, so the
# known pairs live below as fixture data with their provenance. The pin has two
# halves and the first is what does the work: every sha in marketplace.json must
# appear in the table. Bump a sha and the fixture goes stale, which fails, which
# forces a human to re-derive the pair — and re-deriving it is what runs the
# constraint check on the new version. The tripwire cannot catch a bump; it can
# only make one impossible to land silently.
#
# PROVENANCE of each pair, from the critic's measurements:
#   b36e082 -> superpowers 6.3.0   `git ls-remote https://github.com/obra/superpowers.git HEAD`
#                                  + cache path ~/.claude/plugins/cache/bionic/superpowers/6.3.0
#   df1edb2 -> agent-skills 0.6.7  `git ls-remote https://github.com/addyosmani/agent-skills.git HEAD`
#                                  + cache path ~/.claude/plugins/cache/bionic/agent-skills/0.6.7
#   3dcbd5c -> superpowers 6.2.0   the discriminating install under an isolated
#                                  CLAUDE_CONFIG_DIR; installed_plugins.json read back
#                                  {"version":"6.2.0","gitCommitSha":"3dcbd5c…"}
#   5a149f3 -> impeccable 4.1.1    wave-06 S3, derived offline the same way a
#                                  reviewer would: `git ls-remote --tags
#                                  https://github.com/pbakaus/impeccable.git`
#                                  → skill-v4.1.1 is the newest skill tag
#                                  (peeled commit 5a149f3, "Release: skill
#                                  v4.1.1"), and `git show
#                                  skill-v4.1.1^{commit}:.claude-plugin/plugin.json`
#                                  declares "version": "4.1.1". The pin is that
#                                  commit rather than the branch head
#                                  (f88b2837 on 2026-08-20) so the entry names
#                                  a release, not whatever main happens to hold.
SHA_VERSION_PAIRS='superpowers|b36e0829c6d0140e93cfef2ca599b1b07d4a7797|6.3.0
agent-skills|df1edb2e05487d0aa6d93c747141e0aed1187f25|0.6.7
impeccable|5a149f3fdb1b5793f10567233b1dcab98fc305fd|4.1.1
superpowers|3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9|6.2.0'

sha_to_version() {  # <plugin> <sha> -> the known version, or empty
  local want="$1|$2" row
  while IFS= read -r row; do
    case "$row" in "${want}|"*) printf '%s' "${row##*|}"; return 0 ;; esac
  done <<< "$SHA_VERSION_PAIRS"
  return 1
}

while IFS= read -r dep_name; do
  [ -n "$dep_name" ] || continue
  MKT_SHA="$(jq -r --arg n "$dep_name" \
    '[.plugins[] | select(.name == $n) | .source.sha // ""] | first // ""' "$MARKETPLACE_JSON")"
  KNOWN_VERSION="$(sha_to_version "$dep_name" "$MKT_SHA" || true)"
  DEP_CONSTRAINT="$(deps_run -- dep_field "$dep_name" constraint)"

  expect_true "${dep_name}: marketplace.json's sha is one this suite has a version for" \
    test -n "$KNOWN_VERSION"
  expect_eq "${dep_name}: the version that sha installs satisfies the table's ${DEP_CONSTRAINT}" \
    "ok" "$(deps_run -- dep_constraint_verdict "$DEP_CONSTRAINT" "${KNOWN_VERSION:-0.0.0}")"
done <<< "$(deps_run -- dep_names_kind native)"

# The judge is live, not decorative: the third fixture pair is a REAL sha that
# installs a version the table would reject. Without this arm, a pair table
# whose versions all happened to satisfy everything would look identical to one
# that was never checked.
expect_eq "a sha that installs superpowers 6.2.0 would be caught (the check discriminates)" \
  "violation" \
  "$(deps_run -- dep_constraint_verdict "$(deps_run -- dep_field superpowers constraint)" \
      "$(sha_to_version superpowers 3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9)")"

# And the first half is non-vacuous: an unknown sha must fail the lookup rather
# than fall through to some default.
expect_false "an unrecorded sha has no version, so a bump cannot pass silently" \
  sha_to_version superpowers 0000000000000000000000000000000000000000

# R-2. COVERAGE, stated over marketplace.json itself.
#
# The loop above walks the dependency table's lane-3a names, so it reaches
# marketplace.json only sideways — through Group 18's reverse pin, which fails
# any url-sourced entry with no table row. That pin carries a name-based
# exemption for the literal `bionic`, which is right for the SHIPPED entry
# (`"source": "./payload"`, a string, no sha to pair) and wrong as a hole in this
# tripwire: an entry named `bionic` with an object source and any sha at all was
# checked by nothing. Measured before this loop existed — an arbitrary sha
# planted on such an entry left the suite at 137/137.
#
# A22's invariant is unconditional: every sha in marketplace.json appears in the
# pair table. So the coverage assertion iterates marketplace.json's own entries,
# and exempts no name. An object source with a missing or empty sha fails here
# too, which is Group 18's claim from the other side — the two arms disagreeing
# is itself something worth failing on.
MKT_OBJ_ENTRIES="$(jq -r '.plugins[] | select((.source | type) == "object") | "\(.name)|\(.source.sha // "")"' "$MARKETPLACE_JSON")"

MKT_OBJ_SEEN=0
while IFS='|' read -r ENT_NAME ENT_SHA; do
  [ -n "$ENT_NAME" ] || continue
  MKT_OBJ_SEEN=$((MKT_OBJ_SEEN + 1))
  expect_true "marketplace.json entry '${ENT_NAME}' carries a sha this suite has a version for" \
    sha_to_version "$ENT_NAME" "$ENT_SHA"
done <<< "$MKT_OBJ_ENTRIES"

# The loop is only a tripwire if it actually walked the file. A jq that silently
# selected nothing would leave every assertion above unexecuted and the group
# green, which is the failure mode this whole group exists to prevent.
expect_eq "the coverage loop walked every url-sourced entry in marketplace.json" \
  "$(jq '[.plugins[] | select((.source | type) == "object")] | length' "$MARKETPLACE_JSON")" \
  "$MKT_OBJ_SEEN"
expect_true "and there was more than one of them (the count arm is not comparing 0 to 0)" \
  test "$MKT_OBJ_SEEN" -ge 2

echo ""
echo "=== Group 21: the suite is registered in tests/run.sh by name ==="
#
# tests/*.test.sh is NOT globbed by the runner — an unregistered suite is a
# silent false green (tests/run.sh:39-42 records the last time that happened).

expect_true "tests/run.sh names plugin-lib.test.sh" \
  grep -q 'run "plugin-lib.test.sh" bash tests/plugin-lib.test.sh' "${REPO}/tests/run.sh"


echo ""
echo "=== Group R: detect_plugin_root — the CLI's registry is the only oracle (W5 4/4, AC-5) ==="
#
# WHY THIS FUNCTION EXISTS. Payload-native scripts are invoked from a model's own shell as
# often as from a registered command file, and `${CLAUDE_PLUGIN_ROOT}` is set only in the
# latter. The old spelling papered over that with `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}`,
# which resolves — silently, and to a bootstrap-era copy that may be an older build than the
# plugin the CLI actually loaded. A wrong-version hook that runs is worse than no hook: it
# reports on a doctrine nobody is following.
#
# So the root is RESOLVED, once per session at Patrol arming, out of the record the CLI
# itself loads from: ~/.claude/plugins/installed_plugins.json. Ratified 2026-08-19 (design
# ledger D-B, "the reliable source of truth we control" — with the correction that the
# registry is CLI-owned, and reliable BECAUSE it is).
#
# EVERY FAILURE IS LOUD AND EVERY FAILURE IS EMPTY-HANDED. There is no fallback path in
# this function, by design: the one thing it must never do is hand back a plausible
# directory it did not read out of the registry.
#
# The chain is detect_plugin_registered's, SHARED not copied — one expression naming the
# registry file, so a machine whose config dir moves cannot have the two answer about
# different files.

root_run() {  # <env-assignments...> -- [args] ; sets R_OUT, R_ERR, R_ST
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  R_OUT=$(env -i HOME="$TMP/home" PATH="${R_PATH:-$BASE_BIN}" "${envs[@]}" \
    bash -c '. "$1"; shift; detect_plugin_root "$@"' _ "$DETECT_SH" "$@" 2>"$TMP/root.err")
  R_ST=$?
  R_ERR=$(cat "$TMP/root.err")
}

# A registry whose installPath points at a tree that actually exists — the ordinary machine.
R_REAL="$TMP/real-plugin-root"
mkdir -p "$R_REAL/hooks" "$R_REAL/scripts/lib"
R_CH="$TMP/ch-root-ok"; mkdir -p "$R_CH/plugins"
cat > "$R_CH/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "superpowers@claude-plugins-official": [
      { "scope": "user", "installPath": "/elsewhere/superpowers", "version": "6.3.0" }
    ],
    "bionic@bionic": [
      { "scope": "user", "installPath": "${R_REAL}", "version": "0.1.0" }
    ]
  }
}
JSON

root_run BIONIC_CLAUDE_HOME="$R_CH" --
expect_eq "detect_plugin_root: a registered bionic resolves to its installPath" "$R_REAL" "$R_OUT"
expect_eq "…exit 0" "0" "$R_ST"
expect_eq "…and says nothing on stderr on the success path" "" "$R_ERR"

# The neighbouring entry is not bionic's, and a substring match would take it.
R_CH_NEAR="$TMP/ch-root-near"; mkdir -p "$R_CH_NEAR/plugins"
cat > "$R_CH_NEAR/plugins/installed_plugins.json" <<JSON
{ "version": 2, "plugins": {
  "bionic-extras@somewhere": [ { "installPath": "/wrong/one", "version": "9.9.9" } ] } }
JSON
root_run BIONIC_CLAUDE_HOME="$R_CH_NEAR" --
expect_eq "detect_plugin_root: 'bionic-extras' is not bionic (name matched whole, not by prefix)" \
  "1" "$R_ST"
expect_eq "…and hands back nothing at all" "" "$R_OUT"

# ---- every failure arm: loud, named fix, empty stdout, no $HOME/.claude anywhere ----
root_run BIONIC_CLAUDE_HOME="$TMP/ch-nonexistent" --
expect_eq "detect_plugin_root: no registry file -> refusal (exit 1)" "1" "$R_ST"
expect_eq "…and prints NOTHING on stdout, so a caller cannot use a half-answer" "" "$R_OUT"
expect_match "…and names the fix" "*claude plugin install bionic@bionic*" "$R_ERR"
expect_no_match "…and never re-offers the retired \${CLAUDE_PLUGIN_ROOT:-\$HOME/.claude} fallback" \
  "*CLAUDE_PLUGIN_ROOT:-\$HOME*" "$R_ERR"

root_run BIONIC_CLAUDE_HOME="$CH_EMPTY" --
expect_eq "detect_plugin_root: registry with no bionic entry -> refusal" "1" "$R_ST"
expect_match "…named as not-installed rather than as a parse problem" "*not installed*" "$R_ERR"

root_run BIONIC_CLAUDE_HOME="$CH_MALFORMED" --
expect_eq "detect_plugin_root: unparseable registry -> refusal, never a guess" "1" "$R_ST"
expect_eq "…and still hands back nothing" "" "$R_OUT"

# The stale-install hazard AC-5 names: the registry says a tree is there and it is not.
R_CH_GONE="$TMP/ch-root-gone"; mkdir -p "$R_CH_GONE/plugins"
cat > "$R_CH_GONE/plugins/installed_plugins.json" <<JSON
{ "version": 2, "plugins": {
  "bionic@bionic": [ { "installPath": "$TMP/deleted-by-someone", "version": "0.1.0" } ] } }
JSON
root_run BIONIC_CLAUDE_HOME="$R_CH_GONE" --
expect_eq "detect_plugin_root: a registered path that is GONE is a refusal, not a return" \
  "1" "$R_ST"
expect_match "…and names the path it could not find" "*deleted-by-someone*" "$R_ERR"

# ---- the no-jq lane resolves the same path, not an unknown ----
R_PATH="$NOJQ_BIN" root_run BIONIC_CLAUDE_HOME="$R_CH" --
expect_eq "detect_plugin_root: no jq on PATH still resolves, by the grep lane" "$R_REAL" "$R_OUT"
unset R_PATH

# ---- the chain is honoured, and it is the SAME chain detect_plugin_registered walks ----
root_run CLAUDE_CONFIG_DIR="$R_CH" --
expect_eq "detect_plugin_root: CLAUDE_CONFIG_DIR is honoured when BIONIC_CLAUDE_HOME is not set" \
  "$R_REAL" "$R_OUT"
root_run BIONIC_INSTALLED_PLUGINS_FILE="$R_CH/plugins/installed_plugins.json" \
         BIONIC_CLAUDE_HOME="$TMP/ch-nonexistent" --
expect_eq "detect_plugin_root: the file override wins over the config dir, as it does for registration" \
  "$R_REAL" "$R_OUT"
expect_eq "…and detect_plugin_registered answers from that same overridden file" \
  "plugin:registered=yes" \
  "$(detect_run BIONIC_INSTALLED_PLUGINS_FILE="$R_CH/plugins/installed_plugins.json" \
       BIONIC_CLAUDE_HOME="$TMP/ch-nonexistent" -- detect_plugin_registered)"

# ---- read-only, like every other fact here ----
expect_eq "detect_plugin_root writes nothing into the config dir it read" \
  "installed_plugins.json" "$(ls "$R_CH/plugins")"

echo ""
echo "=== Group T: detect_legacy_hook_files — the other thing the installer left (W5 RV-5) ==="
#
# WHAT THIS SEES THAT NOTHING ELSE DID. The retired installer copied every hooks/*.sh into
# the CLI's own hooks directory. `detect_legacy_channel_hooks` already counts the
# REGISTRATIONS those copies were wired through, in settings.json — but a machine can be
# cleaned of every registration and still carry the FILES, and the two states look identical
# in the report. The files are the half a person can see in a directory listing and the half
# the report never mentioned, which is exactly the shape of a diagnosis nobody trusts.
#
# PAYLOAD-SIDE NAMES ONLY, the same rule `detect_installed_agent_copies` states: a .sh in
# that directory that the payload does not ship is somebody's OWN hook, and counting it would
# report a person's work as bionic's leftover. It is the strictly safer error too — this
# count is read by a human deciding whether to delete things.
#
# `unknown` WHERE THE COMPARISON CANNOT BE MADE, and it is a real state, not a defensive one:
# a payload with no hooks/ directory gives nothing to match names against, and answering `0`
# there would report "nothing left behind" on a machine nobody looked at.

T_PAY="$TMP/legacy-hooks-payload"; mkdir -p "$T_PAY/hooks"
for h in protect-main.sh landing-gate.sh stop-guard.sh; do
  printf '#!/bin/bash\nexit 0\n' > "$T_PAY/hooks/$h"
done

# A CLI home carrying three of the payload's names plus one that is not bionic's at all.
T_CH_PRESENT="$TMP/legacy-hooks-ch-present"; mkdir -p "$T_CH_PRESENT/hooks"
for h in protect-main.sh landing-gate.sh my-own-hook.sh; do
  printf '#!/bin/bash\nexit 0\n' > "$T_CH_PRESENT/hooks/$h"
done

T_CH_CLEAN="$TMP/legacy-hooks-ch-clean"; mkdir -p "$T_CH_CLEAN"   # no hooks/ at all
T_CH_EMPTY="$TMP/legacy-hooks-ch-empty"; mkdir -p "$T_CH_EMPTY/hooks"

t_run() {  # <claude-home> [payload-root]
  detect_run BIONIC_PLUGIN_ROOT="${2:-$T_PAY}" BIONIC_CLAUDE_HOME="$1" -- detect_legacy_hook_files
}

expect_eq "legacy hook files: two payload-named leftovers counted, the user's own hook NOT" \
  "env:legacy-hook-files count=2 path=${T_CH_PRESENT}/hooks names=landing-gate.sh,protect-main.sh" \
  "$(t_run "$T_CH_PRESENT")"
expect_eq "legacy hook files: no hooks directory at all is a clean 0, not an unknown" \
  "env:legacy-hook-files count=0 path=${T_CH_CLEAN}/hooks names=-" \
  "$(t_run "$T_CH_CLEAN")"
expect_eq "legacy hook files: an empty hooks directory is 0 too (the directory is not the fact)" \
  "env:legacy-hook-files count=0 path=${T_CH_EMPTY}/hooks names=-" \
  "$(t_run "$T_CH_EMPTY")"

# The unknown arm: nothing to match names against.
T_PAY_BARE="$TMP/legacy-hooks-payload-bare"; mkdir -p "$T_PAY_BARE"
expect_match "legacy hook files: a payload with no hooks/ cannot answer, and says so" \
  "*count=unknown*" "$(t_run "$T_CH_PRESENT" "$T_PAY_BARE")"
expect_match "…naming the reason rather than reporting a clean machine" \
  "*ships no hooks/*" "$(t_run "$T_CH_PRESENT" "$T_PAY_BARE")"

# READ-ONLY, and this one matters more than most: the line it produces is what a person
# reads before deleting files.
T_FP_BEFORE="$(find "$T_CH_PRESENT" | sort; find "$T_CH_PRESENT" -type f -exec shasum -a 256 {} \; 2>/dev/null | sort)"
t_run "$T_CH_PRESENT" >/dev/null 2>&1
T_FP_AFTER="$(find "$T_CH_PRESENT" | sort; find "$T_CH_PRESENT" -type f -exec shasum -a 256 {} \; 2>/dev/null | sort)"
expect_eq "detect_legacy_hook_files changes nothing in the directory it counts" \
  "$T_FP_BEFORE" "$T_FP_AFTER"

# One line, exit 0 — the file's contract, which Group 16 asserts for the older functions.
t_out="$(t_run "$T_CH_PRESENT")"; t_rc=$?
expect_eq "detect_legacy_hook_files exits 0" "0" "$t_rc"
expect_eq "detect_legacy_hook_files prints exactly one line" "1" "$(printf '%s\n' "$t_out" | grep -c .)"

# And it joins the sweep, so `detect_all` is still the whole of what this library knows.
T_ALL="$(detect_run BIONIC_PLUGIN_ROOT="$T_PAY" BIONIC_CLAUDE_HOME="$T_CH_PRESENT" \
  BIONIC_SHELL_RC="$RC_LEGACY" BIONIC_SETTINGS_FILE="$SET_STALE" -- detect_all)"
expect_match "detect_all emits the legacy-hook-files line" "*env:legacy-hook-files count=*" "$T_ALL"

echo ""
echo "=== Group S: detect_plugin_install_path — ONE registry parse, not two (W5 Step-6 RV-4/RV-7) ==="
#
# THE DEFECT THIS CLOSES. The Step-6 review found the registry schema being parsed in two
# places: detect_plugin_root here, and doctor.sh's own _doctor_install_path. Two parses of a
# schema we do not own is the exact shape of the duplication the ownership table exists to
# prevent — the CLI changes `installPath`, one of them is fixed, and the other keeps
# answering confidently with the old shape. Worse, detect_plugin_root had ZERO production
# callsites (RV-4): it was tests plus a pinned doctrine copy, so the copy that mattered was
# the UNPINNED one. Generalizing the pinned parse and giving it the callsite discharges both.
#
# THE SPLIT OF RESPONSIBILITY, and it is the judgment call this group pins:
#
#   detect_plugin_install_path <name>   the PARSE. Quiet — nothing on stderr, ever.
#   detect_plugin_root                  bionic's specialization. Adds the LOUD refusal.
#
# Loudness belongs to the specialization and not the parse, because loudness is a claim
# about CONSEQUENCE, not about failure. "bionic is not installed" is a catastrophe worth
# three lines of stderr and a named fix — it feeds a path something is about to execute.
# "superpowers is not installed" is an ORDINARY answer that doctor renders in a table cell
# twenty times a run, and a parse that shouted it would make `/bionic:doctor` unreadable on
# exactly the half-configured machine it exists to diagnose. The refusal text is bionic's
# own besides ("run claude plugin install bionic@bionic"), and generalizing it would print
# advice that is wrong for every other name.
#
# THE EXIT CODES CARRY WHAT THE STDERR NO LONGER DOES. detect_plugin_root reconstructs its
# three distinct refusals from them, so no message was lost in the move:
#   2 no registry file · 3 no entry, or unparseable · 4 entry present, directory gone.

ip_run() {  # <env-assignments...> -- <name> ; sets S_OUT, S_ERR, S_ST
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  S_OUT=$(env -i HOME="$TMP/home" PATH="${S_PATH:-$BASE_BIN}" "${envs[@]}" \
    bash -c '. "$1"; shift; detect_plugin_install_path "$@"' _ "$DETECT_SH" "$@" 2>"$TMP/ip.err")
  S_ST=$?
  S_ERR=$(cat "$TMP/ip.err")
}

# A registry with TWO installed plugins, both pointing at trees that exist. The second one
# is the arm that matters: a bionic-only parse cannot answer about it at all.
S_SUP="$TMP/real-superpowers-root"; mkdir -p "$S_SUP/skills"
S_CH="$TMP/ch-ip-ok"; mkdir -p "$S_CH/plugins"
cat > "$S_CH/plugins/installed_plugins.json" <<JSON
{
  "version": 2,
  "plugins": {
    "superpowers@claude-plugins-official": [
      { "scope": "user", "installPath": "${S_SUP}", "version": "6.3.0" }
    ],
    "bionic@bionic": [
      { "scope": "user", "installPath": "${R_REAL}", "version": "0.1.0" }
    ]
  }
}
JSON

ip_run BIONIC_CLAUDE_HOME="$S_CH" -- superpowers
expect_eq "install_path: a NON-bionic plugin resolves by name (the whole point of RV-7)" \
  "$S_SUP" "$S_OUT"
expect_eq "…exit 0" "0" "$S_ST"
ip_run BIONIC_CLAUDE_HOME="$S_CH" -- bionic
expect_eq "install_path: and bionic resolves through the same one parse" "$R_REAL" "$S_OUT"

# THE SPECIALIZATION IS THE SAME ANSWER. Not "agrees today" — detect_plugin_root is
# implemented as this call, and this arm is what a future edit that re-forks them fails on.
root_run BIONIC_CLAUDE_HOME="$S_CH" --
expect_eq "install_path: detect_plugin_root returns exactly detect_plugin_install_path bionic" \
  "$S_OUT" "$R_OUT"

# ---- QUIET is a contract, because doctor calls this once per dependency row ----
ip_run BIONIC_CLAUDE_HOME="$S_CH" -- not-a-plugin
expect_eq "install_path: an absent plugin says NOTHING on stderr (doctor renders 20 rows)" \
  "" "$S_ERR"
expect_eq "…and hands back nothing on stdout" "" "$S_OUT"
ip_run BIONIC_CLAUDE_HOME="$TMP/ch-nonexistent" -- superpowers
expect_eq "install_path: a missing registry is quiet too" "" "$S_ERR"

# ---- the exit codes detect_plugin_root rebuilds its three refusals from ----
ip_run BIONIC_CLAUDE_HOME="$TMP/ch-nonexistent" -- bionic
expect_eq "install_path: no registry file -> 2" "2" "$S_ST"
ip_run BIONIC_CLAUDE_HOME="$CH_EMPTY" -- bionic
expect_eq "install_path: registry with no such entry -> 3" "3" "$S_ST"
ip_run BIONIC_CLAUDE_HOME="$CH_MALFORMED" -- bionic
expect_eq "install_path: unparseable registry -> 3, never a guess" "3" "$S_ST"
ip_run BIONIC_CLAUDE_HOME="$R_CH_GONE" -- bionic
expect_eq "install_path: entry present but the directory is gone -> 4" "4" "$S_ST"
expect_eq "…and 4 still hands back nothing, so a caller cannot execute out of it" "" "$S_OUT"

# ---- whole-name match on BOTH lanes, for an arbitrary name ----
S_CH_NEAR="$TMP/ch-ip-near"; mkdir -p "$S_CH_NEAR/plugins"
cat > "$S_CH_NEAR/plugins/installed_plugins.json" <<JSON
{ "version": 2, "plugins": {
  "superpowers-extras@somewhere": [ { "installPath": "/wrong/one", "version": "9.9.9" } ] } }
JSON
ip_run BIONIC_CLAUDE_HOME="$S_CH_NEAR" -- superpowers
expect_eq "install_path: 'superpowers-extras' is not 'superpowers' (jq lane)" "3" "$S_ST"
S_PATH="$NOJQ_BIN" ip_run BIONIC_CLAUDE_HOME="$S_CH_NEAR" -- superpowers
expect_eq "install_path: …nor on the no-jq lane, which is where a prefix match is easiest to write" \
  "3" "$S_ST"
S_PATH="$NOJQ_BIN" ip_run BIONIC_CLAUDE_HOME="$S_CH" -- superpowers
expect_eq "install_path: the no-jq lane resolves a non-bionic name too" "$S_SUP" "$S_OUT"
unset S_PATH

# ---- read-only, like every other fact in this file ----
expect_eq "install_path writes nothing into the config dir it read" \
  "installed_plugins.json" "$(ls "$S_CH/plugins")"

# ---- the doctrine seed stays a LITERAL, and stays derivable from the general program ----
#
# tests/dispatch-spans.test.sh §5i reads DETECT_PLUGIN_ROOT_JQ out of this file with a `sed`
# that requires a single-quoted literal on one line, and demands it byte-identical inside
# SKILL.md. That mechanism must survive generalization untouched: the doctrine has to carry
# a program a model can PASTE, and `--arg n` is not pasteable. So the constant stays
# bionic-shaped and literal — and this arm is what stops it from becoming a third parse,
# by requiring it to be the general program with $n bound to "bionic" and nothing else.
S_GEN="$(sed -n "s/^DETECT_PLUGIN_INSTALL_PATH_JQ='\(.*\)'\$/\1/p" "$DETECT_SH" | head -1)"
S_LIT="$(sed -n "s/^DETECT_PLUGIN_ROOT_JQ='\(.*\)'\$/\1/p" "$DETECT_SH" | head -1)"
expect_eq "the general jq program is readable as a one-line single-quoted literal" \
  "0" "$([ -n "$S_GEN" ] && echo 0 || echo 1)"
expect_eq "DETECT_PLUGIN_ROOT_JQ is the general program with \$n bound to \"bionic\", exactly" \
  "${S_GEN//\$n/\"bionic\"}" "$S_LIT"

echo ""
echo "=== Group W: detect_registry_sha_lag — the installed build vs the repo tip (W5 critic C-6) ==="
#
# THE DEFECT THIS CLOSES. Twice in this epic the machine ran an installed payload built
# from a commit the working tree had long since passed — F-1 at Step 5, and again at the
# Step-6 tip, 20 files apart. Both times every wall, every suite and the doctor itself
# reported a healthy machine, because nothing on it compares the two. The registry already
# records which commit the install came from (`gitCommitSha`); the repo knows its own tip.
# The whole fix is to ask.
#
# WHAT IT IS NOT. Not a verdict, not an exit code, and not a repair — the same posture the
# agent-files line takes. A user who installed from the public feed has no repo here at
# all and reads `unknown`, which is the correct answer and not a complaint. This matters to
# exactly one machine shape — the one developing the plugin it is running — and for that
# shape it is the difference between "my fix did not work" and "my fix is not installed".
#
# HERMETIC AND REAL: real `git init` fixtures, real commits, a real registry file. The
# question is about two live records agreeing, and a stubbed git would be a seam standing
# in for the very value under test.

W_BIN="$TMP/bin-git"; mkdir -p "$W_BIN"; cp -R "$BASE_BIN/." "$W_BIN/" 2>/dev/null
for real in git; do
  p="$(command -v "$real" 2>/dev/null)" && ln -sf "$p" "${W_BIN}/${real}" 2>/dev/null
done

sha_run() {  # <cwd> <env-assignments...> -- ; sets W_OUT
  local cwd="$1"; shift
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  W_OUT=$(env -i HOME="$TMP/home" PATH="$W_BIN" "${envs[@]}" \
    bash -c 'cd "$1" || exit 9; . "$2"; detect_registry_sha_lag' _ "$cwd" "$DETECT_SH" 2>&1)
}

w_registry() {  # <config-home> <sha-or-empty>
  mkdir -p "$1/plugins"
  if [ -n "${2:-}" ]; then
    cat > "$1/plugins/installed_plugins.json" <<JSON
{ "version": 2, "plugins": { "bionic@bionic": [
  { "scope": "user", "installPath": "/somewhere/bionic/0.1.0", "version": "0.1.0",
    "gitCommitSha": "$2" } ] } }
JSON
  else
    cat > "$1/plugins/installed_plugins.json" <<JSON
{ "version": 2, "plugins": { "bionic@bionic": [
  { "scope": "user", "installPath": "/somewhere/bionic/0.1.0", "version": "0.1.0" } ] } }
JSON
  fi
}

# A repo with two commits, so "the tip" and "a commit this repo has" are different shas.
W_REPO="$TMP/w-repo"; mkdir -p "$W_REPO"
( cd "$W_REPO" \
  && git init -q . \
  && git config user.email t@t && git config user.name t \
  && echo one > f && git add f && git commit -qm one \
  && echo two > f && git commit -qam two ) >/dev/null 2>&1
W_TIP=$( cd "$W_REPO" && git rev-parse HEAD )
W_PREV=$( cd "$W_REPO" && git rev-parse HEAD~1 )
expect_eq "fixture: the repo has two distinct commits" "0" \
  "$([ -n "$W_TIP" ] && [ -n "$W_PREV" ] && [ "$W_TIP" != "$W_PREV" ] && echo 0 || echo 1)"

# ---- match: the installed build IS the tip ----
W_CH="$TMP/w-ch-match"; w_registry "$W_CH" "$W_TIP"
sha_run "$W_REPO" BIONIC_CLAUDE_HOME="$W_CH" --
expect_match "an install at the repo tip reads match" "*state=match*" "$W_OUT"
expect_match "…and shows the sha it agreed on" "*registry=${W_TIP}*" "$W_OUT"
expect_eq "…on exactly one line" "1" "$(printf '%s\n' "$W_OUT" | grep -c .)"

# ---- lag: the installed build is a commit this repo has, but not the tip ----
#
# THE F-1 SHAPE, exactly: an install taken before the last few commits landed.
W_CH="$TMP/w-ch-lag"; w_registry "$W_CH" "$W_PREV"
sha_run "$W_REPO" BIONIC_CLAUDE_HOME="$W_CH" --
expect_match "an install behind the tip reads lag" "*state=lag*" "$W_OUT"
expect_match "…naming the installed sha" "*registry=${W_PREV}*" "$W_OUT"
expect_match "…and the tip it is behind" "*repo=${W_TIP}*" "$W_OUT"

# ---- not-in-repo: the recorded sha is not a commit here ----
#
# A DIFFERENT ANSWER FROM `lag`, and the distinction is the actionable one: lag means
# reinstall, this means the installed build came from somewhere else entirely.
W_CH="$TMP/w-ch-foreign"; w_registry "$W_CH" "0123456789abcdef0123456789abcdef01234567"
sha_run "$W_REPO" BIONIC_CLAUDE_HOME="$W_CH" --
expect_match "a sha this repo does not have reads not-in-repo" "*state=not-in-repo*" "$W_OUT"

# ---- unknown, with a named cause, on each way of not being able to tell ----
W_NOTREPO="$TMP/w-not-a-repo"; mkdir -p "$W_NOTREPO"
W_CH="$TMP/w-ch-unknown"; w_registry "$W_CH" "$W_TIP"
sha_run "$W_NOTREPO" BIONIC_CLAUDE_HOME="$W_CH" --
expect_match "outside a git repository the answer is unknown" "*state=unknown*" "$W_OUT"
expect_match "…with a named cause, never a bare shrug" "*cause=*repositor*" "$W_OUT"

W_CH="$TMP/w-ch-nosha"; w_registry "$W_CH" ""
sha_run "$W_REPO" BIONIC_CLAUDE_HOME="$W_CH" --
expect_match "a registry entry with no gitCommitSha reads unknown" "*state=unknown*" "$W_OUT"
expect_match "…and says the record carries no sha, naming the field" \
  "*cause=*no gitCommitSha*" "$W_OUT"

W_CH="$TMP/w-ch-absent"; mkdir -p "$W_CH/plugins"
sha_run "$W_REPO" BIONIC_CLAUDE_HOME="$W_CH" --
expect_match "no registry file at all reads unknown" "*state=unknown*" "$W_OUT"

# ---- read-only, and exit 0, like every other fact in this file ----
W_FP_BEFORE="$(find "$W_REPO" "$TMP/w-ch-lag" -type f 2>/dev/null | sort)"
W_CH="$TMP/w-ch-lag"
env -i HOME="$TMP/home" PATH="$W_BIN" BIONIC_CLAUDE_HOME="$W_CH" \
  bash -c 'cd "$1" || exit 9; . "$2"; detect_registry_sha_lag' _ "$W_REPO" "$DETECT_SH" >/dev/null 2>&1
expect_eq "detect_registry_sha_lag exits 0 even on the lag path" "0" "$?"
expect_eq "…and adds no file to the repo or the config dir it read" \
  "$W_FP_BEFORE" "$(find "$W_REPO" "$TMP/w-ch-lag" -type f 2>/dev/null | sort)"

echo ""
echo "=== Group U: the doctrine block appears ONCE (W5 critic C-4) ==="
#
# 6cc4f38 left a second, orphaned copy of the 24-line "installed plugin root" doctrine
# block above THE PARSE — in the very commit whose message forbids duplicating a doctrine.
# Nothing caught it, because a comment block has no behaviour to test. It is worth an arm
# anyway: this file's whole argument is that one schema gets one reading, and a reader who
# meets the doctrine twice cannot tell which function it governs.
#
# COUNTED, not diffed: the header line is the cheapest thing that is exactly as unique as
# the block it opens, and a count is the assertion — "once" — stated directly.
U_BLOCK_HEADER='─── The installed plugin root ───'
U_COUNT=$(/usr/bin/grep -cF -- "$U_BLOCK_HEADER" "$DETECT_SH")
expect_eq "the installed-plugin-root doctrine block opens exactly once in detect.sh" \
  "1" "$U_COUNT"

# The same question asked of the sentence deepest inside the block, so a future duplication
# that renamed the header would still be caught by the body.
U_BODY_COUNT=$(/usr/bin/grep -cF -- "No fallback exists anywhere in" "$DETECT_SH")
expect_eq "…and its closing contract sentence appears exactly once too" "1" "$U_BODY_COUNT"

echo ""
echo "=== Group V: the registry's truth is two-path, and detect.sh says so (W5 critic C-5) ==="
#
# THE CLAIM THAT WAS TOO STRONG. The doctrine block above detect_plugin_root justifies the
# registry as oracle by saying it is "the same record the CLI itself loads from". W5's S7
# measured that: on a DIRECTORY-source marketplace the CLI reads the marketplace's source
# tree and never opens the cache the registry names. The registry's ANSWER is still right —
# the cache was written from that source at install — but the reason offered is not the
# reason, and the difference is exactly what a user chasing a stale root has to know.
#
# Both halves are pinned, because the disclosure is only useful as a PAIR: the condition
# under which the two paths diverge, and the fact that makes them agree anyway.
# Case-INSENSITIVE on the condition term alone: this file writes its emphasis in capitals
# ("a DIRECTORY-SOURCE MARKETPLACE"), and which words are shouted is a style choice that a
# later edit is free to make differently. The disclosure is what is pinned, not the shouting.
V_DOCTRINE_HITS=$(/usr/bin/grep -ci "directory-source marketplace" "$DETECT_SH")
expect_eq "detect.sh discloses the directory-source condition" \
  "0" "$([ "$V_DOCTRINE_HITS" -ge 1 ] && echo 0 || echo 1)"
expect_eq "…and names what keeps the two paths in agreement" \
  "0" "$(/usr/bin/grep -q "as of the last (re)install" "$DETECT_SH" && echo 0 || echo 1)"
expect_eq "…and says the git-source feed is right by construction" \
  "0" "$(/usr/bin/grep -q "right by construction" "$DETECT_SH" && echo 0 || echo 1)"

echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
