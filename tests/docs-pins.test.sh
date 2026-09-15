#!/bin/bash
# DOCS PINS — one file, one section per task that owns a doc-text agreement pin
# (spec AC-36 for RELEASE; WALLS and SCHED append their own numbered sections here
# in later tasks of this wave — this file is shared harness, not RELEASE-owned).
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
# ANTI-VACUITY, per tests/cross-gate-agreement.test.sh §N.1's differential-control pattern (that
# suite's §G): a pin that only ever reads two already-agreeing files could be
# vacuously true by extractor bug (e.g. a regex that always reports "match"). So
# this section also re-runs its own extractors against DOCTORED copies — a help.md
# with a different version, a plugin.json with a different version — and asserts
# the SAME extractors now report a mismatch. That is proven fresh on every run
# rather than taken on faith from a report.
#
# WHAT THIS SECTION STILL CANNOT SEE, and it is not a gap to be closed here (wave-01
# verification-cannot-lie, AC-17). Every assertion below is an AGREEMENT: it holds when
# every surface says the same thing. A version that is WRONG but AGREEING — a release that
# bumped nothing, or bumped every surface to the same wrong number — passes all of it, at
# every surface, in silence. That is FOG in this wave's sense: a class of defect no
# assertion here can turn red, named rather than claimed away. Its cure is canon R0.1,
# render every surface from one source (wave 02), which removes the several-surfaces
# problem instead of testing around it. This section's power is over DISAGREEMENT, and
# that is what it is claimed to have.
#
# HERMETIC. Reads the two committed files and the template by path; doctored copies
# live under a mktemp dir removed on exit. Nothing in the repo tree is mutated.
# The one subprocess this section shells out to, `agents-src/render.sh --check`, is
# itself read-only in --check mode (see that script).
#
# Usage: bash tests/docs-pins.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PLUGIN_JSON="${REPO}/payload/.claude-plugin/plugin.json"
HELP_MD="${REPO}/payload/commands/help.md"
HELP_TMPL="${REPO}/agents-src/templates/commands/help.md.tmpl"
RENDER_SH="${REPO}/agents-src/render.sh"

command -v jq >/dev/null 2>&1 || { echo "docs-pins.test.sh: jq is required"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# plugin_version_of <plugin.json path> -> the .version field, empty if absent/unparseable.
plugin_version_of() { jq -r '.version // empty' "$1" 2>/dev/null; }

# help_version_of <help.md path> -> the version token on the "bionic <version>
# (installed)" opening line, empty if that line is absent.
help_version_of() {
  grep -m1 -E '^bionic [^ ]+ \(installed\)$' "$1" 2>/dev/null | awk '{print $2}'
}

section "Section 1: the help version pair equals plugin.json's version (RELEASE, AC-36)"

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

# WHOLE-LINE ERE, because the sed two lines down is `^...$`-anchored. A fixed-string
# anchor is a substring test: it survives a reindent of this line while the sed does
# not, leaving a "mutant" byte-identical to the shipped help.md — see plant 2 of
# s19c-planted-move.log, where exactly that hid a broken mutation. The version's dots
# are escaped so a literal `1.4.4` cannot match `1x4x4`.
anchor -E "$HELP_MD" "^bionic ${PLUGIN_VERSION//./\\.} \\(installed\\)$" 1
DOCTORED_HELP="$TMP/help-mismatched.md"
sed "s/^bionic ${PLUGIN_VERSION} (installed)\$/bionic 0.0.0-mismatch (installed)/" \
  "$HELP_MD" > "$DOCTORED_HELP"
DOCTORED_HELP_VERSION="$(help_version_of "$DOCTORED_HELP")"
expect_ne "5: a doctored help.md with a different version reads as a different version (pin discriminates)" \
  "$PLUGIN_VERSION" "$DOCTORED_HELP_VERSION"

anchor "$PLUGIN_JSON" '"version"' 1
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

# ── AC-17: the version is one truth rendered at MANY surfaces ────────────────
#
# Assertions 1-8 pin ONE pair, plugin.json and help.md. The version is restated at more
# surfaces than that, and until this task nothing looked at the rest: the marketplace
# manifest the CLI reads, the `payload/.version` file the plan named, and doctor's own
# header line. Each is asserted against `payload/.claude-plugin/plugin.json`, the single
# owner — and each pin carries the doctored control that proves its extractor discriminates,
# for §N.1's differential-control reason.

MARKETPLACE="${REPO}/.claude-plugin/marketplace.json"
VERSION_FILE="${REPO}/payload/.version"
DOCTOR_SH="${REPO}/payload/scripts/doctor.sh"
DETECT_SH="${REPO}/payload/scripts/lib/detect.sh"

# version_file_of <path> -> the version on the first line, empty if the file is absent.
version_file_of() { [ -f "$1" ] || return 0; head -1 "$1" 2>/dev/null | tr -d '[:space:]'; }

# mkt_version_of <manifest> -> the bionic ENTRY's own .version, empty when it declares none.
mkt_version_of() { jq -r '(.plugins // []) | map(select(.name == "bionic")) | .[0].version // empty' "$1" 2>/dev/null; }

# mkt_source_of <manifest> -> the bionic entry's source, as a string when it is one.
mkt_source_of() { jq -r '(.plugins // []) | map(select(.name == "bionic")) | .[0].source | if type == "string" then . else empty end' "$1" 2>/dev/null; }

# detect_version_of <plugin root> -> what detect_plugin_integrity reports for that root.
# THIS IS DOCTOR'S OWN READER, not a re-implementation of it: doctor.sh:528 takes
# PLUGIN_VERSION out of this line and its header prints that value.
detect_version_of() {
  ( . "$DETECT_SH" >/dev/null 2>&1
    BIONIC_PLUGIN_ROOT="$1" detect_plugin_integrity 2>/dev/null ) \
  | sed -n 's/^plugin: version=\([^ ]*\).*/\1/p'
}

# doctor_header_line <doctor.sh> -> the one line that renders the report header.
doctor_header_line() { grep -m1 -F 'Bionic Doctor — payload' "$1" 2>/dev/null; }

# declaring_sites <root> -> "<path>|<version>" for every file in the tree that DECLARES a
# bionic version, sorted. Declaring, not mentioning: a `"version": "1.2.3"` key in the
# plugin payload or the marketplace manifest, and the `bionic <v> (installed)` line the
# help command opens with. Prose that names a past release ("the 1.4.4 fixit", of which
# there are two dozen) declares nothing and is not swept up.
#
# /usr/bin/grep, not `grep`: the shell grep on this machine is ugrep with --ignore-files,
# which skips hidden directories — and BOTH declaring sites live under one
# (`payload/.claude-plugin`, `.claude-plugin`). The same trap tests/cross-gate-agreement.test.sh
# names at its own expect_absent_ug.
#
# Candidates come from `git ls-files`, not a filesystem walk — an UNTRACKED file (scratch
# tooling debris, a stray virtualenv, anything nobody committed) is not a declaring surface
# just because it happens to sit on disk under payload/. A-48(a): the 2026-09-06 residual
# was an untracked `.venv`'s `package.json` making the census see three surfaces instead of
# two in a polluted checkout, while every committed/archived tree only ever saw two. When
# `$r` is not a git worktree at all (the sweep's own synthetic scratch-tree control below,
# built with plain `mkdir`/`cp`), there is no tracked/untracked distinction to make, so every
# file on disk is a candidate — same as before.
declaring_sites() {
  local r="$1" f v version_candidates installed_candidates
  if git -C "$r" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    version_candidates=$(cd "$r" && git ls-files -- payload .claude-plugin 2>/dev/null)
    installed_candidates=$(cd "$r" && git ls-files -- payload agents-src 2>/dev/null)
  else
    version_candidates=$(cd "$r" && find payload .claude-plugin -type f 2>/dev/null)
    installed_candidates=$(cd "$r" && find payload agents-src -type f 2>/dev/null)
  fi
  {
    for f in $version_candidates; do
      /usr/bin/grep -qE '^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+[^"]*"' "$r/$f" 2>/dev/null || continue
      v=$(/usr/bin/grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$r/$f" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
      printf '%s|%s\n' "$f" "$v"
    done
    for f in $installed_candidates; do
      /usr/bin/grep -qE '^bionic [0-9]+\.[0-9]+\.[0-9]+[^ ]* \(installed\)$' "$r/$f" 2>/dev/null || continue
      v=$(/usr/bin/grep -m1 -E '^bionic [^ ]+ \(installed\)$' "$r/$f" 2>/dev/null | awk '{print $2}')
      printf '%s|%s\n' "$f" "$v"
    done
  } | LC_ALL=C sort
}

# --- surface: payload/.version -----------------------------------------------
#
# The plan named this file as a version-bearing surface. It does not exist in this tree, so
# plugin.json is the sole FILE owner — asserted as the absence it is, with the extractor
# proven able to read one so that "empty" cannot mean "the reader is broken".
expect_empty "9: payload/.version declares nothing — plugin.json is the sole file owner" \
  "$(version_file_of "$VERSION_FILE")"
printf '%s\n' "$PLUGIN_VERSION" > "$TMP/dot-version"
expect_eq "10: …and the same extractor DOES read a .version file that exists (not a broken reader)" \
  "$PLUGIN_VERSION" "$(version_file_of "$TMP/dot-version")"

# --- surface: the marketplace manifest ---------------------------------------
#
# `.claude-plugin/marketplace.json` is what `claude plugin marketplace add` reads, and it is
# where a second version number would be most invisible: nothing renders it beside the
# plugin's own. It carries none, and it must not — its bionic entry points at `./payload`,
# whose plugin.json is the owner. The pin is therefore that this surface RESTATES NOTHING.
expect_eq "11: the marketplace manifest sources bionic from ./payload — the owner's directory" \
  "./payload" "$(mkt_source_of "$MARKETPLACE")"
expect_empty "12: …and declares no version of its own, so there is nothing here to drift" \
  "$(mkt_version_of "$MARKETPLACE")"
# The jq below selects the bionic plugin entry BY NAME, so that name is this mutation's
# anchor. TWO is the measured truth, not a slack bound: the manifest carries its own
# `"name": "bionic"` at the top level and the plugins[] entry carries a second. Either one
# moving turns this row red and says which count it found.
anchor "$MARKETPLACE" '"name": "bionic"' 2
DOCTORED_MKT="$TMP/marketplace-mismatched.json"
jq '(.plugins[] | select(.name == "bionic")) |= (. + {version: "0.0.0-mismatch"})' \
  "$MARKETPLACE" > "$DOCTORED_MKT"
expect_eq "13: …and a manifest that DID carry one is read as carrying it (pin discriminates)" \
  "0.0.0-mismatch" "$(mkt_version_of "$DOCTORED_MKT")"

# --- surface: doctor's header line -------------------------------------------
#
# `Bionic Doctor — payload <v> @ <sha>` is the version most users ever see. It is not an
# independent surface: doctor.sh:528 reads detect_plugin_integrity's `version=` and prints
# that. So the pin has two halves — the header renders the variable rather than a literal,
# and the reader behind the variable really does report plugin.json's value.
DOCTOR_HEADER="$(doctor_header_line "$DOCTOR_SH")"
expect_contains "14: doctor's header renders \${PLUGIN_VERSION}, never a typed-in version" \
  '${PLUGIN_VERSION}' "$DOCTOR_HEADER"
expect_no_regex "15: …and carries no version literal of its own" \
  '[0-9]+\.[0-9]+\.[0-9]+' "$DOCTOR_HEADER"
expect_contains "16: …and PLUGIN_VERSION comes from detect_plugin_integrity, not a second parse" \
  'PLUGIN_VERSION="${PLUGIN_FACT#plugin: version=}"' "$(cat "$DOCTOR_SH")"
expect_eq "17: …and that reader reports plugin.json's version for the shipped payload root" \
  "$PLUGIN_VERSION" "$(detect_version_of "${REPO}/payload")"
anchor "$PLUGIN_JSON" '"version": "' 1
DOCTORED_ROOT="$TMP/doctored-root"
mkdir -p "$DOCTORED_ROOT/.claude-plugin"
jq --arg v "0.0.0-mismatch" '.version = $v' "$PLUGIN_JSON" > "$DOCTORED_ROOT/.claude-plugin/plugin.json"
expect_eq "18: …and reports the DOCTORED version for a doctored root (the header would show it)" \
  "0.0.0-mismatch" "$(detect_version_of "$DOCTORED_ROOT")"

# --- the census: no FOURTH surface appears unnoticed ---------------------------
#
# The four pins above are a fixed list, and a fixed list goes stale the moment somebody adds
# a fifth surface. The sweep is the pin that notices: exactly three files in this tree
# DECLARE a bionic version, and all three agree with the owner.
#
# THE THIRD SURFACE, ADDED AT TASK 14 (E2). `payload/commands/version.md` carries the same
# baked `bionic <version> (installed)` line help.md does — see its template's "The printed
# line begins with:" block — so `/bionic:version`'s own doc text is a version declaration by
# the identical extractor, never a second regex. AC-E2.3's fails-when ("census still 2") is
# what assertion 19 below now refuses.
SITES="$(declaring_sites "$REPO")"
expect_eq "19: exactly three surfaces in the tree DECLARE a version, and they are the known three" \
  "payload/.claude-plugin/plugin.json|${PLUGIN_VERSION}
payload/commands/help.md|${PLUGIN_VERSION}
payload/commands/version.md|${PLUGIN_VERSION}" "$SITES"

SITE_DISAGREEMENTS="$(printf '%s\n' "$SITES" | awk -F'|' -v v="$PLUGIN_VERSION" '$2 != v')"
expect_empty "20: …and every one of them agrees with plugin.json" "$SITE_DISAGREEMENTS"

# The sweep's own controls, over a scratch tree: a THIRD declaring surface is found, and a
# disagreeing one is reported as a disagreement. Without these, an empty sweep and a broken
# sweep look identical.
SWEEP_TREE="$TMP/sweep-tree"
mkdir -p "$SWEEP_TREE/payload/.claude-plugin" "$SWEEP_TREE/payload/commands" \
         "$SWEEP_TREE/payload/scripts" "$SWEEP_TREE/.claude-plugin" "$SWEEP_TREE/agents-src"
cp "$PLUGIN_JSON" "$SWEEP_TREE/payload/.claude-plugin/plugin.json"
cp "$HELP_MD" "$SWEEP_TREE/payload/commands/help.md"
printf '{\n  "name": "bionic-thing",\n  "version": "0.0.0-mismatch"\n}\n' \
  > "$SWEEP_TREE/payload/scripts/third-surface.json"
SWEEP_SITES="$(declaring_sites "$SWEEP_TREE")"
expect_contains "21: the sweep FINDS a third declaring surface planted in a scratch tree" \
  "payload/scripts/third-surface.json|0.0.0-mismatch" "$SWEEP_SITES"
expect_nonempty "22: …and the disagreement filter reports it as a disagreement" \
  "$(printf '%s\n' "$SWEEP_SITES" | awk -F'|' -v v="$PLUGIN_VERSION" '$2 != v')"

# --- E2.2: help's roster carries the /bionic:version row --------------------
expect_contains "22b: payload/commands/help.md's roster carries a /bionic:version row" \
  "/bionic:version" "$(cat "$HELP_MD")"

# --- E2.3: doctoring version.md's OWN line to a different version reads as a
# disagreement, in a scratch tree that otherwise agrees (AC-E2.3's fails-when: "census
# still 2" — this proves version.md is the THIRD surface the census can catch on its own,
# not merely counted alongside an unrelated mismatch). "0.0.0-mismatch" rather than a
# literal like "1.5.1": the doctored value only has to differ from whatever PLUGIN_VERSION
# actually is on the machine running this suite, and a release bump could make a fixed
# literal collide with the real version and doctor nothing at all.
VERSION_MD="${REPO}/payload/commands/version.md"
E23_TREE="$TMP/e23-tree"
mkdir -p "$E23_TREE/payload/.claude-plugin" "$E23_TREE/payload/commands"
cp "$PLUGIN_JSON" "$E23_TREE/payload/.claude-plugin/plugin.json"
cp "$HELP_MD" "$E23_TREE/payload/commands/help.md"
sed "s/^bionic ${PLUGIN_VERSION//./\\.} (installed)\$/bionic 0.0.0-mismatch (installed)/" \
  "$VERSION_MD" > "$E23_TREE/payload/commands/version.md"
E23_SITES="$(declaring_sites "$E23_TREE")"
expect_contains "23: the census counts version.md as its own declaring surface" \
  "payload/commands/version.md|" "$E23_SITES"
expect_nonempty "24: …and a version.md doctored to 1.5.1 reads as a disagreement" \
  "$(printf '%s\n' "$E23_SITES" | awk -F'|' -v v="$PLUGIN_VERSION" '$2 != v')"

# ── SECTION 2 — WALLS (spec AC-14/AC-26, `.bionic/docs/plans/wave-bionic-1.4.0-update/`).
#
# WHAT THIS SECTION OWNS. Four instruction-surface sentences that no hook can check,
# each of which a machine downstream depends on:
#
#   (a) Step 0's probe act in `payload/skills/canonical-sdlc/SKILL.md` — the run's
#       `parallel-budget:` comes from `resources_probe`/`resources_budget` and is
#       recorded verbatim, never re-derived. hooks/dispatch-preflight.sh's budget arm
#       reads that one string; a Step 0 that stopped writing it makes the arm inert.
#   (b) the "fill the budget" dispatch rule in the same file — the sentence that turns
#       a budget from a ceiling into an instruction.
#   (c) the `BIONIC_TEST_JOBS=<test_jobs>` sentence in `agents-src/blocks/survival.md`,
#       which must reach every dispatched writer — so it is asserted in the BLOCK and
#       again in all six rendered `agents/*.md`, which is what proves the render ran.
#   (d) the `/clear` paragraph, which lives in ONE canonical copy — `agents-src/blocks/
#       survival.md`, rendered into all six `agents/*.md` — since S7 (AC-13) retired the
#       second copy that used to live in `.claude/rules/agent-discipline.md`. Two copies
#       of a paragraph is exactly the drift a pin used to exist for; now the pin is over
#       the SINGLE home instead: the block carries it, the six role files match it
#       byte-for-byte, and the rules file is asserted to carry it no longer.
#
# ANTI-VACUITY, same discriminate-a-doctored-copy pattern §1 uses: every extractor here
# is re-run against a mutated copy and must report the mutation.
#
# HERMETIC. Reads committed files by path; doctored copies live under $TMP.

section "Section 2: the WALLS instruction-surface pins (AC-14, AC-26)"

# THE SPLIT SURFACE (wave-11 row 1b). What used to be one 108,652-byte SKILL.md is now a
# CORE plus ten step files plus a dispatch reference, and every pin below names the file that
# carries its sentence rather than "the skill file". That is the whole re-point: no assertion
# was dropped and no needle was reworded — each one moved to the surface its text moved to,
# which is also what makes these pins worth more than they were. A sentence pinned against
# the core now fails if it drifts into a step file, and vice versa, so the split itself is
# held in place by the same assertions that hold the text.
#
# `payload/skills/canonical-sdlc` is a symlink to `../../skills/canonical-sdlc`, so every
# path below is the same real file the render writes and archive.test.sh reads.
SKILL_DIR="${REPO}/payload/skills/canonical-sdlc"
SKILL_MD="${SKILL_DIR}/SKILL.md"
DISPATCH_MD="${SKILL_DIR}/dispatch.md"
STEP0_MD="${SKILL_DIR}/steps/0.md"
STEP1_MD="${SKILL_DIR}/steps/1.md"
STEP2_MD="${SKILL_DIR}/steps/2.md"
STEP3_MD="${SKILL_DIR}/steps/3.md"
STEP5_MD="${SKILL_DIR}/steps/5.md"
STEP6_MD="${SKILL_DIR}/steps/6.md"
STEP8_MD="${SKILL_DIR}/steps/8.md"
STEP9_MD="${SKILL_DIR}/steps/9.md"
SURVIVAL_BLOCK="${REPO}/agents-src/blocks/survival.md"
AGENT_RULES="${REPO}/.claude/rules/agent-discipline.md"

# The four pinned strings, spelled here exactly as they must appear on disk.
PIN_PROBE='`resources_probe` and `resources_budget` from `<plugin-root>/scripts/lib/resources.sh` yield the run'"'"'s `parallel-budget:` — one string, recorded verbatim in plan frontmatter, printed in the display, and never re-derived downstream.'
# RE-POINTED AT THE CORRECTED DOCTRINE (Step-6 architecture A-2). The old needle pinned
# `dispatches in one batch up to `writers`` — the ceiling, unregulated — while the tick fills
# to the RUNG off a live-trimmed open count, so the pin was holding a contradiction green. A
# pin follows the sentence it is a pin FOR: when the doctrine is corrected the needle moves
# with it, or the test outlives the thing it was protecting.
PIN_FILL='every task with no unmet dependency dispatches in one batch sized by the rung the tick prints — `poker: rung=<n>/<ceiling>`, the machine'"'"'s answer to how wide it will carry right now — with `writers` as the ceiling that rung is taken against and the only number the wall enforces'
# RE-POINTED, WRITER-FACING (Step-6 readability R-8). The old needle held a sentence that
# was correct in SKILL.md — where it addresses the DISPATCHER, and where PIN_JOBS_SKILL still
# holds it — and had been pasted verbatim into a block every other bullet of which is
# second-person to the writer. It also named a fix no writer can execute: `pressure_level` is
# a function in a sourced library, not a command on PATH, and tests/run.sh already calls it.
PIN_JOBS='**You do not set your test width.** `tests/run.sh` samples the machine and reads its own width off the pressure rung at suite start, so there is nothing here for you to compute, export, or call — `pressure_level` is a shell function in a sourced library, not a command you can run. Set `BIONIC_TEST_JOBS_CEILING` only when your brief names a ceiling, and never above the one it names.'

# has_pin <file> <string> -> 0 when the file carries the string.
#
# WHITESPACE-NORMALIZED, and that is the only latitude given: the file is folded to one
# line with every run of whitespace collapsed to a single space before the match, so a
# sentence that wraps across two source lines — which every one of these does in at least
# one of its homes — still matches, while a changed word, a changed backtick or a changed
# punctuation mark does not. `tr` + `sed` rather than a regex, so the needle is compared
# literally by `grep -F`.
_flatten() { tr '\n' ' ' < "$1" 2>/dev/null | sed 's/[[:space:]][[:space:]]*/ /g'; }
has_pin() { _flatten "$1" | grep -qF -- "$2"; }

if has_pin "$STEP0_MD" "$PIN_PROBE"; then
  ok "9: SKILL.md Step 0 carries the resources-probe sentence verbatim"
else
  no "9: SKILL.md Step 0 carries the resources-probe sentence verbatim" "file: $STEP0_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_FILL"; then
  ok "10: SKILL.md carries the 'fill the budget' dispatch rule verbatim"
else
  no "10: SKILL.md carries the 'fill the budget' dispatch rule verbatim" "file: $DISPATCH_MD"
fi

if has_pin "$SURVIVAL_BLOCK" "$PIN_JOBS"; then
  ok "11: agents-src/blocks/survival.md carries the rung-pointer sentence verbatim (AC-18)"
else
  no "11: agents-src/blocks/survival.md carries the rung-pointer sentence verbatim (AC-18)" \
     "file: $SURVIVAL_BLOCK"
fi

# The render is the delivery mechanism; asserting the block alone would pass on a repo
# whose rendered output was never refreshed, which is the state a dispatched writer meets.
#
# RE-POINTED (wave-11 1c, was: the six agents/*.md). The survival text renders ONCE now, to
# payload/context/survival.md, and reaches an agent by push (the SubagentStart hook) rather
# than by being restated in six role definitions. So the file this arm reads is the rendered
# SHIPPED copy, not the role files — the same question ("did the render reach the delivered
# text?"), asked of the one file that now carries it.
SURVIVAL_SHIPPED="${REPO}/payload/context/survival.md"
if has_pin "$SURVIVAL_SHIPPED" "$PIN_JOBS"; then
  ok "12: the rendered payload/context/survival.md carries the rung-pointer sentence (render is current, AC-18)"
else
  no "12: the rendered payload/context/survival.md carries the rung-pointer sentence (render is current, AC-18)" \
     "file: $SURVIVAL_SHIPPED — run 'bash agents-src/render.sh'"
fi

# clear_paragraph <file> -> the one paragraph opening with the `/clear` marker, verbatim.
# Paragraph-scoped rather than line-scoped: a difference in how the two channels wrap the
# same words IS a difference, and this pin is for byte identity, not for gist. It ends at a
# blank line or at the render's own `<!-- SURVIVAL-END -->` marker, which agents-src/render.sh
# writes immediately after the last injected line with no blank between them.
clear_paragraph() {
  awk '
    /^\*\*`\/clear` does not kill agents\.\*\*/ { inp = 1 }
    inp && /^[[:space:]]*$/ { exit }
    inp && /^<!--/ { exit }
    inp { print }
  ' "$1" 2>/dev/null
}

CLEAR_BLOCK="$(clear_paragraph "$SURVIVAL_BLOCK")"
CLEAR_RULES="$(clear_paragraph "$AGENT_RULES")"

if [ -n "$CLEAR_BLOCK" ]; then
  ok "13: agents-src/blocks/survival.md carries the '/clear does not kill agents' paragraph"
else
  no "13: agents-src/blocks/survival.md carries the '/clear does not kill agents' paragraph" \
     "file: $SURVIVAL_BLOCK"
fi

# 14: ONE COPY (S7, AC-13) — the second copy that used to live in the rules file is
# retired, not re-homed a third time (r1 §Table 3, AD18: "delete the rules copy. Do not
# port it to the orchestrator role — that would make a fourth"). A bare absence check is
# a vacuous-negative risk (tests/lib/assert.sh's own docblock on `expect_empty`); it is
# paired here with assertion 13's POSITIVE result from the very same `clear_paragraph`
# extractor, on the sibling file, moments above — proof the extractor itself works.
if [ -z "$CLEAR_RULES" ]; then
  ok "14: .claude/rules/agent-discipline.md no longer carries a '/clear' paragraph copy (one copy only)"
else
  no "14: .claude/rules/agent-discipline.md no longer carries a '/clear' paragraph copy (one copy only)" \
     "file: $AGENT_RULES still matches the extractor — a second copy survived the move"
fi

# RE-POINTED (wave-11 1c, was: the six agents/*.md). One rendered home, so one comparison.
if [ "$(clear_paragraph "$SURVIVAL_SHIPPED")" = "$CLEAR_BLOCK" ] && [ -n "$CLEAR_BLOCK" ]; then
  ok "15: the rendered payload/context/survival.md carries that paragraph byte-identically"
else
  no "15: the rendered payload/context/survival.md carries that paragraph byte-identically" \
     "differs or missing in: $SURVIVAL_SHIPPED — run 'bash agents-src/render.sh'"
fi

# 16: CENSUS — no THIRD home exists anywhere in the tree. Assertion 14 proves the one
# named former home is clean; this proves nothing else picked the paragraph up either,
# the same construction-guarded-vs-enforcement-guarded distinction r3 §Part 2 item 18
# draws for AD18's other two copies.
CLEAR_MARKER='`/clear` does not kill agents.'
# RE-POINTED (wave-11 1c): two homes, not seven — the source block and the ONE rendered
# shipped copy. The six role files dropped their injection; a role file that reacquires the
# paragraph makes this census over-count, which is exactly the regression to catch.
CLEAR_HOMES_EXPECTED="agents-src/blocks/survival.md payload/context/survival.md"
CLEAR_HOMES_ACTUAL="$(cd "$REPO" && /usr/bin/grep -rl -F -- "$CLEAR_MARKER" \
  agents-src agents .claude payload skills 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
expect_eq "16: the '/clear' marker exists ONLY at its two expected homes (no third copy anywhere)" \
  "$(printf '%s\n' $CLEAR_HOMES_EXPECTED | sort | tr '\n' ' ' | sed 's/ $//')" "$CLEAR_HOMES_ACTUAL"

# --- Anti-vacuity: the same extractors must report a mutation ---

anchor "$STEP0_MD" 'never re-derived downstream' 1
DOCTORED_SKILL="$TMP/skill-mutated.md"
sed 's/never re-derived downstream/re-derived wherever convenient/' "$STEP0_MD" > "$DOCTORED_SKILL"
if has_pin "$DOCTORED_SKILL" "$PIN_PROBE"; then
  no "17: a doctored SKILL.md fails the probe pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "17: a doctored SKILL.md fails the probe pin (pin discriminates)"
fi

anchor "$SURVIVAL_BLOCK" 'only when your brief names a ceiling' 1
DOCTORED_BLOCK="$TMP/survival-mutated.md"
sed 's/only when your brief names a ceiling/whenever you feel the machine is busy/' \
  "$SURVIVAL_BLOCK" > "$DOCTORED_BLOCK"
if has_pin "$DOCTORED_BLOCK" "$PIN_JOBS"; then
  no "18: a doctored survival.md fails the BIONIC_TEST_JOBS pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "18: a doctored survival.md fails the BIONIC_TEST_JOBS pin (pin discriminates)"
fi

# 19: mutation target moved to the canonical copy (S7, AC-13) — the rules file no
# longer carries this paragraph at all, so mutating it would anchor on nothing (the
# "anchor MOVED" failure `anchor()`'s own docblock warns against) and prove nothing.
anchor "$SURVIVAL_BLOCK" 'the address that survives' 1
DOCTORED_BLOCK2="$TMP/survival-clear-mutated.md"
sed 's/the address that survives/the address that dies/' "$SURVIVAL_BLOCK" > "$DOCTORED_BLOCK2"
expect_ne "19: a doctored survival.md reads as a different '/clear' paragraph (pin discriminates)" \
  "$CLEAR_BLOCK" "$(clear_paragraph "$DOCTORED_BLOCK2")"

# ── SECTION 3 — SCHED (spec AC-29/AC-30/AC-31/AC-38, `.bionic/docs/plans/wave-bionic-1.4.0-update/`).
#
# WHAT THIS SECTION OWNS. Two instruction-surface sentences in
# `payload/skills/canonical-sdlc/SKILL.md`'s Patrol section that no hook can check, and that
# a machine downstream depends on being read as written:
#
#   (e) "the tick reads pressure to throttle, never to re-derive the budget" — the boundary
#       between lib/resources.sh's CEILING (a pure function of machine facts, written once
#       into the plan header by Step 0) and its live PRESSURE reading. An orchestrator that
#       read the second as licence to rewrite the first would make fan-out width a function
#       of the weather, which is the drift the library exists to remove; the sentence is the
#       only thing standing between the two, because the tick cannot enforce it — the tick
#       does not write plans.
#   (f) the AC-38 QUIET line — "an armed session that has dispatched nothing yet decides
#       QUIET, never REFUSED". The tick implements it, but the SENTENCE is what stops the
#       next reader from re-adding the refusal on the reasoning that an empty roster is
#       suspicious. It was measured suspicious exactly once, on this wave's own tick #1,
#       and it was the reader that was wrong.
#
# BYTE-LEVEL, whitespace-normalized, through §2's own `has_pin` — the same latitude and no
# more: a sentence that wraps differently still matches, a changed word does not.
#
# ANTI-VACUITY, same discriminate-a-doctored-copy pattern §1 and §2 use.
#
# APPENDED, NEVER REWRITTEN: §1 is RELEASE's and §2 is WALLS's, and a task that edited
# another task's pins would be a task deciding what that task owns.

section "Section 3: the SCHED Patrol-text pins (AC-30, AC-38)"

PIN_THROTTLE='**the tick reads pressure to throttle, never to re-derive the budget** — the ceiling is the plan header'"'"'s `parallel-budget:`, written once by Step 0 from the probe, and no live reading ever raises or lowers it.'
PIN_QUIET='**An armed session that has dispatched nothing yet decides QUIET, never REFUSED** — `poker: QUIET — armed, nothing dispatched yet on this session`, stamp kept — because arming precedes dispatch by design'

if has_pin "$DISPATCH_MD" "$PIN_THROTTLE"; then
  ok "20: SKILL.md carries the pressure-throttles-never-re-derives sentence verbatim"
else
  no "20: SKILL.md carries the pressure-throttles-never-re-derives sentence verbatim" \
     "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_QUIET"; then
  ok "21: SKILL.md carries the AC-38 QUIET sentence verbatim"
else
  no "21: SKILL.md carries the AC-38 QUIET sentence verbatim" "file: $DISPATCH_MD"
fi

# The two rungs, the tick's rung line and the fill duty are named in the same section —
# asserted as presence rather than byte-for-byte, because their wording is prose the next
# editor may improve while the two sentences above are contracts. NARROW retired from this
# list at S10 (S8's report: "docs-pins.test.sh:327 still pins the token in SKILL.md and is
# S10's to retire" — NARROW is gone from hooks/session-poker.sh entirely).
PINS_RUNGS_MISSING=""
for token in 'EMERGENCY' 'HOLD' 'rung=<n>/<ceiling>' 'FILL <ids>' 'fill-declined: <reason>' 'Step-3 approval pending'; do
  has_pin "$DISPATCH_MD" "$token" || PINS_RUNGS_MISSING="${PINS_RUNGS_MISSING} ${token}"
done
if [ -z "$PINS_RUNGS_MISSING" ]; then
  ok "22: SKILL.md's Patrol section names both rungs, the tick's rung line, the FILL line and the decline"
else
  no "22: SKILL.md's Patrol section names both rungs, the tick's rung line, the FILL line and the decline" \
     "missing:${PINS_RUNGS_MISSING}"
fi

# --- Anti-vacuity: the same extractor must report a mutation ---

anchor "$DISPATCH_MD" 'never to re-derive the budget' 1
DOCTORED_SCHED="$TMP/skill-sched-mutated.md"
sed 's/never to re-derive the budget/and to re-derive the budget/' "$DISPATCH_MD" > "$DOCTORED_SCHED"
if has_pin "$DOCTORED_SCHED" "$PIN_THROTTLE"; then
  no "23: a doctored SKILL.md fails the throttle pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "23: a doctored SKILL.md fails the throttle pin (pin discriminates)"
fi

anchor "$DISPATCH_MD" 'decides QUIET, never REFUSED' 1
DOCTORED_SCHED2="$TMP/skill-sched-mutated-2.md"
sed 's/decides QUIET, never REFUSED/is REFUSED/' "$DISPATCH_MD" > "$DOCTORED_SCHED2"
if has_pin "$DOCTORED_SCHED2" "$PIN_QUIET"; then
  no "24: a doctored SKILL.md fails the QUIET pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "24: a doctored SKILL.md fails the QUIET pin (pin discriminates)"
fi

section "SECTION 4 — the Patrol tick literal, one string in two files (step-6 review R-8)"
#
# WHAT THIS SECTION OWNS. The armed cron job's prompt begins with the token
# `bionic-patrol session=<session-id[0:8]>`. SKILL.md is where the operator is told to
# write it (§The patrol prompt) and where the resume ritual is told to match on it;
# hooks/patrol-duties-gate.sh REBUILDS it — `TICK_MARK="bionic-patrol session=${SID:0:8}"`
# — and scans the transcript for it to decide whether a tick happened. The two are one
# contract with no shared definition between them.
#
# THE FAILURE THIS CLOSES. The ownership table for "a Patrol tick happened" promised
# "docs-pins: the literal pinned in both files" and `/usr/bin/grep -n bionic-patrol
# tests/docs-pins.test.sh` returned nothing. Fixtures exercise the hook's own copy
# (patrol-duties-gate, hook-adoption) with the literal spelled INSIDE the fixture, so
# rewording the SKILL.md sentence breaks the tick match on real transcripts with every
# suite green — the exact silent-drift class AC-22 exists to prevent.
#
# READ FROM BOTH FILES, not asserted against a constant twice. Each extractor pulls the
# prefix out of its own file and the two are compared; a constant on both sides would
# pass on two files that had drifted together away from what the cron actually carries.
# Assertion 25 additionally pins the extracted value, so an extractor that returned empty
# on both sides could not agree its way to green.

# The gate is `stop_patrol_duties` in the library now (epic-23 wave-11, T12); the
# prefix it rebuilds moved with its body, unchanged.
TICK_GATE="${REPO}/payload/scripts/lib/stop.sh"

# tick_literal_doc <SKILL.md> -> the prefix as documented, placeholder stripped.
# Fails LOUD rather than empty: an unmatched sed leaves the whole line, which no
# comparison below can mistake for agreement.
tick_literal_doc() {
  /usr/bin/grep -m1 '^\*\*The patrol prompt\.\*\*' "$1" 2>/dev/null \
    | sed 's/.*its first token `\([^`]*\)`.*/\1/' \
    | sed 's/<session-id\[0:8\]>$//'
}
# tick_literal_code <patrol-duties-gate.sh> -> the prefix the hook builds.
# THE VARIABLE NAME IS DERIVED, NOT SPELLED (epic-23 wave-11, T12). This stripped a
# literal `${SID:0:8}"`, and T10 renamed that variable to `BIONIC_SID` when the context
# preamble became one library call — after which the sed matched nothing, the extractor
# returned the whole right-hand side, and §26 was RED at 852ebd6 before this task touched
# anything. What the pin owns is the PREFIX the two files must agree on, so the suffix is
# matched by its shape and a future rename cannot break it the same way twice.
tick_literal_code() {
  /usr/bin/grep -m1 '^TICK_MARK=' "$1" 2>/dev/null \
    | sed 's/^TICK_MARK="//' \
    | sed 's/\${[A-Za-z_][A-Za-z0-9_]*:0:8}"$//'
}

TICK_DOC=$(tick_literal_doc "$DISPATCH_MD")
TICK_CODE=$(tick_literal_code "$TICK_GATE")

expect_eq "25: SKILL.md's patrol-prompt token is the tick prefix the cron carries" \
  'bionic-patrol session=' "$TICK_DOC"
expect_eq "26: patrol-duties-gate.sh rebuilds the SAME prefix SKILL.md documents" \
  "$TICK_DOC" "$TICK_CODE"

# The resume ritual matches on the same literal to delete a predecessor's clock. If that
# sentence drifts, an operator deletes nothing and two clocks run side by side.
# CAPTURED, THEN MATCHED — never `_flatten | grep -q`. SKILL.md is past the 64 KiB pipe
# buffer, so under this file's `set -o pipefail` an early-exiting `grep -q` SIGPIPEs the
# producer and the pipeline returns 141: a real match reported as a miss, intermittently.
TICK_RESUME_NEEDLE='delete every job whose prompt begins with the patrol marker `bionic-patrol session=`'
TICK_FLAT=$(_flatten "$DISPATCH_MD")
case "$TICK_FLAT" in
  *"$TICK_RESUME_NEEDLE"*)
    ok "27: SKILL.md's resume ritual names the same marker it tells the prompt to carry" ;;
  *)
    no "27: SKILL.md's resume ritual names the same marker it tells the prompt to carry" \
       "file: $DISPATCH_MD" ;;
