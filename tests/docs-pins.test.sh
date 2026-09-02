#!/bin/bash
# DOCS PINS — one file, one section per slice that owns a doc-text agreement pin
# (spec AC-36 for RELEASE; WALLS and SCHED append their own numbered sections here
# in later slices of this wave — this file is shared harness, not RELEASE-owned).
#
# SECTION 1 — RELEASE (spec AC-36, `.bionic/docs/plans/wave-bionic-1.4.0-update/`).
# WHAT THIS SECTION OWNS. The "version pair": `payload/.claude-plugin/plugin.json`'s
# `.version` field is the single owner of the plugin's version number, and
# `payload/commands/help.md` restates it in its opening line, `bionic <version>
# (installed)`. That restatement used to be read from disk at runtime (so it could
# not drift), then baked at render time by `agents-src/render.sh` substituting
# `@@PLUGIN_VERSION@@` in `agents-src/templates/commands/help.md.tmpl` (see that
# script's own "WHY THE VERSION IS BAKED AT RENDER TIME" note). The suite-level pin
# that enforced this — `version-ssot.test.sh` — was deleted at 8582861 (epic-18
# wave-03, MEDIUM/LOW-reliability cut) and nothing replaced it: render.sh --check
# still CATCHES a stale pair when run, but nothing in tests/run.sh's roster ever
# runs it for that reason, so a hand-edit to either half of the pair goes undetected
# by `bash tests/run.sh`. This section is that replacement, scoped to the pair only
# (render.sh --check's five other unrelated agreement classes are not this section's
# concern; assertion 7 below calls it directly rather than re-implementing it).
#
# ANTI-VACUITY, per tests/diagrams.test.sh's differential-control pattern (that
# suite's §G): a pin that only ever reads two already-agreeing files could be
# vacuously true by extractor bug (e.g. a regex that always reports "match"). So
# this section also re-runs its own extractors against DOCTORED copies — a help.md
# with a different version, a plugin.json with a different version — and asserts
# the SAME extractors now report a mismatch. That is proven fresh on every run
# rather than taken on faith from a report.
#
# HERMETIC. Reads the two committed files and the template by path; doctored copies
# live under a mktemp dir removed on exit. Nothing in the repo tree is mutated.
# The one subprocess this section shells out to, `agents-src/render.sh --check`, is
# itself read-only in --check mode (see that script).
#
# Usage: bash tests/docs-pins.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
HELP_MD="${REPO}/payload/commands/help.md"
HELP_TMPL="${REPO}/agents-src/templates/commands/help.md.tmpl"
RENDER_SH="${REPO}/agents-src/render.sh"

command -v jq >/dev/null 2>&1 || { echo "docs-pins.test.sh: jq is required"; exit 1; }

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_ne() { if [ "$2" != "$3" ]; then ok "$1"; else no "$1" "expected values to differ, both were '$2'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# plugin_version_of <plugin.json path> -> the .version field, empty if absent/unparseable.
plugin_version_of() { jq -r '.version // empty' "$1" 2>/dev/null; }

# help_version_of <help.md path> -> the version token on the "bionic <version>
# (installed)" opening line, empty if that line is absent.
help_version_of() {
  grep -m1 -E '^bionic [^ ]+ \(installed\)$' "$1" 2>/dev/null | awk '{print $2}'
}

echo ""
echo "=== Section 1: the help version pair equals plugin.json's version (RELEASE, AC-36) ==="

PLUGIN_VERSION="$(plugin_version_of "$PLUGIN_JSON")"
if [ -n "$PLUGIN_VERSION" ]; then
  ok "1: payload/.claude-plugin/plugin.json declares a non-empty .version"
else
  no "1: payload/.claude-plugin/plugin.json declares a non-empty .version" "file: $PLUGIN_JSON"
fi

HELP_VERSION="$(help_version_of "$HELP_MD")"
if [ -n "$HELP_VERSION" ]; then
  ok "2: payload/commands/help.md opens with a 'bionic <version> (installed)' line"
else
  no "2: payload/commands/help.md opens with a 'bionic <version> (installed)' line" "file: $HELP_MD"
fi

expect_eq "3: help.md's version equals plugin.json's version" "$PLUGIN_VERSION" "$HELP_VERSION"

# The template carries the version GENERATIVELY (render.sh substitutes it from
# plugin.json), never as a hand-typed literal — a hardcoded version in the template
# would still render correctly today and drift silently the next time plugin.json
# is bumped without a matching template edit.
if grep -qF 'bionic @@PLUGIN_VERSION@@ (installed)' "$HELP_TMPL" 2>/dev/null; then
  ok "4: agents-src/templates/commands/help.md.tmpl carries @@PLUGIN_VERSION@@, not a literal"
else
  no "4: agents-src/templates/commands/help.md.tmpl carries @@PLUGIN_VERSION@@, not a literal" \
     "file: $HELP_TMPL"
fi

# --- Anti-vacuity: the same extractors must discriminate a real mismatch ---

DOCTORED_HELP="$TMP/help-mismatched.md"
sed "s/^bionic ${PLUGIN_VERSION} (installed)\$/bionic 0.0.0-mismatch (installed)/" \
  "$HELP_MD" > "$DOCTORED_HELP"
DOCTORED_HELP_VERSION="$(help_version_of "$DOCTORED_HELP")"
expect_ne "5: a doctored help.md with a different version reads as a different version (pin discriminates)" \
  "$PLUGIN_VERSION" "$DOCTORED_HELP_VERSION"

DOCTORED_PLUGIN="$TMP/plugin-mismatched.json"
jq --arg v "0.0.0-mismatch" '.version = $v' "$PLUGIN_JSON" > "$DOCTORED_PLUGIN"
DOCTORED_PLUGIN_VERSION="$(plugin_version_of "$DOCTORED_PLUGIN")"
expect_ne "6: a doctored plugin.json with a different version reads as a different version (pin discriminates)" \
  "$HELP_VERSION" "$DOCTORED_PLUGIN_VERSION"

# The construction-level guarantee behind assertion 3: a fresh render of the
# template against the committed plugin.json must byte-match the committed
# help.md. Called directly rather than assumed — render.sh --check also covers
# five other unrelated agreement classes this section does not own.
if bash "$RENDER_SH" --check >/dev/null 2>&1; then
  ok "7: agents-src/render.sh --check reports every rendered final clean"
else
  no "7: agents-src/render.sh --check reports every rendered final clean" \
     "run 'bash agents-src/render.sh --check' directly for the diff"
fi

if grep -q 'run "docs-pins.test.sh" bash tests/docs-pins.test.sh' "${REPO}/tests/run.sh"; then
  ok "8: tests/run.sh names docs-pins.test.sh"
else
  no "8: tests/run.sh names docs-pins.test.sh"
fi

echo ""
echo "========================================"
echo "docs-pins: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