esac

# --- Anti-vacuity: the same extractors must report a mutation, from either side ---

anchor "$DISPATCH_MD" 'its first token `bionic-patrol session=' 1
DOCTORED_TICK_DOC="$TMP/skill-tick-mutated.md"
sed 's/its first token `bionic-patrol session=/its first token `bionic patrol session=/' \
  "$DISPATCH_MD" > "$DOCTORED_TICK_DOC"
expect_ne "28: a reworded SKILL.md token breaks the pin (pin discriminates)" \
  "$TICK_CODE" "$(tick_literal_doc "$DOCTORED_TICK_DOC")"

anchor -E "$TICK_GATE" '^TICK_MARK="bionic-patrol session=' 1
DOCTORED_TICK_CODE="$TMP/patrol-duties-gate-mutated.sh"
sed 's/^TICK_MARK="bionic-patrol session=/TICK_MARK="bionic-patrol sid=/' \
  "$TICK_GATE" > "$DOCTORED_TICK_CODE"
expect_ne "29: a renamed hook-side literal breaks the pin (pin discriminates)" \
  "$TICK_DOC" "$(tick_literal_code "$DOCTORED_TICK_CODE")"

#
# SECTION 5 — the session-bound run, and the bind step in the resume ritual (wave-session-bound-run, A4/AC-5/AC-8).
# WHAT THIS SECTION OWNS. Two sentences in `payload/skills/canonical-sdlc/SKILL.md`'s Patrol
# paragraph that no hook can check, and that decide whether a resumed session works its own
# run or its neighbour's:
#
#   (g) THE RULE. "Which run" moved from the PROJECT to the SESSION at bionic 1.4.2: the open
#       run is the plan the session's own engagement marker names, and only an UNBOUND session
#       falls back to the newest plan. The hooks enforce it; the SENTENCE is what stops the
#       next reader from re-deriving the old project-keyed rule from the fallback they
#       happened to observe — which is exactly what an unbound session sees, every time.
#   (h) THE STEP. Engagement binds only a SOLE open run (AC-7), so a session resuming into a
#       root with several is unbound, and `adopt` partitions on the binding (AC-2). Without
#       the bind step the resume ritual reads as complete while leaving the session gated on
#       another run's plan and offered another run's agents — the two symptoms the wave was
#       opened for. No hook can require this: binding is an act the model takes, and the only
#       surface that can ask for it is this paragraph.
#
# BYTE-LEVEL, whitespace-normalized, through §2's own `has_pin` — the same latitude and no
# more. ANTI-VACUITY by the discriminate-a-doctored-copy pattern §1-§4 use.
#
# ASSERTION 32 IS THE ONE WITH TEETH ACROSS FILES: the verb this paragraph tells the operator
# to type is read out of SKILL.md and compared to the verb `hooks/session-poker.sh` puts in
# its own usage block. A rename on either side splits them here rather than in a session that
# types a command the tool does not have.
#
# APPENDED, NEVER REWRITTEN: §1-§4 belong to earlier tasks.

section "Section 5: the session-bound run and the resume-ritual bind step"

# THE PARAGRAPH STATES ONE RULE, ONCE (review readability F1, S10b). Before this pin the
# Patrol paragraph carried the PRE-wave rule as a fact — "whether this PROJECT has an OPEN
# run … the open run decides WHAT it enforces" — and then the post-wave correction ~120
# words later in the same paragraph. `payload/scripts/lib/run.sh:313` calls that first
# sentence the defect in the codebase's own words; the doc kept its copy and appended the
# fix after it. The sentence below REPLACED it, so the paragraph no longer teaches the rule
# this wave exists to delete. Pinned as a pair: the new clause present, the old one gone.
PIN_SCOPE_PAIR='whether this SESSION is engaged, and which run this SESSION is bound to. Engagement decides WHETHER a hook acts at all; the bound run decides WHAT it enforces.'
PIN_SCOPE_OLD='whether this PROJECT has an OPEN run'
PIN_BOUND_RUN='**Which run is a property of the SESSION, not of the project** (bionic 1.4.2): the open run is the plan this session is BOUND to, recorded as the `plan=` line of its own engagement marker'
PIN_FALLBACK='Only an UNBOUND session falls back to the newest plan under the docs root'
PIN_BIND_STEP='**The resume ritual binds its run before it adopts anything:** if session-start listed more than one open run — or this session is otherwise unbound in a root that holds several — run `bash <plugin-root>/hooks/session-poker.sh bind <plan>` for the plan this session means, immediately after engaging and before the first dispatch.'

if has_pin "$DISPATCH_MD" "$PIN_BOUND_RUN"; then
  ok "30: SKILL.md states that the run is a property of the session, verbatim"
else
  no "30: SKILL.md states that the run is a property of the session, verbatim" "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_FALLBACK"; then
  ok "31: …and that ONLY an unbound session takes the newest-plan fallback"
else
  no "31: …and that ONLY an unbound session takes the newest-plan fallback" "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_BIND_STEP"; then
  ok "32: SKILL.md's resume ritual carries the bind step verbatim (A4: exactly one added step)"
else
  no "32: SKILL.md's resume ritual carries the bind step verbatim (A4: exactly one added step)" \
     "file: $DISPATCH_MD"
fi

# --- 33: the verb the paragraph types is the verb the tool offers ---
#
# READ FROM BOTH FILES, never asserted against a constant twice — §4's rule. The doc side is
# the operand-carrying spelling inside the bind sentence; the code side is the poker's own
# usage line. An extractor that returned empty on both sides could not agree its way to
# green, because assertion 34 pins the extracted value.
POKER_SH="${REPO}/hooks/session-poker.sh"

# bind_verb_doc <SKILL.md> -> `session-poker.sh bind <plan>` as the ritual spells it
bind_verb_doc() {
  _flatten "$1" \
    | sed -n 's/.*run `bash <plugin-root>\/hooks\/\(session-poker\.sh bind <plan>\)` for the plan.*/\1/p'
}
# bind_verb_code <session-poker.sh> -> the same phrase out of the usage block
bind_verb_code() {
  /usr/bin/grep -m1 'session-poker\.sh bind <plan>' "$1" 2>/dev/null \
    | sed -n 's/.*\(session-poker\.sh bind <plan>\).*/\1/p'
}

BIND_DOC=$(bind_verb_doc "$DISPATCH_MD")
BIND_CODE=$(bind_verb_code "$POKER_SH")

expect_eq "33: SKILL.md tells the operator to type the verb the poker publishes" \
  "$BIND_CODE" "$BIND_DOC"
expect_eq "34: …and the verb both sides name is 'session-poker.sh bind <plan>'" \
  'session-poker.sh bind <plan>' "$BIND_DOC"

# --- Anti-vacuity: the same extractors and pins must report a mutation ---

anchor "$DISPATCH_MD" 'Only an UNBOUND session falls back' 1
DOCTORED_BOUND="$TMP/skill-bound-run-mutated.md"
sed 's/Only an UNBOUND session falls back/Every session falls back/' "$DISPATCH_MD" > "$DOCTORED_BOUND"
if has_pin "$DOCTORED_BOUND" "$PIN_FALLBACK"; then
  no "35: a doctored SKILL.md fails the fallback pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "35: a doctored SKILL.md fails the fallback pin (pin discriminates)"
fi

anchor "$DISPATCH_MD" 'binds its run before it adopts anything' 1
DOCTORED_BIND="$TMP/skill-bind-step-mutated.md"
sed 's/binds its run before it adopts anything/adopts before it binds anything/' \
  "$DISPATCH_MD" > "$DOCTORED_BIND"
if has_pin "$DOCTORED_BIND" "$PIN_BIND_STEP"; then
  no "36: a reordered resume ritual fails the bind-step pin (pin discriminates)" \
     "the pin matched a copy that puts adopt first"
else
  ok "36: a reordered resume ritual fails the bind-step pin (pin discriminates)"
fi

anchor "$POKER_SH" 'session-poker.sh bind <plan>' 1
DOCTORED_BIND_VERB="$TMP/session-poker-verb-mutated.sh"
sed 's/session-poker\.sh bind <plan>/session-poker.sh bindrun <plan>/' "$POKER_SH" > "$DOCTORED_BIND_VERB"
expect_ne "37: a renamed poker verb splits from the doc (pin discriminates)" \
  "$BIND_DOC" "$(bind_verb_code "$DOCTORED_BIND_VERB")"

if has_pin "$DISPATCH_MD" "$PIN_SCOPE_PAIR"; then
  ok "38: SKILL.md's two-facts sentence names the SESSION's bound run, not the project's"
else
  no "38: SKILL.md's two-facts sentence names the SESSION's bound run, not the project's" \
     "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_SCOPE_OLD"; then
  no "39: …and the pre-wave project-scoped clause is gone from the paragraph" \
     "SKILL.md still states the rule this wave deleted: '$PIN_SCOPE_OLD'"
else
  ok "39: …and the pre-wave project-scoped clause is gone from the paragraph"
fi

# Anti-vacuity for 38, same pattern as 35/36: the extractor must report a doctored copy.
anchor "$DISPATCH_MD" 'which run this SESSION is bound to' 1
DOCTORED_SCOPE="$TMP/skill-scope-mutated.md"
sed 's/which run this SESSION is bound to/whether this PROJECT has an OPEN run/' \
  "$DISPATCH_MD" > "$DOCTORED_SCOPE"
if has_pin "$DOCTORED_SCOPE" "$PIN_SCOPE_PAIR"; then
  no "40: a doctored SKILL.md fails the scope pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "40: a doctored SKILL.md fails the scope pin (pin discriminates)"
fi

# --- S10 additions, same section, same shape as PIN_BIND_STEP above ---
#
# PIN_TASKLIST pins the resume-ritual step this wave adds immediately after the bind step:
# a session that resumes into a bound run rebuilds its task list from the plan rather than
# trusting whatever TaskList happens to still hold. PIN_RUNG pins the Patrol prompt's
# replacement for the retired NARROW recommendation (AC-17/AC-19; S8's report: "docs-pins.
# test.sh:327 still pins the token in SKILL.md and is S10's to retire" — Section 3's token
# list above no longer names NARROW, and this is the positive sentence that replaced it).
PIN_TASKLIST='**The resume ritual rebuilds the task list after it binds:** run `TaskList`; if it is empty and the bound plan has `## SDLC State`, recreate one entry per step (and per task at the current step) from the plan, statuses from the step lines.'
# RE-POINTED at the sentence that separates the rung from the two HOLDS (Step-6 readability
# R-5/R-6). The prompt used to say "Three rungs, in order:" and then list two, and used the
# word `rung` for the advisory pair AND for `pressure_level`'s integer eleven words apart.
# The pin still holds the NARROW/RELAX retirement, which is what it was for.
PIN_RUNG='The rung is the separate thing they are often confused with: `pressure_level`'"'"'s integer, printed on every tick as `poker: rung=<n>/<ceiling>`, and it is the number a fill is sized by. NARROW and RELAX are retired — regulation is the rung'"'"'s, read by every consumer at the moment of use, never a tick'"'"'s advice.'

if has_pin "$DISPATCH_MD" "$PIN_TASKLIST"; then
  ok "48: SKILL.md's resume ritual rebuilds the task list after it binds, verbatim"
else
  no "48: SKILL.md's resume ritual rebuilds the task list after it binds, verbatim" \
     "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_RUNG"; then
  ok "49: SKILL.md's Patrol prompt names the rung line and retires NARROW/RELAX, verbatim"
else
  no "49: SKILL.md's Patrol prompt names the rung line and retires NARROW/RELAX, verbatim" \
     "file: $DISPATCH_MD"
fi

anchor "$DISPATCH_MD" 'recreate one entry per step' 1
DOCTORED_TASKLIST="$TMP/skill-tasklist-mutated.md"
sed 's/recreate one entry per step/recreate one entry per task only/' "$DISPATCH_MD" > "$DOCTORED_TASKLIST"
if has_pin "$DOCTORED_TASKLIST" "$PIN_TASKLIST"; then
  no "50: a doctored SKILL.md fails the task-list pin (pin discriminates)" \
     "the pin matched a doctored copy"
else
  ok "50: a doctored SKILL.md fails the task-list pin (pin discriminates)"
fi

anchor "$DISPATCH_MD" 'NARROW and RELAX are retired' 1
DOCTORED_RUNG="$TMP/skill-rung-mutated.md"
sed 's/NARROW and RELAX are retired/NARROW and RELAX still apply/' "$DISPATCH_MD" > "$DOCTORED_RUNG"
if has_pin "$DOCTORED_RUNG" "$PIN_RUNG"; then
  no "51: a doctored SKILL.md fails the rung pin (pin discriminates)" \
     "the pin matched a doctored copy"
else
  ok "51: a doctored SKILL.md fails the rung pin (pin discriminates)"
fi

section "Section 6: Step 8's tmp wipe spares session-keyed state"
#
# THE DEFECT THIS PINS (critic C-2, remediated at S10b). Step 8 said `wipe .bionic/tmp/*`,
# unqualified. `.bionic/tmp/` is where EVERY session in the root keeps its engagement
# marker, its roster, its Patrol stamp, its preflight attestation and its sweeper state —
# all keyed by session id. A blanket wipe therefore destroys the live state of every OTHER
# session working that root, which is precisely the two-run scenario this wave exists for,
# and it contradicts the same file's own sentence that "the marker is never removed during
# the session once written". The Step 8 line now names what it spares.
#
# RE-SPELLED (epic-23 wave-14 T28, review-duplication-d3930dd.md F3). The sentence above
# used to say "every session-keyed file" and enumerated five classes; that went stale
# twice over. (1) T1/REQ-1 (this wave) changed the rule itself: close-out now spares only
# a LIVE neighbour session's keyed files and removes a dead one's, so "every" was already
# wrong going into this wave. (2) `PATROL_STATE_CLASSES` (payload/scripts/lib/patrol.sh:162)
# grew a sixth member, `stop-orders`, at wave-13 — the prose enumeration never followed.
# The re-spelled sentence names all six classes and the live/dead distinction, and 44b/44c/
# 44d below pin the class list against `PATROL_STATE_CLASSES` directly so the two cannot
# drift apart again without one of them turning red.
#
# THE FIELD NAME `tmp-wiped:` IS DELIBERATELY UNTOUCHED (§Evidence, step 8 row). It is an
# evidence key the gate parses, not prose; renaming it would be an interface change and is
# not what the finding asked for.
PIN_TMP_SPARE="sparing a LIVE neighbour session's keyed files across the six \`PATROL_STATE_CLASSES\` (\`roster\`/\`preflight\`/\`engaged\`/\`sweeper\`/\`patrol\`/\`stop-orders\`), because one root can hold another session's live run and a blanket wipe would take its engagement marker, roster and Patrol stamp with it, un-engaging it mid-run; a dead neighbour's keyed files are removed, not spared"
PIN_TMP_BLANKET='wipe `.bionic/tmp/*`;'

if has_pin "$STEP8_MD" "$PIN_TMP_SPARE"; then
  ok "41: SKILL.md's Step 8 names the session-keyed files its wipe spares"
else
  no "41: SKILL.md's Step 8 names the session-keyed files its wipe spares" "file: $STEP8_MD"
fi

if has_pin "$STEP8_MD" "$PIN_TMP_BLANKET"; then
  no "42: …and no longer instructs the blanket wipe that destroyed them" \
     "SKILL.md still says: $PIN_TMP_BLANKET"
else
  ok "42: …and no longer instructs the blanket wipe that destroyed them"
fi

# The evidence key the gate reads is unchanged — the repair is prose, not interface.
if has_pin "$SKILL_MD" 'tmp-wiped:'; then
  ok "43: …while the Step-8 evidence key 'tmp-wiped:' is untouched"
else
  no "43: …while the Step-8 evidence key 'tmp-wiped:' is untouched" \
     "the gate parses this key; the S10b repair must not have renamed it"
fi

# Anti-vacuity, same pattern as 35/36/40.
anchor "$STEP8_MD" "sparing a LIVE neighbour session" 1
DOCTORED_TMP="$TMP/skill-tmp-wipe-mutated.md"
sed "s/sparing a LIVE neighbour session/taking every neighbour session/" "$STEP8_MD" > "$DOCTORED_TMP"
if has_pin "$DOCTORED_TMP" "$PIN_TMP_SPARE"; then
  no "44: a doctored SKILL.md fails the spare-list pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "44: a doctored SKILL.md fails the spare-list pin (pin discriminates)"
fi

# 44b/44c/44d — T28: the class list steps/8.md names must not drift from patrol.sh's own
# PATROL_STATE_CLASSES again (F3's second divergence — the prose was short one class, and
# nothing agreement-checked the two against each other). Read the SSoT directly rather than
# hand-copying a count into this suite, so a future class added to patrol.sh is caught here
# instead of relying on a human to remember to update this pin too.
PATROL_LIB_T28="${REPO}/payload/scripts/lib/patrol.sh"
PATROL_CLASSES_ACTUAL="$(sed -n 's/^PATROL_STATE_CLASSES="\(.*\)"$/\1/p' "$PATROL_LIB_T28")"
expect_nonempty "44a: patrol.sh's PATROL_STATE_CLASSES line is readable (the 44b/44c comparisons have something to measure)" "$PATROL_CLASSES_ACTUAL"

PATROL_CLASSES_MISSING=""
for _pc in $PATROL_CLASSES_ACTUAL; do
  if ! grep -qF "\`${_pc}\`" "$STEP8_MD"; then
    PATROL_CLASSES_MISSING="${PATROL_CLASSES_MISSING} ${_pc}"
  fi
done
if [ -z "$PATROL_CLASSES_MISSING" ]; then
  ok "44b: every patrol.sh PATROL_STATE_CLASSES name (${PATROL_CLASSES_ACTUAL}) appears in steps/8.md's spare-rule sentence"
else
  no "44b: every patrol.sh PATROL_STATE_CLASSES name (${PATROL_CLASSES_ACTUAL}) appears in steps/8.md's spare-rule sentence" \
     "missing from steps/8.md:${PATROL_CLASSES_MISSING}"
fi

PATROL_CLASSES_COUNT="$(printf '%s\n' "$PATROL_CLASSES_ACTUAL" | wc -w | tr -d ' ')"
PATROL_ALT_T28="$(printf '%s' "$PATROL_CLASSES_ACTUAL" | tr ' ' '|')"
STEP8_CLASS_MENTIONS="$(grep -oE "\`(${PATROL_ALT_T28})\`" "$STEP8_MD" | sort -u | wc -l | tr -d ' ')"
if [ "$STEP8_CLASS_MENTIONS" = "$PATROL_CLASSES_COUNT" ]; then
  ok "44c: steps/8.md names exactly ${PATROL_CLASSES_COUNT} distinct classes, matching patrol.sh's PATROL_STATE_CLASSES count"
else
  no "44c: steps/8.md names exactly ${PATROL_CLASSES_COUNT} distinct classes, matching patrol.sh's PATROL_STATE_CLASSES count" \
     "steps/8.md names ${STEP8_CLASS_MENTIONS} distinct classes from the current list, patrol.sh has ${PATROL_CLASSES_COUNT}"
fi

# Anti-vacuity for 44c: a patrol.sh with a class ADDED must desync the count this arm
# compares, proving 44c is a live comparison against the SSoT and not a hardcoded "6".
DOCTORED_PATROL_T28="$TMP/patrol-classes-mutated.sh"
sed "s/^PATROL_STATE_CLASSES=\"${PATROL_CLASSES_ACTUAL}\"\$/PATROL_STATE_CLASSES=\"${PATROL_CLASSES_ACTUAL} extra-class\"/" \
  "$PATROL_LIB_T28" > "$DOCTORED_PATROL_T28"
DOCTORED_CLASSES_T28="$(sed -n 's/^PATROL_STATE_CLASSES="\(.*\)"$/\1/p' "$DOCTORED_PATROL_T28")"
DOCTORED_COUNT_T28="$(printf '%s\n' "$DOCTORED_CLASSES_T28" | wc -w | tr -d ' ')"
if [ "$DOCTORED_CLASSES_T28" = "$PATROL_CLASSES_ACTUAL" ]; then
  no "44d: a patrol.sh with a class added desyncs the 44c count (pin discriminates)" \
     "the sed mutation did not change PATROL_STATE_CLASSES — anchor moved, mutation is a no-op"
elif [ "$DOCTORED_COUNT_T28" != "$STEP8_CLASS_MENTIONS" ]; then
  ok "44d: a patrol.sh with a class added desyncs the 44c count (pin discriminates)"
else
  no "44d: a patrol.sh with a class added desyncs the 44c count (pin discriminates)" \
     "doctored count ${DOCTORED_COUNT_T28} still equalled steps/8.md's ${STEP8_CLASS_MENTIONS}"
fi

section "Section 7: bind's operand takes the spelling session-start prints"
#
# THE PAIR THIS PINS (S10b phase 2). hooks/session-start.sh prints the open-run listing
# DOCS-root-relative, so an operator copies `plans/<epic>/<wave>.md` out of it. That is the
# one spelling `bind` used to reject, because a relative operand was resolved against the
# PROJECT root only. The verb now tries the docs root when the project-relative spelling is
# not a regular file, and this section is the doc half of that agreement: the paragraph a
# reader learns the verb from must name all three spellings the verb accepts.
PIN_BIND_OPERAND='its operand may be absolute, project-root-relative, or docs-root-relative — the spelling session-start'"'"'s own listing prints'

if has_pin "$DISPATCH_MD" "$PIN_BIND_OPERAND"; then
  ok "45: SKILL.md names all three spellings bind accepts"
else
  no "45: SKILL.md names all three spellings bind accepts" "file: $DISPATCH_MD"
fi

# THE CODE HALF, read from the poker rather than asserted against a constant (§4's rule):
# the docs-root fallback must actually be in the verb, not only in the prose. Matched by
# SHAPE (the docs_root("$REPO") interpolation feeding a BIND_DOCS_TRY assignment) rather than
# by the exact operand variable name, so a rename of that operand (as S8 did, BIND_ARG ->
# BIND_ARG_P, for the trailing-slash strip) does not stale this pin the way a literal-string
# grep did.
BIND_DOCS_FALLBACK_RE='BIND_DOCS_TRY="\$\(docs_root "\$REPO"\)/\$[A-Za-z_][A-Za-z_0-9]*"'
if /usr/bin/grep -Eq "$BIND_DOCS_FALLBACK_RE" "$POKER_SH"; then
  ok "46: …and session-poker.sh really does try the docs root for a relative operand"
else
  no "46: …and session-poker.sh really does try the docs root for a relative operand" \
     "file: $POKER_SH"
fi

# Anti-vacuity, same pattern as 35/36/40/44.
anchor "$DISPATCH_MD" 'its operand may be absolute, project-root-relative, or docs-root-relative' 1
DOCTORED_OPERAND="$TMP/skill-bind-operand-mutated.md"
sed 's/its operand may be absolute, project-root-relative, or docs-root-relative/its operand must be absolute/' \
  "$DISPATCH_MD" > "$DOCTORED_OPERAND"
if has_pin "$DOCTORED_OPERAND" "$PIN_BIND_OPERAND"; then
  no "47: a doctored SKILL.md fails the operand pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "47: a doctored SKILL.md fails the operand pin (pin discriminates)"
fi

# Anti-vacuity for 46: a poker with the fallback line deleted must fail the same regex, so
# assertion 46 is proven to discriminate rather than matching everything by accident.
anchor "$POKER_SH" 'BIND_DOCS_TRY=' 1
DOCTORED_POKER_NO_FALLBACK="$TMP/session-poker-no-docs-fallback.sh"
/usr/bin/grep -v 'BIND_DOCS_TRY=' "$POKER_SH" > "$DOCTORED_POKER_NO_FALLBACK"
if /usr/bin/grep -Eq "$BIND_DOCS_FALLBACK_RE" "$DOCTORED_POKER_NO_FALLBACK"; then
  no "52: a poker with the docs-root fallback deleted fails assertion 46's check (pin discriminates)" \
     "the regex matched a copy with the fallback line removed"
else
  ok "52: a poker with the docs-root fallback deleted fails assertion 46's check (pin discriminates)"
fi

section "Section 8: SKILL.md carries its OWN copy of the rung-pointer sentence (AC-18)"
#
# THE GAP THE READBACK NAMED. Assertions 11/12 pin the rendered role files against
# `PIN_JOBS`, but nothing here had ever checked SKILL.md's own restatement of the same
# sentence in its "Fill the budget" paragraph — so a hand-edit to SKILL.md's copy could
# drift from the briefs' copy with no suite ever noticing.
#
# THE ONE REAL DIFFERENCE: SKILL.md's copy is prose inside a running paragraph, never
# bolded, where `agents-src/blocks/survival.md`'s copy leads a bulleted brief and IS bolded
# (`**Each brief…**`). `PIN_JOBS` encodes that bold form, so it is the wrong needle for
# SKILL.md; this pins the same words in the form SKILL.md actually carries them.
PIN_JOBS_SKILL='Each brief in the batch points the writer at the rung: `take your test width from pressure_level at suite start; the ceiling is this header'"'"'s test_jobs`.'

if has_pin "$DISPATCH_MD" "$PIN_JOBS_SKILL"; then
  ok "53: SKILL.md carries its own copy of the rung-pointer sentence (AC-18)"
else
  no "53: SKILL.md carries its own copy of the rung-pointer sentence (AC-18)" "file: $DISPATCH_MD"
fi

# Anti-vacuity, same 47-style shape: a doctored SKILL.md must fail the pin above.
anchor "$DISPATCH_MD" 'Each brief in the batch points the writer at the rung' 1
DOCTORED_SKILL_JOBS="$TMP/skill-jobs-mutated.md"
sed 's/Each brief in the batch points the writer at the rung/Each brief in the batch reads the frozen literal/' \
  "$DISPATCH_MD" > "$DOCTORED_SKILL_JOBS"
if has_pin "$DOCTORED_SKILL_JOBS" "$PIN_JOBS_SKILL"; then
  no "54: a doctored SKILL.md fails the rung-pointer pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "54: a doctored SKILL.md fails the rung-pointer pin (pin discriminates)"
fi


section "Section 9: the tick interval, in every place it is written down (D-3)"
#
# THE GAP THIS CLOSES. The design ledger's tick-interval row named "docs-pins holds the
# sentence" as its agreement test, and docs-pins held no such thing: `grep -n '20m'
# tests/docs-pins.test.sh` returned nothing, and either SKILL.md sentence could have been
# reverted to 30m with the whole suite green. AC-19 states the sentences as a deliverable and
# names no pin for them (Step-6 duplication review D-3).
#
# FOUR SITES, ONE DEFAULT. Two SKILL.md sentences carry it as prose — the config knob and the
# cron-job cadence — hooks/session-poker.sh carries it as `POKER_INTERVAL_DEFAULT`, and
# lib/patrol.sh carries it a FOURTH time as `PATROL_INTERVAL_LAST_RESORT=1200`, a deliberate
# commented copy used only when the poker cannot be reached. That copy shipped stale once
# already (S8 fixed a 1800 in it), which is exactly the drift its own comment predicts, so
# the seconds are compared against the poker's own answer rather than asserted twice.
PIN_INTERVAL_KNOB='config knob `poker-interval:` in `.bionic/config.yaml`, default 20m'
PIN_INTERVAL_CRON='fires into a `command not found` every 20 minutes and reports nothing'
PATROL_LIB="${REPO}/payload/scripts/lib/patrol.sh"

if has_pin "$DISPATCH_MD" "$PIN_INTERVAL_KNOB"; then
  ok "55: SKILL.md names the poker-interval default as 20m, verbatim"
else
  no "55: SKILL.md names the poker-interval default as 20m, verbatim" "file: $DISPATCH_MD"
fi
if has_pin "$DISPATCH_MD" "$PIN_INTERVAL_CRON"; then
  ok "56: SKILL.md's cron sentence names the same cadence in minutes, verbatim"
else
  no "56: SKILL.md's cron sentence names the same cadence in minutes, verbatim" "file: $DISPATCH_MD"
fi

# THE TWO CONSTANTS AGREE, and the poker's own verb is what says so — `interval-default`
# ignores config by contract, so this is the built-in against the last resort and not one
# machine's `.bionic/config.yaml` against another's.
POKER_DEFAULT_SECS="$(bash "$POKER_SH" interval-default 2>/dev/null)"
PATROL_LAST_RESORT="$(sed -n 's/^PATROL_INTERVAL_LAST_RESORT=\([0-9][0-9]*\).*/\1/p' "$PATROL_LIB" | head -1)"
expect_eq "57: lib/patrol.sh's last-resort interval equals the poker's built-in default" \
  "$POKER_DEFAULT_SECS" "$PATROL_LAST_RESORT"
expect_eq "58: …and that default really is 20 minutes, in seconds" "1200" "$POKER_DEFAULT_SECS"

# ANTI-VACUITY, the same doctored-copy shape as 50/51/54: a SKILL.md whose interval was
# reverted to the pre-wave 30m must fail both prose pins.
anchor "$DISPATCH_MD" 'default 20m' 1
anchor "$DISPATCH_MD" 'every 20 minutes' 1
DOCTORED_INTERVAL="$TMP/skill-interval-mutated.md"
sed 's/default 20m/default 30m/; s/every 20 minutes/every 30 minutes/' "$DISPATCH_MD" > "$DOCTORED_INTERVAL"
if has_pin "$DOCTORED_INTERVAL" "$PIN_INTERVAL_KNOB" || has_pin "$DOCTORED_INTERVAL" "$PIN_INTERVAL_CRON"; then
  no "59: a doctored SKILL.md fails both interval pins (they discriminate)" \
     "a pin matched a copy carrying the pre-wave 30m"
else
  ok "59: a doctored SKILL.md fails both interval pins (they discriminate)"
fi

# ---------------------------------------------------------------------------
# SECTION 60-63 — S13: the instrument the brief declares (spec AC-20, AC-21)
# ---------------------------------------------------------------------------
#
# WHAT IT OWNS. `skills/canonical-sdlc/SKILL.md` §Dispatch is where an orchestrator reads
# what a brief must carry. The wall in `hooks/dispatch-preflight.sh` refuses a brief that
# carries neither `Files:` nor `Suites:`, and the writer-side guard refuses a suite outside
# the recorded set — so a §Dispatch section that never mentions either label documents a
# grammar the machine no longer accepts, and every author writes a brief that is refused.
# These pins hold the two labels, the waiver, and the one-regression rule in that section.
#
# THE ROLE FILES ARE NOT PINNED HERE. `agents-src/blocks/survival.md` is the writer-side
# copy and it is GENERATED into agents/*.md — identity by construction, checked by
# `agents-src/render.sh --check`, which section 7 above already calls. A second pin on the
# generated text would be pinning the renderer's arithmetic.
#
# ANTI-VACUITY, the doctored-copy shape sections 50/51/54/59 use: a SKILL.md with the
# instrument sentence removed must fail these pins.
section "SECTION 10 — S13: the instrument the brief declares (spec AC-20, AC-21)"

PIN_S13_FILES='`Files:` on a line of its own names the paths this task will write'
PIN_S13_DERIVE='the impact command named in `.bionic/config.yaml` turns them into the closed set of suites the agent may run'
PIN_S13_DECLARE='Where no impact command is configured, name the closed set yourself under `Suites:`'
PIN_S13_WAIVER='a brief that runs no suite at all waives with `Suites: none`'
PIN_S13_NEITHER='A brief carrying neither label refuses at dispatch.'
PIN_S13_REGRESSION='a second one refuses unless the plan'"'"'s `## SDLC State` carries a `regression-cause:` line for it'

for _p in FILES DERIVE DECLARE WAIVER NEITHER REGRESSION; do
  eval "_pv=\$PIN_S13_$_p"
  if has_pin "$DISPATCH_MD" "$_pv"; then
    ok "60: SKILL.md §Dispatch carries the S13 $_p sentence verbatim"
  else
    no "60: SKILL.md §Dispatch carries the S13 $_p sentence verbatim" "file: $DISPATCH_MD"
  fi
done

anchor "$DISPATCH_MD" '`Files:` on a line of its own names the paths this task will write' 1
DOCTORED_S13="$TMP/skill-s13-mutated.md"
sed 's/`Files:` on a line of its own names the paths this task will write/the brief says what it likes/' \
  "$DISPATCH_MD" > "$DOCTORED_S13"
if has_pin "$DOCTORED_S13" "$PIN_S13_FILES"; then
  no "61: a doctored SKILL.md fails the S13 FILES pin (it discriminates)" \
     "the pin matched a copy with the sentence removed"
else
  ok "61: a doctored SKILL.md fails the S13 FILES pin (it discriminates)"
fi

# THE WRITER-SIDE COPY EXISTS AND IS THE RENDERER'S INPUT. Not its text — its presence in
# the SOURCE block, so the sentence a dispatched agent reads cannot be edited into the
# generated file and lost at the next render (the failure mode agents-src exists to remove).
SURVIVAL_BLOCK="${REPO}/agents-src/blocks/survival.md"
PIN_S13_SURVIVAL='Your suite budget is on your roster row, and it is a wall.'
if has_pin "$SURVIVAL_BLOCK" "$PIN_S13_SURVIVAL"; then
  ok "62: the writer-side budget rule is in agents-src/blocks/survival.md, the rendered SOURCE"
else
  no "62: the writer-side budget rule is in agents-src/blocks/survival.md, the rendered SOURCE" \
     "file: $SURVIVAL_BLOCK"
fi
# …and it reached the rendered file the writer actually receives.
#
# RE-POINTED (wave-11 1c, was: every generated role file). The block renders once now; the
# delivered text is payload/context/survival.md. The companion non-vacuity arm asserts that
# file is non-empty, replacing the old "over a non-empty set of role files" guard.
SURVIVAL_SHIPPED_63="${REPO}/payload/context/survival.md"
expect_eq "63: …and the rendered payload/context/survival.md carries it" "0" \
  "$(has_pin "$SURVIVAL_SHIPPED_63" "$PIN_S13_SURVIVAL" && echo 0 || echo 1)"
expect_eq "63: …over a non-empty rendered file" "0" \
  "$([ -s "$SURVIVAL_SHIPPED_63" ] && echo 0 || echo 1)"

# THE SPELLING RULE THAT MAKES THE BUDGET USABLE (review-c C-6). The wall reads the command
# TEXT, so a loop variable is refused by its unexpanded name — and the one place a writer
# reads the budget rule said nothing about it. A fresh agent with no plan read hit exactly
# that on its first attempt (the walk, heading 10b). Pinned in the SOURCE block, and
# reaching every generated role file, on the same footing as the rule it qualifies.
PIN_S13_SPELLING='Spell each suite as a literal path and call it once per suite'
if has_pin "$SURVIVAL_BLOCK" "$PIN_S13_SPELLING"; then
  ok "63b: the spelling rule is in agents-src/blocks/survival.md, the rendered SOURCE"
else
  no "63b: the spelling rule is in agents-src/blocks/survival.md, the rendered SOURCE" \
     "file: $SURVIVAL_BLOCK"
fi
# RE-POINTED (wave-11 1c, was: every generated role file) — same move as 63.
expect_eq "63b: …and the rendered payload/context/survival.md carries it" "0" \
  "$(has_pin "$SURVIVAL_SHIPPED_63" "$PIN_S13_SPELLING" && echo 0 || echo 1)"

section "Section 11: the plugin renders whole — the skill file is a build output (wave-02 AC-1, AC-6, AC-8)"

# WHAT THIS SECTION OWNS. Until wave-02 S2a, `skills/canonical-sdlc/SKILL.md` was
# hand-written and four of its passages were hand-COPIED into role files under markers
# that said "canonical copy of skills/canonical-sdlc/SKILL.md §…" — a promise, with no
# test between the copies. r3's census found all four, and the irony that one of them IS
# the agreement-test obligation. The repair is not another pairwise diff arm: the skill
# file became the renderer's third unit and the four passages became blocks, so the
# copies are injections and cannot disagree. This section pins BOTH halves of that —
# that `--check` now sees the skill file at all (assertions 64-66, the defect control),
# and that each passage really is one text reaching every surface (67-71).
#
# ANTI-VACUITY. 64 is the positive control 65 and 66 mean nothing without: a clone that
# ALREADY failed --check would make any "the edit turned it red" arm true for free. The
# byte-identity arms (67-71) each assert against a NON-EMPTY extraction, because two
# empty strings are equal and an extractor that found nothing would otherwise pass every
# one of them.
#
# HERMETIC. The clone is a copy of the working tree's render inputs and outputs under
# the same mktemp dir the rest of this file uses; render.sh derives every directory from
# its own location, so the clone renders against its own outputs and the repo is never
# written.

RENDERED_MANIFEST="${REPO}/payload/integrity/rendered.sha256"
BLOCK_DIR="${REPO}/agents-src/blocks"
SKILL_TMPL="${REPO}/agents-src/templates/skills/canonical-sdlc/SKILL.md.tmpl"
OPRULES="${REPO}/skills/canonical-sdlc/operational-rules.md"

expect_true "64a: the skill file has a template (it is a render target, not a hand-written file)" \
  test -f "$SKILL_TMPL"
expect_true "64b: the renderer's unit table names the skill unit" \
  grep -qF 'agents-src/templates/skills/canonical-sdlc|skills/canonical-sdlc' "$RENDER_SH"
# THE STEPS UNIT IS ITS OWN ROW, and it has to be: every unit's template glob is one level
# deep, so without this row the ten step templates render nowhere and --check never looks at
# them. `dispatch.md.tmpl` deliberately has NO row — it sits in the directory the skill unit
# above already globs.
expect_true "64b2: …and the per-step unit, which the one-level-deep glob cannot reach from it" \
  grep -qF 'agents-src/templates/skills/canonical-sdlc/steps|skills/canonical-sdlc/steps' "$RENDER_SH"

# clone_render_tree <dest> — the render inputs and outputs, and nothing else.
clone_render_tree() {
  local dest="$1"
  mkdir -p "$dest/payload/commands" "$dest/payload/.claude-plugin" "$dest/payload/integrity" \
           "$dest/payload/context" "$dest/skills/canonical-sdlc/steps" \
           "$dest/agents" || return 1
  cp -R "${REPO}/agents-src" "$dest/agents-src" || return 1
  cp "${REPO}"/agents/*.md "$dest/agents/" || return 1
  cp "${REPO}"/payload/commands/*.md "$dest/payload/commands/" || return 1
  # The fourth render unit's output (wave-11 1c) — omit it and every fixture below
  # renders against a missing final.
  cp "${REPO}"/payload/context/*.md "$dest/payload/context/" || return 1
  cp "${REPO}/payload/.claude-plugin/plugin.json" "$dest/payload/.claude-plugin/" || return 1
  # EVERY rendered final under skills/canonical-sdlc, not just SKILL.md (wave-11 row 1b). A
  # clone missing the step files or the dispatch reference renders them fresh and then reports
  # every one of them as staleness, which would redden 65's control arm for a reason that has
  # nothing to do with the mutation 66 and 67 are about. `steps/` is a committed output
  # directory, so the mkdir above creates it whether or not it holds anything yet — the
  # renderer's preflight dies on a missing output directory.
  cp "${REPO}/skills/canonical-sdlc/SKILL.md" "$dest/skills/canonical-sdlc/" || return 1
  cp "${REPO}/skills/canonical-sdlc/dispatch.md" "$dest/skills/canonical-sdlc/" || return 1
  cp "${REPO}"/skills/canonical-sdlc/steps/*.md "$dest/skills/canonical-sdlc/steps/" || return 1
  [ -f "$RENDERED_MANIFEST" ] && cp "$RENDERED_MANIFEST" "$dest/payload/integrity/"
  return 0
}

CLONE="$TMP/render-clone"
if clone_render_tree "$CLONE"; then
  ok "64: a clone of the render tree is built (the fixture 65 and 66 mutate)"
else
  no "64: a clone of the render tree is built (the fixture 65 and 66 mutate)" "dest: $CLONE"
fi

# THE POSITIVE CONTROL. An unedited clone must be clean, or every "the edit turned it
# red" arm below is true for a reason that has nothing to do with the edit.
if bash "$CLONE/agents-src/render.sh" --check >/dev/null 2>&1; then
  ok "65: the unedited clone passes --check (the control the next two arms need)"
else
  no "65: the unedited clone passes --check (the control the next two arms need)" \
     "run 'bash $CLONE/agents-src/render.sh --check' for the diff"
fi

# THE DEFECT CONTROL FOR AC-1: one hand edit to the rendered skill file.
sed -i.bak 's/^# Canonical SDLC$/# Canonical SDLC (hand-edited)/' \
  "$CLONE/skills/canonical-sdlc/SKILL.md" 2>/dev/null
rm -f "$CLONE/skills/canonical-sdlc/SKILL.md.bak"
CHECK_OUT="$(bash "$CLONE/agents-src/render.sh" --check 2>&1)"
CHECK_RC=$?
expect_ne "66a: one hand edit to skills/canonical-sdlc/SKILL.md turns --check red" "0" "$CHECK_RC"
expect_match "66b: …and the diff names the file it rejected" \
  "*skills/canonical-sdlc/SKILL.md*" "$CHECK_OUT"

# THE SAME FOR THE WIDENED MANIFEST'S OTHER HALF: a command page is a rendered file too,
# and before this task the manifest answered only for the six role files.
CLONE2="$TMP/render-clone-2"
clone_render_tree "$CLONE2" || true
printf '\nhand-edited\n' >> "$CLONE2/payload/commands/help.md"
CHECK_OUT2="$(bash "$CLONE2/agents-src/render.sh" --check 2>&1)"
expect_ne "67a: one hand edit to a rendered command page turns --check red" "0" "$?"
expect_match "67b: …and the diff names that page" "*commands/help.md*" "$CHECK_OUT2"

# A STRAY TEMPLATE IN THE ROLE UNIT'S OWN DIRECTORY (W4 4/4, AC-15). A `.md.tmpl` that
# names anything other than a current role and lands directly in `agents-src/templates/`
# must never render — no `agents/<name>.md`, no row in either manifest — or a future
# addition there would ship an un-rostered seventh role file invisible to --check.
CLONE3="$TMP/render-clone-3"
clone_render_tree "$CLONE3" || true
{
  echo '---'
  echo 'name: not-a-role'
  echo '---'
  echo '<!-- GENERATED-HEADER -->'
  echo 'stray, never rendered'
} > "$CLONE3/agents-src/templates/not-a-role.md.tmpl"
WRITE_OUT3="$(bash "$CLONE3/agents-src/render.sh" 2>&1)"
WRITE_RC3=$?
expect_eq "68a: a stray template beside the six roles does not fail the render" "0" "$WRITE_RC3"
expect_true "68b: …and it renders no agents/not-a-role.md at all" \
  bash -c '[ ! -e "$1" ]' _ "$CLONE3/agents/not-a-role.md"
CHECK_OUT3="$(bash "$CLONE3/agents-src/render.sh" --check 2>&1)"
expect_eq "68c: …so --check still passes with the stray template still sitting there" \
  "0" "$?"

# ── The four passages: one text, every surface ──────────────────────────────
#
# marker_span reads the injection markers render.sh writes, so the extraction follows the
# renderer's own contract rather than a second guess at where a passage starts.
marker_span() {  # <file> <MARKER-NAME>
  awk -v m="$2" '
    $0 == "<!-- " m "-BEGIN -->" { inp = 1; next }
    $0 == "<!-- " m "-END -->"   { inp = 0 }
    inp { print }
  ' "$1" 2>/dev/null
}

# same_everywhere <n> <label> <block-file> <marker> <surface...>
same_everywhere() {
  local n="$1" label="$2" blockfile="$3" marker="$4"; shift 4
  local body surface span bad=""
  body="$(cat "$blockfile" 2>/dev/null)"
  if [ -z "$body" ]; then
    no "${n}: ${label}" "the block ${blockfile##*/} is missing or empty — an empty pin proves nothing"
    return
  fi
  for surface in "$@"; do
    span="$(marker_span "$surface" "$marker")"
    [ "$span" = "$body" ] || bad="${bad} ${surface#${REPO}/}"
  done
  if [ -z "$bad" ]; then
    ok "${n}: ${label}"
  else
    no "${n}: ${label}" "differs from ${blockfile##*/} in:${bad} — run 'bash agents-src/render.sh'"
  fi
}

# RE-POINTED TWICE, AND THIS MERGE RECONCILES BOTH (wave-11 1c + row 1b; was: the block, the
# skill file and agents/auditor.md). 1c: the orchestrator's dispatch carries the mandate
# VERBATIM to the auditor (canonical-sdlc Step 5), so agents/auditor.md stopped injecting a
# second copy and points at the dispatch instead. Row 1b: the skill's Step-5 text moved out
# of SKILL.md into steps/5.md, so the surviving skill-side surface is that file. Two surfaces
# remain, and the arms below pin that the role file really did give the copy up rather than
# keep a stale one.
same_everywhere 68 "the auditor mandate is one text in the block and the skill's Step-5 file" \
  "${BLOCK_DIR}/auditor-mandate.md" "AUDITOR-MANDATE" "$STEP5_MD"
expect_absent "68d: …and agents/auditor.md no longer carries an injected copy of it" \
  "AUDITOR-MANDATE-BEGIN" "$(cat "${REPO}/agents/auditor.md")"
expect_contains "68e: …it points at the dispatch brief instead" \
  "Your mandate arrives verbatim in the dispatch brief and is authoritative." \
  "$(cat "${REPO}/agents/auditor.md")"

same_everywhere 69 "the critic prompt template is one text in the block, the skill file and agents/critic.md" \
  "${BLOCK_DIR}/critic-template.md" "CRITIC-TEMPLATE" "$STEP6_MD" "${REPO}/agents/critic.md"

same_everywhere 70 "the duplication axis is one text in the block, the skill file and agents/critic.md" \
  "${BLOCK_DIR}/duplication-axis.md" "DUPLICATION-AXIS" "$STEP6_MD" "${REPO}/agents/critic.md"

same_everywhere 71 "the terminal-disposition rule is one text in the block and the skill file" \
  "${BLOCK_DIR}/terminal-disposition.md" "TERMINAL-DISPOSITION" "$STEP9_MD"

same_everywhere 72 "the orchestrator's dispatch body is one text in the block and the skill file" \
  "${BLOCK_DIR}/orchestrator-dispatch.md" "ORCHESTRATOR-DISPATCH" "$DISPATCH_MD"

# The duplicate that had no renderer at all: two hand-written files carrying one span.
expect_true "73a: operational-rules.md no longer carries its own copy of the rule" \
  test -f "$OPRULES"
expect_absent "73b: …the TERMDISP span is gone from it" "TERMDISP" "$(cat "$OPRULES")"
expect_contains "73c: …and it points at the block instead" \
  "agents-src/blocks/terminal-disposition.md" "$(cat "$OPRULES")"

# ── The manifest covers every rendering (AC-8) ──────────────────────────────
expect_true "74a: payload/integrity/rendered.sha256 exists" test -f "$RENDERED_MANIFEST"
expect_false "74b: payload/integrity/agents.sha256 is gone" \
  test -f "${REPO}/payload/integrity/agents.sha256"
MANIFEST_BODY="$(grep -v '^#' "$RENDERED_MANIFEST" 2>/dev/null | grep -v '^[[:space:]]*$')"
# TWENTY-FOUR AT THIS MERGE, reconciling both wave-11 rows against the twelve that came
# before them: six roles, five commands, the split skill's twelve finals (the core, ten step
# files and the dispatch reference — row 1b, +11) and payload/context/survival.md, the fourth
# render unit's one output (1c, +1). The number is hard-coded rather than counted from the
# tree on purpose, exactly as it was at twelve: a count derived from whatever the renderer
# just produced would agree with itself no matter what the renderer dropped.
expect_eq "74c: it carries one row per rendered file (six roles, five commands, the split skill's twelve, the dispatch terms)" \
  "24" "$(printf '%s\n' "$MANIFEST_BODY" | wc -l | tr -d ' ')"
expect_contains "74c2: …including a step file, plugin-root-relative" \
  "  skills/canonical-sdlc/steps/4.md" "$MANIFEST_BODY"
expect_contains "74c3: …and the dispatch reference" \
  "  skills/canonical-sdlc/dispatch.md" "$MANIFEST_BODY"
expect_contains "74g: …and the once-rendered dispatch terms, plugin-root-relative" \
  "  context/survival.md" "$MANIFEST_BODY"
expect_contains "74d: …including the skill file, plugin-root-relative" \
  "  skills/canonical-sdlc/SKILL.md" "$MANIFEST_BODY"
expect_contains "74e: …and the command pages, plugin-root-relative" \
  "  commands/help.md" "$MANIFEST_BODY"
expect_contains "74f: …and the role files, plugin-root-relative" \
  "  agents/auditor.md" "$MANIFEST_BODY"

# The one runtime consumer reads the file the renderer now writes. Named here because a
# rename that missed it would leave doctor answering `unknown` on every machine.
expect_contains "75: payload/scripts/lib/detect.sh reads integrity/rendered.sha256" \
  'integrity/rendered.sha256' "$(cat "$DETECT_SH")"
expect_absent "75b: …and names the deleted manifest nowhere" \
  'integrity/agents.sha256' "$(cat "$DETECT_SH")"

# ── Section 6: K3 — premise text (AC-K3.1, AC-K3.2) ─────────────────────────
#
# ideas/bug-premise-decisions-surface-at-the-pr.md F1/F2 (D3 keeps F1/F2, cuts F3;
# adrs: is F4, covered by tests/canonical-sdlc-governing-skill.test.sh instead — a
# hook wall, not a doc-text pin). Both ACs are STATIC: docs-pins reads the rendered
# Step-2 Design Interview frame span (SKILL.md, "Open with the frame" paragraph)
# byte-for-byte, the same `has_pin` idiom §1-§5 use.
section "Section 6: K3 — premise text (Context/Problem first, Mechanisms inherited)"

# AC-K3.1: Context and Problem is the FIRST thing the frame approves — ahead of
# the orchestrator's own design intuition and every decision below it. Pinned as
# one substring spanning the frame's opening clause straight into the
# Context-and-Problem sentence, so the pin itself IS an adjacency (hence order)
# check: it can only match a copy where nothing has been inserted, or swapped
# in, between "before any question." and "Its first approval is
# **Context and Problem". RE-ANCHORED (epic-23 wave-13 T2, AC-8.1/AC-8.2): the
# heading lost its ", for a stranger" clause — the explanation itself
# ("written as if for a reader who has never opened this repo") stays, just not
# folded into the bold span — and "ratification" became "approval" (the T2
# ratif→approv sweep).
PIN_K3_FIRST='**Open with the frame**, before any question. Its first approval is **Context and Problem**'

# AC-K3.2, half 1: the frame carries a "Mechanisms inherited" item, each line
# marked kept or questioned.
PIN_K3_MECH='**Mechanisms inherited**, one line per substrate or mechanism the design builds on, each marked `kept` or `questioned`'

# AC-K3.2, half 2: placement decisions (tier / runtime surface / hardware) are
# named strategic BY RULE, not left to a default.
PIN_K3_STRATEGIC='placing a test cohort in a tier, a job on a runtime surface, or a workload on hardware is **strategic by rule**'

if has_pin "$STEP2_MD" "$PIN_K3_FIRST"; then
  ok "76: SKILL.md's Step-2 frame approves Context and Problem first"
else
  no "76: SKILL.md's Step-2 frame approves Context and Problem first" "file: $STEP2_MD"
fi

if has_pin "$STEP2_MD" "$PIN_K3_MECH"; then
  ok "77: …and carries a Mechanisms inherited item, each kept or questioned"
else
  no "77: …and carries a Mechanisms inherited item, each kept or questioned" "file: $STEP2_MD"
fi

if has_pin "$STEP2_MD" "$PIN_K3_STRATEGIC"; then
  ok "78: …and names tier/runtime-surface/hardware placement strategic by rule"
else
  no "78: …and names tier/runtime-surface/hardware placement strategic by rule" "file: $STEP2_MD"
fi

# --- Anti-vacuity: the same pins must discriminate a mutated copy ---

# 79: ORDER REVERSED (AC-K3.1's own fails-when). The doctored copy swaps the
# Context-and-Problem sentence and the Design-intuition sentence in place — the
# literal shape of "the order is reversed" — rather than deleting anything, so a
# pin that merely checked PRESENCE of both phrases would stay green through it.
anchor -E "$STEP2_MD" 'Its first approval is \*\*Context and Problem\*\*' 1
DOCTORED_K3_ORDER="$TMP/skill-k3-order-reversed.md"
sed -E '
s/(\*\*Open with the frame\*\*, before any question\. )(Its first approval is \*\*Context and Problem\*\*: the problem and the goal, written as if for a reader who has never opened this repo; this comes before your own design intuition and before every decision in the frame below it — a change not yet explainable to someone who was not there is not yet understood\. )(Then your own \*\*Design intuition\*\*, the shape you expect to be right, stated so the user can push on it; )/\1\3\2/
' "$STEP2_MD" > "$DOCTORED_K3_ORDER"
if has_pin "$DOCTORED_K3_ORDER" "$PIN_K3_FIRST"; then
  no "79: order-reversed SKILL.md fails the first-approval pin (pin discriminates)" \
     "the mutated copy still matched — the pin does not see the reorder"
else
  ok "79: order-reversed SKILL.md fails the first-approval pin (pin discriminates)"
fi
# Control: prove the doctored copy really moved Design intuition ahead of
# Context and Problem, rather than merely mangling the text into something that
# happens to fail the pin for an unrelated reason.
expect_contains "79b: …and the doctored copy really does read Design intuition, then Context and Problem" \
  'Then your own **Design intuition**, the shape you expect to be right, stated so the user can push on it; Its first approval is **Context and Problem' \
  "$(cat "$DOCTORED_K3_ORDER")"

# 80: Mechanisms inherited ABSENT (AC-K3.2's fails-when). The strategic-by-rule
# clause stays untouched in this copy — proof the mutation removed only the
# Mechanisms-inherited item, not the whole paragraph.
anchor "$STEP2_MD" 'Mechanisms inherited' 1
DOCTORED_K3_MECH="$TMP/skill-k3-mechanisms-absent.md"
sed 's/\*\*Mechanisms inherited\*\*, one line per substrate or mechanism the design builds on, each marked `kept` or `questioned` — a `questioned` line becomes a strategic fork; //' \
  "$STEP2_MD" > "$DOCTORED_K3_MECH"
if has_pin "$DOCTORED_K3_MECH" "$PIN_K3_MECH"; then
  no "80: SKILL.md with Mechanisms inherited stripped still passes the mech pin (pin discriminates)" \
     "the mutated copy still matched — the pin does not see the removal"
else
  ok "80: SKILL.md with Mechanisms inherited stripped still passes the mech pin (pin discriminates)"
fi
if has_pin "$DOCTORED_K3_MECH" "$PIN_K3_STRATEGIC"; then
  ok "80b: …and the strategic-by-rule clause survives untouched in the same copy (isolated mutation)"
else
  no "80b: …and the strategic-by-rule clause survives untouched in the same copy (isolated mutation)" \
     "the mutation removed more than the Mechanisms-inherited clause"
fi

# 81: "strategic by rule" ABSENT (AC-K3.2's other half). Mechanisms inherited
# stays untouched here, the mirror-image isolation check of 80b.
anchor "$STEP2_MD" 'strategic by rule' 1
DOCTORED_K3_STRAT="$TMP/skill-k3-strategic-absent.md"
sed "s/is \\*\\*strategic by rule\\*\\* and is never defaulted/is left to the writer's judgment/" \
  "$STEP2_MD" > "$DOCTORED_K3_STRAT"
if has_pin "$DOCTORED_K3_STRAT" "$PIN_K3_STRATEGIC"; then
  no "81: SKILL.md with strategic-by-rule stripped still passes the strategic pin (pin discriminates)" \
     "the mutated copy still matched — the pin does not see the removal"
else
  ok "81: SKILL.md with strategic-by-rule stripped still passes the strategic pin (pin discriminates)"
fi
if has_pin "$DOCTORED_K3_STRAT" "$PIN_K3_MECH"; then
  ok "81b: …and Mechanisms inherited survives untouched in the same copy (isolated mutation)"
else
  no "81b: …and Mechanisms inherited survives untouched in the same copy (isolated mutation)" \
     "the mutation removed more than the strategic-by-rule clause"
fi

section "Section 12: K1 — the Step-0 confirmation display is a settings-only card (spec §Eval design K1, plan task 15)"
#
# WHAT THIS SECTION OWNS. D1 (design ledger record/wave-01-plugin-only/design-ledger.md §D1)
# moves the Verification Matrix to Step 3 and cuts per-line inference rationale from Step 0:
# the confirmation display becomes a ten-section settings card — Purpose, Seed, Run, Branches,
# Paths, Machine, Shape, Gates, Models, Warnings — ending in a direct approval question. AC-K1.1
# pins the section names and their order; AC-K1.2 pins the matrix's absence; AC-K1.3 pins that
# Branches always carries both the working and the integration line (Chris: "You must always
# include the working branch and integration branch.").
#
# ANTI-VACUITY, same discriminate-a-doctored-copy pattern as the sections above: each extractor
# is re-run against a copy mutated to reproduce the AC's own "fails-when", and must go red.

# step0_card <file> -> the fenced Step-0 card, header line through the closing fence.
step0_card() {
  awk '/^Step 0 · Plan Configuration$/{f=1} f{print} f&&/^```$/{exit}' "$1" 2>/dev/null
}

STEP0_CARD="$(step0_card "$STEP0_MD")"

expect_true "76: the Step-0 card block is found in SKILL.md" \
  test -n "$STEP0_CARD"

K1_EXPECTED_SECTIONS="Purpose
Seed
Run
Branches
Paths
Machine
Shape
Gates
Models
Warnings"
K1_SECTION_RE='^  (Purpose|Seed|Run|Branches|Paths|Machine|Shape|Gates|Models|Warnings)([[:space:]]|$)'
K1_ACTUAL_SECTIONS="$(printf '%s\n' "$STEP0_CARD" | grep -E "$K1_SECTION_RE" | sed -E 's/^  ([A-Za-z]+).*/\1/')"

expect_eq "77: AC-K1.1 — the Step-0 card carries the ten sections, in order (fails-when: card partially rendered)" \
  "$K1_EXPECTED_SECTIONS" "$K1_ACTUAL_SECTIONS"

expect_absent "78: AC-K1.2 — no Verification Matrix table renders in the Step-0 card (fails-when: the matrix is left in)" \
  "Verification Matrix" "$STEP0_CARD"

expect_contains "79a: AC-K1.3 — Branches carries the working branch line (fails-when: one branch line dropped)" \
  "    working" "$STEP0_CARD"
expect_contains "79b: AC-K1.3 — …and the integration branch line" \
  "    integration" "$STEP0_CARD"

# --- Anti-vacuity: each extractor must go red on the fails-when it names ---

# 80: a card with a whole section dropped (Gates) fails K1.1's order check.
anchor -E "$STEP0_MD" '^  Gates$' 1
DOCTORED_NO_GATES="$TMP/skill-k1-no-gates.md"
sed '/^  Gates$/,/^$/d' "$STEP0_MD" > "$DOCTORED_NO_GATES"
DOCTORED_SECTIONS_80="$(printf '%s\n' "$(step0_card "$DOCTORED_NO_GATES")" | grep -E "$K1_SECTION_RE" | sed 's/^  //')"
if [ "$DOCTORED_SECTIONS_80" = "$K1_EXPECTED_SECTIONS" ]; then
  no "80: a Step-0 card partially rendered (a section dropped) fails the order check (pin discriminates)" \
     "the mutated copy still matched the expected order — the pin is vacuous"
else
  ok "80: a Step-0 card partially rendered (a section dropped) fails the order check (pin discriminates)"
fi

# 81: a card with the matrix left in fails K1.2.
anchor -E "$STEP0_MD" '^Step 0 · Plan Configuration$' 1
DOCTORED_MATRIX_BACK="$TMP/skill-k1-matrix-back.md"
awk '{print} /^Step 0 · Plan Configuration$/{print "  Verification Matrix:"}' "$STEP0_MD" > "$DOCTORED_MATRIX_BACK"
DOCTORED_CARD_81="$(step0_card "$DOCTORED_MATRIX_BACK")"
case "$DOCTORED_CARD_81" in
  *"Verification Matrix"*) ok "81: a Step-0 card with the matrix left in fails the no-matrix check (pin discriminates)" ;;
  *) no "81: a Step-0 card with the matrix left in fails the no-matrix check (pin discriminates)" \
        "the mutated copy did not carry the matrix string — the mutation is a no-op" ;;
esac

# 82: a card missing the integration branch line fails K1.3.
#
# ONE PER FILE NOW, WHERE IT USED TO BE FOUR IN ONE (wave-11 row 1b). The fact this pin holds
# has not changed since epic-22 K2 landed it: all four cards carry the same branch pair, so a
# reader of any one of them learns where the work lands and where it merges. What changed is
# that the four cards live in four files, which turns a single count of 4 into four counts of
# 1 — and, because the count alone no longer says WHICH files, a fifth assertion that the core
# carries none, since a card left behind in the core would keep the total at four while
# defeating the split.
#
# The anchor immediately below is the mutation's own precondition and reads the ONE file the
# `sed` under it rewrites; the four rows after it are the K2 fact, restated across the split.
for _cardfile in "$STEP0_MD" "$STEP1_MD" "$STEP2_MD" "$STEP3_MD"; do
  expect_eq "82pre.${_cardfile##*/}: AC-K1.3 — this step file's card carries exactly one integration branch line" \
    "1" "$(grep -c '^    integration   ' "$_cardfile" 2>/dev/null | tr -cd '0-9')"
done
expect_eq "82pre.core: …and the core carries none, so no card was left behind in it" \
  "0" "$(grep -c '^    integration   ' "$SKILL_MD" 2>/dev/null | tr -cd '0-9')"
anchor "$STEP0_MD" '    integration   ' 1
DOCTORED_NO_INTEGRATION="$TMP/skill-k1-no-integration.md"
sed '/^    integration   /d' "$STEP0_MD" > "$DOCTORED_NO_INTEGRATION"
DOCTORED_CARD_82="$(step0_card "$DOCTORED_NO_INTEGRATION")"
case "$DOCTORED_CARD_82" in
  *"    integration"*) no "82: a Step-0 card missing the integration branch line still 'has' it (pin is vacuous)" ;;
  *) ok "82: a Step-0 card missing the integration branch line fails the branch-pair check (pin discriminates)" ;;
esac

# ---------------------------------------------------------------------------
section "Section 13: the Step-1/2/3 cards and the spec's Eval design table (epic-22 K2, AC-K2.1/AC-K2.2)"
# ---------------------------------------------------------------------------
#
# WHAT THIS SECTION OWNS. Steps 0-3 each end at a gate, and since the wave-01-plugin-only
# design interview each of those gates ends with a CARD: one line per item, never a
# paragraph, the artifact path for the depth. Step 0's card is task 15's; this section
# owns the other three, plus the `## Eval design` table the Step-2 spec authors and the
# Step-3 card renders.
#
# WHY A DOC PIN AND NOT A HOOK ARM. No hook can see a conversation — the cards are
# printed to a terminal and never written to a file — so the skill's literal template is
# the whole enforcement, exactly as `SKILL.md`'s own "This layout is literal" defence
# says of the Step-0 block. What a test CAN hold is that the template is still there and
# still carries the rows the user ratified; a card silently shortened back into prose is
# the failure this section is pointed at.
#
# ANTI-VACUITY. Every arm below reads the RENDERED, shipped file
# (`payload/skills/canonical-sdlc/SKILL.md`), never the template, so a template edit that
# was never rendered cannot make it green; Section 11's `--check` arms are what tie the
# two together. The two grep helpers are re-run against a DOCTORED copy at the end of the
# section, and must report the loss — a pin that only ever reads an agreeing file could
# be vacuously true by extractor bug.
#
# HERMETIC. Reads the committed file by path; the doctored copy lives under this file's
# own mktemp dir.

# card_span <file> <card heading line> -> the fenced block that follows the heading,
# empty when the heading or its fence is absent. The cards are fenced literals, the same
# shape Step 0's confirmation display uses, so the extractor follows the fence.
card_span() {
  awk -v h="$2" '
    index($0, h) == 1 { inb = 1 }
    inb && /^```/ { exit }
    inb { print }
  ' "$1" 2>/dev/null
}

# has_all <text> <needle>... -> 0 when every needle is present
has_all() {
  local hay="$1"; shift
  local n
  for n in "$@"; do
    case "$hay" in *"$n"*) : ;; *) return 1 ;; esac
  done
  return 0
}

CARD1="$(card_span "$STEP1_MD" 'Step 1 · Requirements')"
CARD2="$(card_span "$STEP2_MD" 'Step 2 · Design')"
CARD3="$(card_span "$STEP3_MD" 'Step 3 · Plan')"

expect_true "90a: the Step-1 card is a fenced literal in the skill file" test -n "$CARD1"
expect_true "90b: the Step-2 card is a fenced literal in the skill file" test -n "$CARD2"
expect_true "90c: the Step-3 card is a fenced literal in the skill file" test -n "$CARD3"

# --- the ratified rows, per card -------------------------------------------
#
# The row NAMES are the ratification (design ledger §"Cards ratified" and §"Step-3 card
# ratified"): Step 1 is purpose/requirements/not-doing/artifact, Step 2 is
# decisions/ownership/eval-design/open/artifacts, Step 3 is
# problem/branches/tasks/width/eval-design/verification/open/artifacts.
if has_all "$CARD1" "Purpose" "Requirements" "Not Doing" "Artifacts"; then
  ok "91a: the Step-1 card carries Purpose, Requirements, Not Doing and Artifacts"
else
  no "91a: the Step-1 card carries Purpose, Requirements, Not Doing and Artifacts" \
     "card body: $CARD1"
fi
if has_all "$CARD1" "provenance" "ACs"; then
  ok "91b: …and a requirement row names its provenance and its criteria count"
else
  no "91b: …and a requirement row names its provenance and its criteria count" "card body: $CARD1"
fi

if has_all "$CARD2" "Decisions" "serves" "ADR" "Ownership" "Eval design" "Open at approval" "Artifacts"; then
  ok "92a: the Step-2 card carries Decisions (serves/ADR), Ownership, Eval design, Open at approval, Artifacts"
else
  no "92a: the Step-2 card carries Decisions (serves/ADR), Ownership, Eval design, Open at approval, Artifacts" \
     "card body: $CARD2"
fi
if has_all "$CARD2" "static" "unit" "hermetic" "live" "human" "total"; then
  ok "92b: …and its Eval design is one row per requirement with the five type counts and a total"
else
  no "92b: …and its Eval design is one row per requirement with the five type counts and a total" \
     "card body: $CARD2"
fi

if has_all "$CARD3" "Problem" "Branches" "Tasks" "kind" "depends" "agent" \
                    "Eval design" "Verification" "Open at approval" "Artifacts"; then
  ok "93a: the Step-3 card carries Problem, Branches, Tasks (kind/depends/agent), Eval design, Verification, Open at approval, Artifacts"
else
  no "93a: the Step-3 card carries Problem, Branches, Tasks (kind/depends/agent), Eval design, Verification, Open at approval, Artifacts" \
     "card body: $CARD3"
fi
if has_all "$CARD3" "first batch"; then
  ok "93b: …and the parallel width names its first batch"
else
  no "93b: …and the parallel width names its first batch" "card body: $CARD3"
fi

# --- both branch lines, on every card --------------------------------------
#
# The working branch alone is half an answer: a reader cannot tell where the wave LANDS.
# Chris corrected exactly this on the Step-0 display (2026-09-07), and the correction is
# a property of every card, not of one.
for _pair in "94a:$CARD1:Step-1" "94b:$CARD2:Step-2" "94c:$CARD3:Step-3"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _body="${_rest%:*}"; _which="${_rest##*:}"
  if has_all "$_body" "working" "integration"; then
    ok "${_n}: the ${_which} card carries BOTH branch lines (working + integration)"
  else
    no "${_n}: the ${_which} card carries BOTH branch lines (working + integration)" "card body: $_body"
  fi
done

# --- the gate wording, verbatim on all three --------------------------------
#
# One word is the gate. The ratified sentence is a QUESTION plus the literal reply, and
# a look-closer line beneath it; the bare footer menu it replaced was rejected by name.
expect_contains "95a: the Step-1 card asks the approved question" \
  'Do you approve these requirements? Reply "approved" to approve it.' "$CARD1"
expect_contains "95b: the Step-2 card asks the approved question" \
  'Do you approve this design? Reply "approved" to approve it.' "$CARD2"
expect_contains "95c: the Step-3 card asks the approved question" \
  'Do you approve this plan? Reply "approved" to approve it.' "$CARD3"
expect_contains "95d: the Step-2 card's look-closer line opens one requirement's evals" \
  'show evals <req>' "$CARD2"
expect_contains "95e: the Step-3 card's look-closer line opens one task" \
  'show task <n>' "$CARD3"

# --- AC-K2.2: the spec template's Eval design table -------------------------
STEP2_BODY="$(cat "$STEP2_MD" 2>/dev/null)"
expect_contains "96a: the skill names the spec's section '## Eval design'" \
  '## Eval design' "$STEP2_BODY"
EVAL_HEADER="$(grep -m1 -F '| Requirement | Approach |' "$STEP2_MD" 2>/dev/null)"
expect_true "96b: …and gives it a column header row" test -n "$EVAL_HEADER"
for _col in Requirement Approach Criterion "Eval type" Eval "Fails when"; do
  expect_contains "96c: …carrying the ratified column '$_col'" "$_col" "$EVAL_HEADER"
done
expect_contains "96d: …and states the invariant that gives the sixth column its force" \
  'is not an eval' "$STEP2_BODY"

# --- Anti-vacuity: the spans are BOUNDED, and each card is in its own file ---
#
# THE FAILURE THIS GUARDS. `card_span` prints from a heading to the next fence. An extractor
# that lost its terminator — or a card whose closing fence was deleted — would return the REST
# OF THE FILE, and every `has_all` above would then pass on words found hundreds of lines away
# in prose that has nothing to do with a card.
#
# HOW THIS IS STATED AFTER THE SPLIT (wave-11 row 1b). Until the split the three cards sat in
# one file in the order Step 1 → Step 2 → Step 3 → Step-5 prose, and each span was bounded by
# naming the NEXT card's question: text that was in the file but outside the span. The cards
# are now one per step file, so that phrasing would be vacuous — an unbounded Step-1 span runs
# to the end of `steps/1.md` and still never reaches the Step-2 card's question, which is in a
# different file. The same two facts are asserted instead, and they are strictly harder to
# satisfy by accident:
#
#   (a) each card's question appears in its OWN step file and in NO other one and not in the
#       core, which is boundedness and correct placement in one statement — an unbounded span
#       cannot swallow a neighbouring card, because the neighbour is not in its file, and a
#       card left behind in the core fails here rather than passing quietly;
#   (b) the ten step files exist, in order, so "it is in its own file" is a claim about a
#       roster that is itself checked rather than about whichever files happen to be present.
#
# The Step-5 sentence 97c used to reach for is pinned in (a)'s shape too: `Wave shape locks at
# approval` closes Step 3, so `steps/3.md` is where it must be and the Step-3 CARD is where it
# must not.
_CARD_Q1='Do you approve these requirements?'
_CARD_Q2='Do you approve this design?'
_CARD_Q3='Do you approve this plan?'
for _spec in "1:$_CARD_Q1" "2:$_CARD_Q2" "3:$_CARD_Q3"; do
  _owner="${_spec%%:*}"; _q="${_spec#*:}"
  _homes=""
  for _n in 0 1 2 3 4 5 6 7 8 9; do
    eval "_f=\"\${SKILL_DIR}/steps/${_n}.md\""
    grep -qF -- "$_q" "$_f" 2>/dev/null && _homes="${_homes}${_n} "
  done
  grep -qF -- "$_q" "$SKILL_MD" 2>/dev/null && _homes="${_homes}core "
  expect_eq "97a.$_owner: the Step-$_owner card's question lives in steps/$_owner.md and nowhere else" \
    "$_owner " "$_homes"
done

# 97b: the card span really is bounded — the Step-3 card stops before the Step-3 prose that
# follows it in the same file, which is the one place the old in-file phrasing still applies.
expect_absent "97b: the Step-3 card's span stops before the Step-3 prose below it in steps/3.md" \
  'Wave shape locks at approval' "$CARD3"

# 97c: the roster (b) — ten step files, in order, each a real file.
_STEPS_PRESENT=""
for _n in 0 1 2 3 4 5 6 7 8 9; do
  [ -f "${SKILL_DIR}/steps/${_n}.md" ] && _STEPS_PRESENT="${_STEPS_PRESENT}${_n}"
done
expect_eq "97c: the ten step files exist, in order (fails-when: a step file is missing)" \
  "0123456789" "$_STEPS_PRESENT"

# …and the positive 97b needs: the sentence it says is outside the card really is in that
# card's file, so the absence cannot be an absence from the whole document.
expect_contains "97d: …and the Step-3 sentence 97b excludes does exist in steps/3.md" \
  'Wave shape locks at approval' "$(cat "$STEP3_MD" 2>/dev/null)"

# --- the authoring half, in operational-rules.md ----------------------------
#
# SKILL.md carries the CONTRACT (the six columns, the ladder, the refusal). The authoring
# guidance lives beside the other Step-2 back-half sections, which is where a writer filling
# a table in actually looks. That file is hand-written, not a render target, so nothing but
# this pin holds the two halves together.
OPRULES_BODY="$(cat "$OPRULES" 2>/dev/null)"
expect_contains "97f: operational-rules.md carries the Eval design authoring section" \
  '### The Eval design table' "$OPRULES_BODY"
expect_contains "97g: …and it states the rule the sixth column exists for" \
  'PLANTED DEFECT' "$OPRULES_BODY"
expect_contains "97h: …and sends an unfalsifiable criterion back to Step 1" \
  'goes back to Step 1' "$OPRULES_BODY"

# The Eval design header is one row, not a swallowed table: the extractor takes the first
# match only, so a second header row elsewhere cannot be what the column checks read.
expect_eq "97e: the Eval design column header is a single line" "1" \
  "$(printf '%s\n' "$EVAL_HEADER" | wc -l | tr -d ' ')"

section "Section 14: K5 — the layout block names .requirements.md and the three-artifact sentence (spec §Eval design K5, plan task 19)"
#
# WHAT THIS SECTION OWNS. K5 (design ledger K5; ADR-001) fixes three artifacts to three
# steps. AC-K5.3 pins that SKILL.md's own text — the Artifact-layout code block and the
# Steps table's rows 1–3 — names all three (requirements.md, spec.md, plan.md) and, in
# one sentence each, what each holds. This is the "human reads the skill" half of K5; the
# hook arms that enforce it (governing-skill's frontmatter contract, evidence-gate's
# Step-1 pointer) are pinned by their own suites, not here.
#
# NUMBERED FROM 98 (renumbered at the epic-22 K2+K5 merge, plan tasks 16/19 landing
# together — both sections were independently numbered "Section 13" and started their own
# assertions back at ~83/90a; Section 13 above is K2's and keeps its numbers, this section
# is K5's and starts fresh past its last one, 97h).
#
# ANTI-VACUITY, same discriminate-a-doctored-copy pattern as Section 12: each extractor is
# re-run against a copy mutated to reproduce K5.3's own "fails-when" (absent), and must go red.

LAYOUT_BLOCK="$(awk '/^## Artifact layout$/{f=1;next} f&&/^```$/{c++; if(c==2) exit} f&&c==1{print}' "$SKILL_MD")"

expect_true "98: the Artifact-layout code block is found in SKILL.md" \
  test -n "$LAYOUT_BLOCK"

expect_contains "99: AC-K5.3 — the layout block names wave-NN-<slug>.requirements.md beside the spec (fails-when: absent)" \
  "wave-NN-<slug>.requirements.md" "$LAYOUT_BLOCK"

expect_regex "100: 99's requirements.md sits in the SAME specs/ line as .spec.md, not its own directory" \
  '^<docs-root>/specs/epic-NN-<slug>/\{[^}]*wave-NN-<slug>\.spec\.md[^}]*wave-NN-<slug>\.requirements\.md[^}]*\}$' \
  "$LAYOUT_BLOCK"

# The three-artifact sentence: one sentence each, naming what requirements.md, spec.md
# and plan.md hold. Pinned as three separate substring checks (the exact prose is not
# pinned, only that each artifact name co-occurs with its content description) rather
# than one long regex, so a future reword of the connective prose does not false-fail
# a check whose real subject is "does the sentence exist and name the right things".
THREE_ARTIFACT_TEXT="$(awk '/^\*\*Three artifacts, three steps\*\*/{f=1} f{print} f&&/^$/{exit}' "$SKILL_MD")"

expect_true "101: the three-artifact sentence is found in SKILL.md" \
  test -n "$THREE_ARTIFACT_TEXT"

expect_contains "102a: AC-K5.3 — names requirements.md and what it holds (fails-when: absent)" \
  "requirements.md\`: numbered requirements" "$THREE_ARTIFACT_TEXT"
expect_contains "102b: AC-K5.3 — names spec.md and what it holds (fails-when: absent)" \
  "spec.md\`: the technical design" "$THREE_ARTIFACT_TEXT"
expect_contains "102c: AC-K5.3 — names plan.md and what it holds (fails-when: absent)" \
  "plan.md\`: tasks, sequencing" "$THREE_ARTIFACT_TEXT"

# Steps table rows 1-3: each row's Gate cell also names its Step's artifact + one-line content.
STEP1_ROW="$(grep -E '^\| 1 Scope \|' "$SKILL_MD")"
STEP2_ROW="$(grep -E '^\| 2 Design \|' "$SKILL_MD")"
STEP3_ROW="$(grep -E '^\| 3 Plan \|' "$SKILL_MD")"

expect_contains "103a: AC-K5.3 — Step 1's table row names requirements.md + what it holds (fails-when: absent)" \
  "requirements.md\` — numbered requirements" "$STEP1_ROW"
expect_contains "103b: AC-K5.3 — Step 2's table row names spec.md + what it holds (fails-when: absent)" \
  "spec.md\` — the technical design" "$STEP2_ROW"
expect_contains "103c: AC-K5.3 — Step 3's table row names plan.md + what it holds (fails-when: absent)" \
  "plan.md\` — tasks, sequencing" "$STEP3_ROW"

# --- Anti-vacuity: each extractor must go red on the fails-when it names (absent) ---

# 104: a layout block with requirements.md stripped out fails 99.
anchor "$SKILL_MD" ', wave-NN-<slug>.requirements.md}' 1
DOCTORED_NO_REQ_LAYOUT="$TMP/skill-k5-no-req-layout.md"
sed 's/, wave-NN-<slug>\.requirements\.md}/}/' "$SKILL_MD" > "$DOCTORED_NO_REQ_LAYOUT"
DOCTORED_LAYOUT_104="$(awk '/^## Artifact layout$/{f=1;next} f&&/^```$/{c++; if(c==2) exit} f&&c==1{print}' "$DOCTORED_NO_REQ_LAYOUT")"
case "$DOCTORED_LAYOUT_104" in
  *"wave-NN-<slug>.requirements.md"*) no "104: a layout block with requirements.md stripped still 'has' it (pin is vacuous)" ;;
  *) ok "104: a layout block with requirements.md stripped fails the name check (pin discriminates)" ;;
esac

# 105: a SKILL.md with the whole three-artifact sentence removed fails 101/102a-c.
anchor -E "$SKILL_MD" '^\*\*Three artifacts, three steps\*\*' 1
DOCTORED_NO_SENTENCE="$TMP/skill-k5-no-sentence.md"
awk '/^\*\*Three artifacts, three steps\*\*/{skip=1} skip&&/^$/{skip=0;next} !skip{print}' "$SKILL_MD" > "$DOCTORED_NO_SENTENCE"
DOCTORED_SENTENCE_105="$(awk '/^\*\*Three artifacts, three steps\*\*/{f=1} f{print} f&&/^$/{exit}' "$DOCTORED_NO_SENTENCE")"
if [ -z "$DOCTORED_SENTENCE_105" ]; then
  ok "105: a SKILL.md with the three-artifact sentence removed fails the presence check (pin discriminates)"
else
  no "105: a SKILL.md with the three-artifact sentence removed fails the presence check (pin discriminates)" \
     "the mutated copy still carried the sentence — the mutation is a no-op"
fi

# 106: a Step-1 table row with its artifact clause stripped fails 103a.
anchor "$SKILL_MD" "requirements.md\` — numbered requirements" 1
DOCTORED_NO_ROW_CLAUSE="$TMP/skill-k5-no-row-clause.md"
sed -E "s/; writes \`wave-NN-<slug>\.requirements\.md\`[^|]*//" "$SKILL_MD" > "$DOCTORED_NO_ROW_CLAUSE"
DOCTORED_ROW1_106="$(grep -E '^\| 1 Scope \|' "$DOCTORED_NO_ROW_CLAUSE")"
case "$DOCTORED_ROW1_106" in
  *"requirements.md\` — numbered requirements"*) no "106: a Step-1 row with its artifact clause stripped still 'has' it (pin is vacuous)" ;;
  *) ok "106: a Step-1 row with its artifact clause stripped fails the row check (pin discriminates)" ;;
esac

# ── Section 15: K4 — the prototype unit (AC-K4.1, AC-K4.3) ──────────────────
#
# NUMBERED FROM 107, past K5's last number (106) — same renumber-at-merge
# convention Section 14's own header note explains.
#
# AC-K4.1: the skill defines the prototype unit — three fields (question, what "right"
# looks like, timebox), two homes (Step 2 by default, Step 4 by exception with a stated
# reason), the ruling-to-spec rule, ships nothing, and the no-row rule. It is one bounded
# paragraph, extracted the same way the Step-2/3 cards are (heading in, blank line out) so
# a `has_all` below cannot be satisfied by unrelated prose living elsewhere in the file.
proto_span() {
  awk '
    index($0, "The prototype unit") { f=1 }
    f { print }
    f && /^$/ { exit }
  ' "$STEP2_MD"
}
PROTO_SPAN="$(proto_span)"

expect_true "107a: the prototype-unit paragraph exists in the skill file" test -n "$PROTO_SPAN"

if has_all "$PROTO_SPAN" "question" '"right"' "timebox" "ships nothing" \
                        "never owns a matrix row" "Step 2" "Step 4" "kind: prototype" \
                        "states that reason" "refused by the evidence gate"; then
  ok "107b: AC-K4.1 — the prototype unit names its three fields, two homes (the Step-4 exception stating its reason), the ruling-to-spec rule, ships nothing, and the no-row rule"
else
  no "107b: AC-K4.1 — the prototype unit names its three fields, two homes (the Step-4 exception stating its reason), the ruling-to-spec rule, ships nothing, and the no-row rule" \
     "span: $PROTO_SPAN"
fi

# 107c: Anti-vacuity — a copy with the no-row rule's sentence stripped fails 107b's check.
anchor "$STEP2_MD" 'never owns a matrix row' 1
DOCTORED_NO_ROWRULE="$TMP/skill-k4-no-rowrule.md"
sed '/never owns a matrix row/d' "$STEP2_MD" > "$DOCTORED_NO_ROWRULE"
DOCTORED_PROTO_SPAN="$(awk '
    index($0, "The prototype unit") { f=1 }
    f { print }
    f && /^$/ { exit }
  ' "$DOCTORED_NO_ROWRULE")"
if has_all "$DOCTORED_PROTO_SPAN" "question" '"right"' "timebox" "ships nothing" \
                        "never owns a matrix row" "Step 2" "Step 4" "kind: prototype" \
                        "states that reason" "refused by the evidence gate"; then
  no "107c: a prototype-unit paragraph missing the no-row rule still passes 107b's check (pin is vacuous)" \
     "doctored span: $DOCTORED_PROTO_SPAN"
else
  ok "107c: a prototype-unit paragraph missing the no-row rule fails 107b's check (pin discriminates)"
fi

# AC-K4.3: the Step-3 card's "Open at approval" section is a QUESTION → TASK mapping, not
# just a bare header — 93a already pins the header string; this pins the row shape it
# names, `closed by task <n>`, which is what makes the section machine-checkable rather
# than a caption with nothing under it.
expect_contains "107d: AC-K4.3 — the Step-3 card's Open-at-approval row maps a question to the task that closes it" \
  "closed by task" "$CARD3"

# 107e: Anti-vacuity — a Step-3 card with the mapping text stripped fails 107d.
anchor "$STEP3_MD" 'closed by task' 1
DOCTORED_NO_CLOSEDBY="$TMP/skill-k4-no-closedby.md"
sed 's/closed by task/discharged eventually/' "$STEP3_MD" > "$DOCTORED_NO_CLOSEDBY"
DOCTORED_CARD3_107="$(card_span "$DOCTORED_NO_CLOSEDBY" 'Step 3 · Plan')"
case "$DOCTORED_CARD3_107" in
  *"closed by task"*) no "107f: a Step-3 card missing the 'closed by task' mapping still 'has' it (pin is vacuous)" ;;
  *) ok "107f: a Step-3 card missing the 'closed by task' mapping fails the K4.3 check (pin discriminates)" ;;
esac

section "Section 16: K5.4 — the goal-paragraph rule text (design ledger K5.4, plan task 21)"
#
# WHAT THIS SECTION OWNS. AC-K5.4 pins that SKILL.md's own text says each of the three
# artifacts opens with a concise goal paragraph under '## Goal', and that a
# governing-skill arm enforces it. The sentence is appended onto the END of Section 14's
# "Three artifacts, three steps" paragraph, so it reuses THREE_ARTIFACT_TEXT (extracted
# above) rather than re-deriving the same awk. The arm itself — its empty-section check,
# its wave|epic scoping, its per-file messages — is pinned by
# tests/canonical-sdlc-governing-skill.test.sh's own K5.4 section, not here; this section
# owns the "human reads the skill" half only, same division Section 14 draws for K5.3.
#
# NUMBERED FROM 108 (continuing past Section 15's last number, 107f). Section 15 (K4) and
# this section both landed a "Section 15" numbered from 107 in their own worktrees — the
# same renumber-at-merge convention Section 14's own header note describes; K5.4 is the
# one that moves, since it merges second.

expect_contains "108: AC-K5.4 — the three-artifact sentence says each opens with a concise goal paragraph under '## Goal' (fails-when: absent)" \
  "\`## Goal\` section — one concise paragraph" "$THREE_ARTIFACT_TEXT"

expect_contains "109: AC-K5.4 — …and that a governing-skill arm refuses a write whose first section is not Goal (fails-when: absent)" \
  "first section is not Goal" "$THREE_ARTIFACT_TEXT"

# --- Anti-vacuity: 108/109 must go red when the K5.4 clause is stripped ---
#
# The clause is the tail of Section 14's own paragraph (spans the last four physical
# lines of it, wrapped) — a narrower mutation than 105's whole-paragraph removal above,
# because 105 already discharges anti-vacuity for 101/102a-c and would prove nothing new
# for 108/109 specifically: this mutation keeps the rest of the paragraph (including the
# ". Each" boundary) and strips only the sentence 108/109 are about.
anchor "$SKILL_MD" 'validates `*.spec.md`, minus the design three-way rule (that stays spec-only). Each' 1
DOCTORED_NO_K54_CLAUSE="$TMP/skill-k54-no-clause.md"
sed -e "s/(that stays spec-only)\. Each\$/(that stays spec-only)./" \
    -e '/^of the three opens with a `## Goal` section/d' \
    -e '/^(design ledger K5\.4) — and a governing-skill arm/d' \
    -e '/^write whose first section is not Goal, or whose Goal section is empty\.$/d' \
    "$SKILL_MD" > "$DOCTORED_NO_K54_CLAUSE"
DOCTORED_THREE_ARTIFACT_110="$(awk '/^\*\*Three artifacts, three steps\*\*/{f=1} f{print} f&&/^$/{exit}' "$DOCTORED_NO_K54_CLAUSE")"
case "$DOCTORED_THREE_ARTIFACT_110" in
  *"\`## Goal\` section — one concise paragraph"*) no "110a: a sentence with the K5.4 clause stripped still 'has' the goal-paragraph text (108 is vacuous)" ;;
  *) ok "110a: a sentence with the K5.4 clause stripped fails 108's check (pin discriminates)" ;;
esac
case "$DOCTORED_THREE_ARTIFACT_110" in
  *"first section is not Goal"*) no "110b: a sentence with the K5.4 clause stripped still 'has' the arm-refusal text (109 is vacuous)" ;;
  *) ok "110b: a sentence with the K5.4 clause stripped fails 109's check (pin discriminates)" ;;
esac
# The mutation kept the rest of the paragraph — proof the delete was surgical, not
# 105's whole-paragraph wipe reused under a new number.
expect_contains "110c: the doctored copy still carries the REST of the paragraph (the mutation is surgical, not 105's whole-paragraph wipe)" \
  "requirements.md\`: numbered requirements" "$DOCTORED_THREE_ARTIFACT_110"

# ---- 111: the five user-only commands are hidden from model invocation (wave-11 row 1d) ----
# `disable-model-invocation: true` is what drops a command's description from the Skill
# roster the model sees; a template that loses the line silently puts ~600 B back into every
# request. Pinned on the rendered file (the shipped surface) AND the template (the source).
for _cmd in setup doctor remove version help; do
  _md="${REPO}/payload/commands/${_cmd}.md"; _tp="${REPO}/agents-src/templates/commands/${_cmd}.md.tmpl"
  if awk '/^---$/{c++; next} c==1' "$_md" | grep -q '^disable-model-invocation: true$'; then
    ok "111-${_cmd}: payload/commands/${_cmd}.md frontmatter carries disable-model-invocation: true"
  else
    no "111-${_cmd}: payload/commands/${_cmd}.md frontmatter lacks disable-model-invocation: true"
  fi
  if awk '/^---$/{c++; next} c==1' "$_tp" | grep -q '^disable-model-invocation: true$'; then
    ok "111t-${_cmd}: the ${_cmd} template carries the line (source, not just output)"
  else
    no "111t-${_cmd}: the ${_cmd} template lacks disable-model-invocation: true"
  fi
done

section "Section 17: the lean spine — role files are role-sized and the dispatch terms render once (wave-11 REQ-1c, AC-1c.1/.2/.3)"

# WHAT THIS SECTION OWNS. Until wave-11 the survival block rendered into all six role
# files: 33,222 B of the 57,013 B role surface was six copies of one 5,491 B text
# (record/wave-11-lean-spine/step1-measure-1c-1d.md §1.3). A role file is read in full at
# every dispatch, so six copies is six times the cost for one text that never varies by
# role. The repair is structural, not editorial — the block renders ONCE, to
# payload/context/survival.md, and the SubagentStart hook pushes it — so what needs pinning
# is the SHAPE of the result: role files stay role-sized, exactly one shipped copy of the
# terms exists, and that copy says who sent it.
#
# WHY A BYTE CAP IS A LEGITIMATE PIN. It is not style policing. The cap is what makes the
# six-copies regression impossible to reintroduce quietly: a re-added `<!-- INJECT: survival
# -->` puts 5,537 B back into a role file and this section goes red naming the file, whereas
# a prose-only pin would stay green until someone happened to read the render.
#
# ANTI-VACUITY. The census arm (113) is a COUNT, not an absence, so it fails in BOTH
# directions — zero copies (the render never ran) and two (a second home appeared) are each
# red, and the first-line arm below proves the one copy found is the real rendered file
# rather than an empty placeholder that would satisfy a count.
#
# HERMETIC. Reads committed files by path; the doctored copies live under this file's own
# mktemp dir. Nothing in the repo tree is written.
#
# CAP RAISED 5,120 -> 5,500 (epic-23 wave-12 T3, A-orch-4, record/wave-12-fixit-171/
# assumptions.md): the brief-scaffold block this wave adds to every role file (Section 22)
# costs ~500-600 B each, non-negotiable per its own brief; senior-implementor.md still reads
# 5,322 B after every safe trim available within T3's scope. The orchestrator raised this
# cap rather than have T3 touch a shared block outside its declared Files or cut the
# Discretion-contract text below what its lever authorized.
#
# ROLE_TOTAL_CAP RAISED 26,000 -> 26,300 (epic-23 wave-13 T17, A-T17.1, R6 finding 3): the
# scaffold's two new lines (`Progress artifact:`, `Cadence:`) render into all six role files
# identically, at their shortest label-legal form (no trailing comment, unlike Files:/Suites:
# — T17's Files did not authorize touching the labels the dispatch wall reads, so there is no
# further trim available). +43 B/file × 6 = +258 B put the measured total at 26,221 B, 221 B
# over the old cap with only 37 B of headroom to spend against; same shape of ratchet as the
# per-file raise above, same reason.

ROLE_CAP=5500
ROLE_TOTAL_CAP=26300
ROLE_OVER=""
ROLE_TOTAL=0
ROLE_COUNT=0
for _rf in "${REPO}"/agents/*.md; do
  [ -f "$_rf" ] || continue
  ROLE_COUNT=$((ROLE_COUNT + 1))
  _rb="$(wc -c < "$_rf" | tr -d ' ')"
  ROLE_TOTAL=$((ROLE_TOTAL + _rb))
  [ "$_rb" -le "$ROLE_CAP" ] || ROLE_OVER="${ROLE_OVER} ${_rf##*/}=${_rb}"
done

# The set arm first: a glob that matched nothing would make every cap below true for free.
expect_eq "111a: the role-file set is the six roles (the cap arms have something to measure)" \
  "6" "$ROLE_COUNT"
if [ -z "$ROLE_OVER" ]; then
  ok "111b: AC-1c.1 — every agents/*.md is at or under ${ROLE_CAP} B"
else
  no "111b: AC-1c.1 — every agents/*.md is at or under ${ROLE_CAP} B" \
     "over cap:${ROLE_OVER} — the survival block renders once now; a role file this large is carrying a copy of something shared"
fi
if [ "$ROLE_TOTAL" -le "$ROLE_TOTAL_CAP" ]; then
  ok "111c: AC-1c.2 — the six role files total ${ROLE_TOTAL} B, at or under ${ROLE_TOTAL_CAP} B"
else
  no "111c: AC-1c.2 — the six role files total ${ROLE_TOTAL} B, at or under ${ROLE_TOTAL_CAP} B" \
     "total=${ROLE_TOTAL} — was 57013 before wave-11 1c"
fi

# EVERY ROLE POINTS AT THE TERMS. Dropping the injection without leaving the pointer would
# satisfy the cap and strand the agent, which is the failure this arm exists for.
SURVIVAL_POINTER='Dispatch terms: payload/context/survival.md — delivered to you at start; they bind.'
ROLE_NOPTR=""
for _rf in "${REPO}"/agents/*.md; do
  has_pin "$_rf" "$SURVIVAL_POINTER" || ROLE_NOPTR="${ROLE_NOPTR} ${_rf##*/}"
done
if [ -z "$ROLE_NOPTR" ]; then
  ok "112: every role file carries the one-line pointer to the dispatch terms"
else
  no "112: every role file carries the one-line pointer to the dispatch terms" \
     "missing in:${ROLE_NOPTR} — run 'bash agents-src/render.sh'"
fi

# THE CENSUS (AC-1c.3, shipped half). Exactly one file under payload/ carries the terms.
# `grep -rl` over payload/ is the brief's own instrument; payload/agents and
# payload/skills/canonical-sdlc are symlinks into the repo, so a role file that reacquired
# the block would be found through them and this count would read 2 or more.
SURVIVAL_SENTINEL='Agents have died on each of these, mid-task, with the work already finished.'
SURVIVAL_HOMES="$(cd "$REPO" && /usr/bin/grep -rl -F -- "$SURVIVAL_SENTINEL" payload 2>/dev/null | sort)"
SURVIVAL_HOME_COUNT="$(printf '%s' "$SURVIVAL_HOMES" | grep -c . | tr -d ' ')"
expect_eq "113a: AC-1c.3 — the survival sentinel is in exactly ONE file under payload/" \
  "1" "$SURVIVAL_HOME_COUNT"
expect_eq "113b: …and that file is payload/context/survival.md" \
  "payload/context/survival.md" "$SURVIVAL_HOMES"

# THE SELF-ATTRIBUTION. Pushed text an agent did not ask for is text an agent can reasonably
# distrust; the first line says what it is and who delivered it, which is the whole of why
# the hook's stdout is obeyed rather than queried.
SURVIVAL_FIRST_LINE="$(head -1 "${REPO}/payload/context/survival.md" 2>/dev/null)"
case "$SURVIVAL_FIRST_LINE" in
  '> bionic dispatch terms'*)
    ok "114a: payload/context/survival.md opens with its self-attribution line" ;;
  *)
    no "114a: payload/context/survival.md opens with its self-attribution line" \
       "first line reads: ${SURVIVAL_FIRST_LINE:-<empty or missing file>}" ;;
esac
expect_contains "114b: …naming the hook that delivers it" \
  "hooks/execution-recorder.sh" "$SURVIVAL_FIRST_LINE"

# --- Anti-vacuity: the census and the first-line arm must report a mutation ---
anchor "${REPO}/payload/context/survival.md" 'Agents have died on each of these' 1
DOCTORED_SURVIVAL="$TMP/survival-second-home.md"
cp "${REPO}/payload/context/survival.md" "$DOCTORED_SURVIVAL" 2>/dev/null
DOCTORED_HOME_COUNT="$(/usr/bin/grep -rl -F -- "$SURVIVAL_SENTINEL" \
  "${REPO}/payload" "$DOCTORED_SURVIVAL" 2>/dev/null | sort -u | grep -c . | tr -d ' ')"
expect_eq "115a: a second copy of the sentinel makes the census read 2 (the count discriminates)" \
  "2" "$DOCTORED_HOME_COUNT"
anchor "${REPO}/payload/context/survival.md" '> bionic dispatch terms' 1
DOCTORED_FIRST="$TMP/survival-no-attribution.md"
tail -n +2 "${REPO}/payload/context/survival.md" > "$DOCTORED_FIRST" 2>/dev/null
case "$(head -1 "$DOCTORED_FIRST")" in
  '> bionic dispatch terms'*)
    no "115b: a copy with the attribution line stripped still passes 114a (the arm is vacuous)" ;;
  *)
    ok "115b: a copy with the attribution line stripped fails 114a (the arm discriminates)" ;;
esac

# ── AC-1c.4: the four writer-side field rules are role-file DEFAULTS ─────────
#
# WHY THESE FOUR AND NOT THE OTHER FIVE. The brief's §5 carries nine rules; five of them
# ("every brief names the main-root .bionic path", the A-range reservation, the evidence
# field block, verify-before-land, artifact names checked against the record directory) are
# addressed to whoever WRITES the brief and cannot be a role-file default — a writer cannot
# obey a rule about how it was dispatched (record/wave-11-lean-spine/step1-measure-1c-1d.md
# §3). The four below are the writer's own, and each was either absent from every role file
# or, in PIPESTATUS's case, actively CONTRADICTED by one.
WRITER_ROLES="implementor senior-implementor test-runner"
pin_writer_rule() {  # <n> <label> <pin text>
  local n="$1" label="$2" pin="$3" missing="" r
  for r in $WRITER_ROLES; do
    has_pin "${REPO}/agents/${r}.md" "$pin" || missing="${missing} ${r}"
  done
  if [ -z "$missing" ]; then
    ok "${n}: ${label}"
  else
    no "${n}: ${label}" "missing in:${missing} — the rule is a default only where it renders"
  fi
}

pin_writer_rule "116a" "AC-1c.4 §5 #1 — suites run foreground with the tool timeout at 600000 ms" \
  'Suites run FOREGROUND with the Bash tool `timeout` parameter set to 600000 ms, never `run_in_background`, never a timeout binary.'
pin_writer_rule "116b" "AC-1c.4 §5 #2 — only the suites the brief names" \
  "Run only the suites the brief's \`Suites:\` names."
pin_writer_rule "116c" "AC-1c.4 §5 #8 — the cd guard covers the whole command" \
  '`cd <tree> || exit 1` guards the WHOLE command'

# #7 is a CORRECTION, so it takes both halves: the new rule present, and the sentence that
# taught the opposite gone. An absence arm alone would pass on a file that lost the whole
# Logging section, which is why the positive half is asserted over the same file first.
expect_contains "116d: AC-1c.4 §5 #7 — agents/test-runner.md captures exit codes with the rc= form" \
  'Capture exit codes as `{ cmd; echo "rc=$?"; } > log 2>&1`, never PIPESTATUS' \
  "$(cat "${REPO}/agents/test-runner.md")"
expect_absent "116e: …and no longer INSTRUCTS the shell-specific PIPESTATUS array (the contradiction is gone)" \
  'the per-stage array is shell-specific — `${PIPESTATUS[0]}` in **bash** (zero-indexed)' \
  "$(cat "${REPO}/agents/test-runner.md")"
expect_contains "116f: …and the implementors carry the same rc= rule" \
  'Capture exit codes as' "$(cat "${REPO}/agents/senior-implementor.md")"
section "Section 18: REQ-1b — the split skill's byte caps and the core's step index"
#
# WHAT THIS SECTION OWNS. wave-11-lean-spine row 1b split the governing skill into a CORE
# (`skills/canonical-sdlc/SKILL.md`), ten STEP FILES (`steps/0.md` … `steps/9.md`) and a
# DISPATCH REFERENCE (`dispatch.md`). The split is only worth its cost while the pieces stay
# small: the whole point is that a session carries the core plus the one step it is on, not
# the file that used to be 108,652 B. Nothing else in this tree measures that, so the four
# caps of AC-1b.1 through AC-1b.4 are pinned here, in bytes, against the rendered finals.
#
# WHY BYTES AND NOT LINES. The cost the split exists to cut is context, and context is
# charged by bytes, not by how they are wrapped. A line pin would go green on a re-wrap that
# moved nothing.
#
# THE CAPS ARE THE RATIFIED NUMBERS, not measurements of what happened to land: core 25,000 ·
# each step file 14,000 · dispatch 35,000 · the three together 108,652 (2026-09-11's exact
# size — "no growth," literally), from the requirements file's AC table as AMENDED 2026-09-11
# (user ruling "Ok, option 1": caps measure the loaded surface; the prose cut is a chartered
# later wave) and RE-AMENDED the same day once the T5-report §3 prunable-narrative estimate
# proved too small to reach a tighter pair of caps on its own: dispatch to the measured cut
# (35,000, still below that day's 35,366) and total to the measured no-growth line (108,652),
# reached by giving the core and dispatch reference the same one-line GENERATED header the
# step files already use, not by cutting more prose. RE-RAISED to 109,118 (epic-23 wave-13
# T2, 2026-09-14): the brief scaffold injected into SKILL.md (AC-2.2, +508 B) and the Step-3
# card's conditional governing-design slot (AC-8.3) are both chartered growth this same wave
# approved, not drift — the requirements file records neither the old nor the new total as a
# ratified number of its own, so this comment carries the amendment instead; a future wave
# that needs the cap raised again still raises it in the requirements first. RE-RAISED AGAIN
# to 109,293 (epic-23 wave-13 T7, 2026-09-14, +175 B): the one-sentence "one docs tree"
# addition AC-7.4 requires in orchestrator-dispatch.md (a positive statement that a worktree
# writer's relative record path lands in the project's docs tree by construction) is this
# wave's own chartered growth too — cut to the shortest wording that still carries a
# grep-pinnable "one docs tree" phrase (Section 25 below), with T2's zero-slack total
# leaving no room to add it for free. A fifth cap,
# also from the 2026-09-11 ruling, pins the loaded surface itself: core + the largest single
# steps/N.md ≤ 36,000 B, since that pair
# is what a session actually carries at a step boundary — the whole-surface total below it
# does not measure that. Headroom under a cap is not a reason to move the cap down, and a
# future wave that needs a cap raised raises it in the requirements first.
#
# SET TO 110,000 (epic-23 wave-13 T11, 2026-09-14, A-orch-29): Chris ruled
# "Option 2" on the aggregate cap directly, not another chartered-growth
# increment — a RATCHET WITH AN OWNER, moved only by a named ruling with its
# reason, the number itself the recommended one Chris accepted with the
# option. This is not headroom for a specific sentence the way the two raises
# above were; it is the ceiling itself changing, recorded here in AC-2.2
# (requirements + plan) as well as in this comment's own established pattern.
#
# RAISED to 110,500 — Chris 2026-09-14 "Option 2" (wave-14 T14): the two
# remaining Step-2 row shapes — the Ownership row and the Eval-design row,
# left unannotated by T10 for lack of headroom (A-T10.1) — are now annotated
# with their own printf format beside the card, same pattern and same named
# ruling as the raise directly above: the ceiling itself moves, owned here.
#
# AC-1b.5 is the structural half, and it is what makes the byte caps mean anything: a core
# that still carried its `### Step N` sections would be under no cap at all, and a core that
# dropped the sections without naming the files would leave the model with no way to find
# them. Both halves are pinned — zero `### Step` headings in the core, and every one of the
# ten step files named in it by path.
#
# `steps/4.md` gets its own, much tighter cap. It is a POINTER, not a step file: Step 4 is
# dispatch, whose text lives in `dispatch.md` and nowhere else, and the one thing that must
# never happen to it is that someone answers "steps/4.md is nearly empty" by writing new
# Step-4 prose into it. 1,024 B is small enough that the answer has to be the pointer.
#
# HERMETIC. Reads the committed rendered finals by path; measures with `wc -c`.

SPLIT_SKILL_DIR="${REPO}/skills/canonical-sdlc"
SPLIT_CORE="${SPLIT_SKILL_DIR}/SKILL.md"
SPLIT_DISPATCH="${SPLIT_SKILL_DIR}/dispatch.md"

# bytes_of <file> -> the byte count, or -1 when the file is not there. -1 rather than 0
# because a MISSING file measures 0 and would slide under every cap below: the absence has
# to fail the cap, not satisfy it.
bytes_of() { [ -f "$1" ] && wc -c < "$1" | tr -cd '0-9' || echo -1; }

# le_cap <label> <file> <cap> — one assertion, reporting the measurement either way.
le_cap() {
  local _label="$1" _file="$2" _cap="$3" _got
  _got="$(bytes_of "$_file")"
  if [ "$_got" -ge 0 ] 2>/dev/null && [ "$_got" -le "$_cap" ] 2>/dev/null; then
    ok "$_label ($_got B ≤ $_cap B)"
  elif [ "$_got" -lt 0 ] 2>/dev/null; then
    no "$_label" "no file at $_file"
  else
    no "$_label" "$_got B exceeds the $_cap B cap by $((_got - _cap)) B: $_file"
  fi
}

le_cap "111: AC-1b.1 — the core is at or under its cap (fails-when: the core grows back)" \
  "$SPLIT_CORE" 25000

for _n in 0 1 2 3 4 5 6 7 8 9; do
  le_cap "112.$_n: AC-1b.2 — steps/$_n.md exists and is at or under its cap (fails-when: missing or oversized)" \
    "${SPLIT_SKILL_DIR}/steps/${_n}.md" 14000
done

le_cap "113: AC-1b.3 — the dispatch reference is at or under its cap (fails-when: the dispatch body grows back)" \
  "$SPLIT_DISPATCH" 35000

# steps/4.md's own cap — the no-new-Step-4-prose wall (REQ-1b: "No new Step-4 prose is
# authored: the dispatch reference serves Step 4").
le_cap "114: AC-1b.2 — steps/4.md is a pointer, not a step file (fails-when: Step-4 prose is authored into it)" \
  "${SPLIT_SKILL_DIR}/steps/4.md" 1024

# The total the model is told to read. operational-rules.md is excluded by AC-1b.4's own
# wording — nothing tells the model to read it, and it is not part of this budget.
SPLIT_TOTAL=0
SPLIT_TOTAL_MISSING=""
for _f in "$SPLIT_CORE" "$SPLIT_DISPATCH" \
          "${SPLIT_SKILL_DIR}"/steps/0.md "${SPLIT_SKILL_DIR}"/steps/1.md \
          "${SPLIT_SKILL_DIR}"/steps/2.md "${SPLIT_SKILL_DIR}"/steps/3.md \
          "${SPLIT_SKILL_DIR}"/steps/4.md "${SPLIT_SKILL_DIR}"/steps/5.md \
          "${SPLIT_SKILL_DIR}"/steps/6.md "${SPLIT_SKILL_DIR}"/steps/7.md \
          "${SPLIT_SKILL_DIR}"/steps/8.md "${SPLIT_SKILL_DIR}"/steps/9.md; do
  _b="$(bytes_of "$_f")"
  if [ "$_b" -lt 0 ] 2>/dev/null; then SPLIT_TOTAL_MISSING="$SPLIT_TOTAL_MISSING ${_f##*canonical-sdlc/}"; else
    SPLIT_TOTAL=$((SPLIT_TOTAL + _b)); fi
done
if [ -n "$SPLIT_TOTAL_MISSING" ]; then
  no "115: AC-1b.4 — core + steps + dispatch at or under 110,500 B" "missing:$SPLIT_TOTAL_MISSING"
elif [ "$SPLIT_TOTAL" -le 110500 ]; then
  ok "115: AC-1b.4 — core + steps + dispatch at or under 110,500 B ($SPLIT_TOTAL B ≤ 110500 B)"
else
  no "115: AC-1b.4 — core + steps + dispatch at or under 110,500 B" \
     "$SPLIT_TOTAL B exceeds the cap by $((SPLIT_TOTAL - 110500)) B"
fi

# The LOADED surface — core + the largest single step file — is what a session actually
# carries at a step boundary, which the whole-surface total above does not measure (it sums
# every step file, only one of which is ever loaded at once). New pin from the 2026-09-11 cap
# ruling ("Ok, option 1").
SPLIT_MAX_STEP=0
SPLIT_MAX_STEP_MISSING=""
for _n in 0 1 2 3 4 5 6 7 8 9; do
  _b="$(bytes_of "${SPLIT_SKILL_DIR}/steps/${_n}.md")"
  if [ "$_b" -lt 0 ] 2>/dev/null; then
    SPLIT_MAX_STEP_MISSING="$SPLIT_MAX_STEP_MISSING steps/${_n}.md"
  elif [ "$_b" -gt "$SPLIT_MAX_STEP" ] 2>/dev/null; then
    SPLIT_MAX_STEP="$_b"
  fi
done
SPLIT_CORE_BYTES="$(bytes_of "$SPLIT_CORE")"
if [ -n "$SPLIT_MAX_STEP_MISSING" ] || [ "$SPLIT_CORE_BYTES" -lt 0 ] 2>/dev/null; then
  SPLIT_LOADED_MISSING="$SPLIT_MAX_STEP_MISSING"
  [ "$SPLIT_CORE_BYTES" -lt 0 ] 2>/dev/null && SPLIT_LOADED_MISSING="$SPLIT_LOADED_MISSING ${SPLIT_CORE##*canonical-sdlc/}"
  no "115as: AC-1b.4 — loaded surface: core + largest steps/N.md at or under 36,000 B" \
     "missing:$SPLIT_LOADED_MISSING"
else
  SPLIT_LOADED_SURFACE=$((SPLIT_CORE_BYTES + SPLIT_MAX_STEP))
  if [ "$SPLIT_LOADED_SURFACE" -le 36000 ]; then
    ok "115as: AC-1b.4 — loaded surface: core + largest steps/N.md at or under 36,000 B ($SPLIT_LOADED_SURFACE B ≤ 36000 B)"
  else
    no "115as: AC-1b.4 — loaded surface: core + largest steps/N.md at or under 36,000 B" \
       "$SPLIT_LOADED_SURFACE B exceeds the cap by $((SPLIT_LOADED_SURFACE - 36000)) B"
  fi
fi

# AC-1b.5, both halves.
expect_eq "116: AC-1b.5 — the core carries no '### Step N' section (fails-when: a step section is left behind)" \
  "0" "$(grep -c '^### Step' "$SPLIT_CORE" 2>/dev/null | tr -cd '0-9')"

SPLIT_INDEX_HITS="$(grep -c 'steps/[0-9]\.md' "$SPLIT_CORE" 2>/dev/null | tr -cd '0-9')"
SPLIT_INDEX_HITS="${SPLIT_INDEX_HITS:-0}"
if [ "$SPLIT_INDEX_HITS" -ge 10 ] 2>/dev/null; then
  ok "117: AC-1b.5 — the core names all ten step files by path ($SPLIT_INDEX_HITS lines)"
else
  no "117: AC-1b.5 — the core names all ten step files by path" \
     "only $SPLIT_INDEX_HITS line(s) name a steps/N.md path"
fi

# The read rule itself — the sentence that turns the index into an instruction. Without it
# the paths are decoration and the model has no boundary at which to read one.
if has_pin "$SPLIT_CORE" 'Before any Step-N action, read `steps/N.md`. Before Step 4'"'"'s first action and before the first dispatch, read `dispatch.md`. The load-time announcement names the file just read.'; then
  ok "118: AC-1b.5 — the core carries the read rule verbatim"
else
  no "118: AC-1b.5 — the core carries the read rule verbatim" "file: $SPLIT_CORE"
fi

# --- Anti-vacuity: the cap assertions must go red on an oversized file ---
#
# le_cap is the only new extractor in this section and every cap above runs through it, so
# one doctored measurement discharges all sixteen. The mutant is a copy of the core padded
# past its own cap; the same helper must report it.
anchor "$SPLIT_CORE" '## Steps' 1
DOCTORED_FAT_CORE="$TMP/skill-core-oversized.md"
{ cat "$SPLIT_CORE"; head -c 26000 /dev/zero | tr '\0' 'x'; } > "$DOCTORED_FAT_CORE"
DOCTORED_FAT_BYTES="$(bytes_of "$DOCTORED_FAT_CORE")"
if [ "$DOCTORED_FAT_BYTES" -gt 25000 ] 2>/dev/null; then
  ok "119: a core padded past 25,000 B measures over the cap (the cap discriminates)"
else
  no "119: a core padded past 25,000 B measures over the cap (the cap discriminates)" \
     "padded copy measured $DOCTORED_FAT_BYTES B"
fi

# …and a MISSING file must fail rather than measure zero, which is the failure mode a plain
# `wc -c` would have: the cap would be satisfied by deleting the file.
expect_eq "120: a missing step file measures -1, not 0 (absence fails the cap, never satisfies it)" \
  "-1" "$(bytes_of "${SPLIT_SKILL_DIR}/steps/nonexistent.md")"

section "Section 19: REQ-1f — hooks/stop-check.sh's header names it the hand-run observation producer (wave-11 T9 ruling)"
#
# step1-census-1f.md §5 read stop-check.sh's absence from hooks/hooks.json as evidence of
# dead code; the wave-11 T9 ruling (2026-09-11) corrected that: it is unregistered BY
# DESIGN, the orchestrator's own hand-run producer of the stop-check-observation/v1 record
# the stop gate spends, not a hook the loader is ever supposed to fire. This pin holds the
# header's own statement of that fact, read OUTSIDE the loader span (T11 is editing that
# span in parallel elsewhere in this wave), so a future census does not re-derive
# "unregistered" as "dead" a second time without a live sentence contradicting it.
STOP_CHECK_SH="${BIONIC_HOOKS_DIR}/stop-check.sh"
if [ -f "$STOP_CHECK_SH" ]; then
  STOP_CHECK_HEADER="$(awk '/^# --- bionic-loader\/v2 BEGIN$/{exit} {print}' "$STOP_CHECK_SH")"
  expect_contains "121: REQ-1f — stop-check.sh's header names it the hand-run observation producer" \
    "hand-run observation producer" "$STOP_CHECK_HEADER"
else
  no "121: REQ-1f — stop-check.sh's header names it the hand-run observation producer" \
     "hooks/stop-check.sh does not exist"
fi
section "Section 20: REQ-1a — the AC block's evidence: key resolves under record/ (AC-1a.3)"
#
# WHAT THIS SECTION OWNS. Row 1a's evidence-gate arm requires a `discharged` matrix row's AC
# block to carry an `evidence:` key resolving to a real file under `<docs-root>/record/` — the
# per-tier "required keys" table is the canonical copy the hook's keys_for_tier() mirrors (R27),
# so a table that stops naming the key is a table the hook has silently outgrown. HERMETIC:
# reads the committed rendered Step-5 final by path.

AC1A_STEP5="${SPLIT_SKILL_DIR}/steps/5.md"
AC1A_KEYS_TABLE="$(awk '/Per-tier required keys/{f=1} f{print} f&&/^\|.*T4/{exit}' "$AC1A_STEP5" 2>/dev/null)"
expect_contains "121: AC-1a.3 — the Step-5 per-tier required-keys table names 'evidence'" \
  '`evidence`' "$AC1A_KEYS_TABLE"

section "Section 21: REQ-1a — assumptions and narratives are cited from record/, never appended to the plan (AC-1a.4)"
#
# WHAT THIS SECTION OWNS. Row 1a moved assumption bullets and landing narratives out of the
# plan into record/<wave>/ files cited by path — the plan's `## Assumptions` is now a one-line
# pointer to `record/<wave>/assumptions.md`, never a place a writer appends a bullet to
# directly. Three prose surfaces used to say otherwise (the critic block, the
# senior-implementor role description and body, and the skill's Step-0/3 text); this section
# pins that none of them still does.
#
# THE OLD PHRASES, verbatim, are the regression pin: each is the exact instruction this wave
# retired (measured at step1-measure-1a-1e.md §2), so a grep for any of them returning a hit
# is the failure mode this section exists to catch — a reverted edit, or a fresh writer copying
# the old shape into a new surface. HERMETIC: reads the committed rendered finals by path.

AC1A_SCAN_DIRS="${REPO}/skills/canonical-sdlc ${REPO}/agents"
AC1A_OLD_PHRASES='append one line to the plan|logged to the plan.s Assumptions|logged in the `## Assumptions` section|record in `## Assumptions`|go to `## Assumptions` as W\+1'

AC1A_HITS="$(grep -rnE "$AC1A_OLD_PHRASES" $AC1A_SCAN_DIRS 2>/dev/null || true)"
expect_eq "122: AC-1a.4 — no rendered file under skills/canonical-sdlc/ or agents/ still tells a writer to append assumption lines to the plan" \
  "" "$AC1A_HITS"

# Anti-vacuity: the pattern must actually fire on the shape it is supposed to catch, proven
# against a doctored copy carrying one of the retired sentences verbatim.
AC1A_MUT="$TMP/ac1a-old-phrase.md"
printf 'silent wrong assumptions not logged in the `## Assumptions` section\n' > "$AC1A_MUT"
expect_true "123: the retired-phrase grep fires on the shape it targets (the pattern discriminates)" \
  grep -qE "$AC1A_OLD_PHRASES" "$AC1A_MUT"

section "Section 22: T3 — the brief scaffold renders into all seven surfaces, and the ListAgents-before-dispatch text is gone (epic-23 wave-12, REQ-2/REQ-3/REQ-4, AC-2.1/AC-2.3/AC-4.4)"

# WHAT THIS SECTION OWNS. `agents-src/blocks/brief-scaffold.md` is the single source of the
# labelled brief shape (`Expected duration:`, `Expected artifact:`, `Progress artifact:`,
# `Cadence:` — T17, R6 finding 3 — `Files:`, `Suites:`, `Deliverable-waiver:`);
# `agents-src/render.sh` renders it into
# `skills/canonical-sdlc/dispatch.md` and all six `agents/*.md` role files — seven surfaces,
# one block, identical bytes by construction. This section pins the SHAPE of that result
# (count, not content, so the block's own wording stays free to improve) and two carry-over
# regression guards from the same wave: the `agents/*.md` byte cap (AC-2.3), and the absence
# of the retired "call ListAgents, then dispatch" dispatch precondition from the rendered doc
# surfaces (AC-4.4's docs half; the hook-side half is dispatch-preflight.sh, pinned by
# tests/dispatch-preflight.test.sh, not here).
#
# HERMETIC. Reads the committed rendered finals by path; the doctored copy for the
# anti-vacuity arm lives under this file's own mktemp dir.

AC2_SURFACES="${REPO}/skills/canonical-sdlc/dispatch.md ${REPO}/agents/researcher.md ${REPO}/agents/implementor.md ${REPO}/agents/senior-implementor.md ${REPO}/agents/test-runner.md ${REPO}/agents/auditor.md ${REPO}/agents/critic.md"

# AC-2.1: the scaffold's own FENCED LINE — not the bare label — appears EXACTLY ONCE in
# each of the seven surfaces. The bare label alone is the wrong instrument here:
# orchestrator-dispatch.md's own prose already names `Expected artifact:` twice, describing
# the label in general terms, before this wave's block ever renders a single byte — a
# `grep -c` of the bare word would read 3 in skills/canonical-sdlc/dispatch.md even with the
# scaffold present once. The exact templated line the block emits is unambiguous: zero says
# the block never rendered there, two says it rendered twice (a stray hand-copy alongside
# the injected one).
AC2_SCAFFOLD_LINE='Expected artifact: <ONE path inside the repo, e.g. .bionic/docs/record/<wave>/<name>.md>'
AC2_MISSING=""
AC2_DOUBLED=""
for _sf in $AC2_SURFACES; do
  if [ ! -f "$_sf" ]; then
    AC2_MISSING="${AC2_MISSING} ${_sf##*/}=absent"
    continue
  fi
  _n="$(grep -Fc -- "$AC2_SCAFFOLD_LINE" "$_sf" 2>/dev/null | tr -cd '0-9')"
  case "$_n" in
    1) : ;;
    0) AC2_MISSING="${AC2_MISSING} ${_sf##*/}=0" ;;
    *) AC2_DOUBLED="${AC2_DOUBLED} ${_sf##*/}=${_n}" ;;
  esac
done
if [ -z "$AC2_MISSING" ] && [ -z "$AC2_DOUBLED" ]; then
  ok "124a: AC-2.1 — the brief scaffold's fenced 'Expected artifact:' line appears exactly once in all seven surfaces"
else
  no "124a: AC-2.1 — the brief scaffold's fenced 'Expected artifact:' line appears exactly once in all seven surfaces" \
     "missing:${AC2_MISSING:-none} doubled:${AC2_DOUBLED:-none}"
fi

# Anti-vacuity: the count must actually discriminate a surface that lost the block.
AC2_MUT_DIR="$TMP/ac2-scaffold"; mkdir -p "$AC2_MUT_DIR"
AC2_MUT="$AC2_MUT_DIR/no-scaffold.md"
grep -Fv -- "$AC2_SCAFFOLD_LINE" "${REPO}/agents/researcher.md" > "$AC2_MUT" 2>/dev/null
expect_eq "124b: a surface with the fenced line stripped reads 0, not 1 (the count discriminates)" \
  "0" "$(grep -Fc -- "$AC2_SCAFFOLD_LINE" "$AC2_MUT" 2>/dev/null | tr -cd '0-9')"

# AC-2.3 (lean-spine byte rule, carried into this wave by the scaffold's own weight): every
# agents/*.md stays at or under the cap. Reported per-file, like Section 17's arm, so a
# regression names the file rather than only the aggregate. Cap is 5,500 B, not the wave's
# original 5,000 — A-orch-4 (record/wave-12-fixit-171/assumptions.md): the scaffold's fixed
# cost (fence + wrapper, ~500 B, non-negotiable per-brief) left senior-implementor.md at
# 5,322 B even after every safe, meaning-preserving trim this task's lever ("shorten the
# scaffold heading, not the five lines") authorized without touching a shared block outside
# T3's declared Files (report-contract.md, shared-core.md, implementor-mechanics.md) or
# gutting its Discretion-contract text; the orchestrator raised the cap rather than either.
AC2_BYTE_CAP=5500
AC2_OVER=""
for _rf in "${REPO}"/agents/*.md; do
  [ -f "$_rf" ] || continue
  _rb="$(wc -c < "$_rf" | tr -d ' ')"
  [ "$_rb" -le "$AC2_BYTE_CAP" ] || AC2_OVER="${AC2_OVER} ${_rf##*/}=${_rb}"
done
if [ -z "$AC2_OVER" ]; then
  ok "125: AC-2.3 — every agents/*.md is at or under ${AC2_BYTE_CAP} B"
else
  no "125: AC-2.3 — every agents/*.md is at or under ${AC2_BYTE_CAP} B" \
     "over cap:${AC2_OVER}"
fi

# AC-4.4 (docs half): the retired dispatch precondition never made it into a rendered doc
# surface — the hook-side removal is T1's, this is the prose's.
# WIDENED TO THE WHOLE TREE (T22, A-orch-33). The span Chris ratified is `hooks payload
# agents skills` — every surface, not the dispatch half — so the stop path is inside it now:
# the roster resolves a name to an id, and nothing on any path asks the model for a panel
# reading before it will judge.
AC4_HITS="$(grep -rn 'call ListAgents' "${REPO}/hooks" "${REPO}/payload" "${REPO}/skills" "${REPO}/agents" 2>/dev/null || true)"
expect_eq "126a: AC-4.4 — no hooks/, payload/, skills/ or agents/ surface still instructs 'call ListAgents'" \
  "" "$AC4_HITS"

# ---------- T22: the roster is the identity register — the doctrine, published ----------
#
# Two sentences the dispatching model reads before it invents anything. The name comes off
# the tick's FILL line and nowhere else, and a message is addressed to a NAME: a SendMessage
# to a transcript id after a /clear makes the harness resume a COPY while the original keeps
# running (measured 2026-09-14). Both are rendered from agents-src/blocks/orchestrator-dispatch.md
# through agents-src/templates/skills/canonical-sdlc/dispatch.md.tmpl, so the pin is on the
# RENDERED surface — a hand-edit to the output, or a render that never ran, both read here.
PIN_T22_NAME='**The name is the FILL line'"'"'s; you never choose one.**'
PIN_T22_ADDR='**Messages go to names, never ids.**'

if has_pin "$DISPATCH_MD" "$PIN_T22_NAME"; then
  ok "126c: dispatch.md carries the derived-name doctrine verbatim (T22 (a))"
else
  no "126c: dispatch.md carries the derived-name doctrine verbatim (T22 (a))" "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_T22_ADDR"; then
  ok "126d: dispatch.md carries the message-address doctrine verbatim (T22 (c))"
else
  no "126d: dispatch.md carries the message-address doctrine verbatim (T22 (c))" "file: $DISPATCH_MD"
fi

# THE SOURCE, NOT ONLY THE OUTPUT. `agents/` and `skills/` are render products; a pin that
# read only them would stay green over a hand-edit that the next `render.sh` silently
# reverts. Both sentences must be in the block the renderer reads.
T22_BLOCK="${REPO}/agents-src/blocks/orchestrator-dispatch.md"
if has_pin "$T22_BLOCK" "$PIN_T22_NAME" && has_pin "$T22_BLOCK" "$PIN_T22_ADDR"; then
  ok "126e: agents-src/blocks/orchestrator-dispatch.md is the SOURCE of both T22 sentences"
else
  no "126e: agents-src/blocks/orchestrator-dispatch.md is the SOURCE of both T22 sentences" \
     "file: $T22_BLOCK"
fi

# Anti-vacuity: the grep must fire on the shape it targets.
AC4_MUT="$TMP/ac4-listagents.md"
printf 'live-agents: stale — call ListAgents, then dispatch\n' > "$AC4_MUT"
expect_true "126b: the 'call ListAgents' grep fires on the shape it targets (the pattern discriminates)" \
  grep -q 'call ListAgents' "$AC4_MUT"

# AC-2.4: the rules file no longer claims the scaffold is unreachable from any role file — it
# now IS one of the seven rendered surfaces above.
AGENT_DISCIPLINE_MD="${REPO}/.claude/rules/agent-discipline.md"
if [ -f "$AGENT_DISCIPLINE_MD" ]; then
  AD_HITS="$(grep -c 'no role file can reach' "$AGENT_DISCIPLINE_MD" 2>/dev/null || true)"
  expect_eq "127: AC-2.4 — .claude/rules/agent-discipline.md no longer says 'no role file can reach'" \
    "0" "${AD_HITS:-0}"
else
  no "127: AC-2.4 — .claude/rules/agent-discipline.md no longer says 'no role file can reach'" \
     "file does not exist: $AGENT_DISCIPLINE_MD"
fi

# T15 (record/wave-12-fixit-171/assumptions.md, A-orch-5): the scaffold's own `Suites:` line
# comment must carry no token ending in `.test.sh`. The dispatch wall lifts any such token from
# a line starting `Suites:` as the agent's suite budget, so a brief that pastes this block
# verbatim would record the literal glob `*.test.sh` — a budget the wall's substring match can
# never expand, refusing the agent every suite. Pins the ABSENCE of that shape across all seven
# rendered surfaces, not just the source block, since render.sh is what a session actually reads.
AC2_SUITES_HITS=""
for _sf in $AC2_SURFACES; do
  if [ ! -f "$_sf" ]; then
    AC2_SUITES_HITS="${AC2_SUITES_HITS} ${_sf##*/}=absent"
    continue
  fi
  _hit="$(grep -n '^Suites:' "$_sf" 2>/dev/null | grep -o '[^[:space:]]*\.test\.sh' || true)"
  if [ -n "$_hit" ]; then
    AC2_SUITES_HITS="${AC2_SUITES_HITS} ${_sf##*/}=${_hit}"
  fi
done
if [ -z "$AC2_SUITES_HITS" ]; then
  ok "128a: T15 — the scaffold's 'Suites:' line carries no .test.sh token in any of the seven surfaces"
else
  no "128a: T15 — the scaffold's 'Suites:' line carries no .test.sh token in any of the seven surfaces" \
     "hits:${AC2_SUITES_HITS}"
fi

# Anti-vacuity: the grep must fire on the shape it targets.
AC2_SUITES_MUT="$TMP/ac2-suites-token.md"
printf 'Suites: none   # or *.test.sh tokens only\n' > "$AC2_SUITES_MUT"
expect_true "128b: the .test.sh-token grep fires on the shape it targets (the pattern discriminates)" \
  grep -qE '^Suites:.*\.test\.sh' "$AC2_SUITES_MUT"

section "Section 23: T2 — refusal scaffold in SKILL.md, the gate word, the Step-3 conditional design slot (epic-23 wave-13, REQ-2/REQ-8, AC-8.1/AC-8.2/AC-8.3)"

# WHAT THIS SECTION OWNS. Three independent AC-8 pins that all landed with T2: the Step-2
# frame heading dropped ", for a stranger" (AC-8.1); every step template, SKILL.md.tmpl and
# orchestrator-dispatch.md swapped "ratif*" for "approv*" (AC-8.2); the Step-3 card's
# "governing design" line moved from unconditional prose into a conditional slot inside the
# card template itself (AC-8.3). The scaffold's SECOND home — SKILL.md, via the new
# `<!-- INJECT: brief-scaffold -->` in SKILL.md.tmpl — is pinned here too, beside 124a's
# seven-surface count, because SKILL.md was never one of the AC2_SURFACES loop's seven.
#
# HERMETIC. Reads the committed rendered finals by path; doctored copies live under $TMP.

# --- AC-8.1: "for a stranger" is gone from every surface that could carry it ---
#
# fails-when (plan Verification Matrix): grep 'for a stranger' over agents-src, payload,
# tests hits, or render.sh produces a diff, or §76 no longer asserts first position (§76/§79
# above, re-anchored to the new heading, already cover the second half). EXCLUDES this suite's
# own file from the tests/ half of the sweep — its comments quote the retired phrase verbatim
# as the pin's own documentation of what was removed, the same reason $TMP mutants never count
# against a section's own grep elsewhere in this file.
AC81_HITS="$(grep -rl --exclude='docs-pins.test.sh' 'for a stranger' "${REPO}/agents-src" "${REPO}/payload" "${REPO}/tests" 2>/dev/null || true)"
expect_empty "129: AC-8.1 — no file under agents-src/, payload/ or tests/ (excluding this suite's own commentary) still reads 'for a stranger'" \
  "$AC81_HITS"

# Anti-vacuity: the grep must fire on the shape it targets.
AC81_MUT="$TMP/ac81-for-a-stranger.md"
printf 'Its first ratification is **Context and Problem, for a stranger**\n' > "$AC81_MUT"
expect_true "129b: the 'for a stranger' grep fires on the shape it targets (the pattern discriminates)" \
  grep -q 'for a stranger' "$AC81_MUT"

# --- AC-8.2: the gate word is "approve*", never "ratif*", on the gate-asking surfaces ---
#
# fails-when: `grep -rci 'ratif'` over SKILL.md, dispatch.md and steps/ sums to more than 0,
# or a docs-pins assertion still pins a "ratif" phrase there. SCOPED per A-orch-16 (ruling,
# recorded in assumptions.md, the requirements and the plan): `operational-rules.md`, same
# directory, is OUT of T2's scope — its dated historical attributions stay by the AC's own
# exception, and its seven undated prose uses move to T7. The three gate-asking surfaces
# below are the whole of AC-8.2's actual scope, not a narrowing of it: `steps/` is the WHOLE
# directory (all ten rendered step files), not only the six this task's Files declared —
# 4/7/8/9 never carried the word to begin with, verified before this pin shipped.
NORATIF_TARGETS="${SKILL_DIR}/SKILL.md ${SKILL_DIR}/dispatch.md ${SKILL_DIR}/steps"
NORATIF_SUM="$(grep -rci 'ratif' $NORATIF_TARGETS 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')"
if [ "$NORATIF_SUM" -eq 0 ] 2>/dev/null; then
  ok "130: AC-8.2 — SKILL.md, dispatch.md and steps/ read 'ratif' nowhere (case-insensitive)"
else
  no "130: AC-8.2 — SKILL.md, dispatch.md and steps/ read 'ratif' nowhere (case-insensitive)" \
     "sum=${NORATIF_SUM}: $(grep -rci 'ratif' $NORATIF_TARGETS 2>/dev/null | grep -v ':0$')"
fi

# Anti-vacuity: the grep must fire on the shape it targets.
NORATIF_MUT="$TMP/ac82-ratif.md"
printf 'Reply "approved" to ratify it.\n' > "$NORATIF_MUT"
expect_true "130b: the case-insensitive ratif grep fires on the shape it targets (the pattern discriminates)" \
  grep -qi 'ratif' "$NORATIF_MUT"

# --- AC-8.2 (SKILL scaffold-presence, beside 124a): SKILL.md carries the injected scaffold ---
#
# AC2_SCAFFOLD_LINE and AC2_SURFACES are Section 22's; SKILL.md was never one of the seven
# AC2_SURFACES (it renders from a different template, with its own byte cap), so this is a
# SEPARATE presence pin over an eighth surface, not a widening of 124a's loop.
SKILL_SCAFFOLD_N="$(grep -Fc -- "$AC2_SCAFFOLD_LINE" "$SKILL_MD" 2>/dev/null | tr -cd '0-9')"
[ -n "$SKILL_SCAFFOLD_N" ] || SKILL_SCAFFOLD_N=0
expect_eq "131: AC-2.2/AC-2.3 — SKILL.md carries the injected brief scaffold's fenced 'Expected artifact:' line exactly once" \
  "1" "$SKILL_SCAFFOLD_N"

# Anti-vacuity: a SKILL.md with the block stripped reads 0, not 1.
SKILL_SCAFFOLD_MUT="$TMP/skill-no-scaffold.md"
grep -Fv -- "$AC2_SCAFFOLD_LINE" "$SKILL_MD" > "$SKILL_SCAFFOLD_MUT" 2>/dev/null
expect_eq "131b: a SKILL.md with the fenced line stripped reads 0, not 1 (the count discriminates)" \
  "0" "$(grep -Fc -- "$AC2_SCAFFOLD_LINE" "$SKILL_SCAFFOLD_MUT" 2>/dev/null | tr -cd '0-9')"

# --- AC-8.3: the governing-design line is a conditional slot INSIDE the Step-3 card ---
#
# fails-when: the rendered steps/3.md still instructs a governing-design line outside the
# card or unconditionally, or its card template lacks the conditional slot.
PIN_GOV_SLOT='governing design <the spec'"'"'s `design:` pointer target, or the word "waived">'
if has_pin "$STEP3_MD" "$PIN_GOV_SLOT"; then
  ok "132: AC-8.3 — the Step-3 card carries the governing-design line as a slot under Artifacts"
else
  no "132: AC-8.3 — the Step-3 card carries the governing-design line as a slot under Artifacts" \
     "file: $STEP3_MD"
fi

PIN_GOV_OMIT='omit this line when the spec carries its own ## Design'
if has_pin "$STEP3_MD" "$PIN_GOV_OMIT"; then
  ok "132b: …and the slot names its own omission condition (a spec's own ## Design prints nothing extra)"
else
  no "132b: …and the slot names its own omission condition (a spec's own ## Design prints nothing extra)" \
     "file: $STEP3_MD"
fi

# The retired unconditional sentence must be gone, not just superseded — a template that
# kept both would print the governing-design line twice on every card.
GOV_OLD_HITS="$(grep -c 'It names the governing design on one line' "$STEP3_MD" 2>/dev/null | tr -cd '0-9')"
[ -n "$GOV_OLD_HITS" ] || GOV_OLD_HITS=0
expect_eq "132c: …and the old unconditional 'It names the governing design on one line' sentence is gone" \
  "0" "$GOV_OLD_HITS"

# Anti-vacuity: the slot pin must discriminate a card with the line stripped. Stripped by
# the "governing design" anchor, not by the (flattened, single-spaced) PIN_GOV_SLOT itself —
# the shipped line double-spaces its label column to align with its Artifacts siblings, and
# `grep -F` reads the raw file, unflattened.
GOV_MUT="$TMP/step3-no-gov-slot.md"
grep -v 'governing design' "$STEP3_MD" > "$GOV_MUT" 2>/dev/null
if has_pin "$GOV_MUT" "$PIN_GOV_SLOT"; then
  no "132d: a Step-3 card with the governing-design slot stripped still passes the slot pin (pin discriminates)" \
     "the mutated copy still matched — the pin does not see the removal"
else
  ok "132d: a Step-3 card with the governing-design slot stripped still passes the slot pin (pin discriminates)"
fi

# ---------------------------------------------------------------------------
section "Section 24: T3 — the repair rule reaches the rendered survival text (REQ-3, AC-3.3)"
#
# WHAT THIS OWNS. AC-3.3 (epic-23 wave-13-fixit-180 spec): "payload/context/survival.md
# lacks the rule" is a fail condition on its own — independent of the §AC2 byte-cap arms
# above (111b/125), which pin the SIX ROLE FILES' size. Those are a different set of files
# entirely: the survival text renders ONCE, to payload/context/survival.md, and never into
# any agents/*.md (record/wave-13-fixit-180/research-R2-walls.md §6), so this sentence adds
# no bytes there and those caps are unaffected by it.

PIN_REPAIR="sized to the harness maximum"
SURVIVAL_BLOCK_T3="${REPO}/agents-src/blocks/survival.md"
SURVIVAL_SHIPPED_T3="${REPO}/payload/context/survival.md"

if has_pin "$SURVIVAL_BLOCK_T3" "$PIN_REPAIR"; then
  ok "133a: agents-src/blocks/survival.md (the SOURCE) carries the repair rule"
else
  no "133a: agents-src/blocks/survival.md (the SOURCE) carries the repair rule" \
     "file: $SURVIVAL_BLOCK_T3"
fi

# The render is the delivery mechanism (same reasoning as assertion 12 above) — a pin on
# the source alone would pass on a repo whose render never ran, which is the state a
# dispatched writer who edited the block but skipped `render.sh` would be in.
if has_pin "$SURVIVAL_SHIPPED_T3" "$PIN_REPAIR"; then
  ok "133b: the rendered payload/context/survival.md carries the repair rule (render is current)"
else
  no "133b: the rendered payload/context/survival.md carries the repair rule (render is current)" \
     "file: $SURVIVAL_SHIPPED_T3 — run 'bash agents-src/render.sh'"
fi

# Anti-vacuity: the pin must discriminate against a mutated copy.
anchor "$SURVIVAL_BLOCK_T3" "$PIN_REPAIR" 1
DOCTORED_REPAIR="$TMP/survival-repair-mutated.md"
sed 's/sized to the harness maximum/sized however feels right/' "$SURVIVAL_BLOCK_T3" > "$DOCTORED_REPAIR"
if has_pin "$DOCTORED_REPAIR" "$PIN_REPAIR"; then
  no "133c: a doctored survival.md fails the repair-rule pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "133c: a doctored survival.md fails the repair-rule pin (pin discriminates)"
fi

# ---------------------------------------------------------------------------
section "Section 25: T5 — the no-row stop refusal doctrine (REQ-5, D8, AC-5.4)"
#
# WHAT THIS SECTION OWNS. Two sentences in agents-src/blocks/orchestrator-dispatch.md,
# rendered into skills/canonical-sdlc/dispatch.md (and its payload/ symlink). The doctrine
# sentence used to say a no-row name "passes through — not this gate's to guard; the refusal
# returns in 1.8.0."; it now states the refusal itself (D8, AC-5.4). The Panel-refresh
# bullet named the retired `poker: TASKSTOP <name>` line; it now names the `poker: STANDDOWN
# <name>` line T1 actually shipped (A-T1.11 — owed by this row, not T1's).

DISPATCH_BLOCK_T5="${REPO}/agents-src/blocks/orchestrator-dispatch.md"

PIN_T5_REFUSAL='A name with no row on this session'"'"'s roster is refused unless address- or bash-task-shaped.'
if has_pin "$DISPATCH_MD" "$PIN_T5_REFUSAL"; then
  ok "134a: dispatch.md carries the no-row REFUSAL sentence verbatim (D8, AC-5.4)"
else
  no "134a: dispatch.md carries the no-row REFUSAL sentence verbatim (D8, AC-5.4)" "file: $DISPATCH_MD"
fi

# THE SOURCE, NOT ONLY THE OUTPUT — same reasoning as 126e: a pin that read only the render
# product would stay green over a hand-edit that the next render.sh silently reverts.
if has_pin "$DISPATCH_BLOCK_T5" "$PIN_T5_REFUSAL"; then
  ok "134b: agents-src/blocks/orchestrator-dispatch.md is the SOURCE of the refusal sentence"
else
  no "134b: agents-src/blocks/orchestrator-dispatch.md is the SOURCE of the refusal sentence" \
     "file: $DISPATCH_BLOCK_T5"
fi

# AC-5.4's own grep: no surface that could ship the stale doctrine still carries it.
T5_STALE_HITS="$(grep -rl 'roster passes through' "${REPO}/agents-src" "${REPO}/skills" "${REPO}/payload/skills" 2>/dev/null || true)"
expect_eq "134c: AC-5.4 — no agents-src/, skills/ or payload/skills/ surface still says 'roster passes through'" \
  "" "$T5_STALE_HITS"

# Anti-vacuity: the grep must fire on the shape it targets.
T5_STALE_MUT="$TMP/t5-stale-doctrine.md"
printf "A name with no row on this session's roster passes through — not this gate's to guard.\n" > "$T5_STALE_MUT"
expect_true "134d: the 'roster passes through' grep fires on the shape it targets (the pattern discriminates)" \
  grep -q 'roster passes through' "$T5_STALE_MUT"

PIN_T5_STANDDOWN='the tick prints `poker: STANDDOWN <name>` per MET lineage still open on the roster and orders it, so one TaskStop passes'
if has_pin "$DISPATCH_MD" "$PIN_T5_STANDDOWN"; then
  ok "135a: dispatch.md's Panel-refresh bullet says STANDDOWN, not the retired TASKSTOP (A-T1.11)"
else
  no "135a: dispatch.md's Panel-refresh bullet says STANDDOWN, not the retired TASKSTOP (A-T1.11)" \
     "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_BLOCK_T5" "$PIN_T5_STANDDOWN"; then
  ok "135b: agents-src/blocks/orchestrator-dispatch.md is the SOURCE of the STANDDOWN sentence"
else
  no "135b: agents-src/blocks/orchestrator-dispatch.md is the SOURCE of the STANDDOWN sentence" \
     "file: $DISPATCH_BLOCK_T5"
fi

# The retired sentence must be gone, not just superseded — a template carrying both would
# print the wrong instruction on every tick that reads it.
T5_TASKSTOP_HITS="$(grep -c 'poker: TASKSTOP <name>' "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
[ -n "$T5_TASKSTOP_HITS" ] || T5_TASKSTOP_HITS=0
expect_eq "135c: …and the retired 'poker: TASKSTOP <name>' line is gone from dispatch.md" \
  "0" "$T5_TASKSTOP_HITS"

# ---------------------------------------------------------------------------
section "Section 26: T7 — the worktree alias, and operational-rules.md's own ratif sweep (REQ-7, AC-7.4, AC-8.2)"
#
# WHAT THIS OWNS. AC-7.4 (epic-23 wave-13-fixit-180 spec): the rendered dispatch.md carries
# a positive sentence about the one docs tree, and spawn-worktree.sh no longer carries the
# retired C2 sentence — both independent of T2's Section 23 pins, which cover the other
# three ratif→approv surfaces. AC-8.2's OWN scope split (Section 23's pin comment, line
# ~2634): operational-rules.md's seven UNDATED "ratif*" prose uses were explicitly OUT of
# T2's span and move here (A-orch-16) — this is that arm.

SPAWN_WORKTREE="${REPO}/payload/scripts/spawn-worktree.sh"

# --- AC-7.4a: the rendered dispatch.md carries the "one docs tree" sentence ---
#
# fails-when: grep -c "one docs tree" dispatch.md is 0.
ONEDOCS_N="$(grep -c 'one docs tree' "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
[ -n "$ONEDOCS_N" ] || ONEDOCS_N=0
if [ "$ONEDOCS_N" -ge 1 ] 2>/dev/null; then
  ok "137: AC-7.4 — the rendered dispatch.md names the one docs tree a relative worktree write lands in"
else
  no "137: AC-7.4 — the rendered dispatch.md names the one docs tree a relative worktree write lands in" \
     "count=${ONEDOCS_N} file=$DISPATCH_MD"
fi

# Anti-vacuity: a dispatch.md with the sentence stripped reads 0.
ONEDOCS_MUT="$TMP/dispatch-no-onedocs.md"
grep -v 'one docs tree' "$DISPATCH_MD" > "$ONEDOCS_MUT" 2>/dev/null
expect_eq "137b: a dispatch.md with the sentence stripped reads 0, not ≥1 (the count discriminates)" \
  "0" "$(grep -c 'one docs tree' "$ONEDOCS_MUT" 2>/dev/null | tr -cd '0-9')"

# --- AC-7.4b: spawn-worktree.sh no longer carries the retired C2 sentence ---
#
# fails-when: spawn-worktree.sh still says "NO SYMLINK, AND THAT IS THE POINT".
NOSYMLINK_N="$(grep -c 'NO SYMLINK, AND THAT IS THE POINT' "$SPAWN_WORKTREE" 2>/dev/null | tr -cd '0-9')"
[ -n "$NOSYMLINK_N" ] || NOSYMLINK_N=0
expect_eq "138: AC-7.4 — spawn-worktree.sh no longer says 'NO SYMLINK, AND THAT IS THE POINT'" \
  "0" "$NOSYMLINK_N"

# Anti-vacuity: the grep must fire on the shape it targets.
NOSYMLINK_MUT="$TMP/spawn-worktree-old-header.md"
printf '# NO SYMLINK, AND THAT IS THE POINT (bionic 1.4.0, design ledger C2).\n' > "$NOSYMLINK_MUT"
expect_true "138b: the NO-SYMLINK grep fires on the shape it targets (the pattern discriminates)" \
  grep -q 'NO SYMLINK, AND THAT IS THE POINT' "$NOSYMLINK_MUT"

# --- AC-8.2 (A-orch-16): operational-rules.md's seven UNDATED "ratif*" prose uses are gone;
# every DATED historical attribution stays byte-identical (this pin does not touch those). ---
#
# "Undated" = the line containing "ratif" carries no 2026-NN-NN date pattern anywhere on it
# — the same discriminator Section 23's comment describes and this task's brief measured
# (lines ~60, 167, 206, 241, 312, 365, 452 before the sweep). A dated line ("user-ratified,
# 2026-07-18", "ratified 2026-08-15") is untouched by design and must remain.
OPRULES_UNDATED_N="$(grep -i 'ratif' "$OPRULES" 2>/dev/null | grep -viE '2026-[0-9]{2}-[0-9]{2}' | grep -c .)"
[ -n "$OPRULES_UNDATED_N" ] || OPRULES_UNDATED_N=0
if [ "$OPRULES_UNDATED_N" -eq 0 ] 2>/dev/null; then
  ok "139: AC-8.2 — operational-rules.md carries no undated 'ratif' line (dated historical attributions untouched)"
else
  no "139: AC-8.2 — operational-rules.md carries no undated 'ratif' line (dated historical attributions untouched)" \
     "count=${OPRULES_UNDATED_N}: $(grep -in 'ratif' "$OPRULES" 2>/dev/null | grep -viE '2026-[0-9]{2}-[0-9]{2}')"
fi

# The dated lines must still be there — this pin narrows AC-8.2's scope, it does not widen
# it into a second copy of Section 23's "ratif" ban over the whole file (A-orch-16 is
# explicit that dated historical attributions stay byte-identical).
OPRULES_DATED_N="$(grep -i 'ratif' "$OPRULES" 2>/dev/null | grep -ciE '2026-[0-9]{2}-[0-9]{2}')"
[ -n "$OPRULES_DATED_N" ] || OPRULES_DATED_N=0
expect_true "139b: …and at least one dated historical attribution survives (this pin narrows, never widens)" \
  test "$OPRULES_DATED_N" -ge 1

# Anti-vacuity: the discriminator must actually tell dated from undated.
UNDATED_MUT="$TMP/opr-undated.md"
printf 'It is guidance ratified in conversation.\n' > "$UNDATED_MUT"
DATED_MUT="$TMP/opr-dated.md"
printf 'Epic integration-branch convention (user-ratified, 2026-07-18): a true epic.\n' > "$DATED_MUT"
expect_true "139c: an undated ratif line is caught by the discriminator" \
  bash -c "grep -i ratif '$UNDATED_MUT' | grep -viE '2026-[0-9]{2}-[0-9]{2}' | grep -q ."
expect_false "139d: …a dated one is not (the discriminator does not over-fire)" \
  bash -c "grep -i ratif '$DATED_MUT' | grep -viE '2026-[0-9]{2}-[0-9]{2}' | grep -q ."

# ---------------------------------------------------------------------------
section "Section 27: T10 — card row formats at fixed widths (REQ-9: AC-9.1, AC-9.2, AC-9.3, AC-9.4)"
#
# WHAT THIS SECTION OWNS. wave-14-tune-181 D9: a card row with a trailing column (the
# Step-1 requirement row, the Step-2 decision row, the Step-3 task row) used to be padded
# by eye — no stated width — which is why the user saw a column drift out of alignment
# ("Why is the implied third column Acceptance Criteria not left justified anymore?").
# Each of the three rendered step files now carries, beside its card, the row's printf
# format and one shared rule line (identical text in all three); AC-9.4 additionally
# requires the Step-2 decision row and the Step-3 task row to be a single line per row —
# trailing columns on the row's own first line, never staggered onto a line below it.
#
# WHY GREP 'printf', NOT THE EXACT FORMAT STRING. The spec's own Eval design row (§REQ-9
# "format lines") states the eval as `grep -c 'printf' … ≥ 1 each` — the format STRING is
# incidental to a particular width choice, the literal word `printf` is what a reader (or a
# future editor) can hold the row to: it says a stated format governs this row, not eyeballed
# spacing. AC-9.2 is what pins the rule line's own exact wording, with a mutation arm.
#
# HERMETIC. Reads the committed rendered finals by path; the mutation arms work on TMP copies.

# --- AC-9.1a: each of the three rendered step files names a printf format ---
for _pair in "140a:$STEP1_MD:steps/1.md" "140b:$STEP2_MD:steps/2.md" "140c:$STEP3_MD:steps/3.md"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _file="${_rest%:*}"; _which="${_rest##*:}"
  _cnt="$(grep -c 'printf' "$_file" 2>/dev/null | tr -cd '0-9')"
  [ -n "$_cnt" ] || _cnt=0
  if [ "$_cnt" -ge 1 ] 2>/dev/null; then
    ok "${_n}: AC-9.1 — ${_which} names its card row's printf format at least once"
  else
    no "${_n}: AC-9.1 — ${_which} names its card row's printf format at least once" "count=$_cnt file=$_file"
  fi
done

# --- AC-9.1b / AC-9.2: the shared rule line, verbatim, in all three -----------------------
CARD_RULE_LINE='Rows are rendered by that format, never padded by hand.'
for _pair in "141a:$STEP1_MD:steps/1.md" "141b:$STEP2_MD:steps/2.md" "141c:$STEP3_MD:steps/3.md"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _file="${_rest%:*}"; _which="${_rest##*:}"
  expect_contains "${_n}: AC-9.1/AC-9.2 — ${_which} carries the shared rule line verbatim" \
    "$CARD_RULE_LINE" "$(cat "$_file" 2>/dev/null)"
done

# 142: Anti-vacuity (AC-9.2's own mutation arm) — a copy of steps/1.md with the rule line
# stripped must make 141a's check go red.
anchor "$STEP1_MD" "$CARD_RULE_LINE" 1
DOCTORED_NO_RULE="$TMP/step1-no-rule-line.md"
grep -v -F "$CARD_RULE_LINE" "$STEP1_MD" > "$DOCTORED_NO_RULE"
case "$(cat "$DOCTORED_NO_RULE")" in
  *"$CARD_RULE_LINE"*) no "142: AC-9.2 — a copy of steps/1.md missing the rule line still 'has' it (pin is vacuous)" ;;
  *) ok "142: AC-9.2 — a copy of steps/1.md missing the rule line fails the rule-line check (pin discriminates)" ;;
esac

# --- AC-9.4: the Step-2 decision row and the Step-3 task row are single-line rows,
# trailing columns on the row's own first line, never staggered onto a line below it. ---
#
# THE ANTI-PATTERN. Before this task, the Step-2 card's Decisions row was two physical
# lines: the decision text on one, then a line starting with whitespace and the bare word
# "serves" (its trailing columns) on the next — staggered, not on the row's own first line.
# A staggered trailing-column line reads as whitespace, then the FIRST WORD of the line is
# one of the row's own trailing-column names — never true of a header line, where the
# column names sit to the right of a section label ("Decisions … serves … ADR").
staggered_trailing() {
  # $1 = card body, $2.. = trailing column names to check as a staggered line's first word
  local _body="$1"; shift
  local _col
  for _col in "$@"; do
    if printf '%s\n' "$_body" | grep -qE "^[[:space:]]+${_col}([[:space:]]|\$)"; then
      return 0
    fi
  done
  return 1
}

if staggered_trailing "$CARD2" "serves" "ADR"; then
  no "143: AC-9.4 — the Step-2 card's decision row keeps serves/ADR on the row's first line (no staggered line found 'serves'/'ADR' as a line's first word)" \
     "card body: $CARD2"
else
  ok "143: AC-9.4 — the Step-2 card's decision row keeps serves/ADR on the row's first line (no staggered second line)"
fi

if staggered_trailing "$CARD3" "kind" "depends" "agent"; then
  no "144: AC-9.4 — the Step-3 card's task row keeps kind/depends/agent on the row's first line (no staggered line found)" \
     "card body: $CARD3"
else
  ok "144: AC-9.4 — the Step-3 card's task row keeps kind/depends/agent on the row's first line (no staggered second line)"
fi

# 145: Anti-vacuity — the pre-T10 staggered shape (D<n> line, then a line whose first word
# is "serves") must make 143's check discriminate: fed the OLD Step-2 decision row shape,
# staggered_trailing must return true (found).
OLD_STAGGERED_DECISIONS='  Decisions
    D<n>   <the decision in one line>
           serves <REQ ids>                                    ADR <file | none>'
if staggered_trailing "$OLD_STAGGERED_DECISIONS" "serves" "ADR"; then
  ok "145: AC-9.4 — the pre-T10 staggered Decisions shape is caught by the 143 discriminator (pin is not vacuous)"
else
  no "145: AC-9.4 — the pre-T10 staggered Decisions shape is caught by the 143 discriminator" \
     "fixture: $OLD_STAGGERED_DECISIONS"
fi

# --- AC-9.1 (fold-in, T14): the Step-2 card's Ownership and Eval-design rows also name
# their own printf format beside the card — the two row shapes T10 left unannotated for
# lack of aggregate-cap headroom (A-T10.1; Chris 2026-09-14 "Option 2" at the T10 landing,
# wave-14 T14). Verbatim checks, the same idiom as 141a/141b/141c above.
OWNERSHIP_ROW_LINE='Ownership row: `    %-20s owner %-42s surfaces %-44s test %s` (concept, owner, surfaces, test) (printf).'
expect_contains "146: AC-9.1 — steps/2.md names the Ownership row's printf format verbatim (T14 fold-in)" \
  "$OWNERSHIP_ROW_LINE" "$(cat "$STEP2_MD" 2>/dev/null)"

EVAL_DESIGN_ROW_LINE='Eval-design row: `    %-8s %-58s %6s %5s %9s %5s %6s` (requirement, approach, static, unit, hermetic, live, human) (printf).'
expect_contains "147: AC-9.1 — steps/2.md names the Eval-design row's printf format verbatim (T14 fold-in)" \
  "$EVAL_DESIGN_ROW_LINE" "$(cat "$STEP2_MD" 2>/dev/null)"

# AC-9.3 (render clean, byte caps hold) is discharged by Section 11's `--check` arms and
# Section 18's byte-cap arms against these same rendered finals — both already read
# steps/1.md, steps/2.md and steps/3.md unconditionally, so no separate pin is needed here;
# a cap regression from this task's own additions shows up there, not in this section.

finish
