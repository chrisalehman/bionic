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
PIN_PROBE='`resources_probe` prints `cores=… mem_gb=… disk_free_gb=…`; `resources_budget <cores> <mem_gb> <disk_free_gb>` yields the run'"'"'s `parallel-budget:`, verbatim in plan frontmatter, displayed, never re-derived downstream.'
# RE-POINTED AT THE CORRECTED DOCTRINE (Step-6 architecture A-2). The old needle pinned
# `dispatches in one batch up to `writers`` — the ceiling, unregulated — while the tick fills
# to the RUNG off a live-trimmed open count, so the pin was holding a contradiction green. A
# pin follows the sentence it is a pin FOR: when the doctrine is corrected the needle moves
# with it, or the test outlives the thing it was protecting.
PIN_FILL='every ready task dispatches in one batch sized by the rung the tick prints — `poker: rung=<n>/<ceiling>`, the machine'"'"'s answer to how wide it will carry right now — with `writers` as the ceiling that rung is taken against and the only number the wall enforces'
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
for token in 'EMERGENCY' 'HOLD' 'rung=<n>/<ceiling>' 'FILL <ids>' 'fill-declined: <reason>' 'approval:<name>'; do
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
TICK_RESUME_NEEDLE='delete every job whose prompt begins with `bionic-patrol session=`'
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
# RE-POINTED (wave-26): the NARROW/RELAX retirement sentence described a mechanism long gone
# and was cut; the pin now holds the sentence that says what sizes a fill.
PIN_RUNG='Neither resizes a fill. The rung is `pressure_level`'"'"'s integer, printed on every tick as `poker: rung=<n>/<ceiling>`, and it is the number a fill is sized by.'

if has_pin "$DISPATCH_MD" "$PIN_TASKLIST"; then
  ok "48: SKILL.md's resume ritual rebuilds the task list after it binds, verbatim"
else
  no "48: SKILL.md's resume ritual rebuilds the task list after it binds, verbatim" \
     "file: $DISPATCH_MD"
fi

if has_pin "$DISPATCH_MD" "$PIN_RUNG"; then
  ok "49: SKILL.md's Patrol prompt names the rung line and what sizes a fill, verbatim"
else
  no "49: SKILL.md's Patrol prompt names the rung line and what sizes a fill, verbatim" \
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

anchor "$DISPATCH_MD" 'it is the number a fill is sized by' 1
DOCTORED_RUNG="$TMP/skill-rung-mutated.md"
sed 's/it is the number a fill is sized by/it is a number a fill may ignore/' "$DISPATCH_MD" > "$DOCTORED_RUNG"
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
# NO HAND COUNT (wave-25 T15). The sentence said "the seven" until `workspaces` and `gate`
# joined the list; the count is gone, because 44c below already compares the number of
# names against `PATROL_STATE_CLASSES`, and the six bytes paid for the two new names under
# row 115's cap.
#
# THE FIELD NAME `tmp-wiped:` IS DELIBERATELY UNTOUCHED (§Evidence, step 8 row). It is an
# evidence key the gate parses, not prose; renaming it would be an interface change and is
# not what the finding asked for.
PIN_TMP_SPARE="sparing a LIVE neighbour session's keyed files across the \`PATROL_STATE_CLASSES\` (\`roster\`/\`preflight\`/\`engaged\`/\`sweeper\`/\`patrol\`/\`stop-orders\`/\`tick-digest\`/\`workspaces\`/\`gate\`), because one root can hold another session's live run and a blanket wipe would take its engagement marker, roster and Patrol stamp with it, un-engaging it mid-run; a dead neighbour's keyed files are removed, not spared"
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
anchor "$PATROL_LIB_T28" "PATROL_STATE_CLASSES=\"${PATROL_CLASSES_ACTUAL}\"" 1
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

section "Section 8: dispatch.md no longer points a writer at the rung (the writer does not set its width)"
#
# RETIRED (wave-26). This section pinned dispatch.md's sentence telling every brief to say
# "take your test width from pressure_level at suite start", while the dispatch terms
# (PIN_JOBS, pins 11/12) tell the writer the opposite: tests/run.sh reads its own width and
# `pressure_level` is not a command. The sentence was cut; the pin now holds its absence,
# beside the positive it contradicted, and a doctored copy proves the absence arm can fail.
PIN_JOBS_SKILL='take your test width from pressure_level at suite start'
expect_true "53 precondition: the dispatch terms still tell the writer it does not set its width" \
  has_pin "$SURVIVAL_SHIPPED" "$PIN_JOBS"
expect_false "53: dispatch.md no longer tells a brief to point the writer at the rung" \
  has_pin "$DISPATCH_MD" "$PIN_JOBS_SKILL"
anchor "$DISPATCH_MD" '**Fill the budget.**' 1
DOCTORED_SKILL_JOBS="$TMP/skill-jobs-mutated.md"
sed 's/\*\*Fill the budget\.\*\*/**Fill the budget.** Each brief in the batch points the writer at the rung: `take your test width from pressure_level at suite start`./' \
  "$DISPATCH_MD" > "$DOCTORED_SKILL_JOBS"
expect_true "54: a dispatch.md that brings the sentence back is caught (pin discriminates)" \
  has_pin "$DOCTORED_SKILL_JOBS" "$PIN_JOBS_SKILL"


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
PIN_S13_REGRESSION='The dispatch wall refuses any other full run and names the suites that prove the change.'

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
# RE-POINTED (wave-27 T11, D5): the evidence checks are pushed at start, so the role file
# points at the checks file, no longer at the dispatch brief.
expect_contains "68e: …it points at the checks delivered at start instead" \
  "Checks: payload/context/checks-<question>.md" \
  "$(cat "${REPO}/agents/auditor.md")"

# RE-POINTED (wave-27 T11, D5): agents/critic.md no longer carries the template; its checks are
# pushed at start, and §W27-T11 pins the absence against a mutant render.
same_everywhere 69 "the critic prompt template is one text in the block and the skill file" \
  "${BLOCK_DIR}/critic-template.md" "CRITIC-TEMPLATE" "$STEP6_MD"

# RE-POINTED (wave-26 T1, AC-1.3): the axis is the Stance-1 reviewer's, so agents/critic.md
# stopped injecting it; §W26-3 pins the absence against a mutant render.
same_everywhere 70 "the duplication axis is one text in the block and the skill file" \
  "${BLOCK_DIR}/duplication-axis.md" "DUPLICATION-AXIS" "$STEP6_MD"

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
# ONE ROW PER TEMPLATE, a relation rather than a number (wave-27 T8: a hard-coded 24 went red
# on every new rendering, and two rows were adding them side by side). The count is taken
# from the SOURCES, the templates of the five render units, never from the finals: a count
# derived from whatever the renderer just produced would agree with itself no matter what the
# renderer dropped, and the templates are what it was asked to render.
MANIFEST_TMPLS="$(ls "${REPO}"/agents-src/templates/*.md.tmpl "${REPO}"/agents-src/templates/commands/*.md.tmpl \
  "${REPO}"/agents-src/templates/skills/canonical-sdlc/*.md.tmpl \
  "${REPO}"/agents-src/templates/skills/canonical-sdlc/steps/*.md.tmpl \
  "${REPO}"/agents-src/templates/context/*.md.tmpl 2>/dev/null | wc -l | tr -d ' ')"
expect_true "74c precondition: the five render units hold templates" test "${MANIFEST_TMPLS:-0}" -gt 0
expect_eq "74c: it carries one row per template (roles, commands, the split skill, the context files)" \
  "$MANIFEST_TMPLS" "$(printf '%s\n' "$MANIFEST_BODY" | wc -l | tr -d ' ')"
for _ctx in "${REPO}"/agents-src/templates/context/*.md.tmpl; do
  _ctx="${_ctx##*/}"
  expect_contains "74h: …including context/${_ctx%.tmpl}, plugin-root-relative" \
    "  context/${_ctx%.tmpl}" "$MANIFEST_BODY"
done
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

# AC-K3.1, REWRITTEN (wave-26 T19, AC-2.1): the frame used to open by approving Context and
# Problem first. Step 1 already approves the problem and its context, so the frame now opens by
# saying so and asks nothing again; §W26-7e pins the old approval's absence beside a mutation.
PIN_K3_FIRST='**Open with the frame**, before any question. Step 1 approved the problem and its context; the frame does not ask again.'

# AC-K3.2, half 1: the frame carries a "Mechanisms inherited" item, each line
# marked kept or questioned.
PIN_K3_MECH='**Mechanisms inherited**, one line per substrate or mechanism the design builds on, each marked `kept` or `questioned`'

# AC-K3.2, half 2: placement decisions (tier / runtime surface / hardware) are
# named strategic BY RULE, not left to a default.
PIN_K3_STRATEGIC='placing a test cohort in a tier, a job on a runtime surface, or a workload on hardware is **strategic by rule**'

if has_pin "$STEP2_MD" "$PIN_K3_FIRST"; then
  ok "76: steps/2.md's frame opens without re-approving the problem Step 1 approved"
else
  no "76: steps/2.md's frame opens without re-approving the problem Step 1 approved" "file: $STEP2_MD"
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

# 79 and 79b (the Context-and-Problem order reversal) were deleted with the text they
# mutated (wave-26 T19); W26-7em is the mutation arm for its return.

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

# 92a REWRITTEN (wave-26 T19, D13): the card the design is approved on carries a prose head
# and names every artifact by path; Ownership left the card for the `show ownership` sub-view.
if has_all "$CARD2" "Goal" "Approach" "Worth your eye" "Decisions" "serves" "ADR" "Eval design" \
                    "Artifacts" "ledger" "reqs" "show ownership"; then
  ok "92a: the Step-2 card carries Goal, Approach, Worth your eye, Decisions (serves/ADR), Eval design, Artifacts (with the ledger and requirements) and the ownership sub-view"
else
  no "92a: the Step-2 card carries Goal, Approach, Worth your eye, Decisions (serves/ADR), Eval design, Artifacts (with the ledger and requirements) and the ownership sub-view" \
     "card body: $CARD2"
fi
expect_absent "92a1: …and no Ownership block of its own (it is the sub-view)" \
  "$(printf '\n  Ownership\n')" "$(printf '\n%s\n' "$CARD2")"
anchor -E "$STEP2_MD" '^  Eval design' 1
DOCTORED_STEP2_OWN="$TMP/step2-ownership-back.md"
awk '/^  Eval design/ { print "  Ownership"; print "    <concept>    owner <module>"; print "" } { print }' \
  "$STEP2_MD" > "$DOCTORED_STEP2_OWN"
expect_contains "92a1m: a Step-2 card with its Ownership block put back is caught by 92a1's extractor" \
  "$(printf '\n  Ownership\n')" "$(printf '\n%s\n' "$(card_span "$DOCTORED_STEP2_OWN" 'Step 2 · Design')")"

# 92a2: AC-11.2's sibling for Step 2 (T8's carry-over, wave-19 REQ-11). `_card_step2`
# (payload/scripts/card.sh) never prints an `Open at approval` section — the scaffold
# carried one anyway until this wave, the same lying-surface class C8 found and fixed on
# Step 3 (docs-pins 107d-g). The scaffold is now the step's sole statement of what the
# card carries, so the section's absence is pinned directly, not left to an omission from
# 92a's needle list — a needle list a reintroduced section would still satisfy in silence.
case "$CARD2" in
  *"Open at approval"*)
    no "92a2: the Step-2 card no longer carries the un-rendered Open-at-approval section" \
       "card body: $CARD2" ;;
  *)
    ok "92a2: the Step-2 card no longer carries the un-rendered Open-at-approval section" ;;
esac

# 92a3: Anti-vacuity — the retired section put back into a copy of the scaffold must fail
# 92a2's check, proving 92a2 discriminates rather than being vacuously true forever.
anchor "$STEP2_MD" '  Artifacts' 1
DOCTORED_STEP2_OPEN_AT="$TMP/step2-open-at-approval.md"
awk '/^  Artifacts$/ { print "  Open at approval"; print "    <design question still open>   → <what closes it>"; print "" }
     { print }' "$STEP2_MD" > "$DOCTORED_STEP2_OPEN_AT"
DOCTORED_CARD2="$(card_span "$DOCTORED_STEP2_OPEN_AT" 'Step 2 · Design')"
case "$DOCTORED_CARD2" in
  *"Open at approval"*)
    ok "92a3: a scaffold carrying the retired Open-at-approval section fails 92a2's check (pin discriminates)" ;;
  *)
    no "92a3: a scaffold carrying the retired Open-at-approval section still passes 92a2's check (pin is vacuous)" \
       "doctored card body: $DOCTORED_CARD2" ;;
esac

if has_all "$CARD2" "static" "unit" "hermetic" "live" "human" "total"; then
  ok "92b: …and its Eval design is one row per requirement with the five type counts and a total"
else
  no "92b: …and its Eval design is one row per requirement with the five type counts and a total" \
     "card body: $CARD2"
fi

if has_all "$CARD3" "Branches" "Tasks" "kind" "depends" "agent" "serves" \
                    "Chain and width" "Verification" "Artifacts"; then
  ok "93a: the Step-3 card carries Branches, Tasks (kind/depends/agent, each with what it serves), Chain and width, Verification, Artifacts"
else
  no "93a: the Step-3 card carries Branches, Tasks (kind/depends/agent, each with what it serves), Chain and width, Verification, Artifacts" \
     "card body: $CARD3"
fi
if has_all "$CARD3" "longest chain" " min" "peak width" " writers" "    spec  "; then
  ok "93b: …the longest chain with its minutes, the peak width against the writers, and the design's path"
else
  no "93b: …the longest chain with its minutes, the peak width against the writers, and the design's path" "card body: $CARD3"
fi
# Step 3 approves the plan and the matrix only (wave-26 D12): the purpose and the eval counts
# were approved with the design, so the card the two rows above read repeats neither.
expect_absent "93c: …and no Problem block repeats the purpose" "  Problem" "$CARD3"
expect_absent "93d: …and no eval-count line repeats the design's counts" "criteria ·" "$CARD3"

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

# AC-11.2 (wave-19 REQ-11, D12) — RETIRES AC-K4.3's 107d-f. The scaffold's `Open at
# approval` section and its `governing design` artifact line were never rendered:
# `_card_step3` (payload/scripts/card.sh) emits neither, so the picture promised a
# contract the approval never saw. The scaffold is the step's sole statement of what the
# card carries now (the paragraph above it became a pointer), so it is pinned to the
# RENDERER, not to a word list: its section headings and its Artifacts labels must equal
# what `card.sh step3` prints for a plan. A section added to one side only goes red here.
# C8 (wave-19-fixit-186 critic, 26b6b65): the pin stopped at section headings and
# Artifacts labels, so a `batch <k> · <n> of <n>` line under `Parallel width` — the card's
# OWN output, per `_card_batch_widths` — went unseen on both sides. `pw` counts those
# lines (marker only, not the numbers, which are plan-specific) the same way `art` counts
# artifact labels, so a side that drops the line goes red against the side that keeps it.
# wave-26 D12: the width block is `Chain and width`, and its chain and peak lines are read the
# way the batch lines are, so a side that drops one goes red against the side that keeps it.
card3_shape() {  # <card text on stdin> -> each section heading's first word, artifact labels, width lines
  awk '/^  [A-Z]/ { print $1; art = ($1 == "Artifacts"); pw = ($1 == "Chain"); next }
       art && /^    [a-z]/ { print "artifact:" $1 }
       pw && /^    (longest chain|peak width)  / { print "width:" $1 }
       pw && /^    batch / { print "batch" }'
}
SHAPE_PLAN="$TMP/wave-97-shape.plan.md"
printf '%s\n' '---' 'scale: wave' 'walk: required' 'rigor: audited' \
  'parallel-budget: writers=8 suites=4 worktrees=32 test_jobs=8 source=probe' \
  'working-branch: wave/97-shape' 'integration-branch: main' 'base-sha: abc1234' \
  'spec: specs/epic-97/wave-97-shape.spec.md' '---' '' \
  '# fixture wave 97 · plan' '' '## Goal' '' 'Render one card to compare against the scaffold.' '' \
  '## SDLC State' '' 'current: 3' '' '## Tasks' '' \
  '| id | step | kind | task | agent | deps | size | serves | Files | worktree | status |' \
  '|---|---|---|---|---|---|---|---|---|---|---|' \
  '| T1 | 4 | build | REQ-1: the task. complexity: standard | implementor | — | 30 | REQ-1 | a.sh | — | pending |' \
  '' '## Verification Matrix' '' '| AC | tier | status | evidence | auditor |' '|---|---|---|---|---|' \
  '| AC-1.1 | T2 | pending | — | — |' > "$SHAPE_PLAN"
SHAPE_RENDERED="$(bash "${REPO}/payload/scripts/card.sh" step3 "$SHAPE_PLAN" 2>/dev/null | card3_shape)"
expect_contains "107d: AC-11.2 — card.sh step3 renders a card with an Artifacts section (the comparison has a subject)" \
  "Artifacts" "$SHAPE_RENDERED"
expect_eq "107e: AC-11.2 — the Step-3 scaffold's sections and artifact labels are exactly what card.sh step3 renders" \
  "$SHAPE_RENDERED" "$(printf '%s\n' "$CARD3" | card3_shape)"

# 107f: Anti-vacuity — the retired section put back into a copy of the scaffold fails 107e.
anchor "$STEP3_MD" '  Artifacts' 1
DOCTORED_OPEN_AT="$TMP/step3-open-at-approval.md"
awk '/^  Artifacts$/ { print "  Open at approval"; print "    <question>   → closed by task <n>"; print "" }
     { print }' "$STEP3_MD" > "$DOCTORED_OPEN_AT"
if [ "$(card_span "$DOCTORED_OPEN_AT" 'Step 3 · Plan' | card3_shape)" = "$SHAPE_RENDERED" ]; then
  no "107f: a scaffold carrying a section the renderer never emits still matches (pin is vacuous)"
else
  ok "107f: a scaffold carrying a section the renderer never emits fails 107e (pin discriminates)"
fi

# 107g: Anti-vacuity — C8 (wave-19-fixit-186 critic, 26b6b65). 107f mutates a whole
# section that never renders; that proves the pin sees a section-level drift, but says
# nothing about a single line dropped FROM a section the renderer does emit, which is
# exactly the shape C8 found (the `batch <k> · <n> of <n>` line under `Parallel width`
# was simply absent — no stray section, no wrong label, just a missing line). This
# mutation strips only that line and leaves `Parallel width` and every other section
# intact, so it targets 107e's `pw` arm specifically.
anchor "$STEP3_MD" '    batch ' 1
DOCTORED_NO_BATCH="$TMP/step3-no-batch-line.md"
awk '/^    batch / { next } { print }' "$STEP3_MD" > "$DOCTORED_NO_BATCH"
if [ "$(card_span "$DOCTORED_NO_BATCH" 'Step 3 · Plan' | card3_shape)" = "$SHAPE_RENDERED" ]; then
  no "107g: a scaffold missing the renderer's batch line still matches (pin is vacuous)"
else
  ok "107g: a scaffold missing the renderer's batch line fails 107e (pin discriminates)"
fi

# 107h: Anti-vacuity — wave-26 D12. The chain line is the card's own output, like the batch
# line; a scaffold that drops it must fail 107e through the `width:` arm.
anchor "$STEP3_MD" '    longest chain  ' 1
DOCTORED_NO_CHAIN="$TMP/step3-no-chain-line.md"
awk '/^    longest chain  / { next } { print }' "$STEP3_MD" > "$DOCTORED_NO_CHAIN"
if [ "$(card_span "$DOCTORED_NO_CHAIN" 'Step 3 · Plan' | card3_shape)" = "$SHAPE_RENDERED" ]; then
  no "107h: a scaffold missing the renderer's chain line still matches (pin is vacuous)"
else
  ok "107h: a scaffold missing the renderer's chain line fails 107e (pin discriminates)"
fi

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
#
# ROLE_TOTAL_CAP RAISED 26,300 -> 26,400 (epic-23 wave-16-fixit-183 T3, A-T3.3, REQ-1 AC-1.8):
# the brief-scaffold block's new `Re-executes:` line (AC-1.8 — the label must reach all six
# role files, dispatch.md, and SKILL.md, rendered from agents-src/) costs a minimum of 21 B
# per role file even at its shortest label-legal form, `` `Re-executes: `<cmd>`` `` with no
# comment and a single placeholder (the two-command example and the ≤3 comment T3's own brief
# suggested were cut first, in agents-src/blocks/brief-scaffold.md and
# agents-src/templates/auditor.md.tmpl's own "Suites:/Re-executes:" sentence, which is a
# byte-for-byte tightening of its pre-task wording, not a growth). 21 B/file × 6 = +126 B
# against the 79 B of headroom the previous raise left (26,300 − 26,221) put the measured
# total at 26,344 B, 44 B over. Raised here (T3's own declared Files: includes this suite)
# rather than drop the label from a role file the AC names, or touch a template outside T3's
# declared Files to trim further; logged as A-T3.3 in record/wave-16-fixit-183/assumptions.md.

ROLE_CAP=5500
ROLE_TOTAL_CAP=26400
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
# RE-POINTED (wave-27 T11, D6): was `"6" = $ROLE_COUNT`, which a seventh role turned red for
# no defect. A relation now, naming no count (.claude/rules/test-harness.md): the role files
# are exactly the roles render.sh renders, and that set is not empty.
# role_files_are_roles <agents dir> <roles> -> yes when the dir's *.md basenames are the roles.
role_files_are_roles() {
  local _have _want _f
  _have="$(for _f in "$1"/*.md; do [ -f "$_f" ] && basename "$_f" .md; done | LC_ALL=C sort | tr '\n' ' ')"
  _want="$(printf '%s\n' $2 | /usr/bin/grep -v '^$' | LC_ALL=C sort | tr '\n' ' ')"
  [ -n "$_want" ] && [ "$_have" = "$_want" ] && echo yes || echo no
}
ROLES_DECLARED="$(sed -n 's/^ROLES="\(.*\)"$/\1/p' "$RENDER_SH")"
expect_nonempty "111a precondition: render.sh declares its ROLES" "$ROLES_DECLARED"
expect_eq "111a: the role files are the roles render.sh renders (the cap arms have something to measure)" \
  "yes" "$(role_files_are_roles "${REPO}/agents" "$ROLES_DECLARED")"
mkdir -p "$TMP/111a-plus" "$TMP/111a-stray"
cp "${REPO}"/agents/*.md "$TMP/111a-plus/" 2>/dev/null
cp "${REPO}"/agents/*.md "$TMP/111a-stray/" 2>/dev/null
cp "${REPO}/agents/researcher.md" "$TMP/111a-plus/planted.md" 2>/dev/null
cp "${REPO}/agents/researcher.md" "$TMP/111a-stray/planted.md" 2>/dev/null
expect_eq "111a-m1: a planted role in ROLES with its file stays green (no count is pinned)" \
  "yes" "$(role_files_are_roles "$TMP/111a-plus" "$ROLES_DECLARED planted")"
expect_eq "111a-m2: a role file render.sh does not declare is caught" \
  "no" "$(role_files_are_roles "$TMP/111a-stray" "$ROLES_DECLARED")"
mkdir -p "$TMP/111a-none"
expect_eq "111a-m3: no role and no role file reads as red, not as an empty match" \
  "no" "$(role_files_are_roles "$TMP/111a-none" "")"
if [ -z "$ROLE_OVER" ]; then
  ok "111b: AC-1c.1 — every agents/*.md is at or under ${ROLE_CAP} B"
else
  no "111b: AC-1c.1 — every agents/*.md is at or under ${ROLE_CAP} B" \
     "over cap:${ROLE_OVER} — the survival block renders once now; a role file this large is carrying a copy of something shared"
fi
if [ "$ROLE_TOTAL" -le "$ROLE_TOTAL_CAP" ]; then
  ok "111c: AC-1c.2 — the role files total ${ROLE_TOTAL} B, at or under ${ROLE_TOTAL_CAP} B"
else
  no "111c: AC-1c.2 — the role files total ${ROLE_TOTAL} B, at or under ${ROLE_TOTAL_CAP} B" \
     "total=${ROLE_TOTAL} — was 57013 before wave-11 1c"
fi

# TWO VIEWS OF ONE SCAFFOLD (wave-21 T7b, design ledger Δ9). The scaffold has two readers.
# The orchestrator AUTHORS briefs from `agents-src/blocks/brief-scaffold.md`, rendered into
# dispatch.md and SKILL.md. A dispatched agent READS a brief and needs only what each label
# obliges it to do, so the six role files carry `brief-scaffold-reader.md` instead. Two
# blocks can drift where one could not; 111d holds their label sets equal (order-free), so a
# label added to the author view without a reader clause turns this red. 111c's cap is why
# the reader view exists; it does not move.
#
# fails-when: a `<Label>:` line is in one view and not the other; a role file carries the
# author block or lacks the reader block; dispatch.md or SKILL.md lacks the author block.
scaffold_label_set() {  # <file> -> its line-start `<Label>:` tokens, sorted, one line
  /usr/bin/grep -oE '^[A-Z][A-Za-z-]*( [a-z]+)?:' "$1" 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' '
}
SV2_AUTHOR="${REPO}/agents-src/blocks/brief-scaffold.md"
SV2_READER="${REPO}/agents-src/blocks/brief-scaffold-reader.md"
SV2_A="$(scaffold_label_set "$SV2_AUTHOR")"
SV2_R="$(scaffold_label_set "$SV2_READER")"
if [ -n "$SV2_A" ] && [ "$SV2_A" = "$SV2_R" ]; then
  ok "111d: Δ9 — the reader scaffold names the same label set as the author scaffold"
else
  no "111d: Δ9 — the reader scaffold names the same label set as the author scaffold" \
     "author=[${SV2_A}] reader=[${SV2_R}]"
fi
# Anti-vacuity: a copy of the reader block with one label line removed must fail 111d's check.
SV2_MUT="$TMP/reader-one-label-short.md"
/usr/bin/grep -v '^Subprocess claim:' "$SV2_READER" > "$SV2_MUT" 2>/dev/null
SV2_M="$(scaffold_label_set "$SV2_MUT")"
expect_eq "111e: a reader block missing one label fails 111d's check (the pin discriminates)" \
  "differs" "$([ -n "$SV2_M" ] && [ "$SV2_M" != "$SV2_A" ] && echo differs || echo same-or-empty)"

# Which view lands where: the reader block in all six role files and the author block in none
# of them; the author block in dispatch.md and SKILL.md.
SV2_BAD=""
for _rf in "${REPO}"/agents/*.md; do
  /usr/bin/grep -qF '<!-- BRIEF-SCAFFOLD-READER-BEGIN -->' "$_rf" || SV2_BAD="${SV2_BAD} ${_rf##*/}:no-reader"
  /usr/bin/grep -qF '<!-- BRIEF-SCAFFOLD-BEGIN -->' "$_rf" && SV2_BAD="${SV2_BAD} ${_rf##*/}:author"
done
for _sf in "${REPO}/skills/canonical-sdlc/dispatch.md" "${REPO}/skills/canonical-sdlc/SKILL.md"; do
  /usr/bin/grep -qF '<!-- BRIEF-SCAFFOLD-BEGIN -->' "$_sf" || SV2_BAD="${SV2_BAD} ${_sf##*/}:no-author"
done
expect_eq "111f: Δ9 — role files carry the reader scaffold only; dispatch.md and SKILL.md the author scaffold" \
  "" "$SV2_BAD"

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

# 116a retired (wave-26 T1, AC-1.5): the foreground timeout is stated once, in the dispatch
# terms, by the harness maximum the wall enforces; §W26-5 pins that no role file restates it.
pin_writer_rule "116b" "AC-1c.4 §5 #2 — only the suites the brief names" \
  "Run only the suites the brief's \`Suites:\` names."
pin_writer_rule "116c" "AC-1c.4 §5 #8 — the cd guard covers the whole command" \
  '`cd <tree> || exit 1` guards the WHOLE command'

# #7 is a CORRECTION, so it takes both halves. RE-POINTED (wave-26 T1, AC-1.5): the rc= recipe
# was a second capture recipe beside the dispatch terms' `2>&1 | tee`, the one the wall's own
# remedy prints; the role files now carry neither, and §W26-5 pins the one kept. The positive
# half is the Logging section the recipe sat in, asserted over the same file first.
expect_contains "116d: AC-1c.4 §5 #7 — agents/test-runner.md keeps its Logging section" \
  'Log path: `.bionic/tmp/test-runner-<suite>-<timestamp>.log`' \
  "$(cat "${REPO}/agents/test-runner.md")"
expect_absent "116e: …and no longer INSTRUCTS the shell-specific PIPESTATUS array (the contradiction is gone)" \
  'PIPESTATUS' "$(cat "${REPO}/agents/test-runner.md")"
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
# LOWERED to 110,000 — Chris 2026-09-15 "option 1 - renderer script and cap at
# 110k" (wave-14 T36): the printf format lines (646 B) left the templates for
# payload/scripts/card.sh, which owns them. Same pattern and same named ruling as
# the two moves above — the ceiling itself moves, owned here — and it moves DOWN,
# which is the direction a ratchet with an owner is allowed to go only by his
# word. The 500 B T14 bought for the two Step-2 format lines is returned with the
# lines themselves; the renderer's three pointer lines are paid for out of what is
# left, and the total is measured in the report, not predicted.
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
  no "115: AC-1b.4 — core + steps + dispatch at or under 110,000 B" "missing:$SPLIT_TOTAL_MISSING"
elif [ "$SPLIT_TOTAL" -le 110000 ]; then
  ok "115: AC-1b.4 — core + steps + dispatch at or under 110,000 B ($SPLIT_TOTAL B ≤ 110000 B)"
else
  no "115: AC-1b.4 — core + steps + dispatch at or under 110,000 B" \
     "$SPLIT_TOTAL B exceeds the cap by $((SPLIT_TOTAL - 110000)) B"
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

# RE-POINTED (wave-21 T7b, Δ9): the six role files carry the reader view of the scaffold
# (agents-src/blocks/brief-scaffold-reader.md), not this fenced block; 111d/111f pin that
# view. The author block's surface here is dispatch.md (SKILL.md's copy is 131's).
AC2_SURFACES="${REPO}/skills/canonical-sdlc/dispatch.md"

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
  ok "124a: AC-2.1 — the brief scaffold's fenced 'Expected artifact:' line appears exactly once in dispatch.md"
else
  no "124a: AC-2.1 — the brief scaffold's fenced 'Expected artifact:' line appears exactly once in dispatch.md" \
     "missing:${AC2_MISSING:-none} doubled:${AC2_DOUBLED:-none}"
fi

# Anti-vacuity: the count must actually discriminate a surface that lost the block.
AC2_MUT_DIR="$TMP/ac2-scaffold"; mkdir -p "$AC2_MUT_DIR"
AC2_MUT="$AC2_MUT_DIR/no-scaffold.md"
grep -Fv -- "$AC2_SCAFFOLD_LINE" "${REPO}/skills/canonical-sdlc/dispatch.md" > "$AC2_MUT" 2>/dev/null
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

# T15/128a/128b RETIRED (epic-23 wave-18 T8, REQ-6/D10): this pin banned a literal `.test.sh`
# token on the scaffold's `Suites:` line because the dispatch wall's suite-lift once read every
# whitespace token on that line as a budget entry. That cause was removed by wave-17 T23
# (`hooks/dispatch-preflight.sh:1751`: `#` stops the scan), so the scaffold's line can and now
# does name the `*.test.sh` shape directly; see `cross-gate-agreement.test.sh` SV_SUITES_LINE.

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

# --- AC-8.3, RETIRED by AC-11.2 (wave-19 D12): no governing-design line on the Step-3 card ---
#
# AC-8.3 moved the governing-design line into a conditional slot under Artifacts; the
# renderer never printed that slot, so it promised a line the approval never saw. D12
# drops it, and 107e now pins the whole Artifacts label set to card.sh step3's own. What
# stays pinned here is that neither the slot nor the older unconditional sentence returns
# — a card printing a governing-design line is a card the renderer does not produce.
GOV_HITS="$(grep -c 'governing design' "$STEP3_MD" 2>/dev/null | tr -cd '0-9')"
[ -n "$GOV_HITS" ] || GOV_HITS=0
expect_eq "132: AC-11.2 — steps/3.md carries no governing-design line, slot or sentence (card.sh step3 prints none)" \
  "0" "$GOV_HITS"

# Anti-vacuity: the count must see the slot's own spelling when it is put back.
GOV_MUT="$TMP/step3-gov-slot-back.md"
{ cat "$STEP3_MD"; printf '    governing design  <the spec'"'"'s `design:` pointer target>\n'; } > "$GOV_MUT" 2>/dev/null
expect_eq "132d: a steps/3.md with the governing-design slot put back reads 1, not 0 (the count discriminates)" \
  "1" "$(grep -c 'governing design' "$GOV_MUT" 2>/dev/null | tr -cd '0-9')"

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

# --- AC-9.1a: each of the three rendered step files names the RENDERER that owns its format ---
#
# RE-SPELLED AT wave-14 T36 (Chris 2026-09-15: "D4: I want the wrapped version", then
# "option 1 - renderer script and cap at 110k"). The formats no longer live beside the
# cards for a model to apply by hand. `payload/scripts/card.sh` owns them, and it FOLDS the
# free-text cell inside its own column — the thing a printf format cannot do, which is why
# a long requirement used to push its trailing columns off the row (126 and 165 columns,
# measured, before T31 re-cut the widths; re-cutting the widths never fixed it, it only
# moved the sentence that overflows). So what each card must carry is no longer the word
# `printf`, it is the NAME OF THE RENDERER, and the inverse is pinned immediately below:
# a format line left behind beside a card is worse than none at all, because it is a second
# owner of a number only one file owns now.
for _pair in "140a:$STEP1_MD:steps/1.md" "140b:$STEP2_MD:steps/2.md" "140c:$STEP3_MD:steps/3.md"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _file="${_rest%:*}"; _which="${_rest##*:}"
  _cnt="$(grep -c 'card\.sh' "$_file" 2>/dev/null | tr -cd '0-9')"
  [ -n "$_cnt" ] || _cnt=0
  if [ "$_cnt" -ge 1 ] 2>/dev/null; then
    ok "${_n}: AC-9.1 — ${_which} names the renderer that owns its card row format (card.sh)"
  else
    no "${_n}: AC-9.1 — ${_which} names the renderer that owns its card row format (card.sh)" "count=$_cnt file=$_file"
  fi
done

# --- AC-9.1b / AC-9.2: the shared rule, verbatim, in all three -----------------------
# The sentence survived the rewrite by design: "never padded by hand" was always the rule,
# and what changed is only WHO does the padding. The tail below is identical in all three
# pointer lines, which is what makes it one rule rather than three.
#
# RE-SPELLED AGAIN AT wave-15 T11 (REQ-10, AC-10.5). The pointer line stopped being a row
# recipe and became a WHOLE-CARD invocation: `card.sh step1 <requirements.md>` reads the
# artifact and prints the card entire, so there is no TSV for a caller to assemble and no
# cell left for a caller to pad. "never padded by hand" retired with the hand-fed row it
# described; the rule that replaces it is the one the new design turns on — the renderer
# needs NOTHING but the artifact, which is what makes the card a rendering of the file
# rather than a retelling of it. Same three files, same one shared tail, same mutation arm
# below; only the sentence moved.
CARD_RULE_LINE=' renders it whole; no stdin.'
for _pair in "141a:$STEP1_MD:steps/1.md" "141b:$STEP2_MD:steps/2.md" "141c:$STEP3_MD:steps/3.md"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _file="${_rest%:*}"; _which="${_rest##*:}"
  expect_contains "${_n}: AC-9.1/AC-9.2 — ${_which} carries the shared pointer rule verbatim" \
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

# --- AC-9.1c (T36): THE INVERSE — no format line survives beside a card ------------------
#
# WHY AN ABSENCE IS PINNED AT ALL. The positive rows above are satisfied by a file that
# names card.sh AND still carries the old `%-44s` line underneath it. That file has two
# owners for one number, and the stale one is the one a reader believes, because it is the
# one that states a width. The three cards carried five such lines and 645 B of them at
# 89f6944; this row is what keeps them gone.
for _pair in "142a:$STEP1_MD:steps/1.md" "142b:$STEP2_MD:steps/2.md" "142c:$STEP3_MD:steps/3.md"; do
  _n="${_pair%%:*}"; _rest="${_pair#*:}"; _file="${_rest%:*}"; _which="${_rest##*:}"
  _cnt="$(grep -c 'printf' "$_file" 2>/dev/null | tr -cd '0-9')"
  [ -n "$_cnt" ] || _cnt=0
  if [ "$_cnt" = "0" ]; then
    ok "${_n}: AC-9.1 — ${_which} carries no printf format line beside its card (the renderer owns the widths)"
  else
    no "${_n}: AC-9.1 — ${_which} carries no printf format line beside its card" \
       "found $_cnt: $(grep -n 'printf' "$_file" 2>/dev/null | head -3 | tr '\n' ' ')"
  fi
done

# 142d: Anti-vacuity for the inverse. The mutation is an APPEND, not a strip, so it carries
# no `anchor` — an anchor exists to catch a pattern-based rewrite that silently matched
# nothing, and an append cannot no-op (§Roots in tests/cross-gate-agreement.test.sh makes
# the same call for the same reason). A copy of steps/2.md with T31's Ownership format line
# put back must make the absence check above fire.
REPLANTED_FMT="$TMP/step2-format-replanted.md"
cp "$STEP2_MD" "$REPLANTED_FMT"
printf 'Ownership row: `    %%-12s owner %%-14s surfaces %%-22s test %%s` (concept, owner, surfaces, test) (printf).\n' \
  >> "$REPLANTED_FMT"
expect_eq "142d: AC-9.1 — a copy of steps/2.md with a format line replanted is caught by the absence check (pin is not vacuous)" \
  "1" "$(grep -c 'printf' "$REPLANTED_FMT" 2>/dev/null | tr -cd '0-9')"

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

# --- AC-9.1 (T36): the two Step-2 row shapes T14 annotated are annotated NO LONGER --------
# T14 raised the aggregate cap by 500 B to buy the Ownership and Eval-design format lines a
# place beside the card (Chris 2026-09-14 "Option 2"); T36 spends that room the other way,
# on the renderer, and Chris moved the cap back to 110,000 with it. The two verbatim strings
# below are T31's own spelling of those lines, kept here as the thing that must now be
# ABSENT — the strongest form of "it was removed", since a re-added line is caught by its
# exact text rather than by a pattern that might drift.
OWNERSHIP_ROW_LINE='Ownership row: `    %-12s owner %-14s surfaces %-22s test %s` (concept, owner, surfaces, test) (printf).'
expect_absent "146: AC-9.1 — steps/2.md no longer states the Ownership row's printf format (card.sh owns it)" \
  "$OWNERSHIP_ROW_LINE" "$(cat "$STEP2_MD" 2>/dev/null)"

EVAL_DESIGN_ROW_LINE='Eval-design row: `    %-8s %-36s %6s %5s %9s %5s %6s` (requirement, approach, static, unit, hermetic, live, human) (printf).'
expect_absent "147: AC-9.1 — steps/2.md no longer states the Eval-design row's printf format (card.sh owns it)" \
  "$EVAL_DESIGN_ROW_LINE" "$(cat "$STEP2_MD" 2>/dev/null)"

# --- AC-9.1/AC-9.4 (T31, re-pointed at T36): every card's own header and sample rows are
# exactly what the RENDERER prints for the card's own sample values. -----------------------
#
# WHAT CHANGED AND WHAT DID NOT. T31 built these arms to stop a card's header and its stated
# printf format drifting apart (the Decisions header said serves@57/ADR@75 while the format
# put them at @77/@92). The drift they exist to catch is unchanged; the right-hand side is.
# It used to be the format re-derived off the same file — which could only ever prove the
# file agreed with itself — and it is now the OUTPUT OF payload/scripts/card.sh, the file
# that renders these rows for real. So the card in the skill is held to the renderer a
# session is told to run, and a width changed in card.sh and not in the card (or the other
# way round) turns these rows red. tests/card.test.sh holds card.sh to the printf formats
# the cards carried at 89f6944, so the widths themselves cannot drift silently either: two
# suites, one number, neither of them the file's own copy of it.
#
# HERMETIC: runs a committed script in this checkout against literal values; no network,
# no fixtures, nothing written.
CARD_SH="${REPO}/payload/scripts/card.sh"
card_rows() {  # <kind> — TSV rows on stdin -> the rendered header and rows
  bash "$CARD_SH" "$1" 2>/dev/null
}
card_cols() {  # <line> -> its width in terminal columns, through width.sh
  ( . "${REPO}/payload/scripts/lib/width.sh" 2>/dev/null && bionic_cols "${1:-}" ) || printf '0'
}
expect_true "147a: the card renderer the three cards now point at exists" test -f "$CARD_SH"

# 148: Step-1 requirement row — ONE folding stream (title, the seam
# " · provenance ", then the provenance text; T23 rule 5), no separate column
# header, wrapping onto a second physical line with these sample values.
REQ1_LINE_A="$(grep -m1 '^    REQ-<id>' "$STEP1_MD" 2>/dev/null)"
REQ1_LINE_B="$(grep -m1 '| report>' "$STEP1_MD" 2>/dev/null)"
REQ1_STREAM='<the requirement in one line> · provenance <user quote | spec section | ticket | report>'
REQ1_RENDERED="$(printf '%s\t%s\t%s\n' \
  'REQ-<id>' "$REQ1_STREAM" '<n>' \
  | card_rows requirement)"
expect_eq "148: AC-9.1/AC-9.4 — steps/1.md's Requirements header and row are exactly what card.sh renders" \
  "$(printf '%s\n' '  Requirements' "$REQ1_LINE_A" "$REQ1_LINE_B")" "$REQ1_RENDERED"
if [ "$(card_cols "$REQ1_LINE_A")" -le 100 ] && [ "$(card_cols "$REQ1_LINE_B")" -le 100 ]; then
  ok "148c: AC-9.1 — steps/1.md's requirement row fits within 100 columns with the sample values ($(card_cols "$REQ1_LINE_A") / $(card_cols "$REQ1_LINE_B"))"
else
  no "148c: AC-9.1 — steps/1.md's requirement row fits within 100 columns with the sample values" \
     "line A=$(card_cols "$REQ1_LINE_A") line B=$(card_cols "$REQ1_LINE_B")"
fi

# 149: Step-2 Decision row and its serves/ADR column header, rendered together.
DEC_HEADER_LINE="$(grep -m1 '^  Decisions' "$STEP2_MD" 2>/dev/null)"
DEC_ROW_LINE="$(grep -m1 '^    D<n>' "$STEP2_MD" 2>/dev/null)"
DEC_RENDERED="$(printf '%s\t%s\t%s\t%s\n' 'D<n>' '<the decision in one line>' '<REQ ids>' '<file | none>' \
  | card_rows decision)"
expect_eq "149: AC-9.1/AC-9.4 — steps/2.md's Decisions header and row are exactly what card.sh renders" \
  "$(printf '%s\n' "$DEC_HEADER_LINE" "$DEC_ROW_LINE")" "$DEC_RENDERED"
if [ "$(card_cols "$DEC_ROW_LINE")" -le 100 ]; then
  ok "149b: AC-9.1 — steps/2.md's decision row fits within 100 columns with the sample values ($(card_cols "$DEC_ROW_LINE"))"
else
  no "149b: AC-9.1 — steps/2.md's decision row fits within 100 columns with the sample values" "width=$(card_cols "$DEC_ROW_LINE")"
fi

# 150 and 150b (the Step-2 Ownership row against card.sh) were deleted with the row (wave-26
# T19): Ownership is the `show ownership` sub-view, and tests/card.test.sh holds its format.

# 151: Step-2 Eval-design header, both REQ rows and the total row — five RIGHT-aligned
# count columns, which is the one kind whose fields are not all left-padded.
EVAL_HEADER_LINE="$(grep -m1 '^  Eval design' "$STEP2_MD" 2>/dev/null)"
EVAL_REQ_LINES=()
while IFS= read -r _line; do EVAL_REQ_LINES+=("$_line"); done < <(grep '^    REQ-<id>' "$STEP2_MD" 2>/dev/null)
EVAL_TOTAL_LINE="$(grep -m1 '^    total' "$STEP2_MD" 2>/dev/null)"
EVAL_RENDERED="$( { printf '%s\t%s\t2\t1\t3\t0\t1\n' 'REQ-<id>' '<how it is proven, one line>'
                    printf '%s\t%s\t1\t0\t2\t1\t0\n' 'REQ-<id>' '<how it is proven, one line>'
                    printf 'total\t\t3\t1\t5\t1\t1\n'; } | card_rows eval-design)"
expect_eq "151: AC-9.1 — steps/2.md's Eval design header and three rows are exactly what card.sh renders" \
  "$(printf '%s\n' "$EVAL_HEADER_LINE" "${EVAL_REQ_LINES[0]:-}" "${EVAL_REQ_LINES[1]:-}" "$EVAL_TOTAL_LINE")" \
  "$EVAL_RENDERED"
if [ "$(card_cols "${EVAL_REQ_LINES[0]:-}")" -le 100 ]; then
  ok "151d: AC-9.1 — steps/2.md's eval-design row fits within 100 columns with the sample values ($(card_cols "${EVAL_REQ_LINES[0]:-}"))"
else
  no "151d: AC-9.1 — steps/2.md's eval-design row fits within 100 columns with the sample values" \
     "width=$(card_cols "${EVAL_REQ_LINES[0]:-}")"
fi

# 152: Step-3 Task header and both sample task rows. The `depends` cell of the first row
# carries an em dash — three bytes, one column — which is the cell that proves the renderer
# pads in COLUMNS: a byte-padded row puts `agent` two columns left of its header here.
TASK_HEADER_LINE="$(grep -m1 '^  Tasks' "$STEP3_MD" 2>/dev/null)"
TASK_ROW_LINES=()
while IFS= read -r _line; do TASK_ROW_LINES+=("$_line"); done < <(grep '^    <n>' "$STEP3_MD" 2>/dev/null)
TASK_RENDERED="$( { printf '%s\t%s\tbuild\t—\tsenior-implementor\n' '<n>' '<the task> · serves <REQ-n>'
                    printf '%s\t%s\ttest\t<n>\timplementor\n' '<n>' '<the task> · serves <REQ-n>'; } | card_rows task)"
expect_eq "152: AC-9.1/AC-9.4 — steps/3.md's Tasks header and both rows are exactly what card.sh renders" \
  "$(printf '%s\n' "$TASK_HEADER_LINE" "${TASK_ROW_LINES[0]:-}" "${TASK_ROW_LINES[1]:-}")" "$TASK_RENDERED"
if [ "$(card_cols "${TASK_ROW_LINES[0]:-}")" -le 100 ] && [ "$(card_cols "${TASK_ROW_LINES[1]:-}")" -le 100 ]; then
  ok "152c: AC-9.1 — steps/3.md's task row fits within 100 columns with the sample values ($(card_cols "${TASK_ROW_LINES[0]:-}") / $(card_cols "${TASK_ROW_LINES[1]:-}"))"
else
  no "152c: AC-9.1 — steps/3.md's task row fits within 100 columns with the sample values" \
     "row1=$(card_cols "${TASK_ROW_LINES[0]:-}") row2=$(card_cols "${TASK_ROW_LINES[1]:-}")"
fi

# 153: THE PAIRED DISCRIMINATOR for 148-152. A card row nudged by one column must make the
# equality above fail — without this, a renderer that printed nothing at all, or a
# comparison that compared two empty strings, would pass every row in this block.
anchor -E "$STEP2_MD" '^    D<n> ' 1
DOCTORED_CARD_ROW="$TMP/step2-decision-row-nudged.md"
sed -e 's|^    D<n> |    D<n>  |' "$STEP2_MD" > "$DOCTORED_CARD_ROW"
expect_eq "153: AC-9.4 — a decision row nudged one column right no longer matches what card.sh renders (pin is not vacuous)" \
  "no" \
  "$([ "$(grep -m1 '^    D<n>' "$DOCTORED_CARD_ROW")" = "$DEC_ROW_LINE" ] && echo yes || echo no)"

# AC-9.3 (render clean, byte caps hold) is discharged by Section 11's `--check` arms and
# Section 18's byte-cap arms against these same rendered finals — both already read
# steps/1.md, steps/2.md and steps/3.md unconditionally, so no separate pin is needed here;
# a cap regression from this task's own additions shows up there, not in this section.

section "Section 28: T3 — the Patrol's task-list duty is a refresh, not a reorder (REQ-3, AC-3.1)"
#
# WHAT THIS SECTION OWNS. wave-15-fixit-182 D5: the tick's task-list duty used to be
# prescribed as a mechanical REORDER — fresh TaskCreate copies of every later-step entry,
# TaskUpdate status=deleted on the stale originals, so the panel reads in chronological
# display order — at a cost research row 3 measured as five reorders × twelve tool calls in
# wave-14 alone. No hook ever enforced the reorder (`grep -rn chronological payload/` finds
# only unrelated comments — research row 3(d)); it was prose-only, in this one block. The
# duty line now reads "TaskList, then statuses reconciled with verified reality" — the
# `TaskList` call and the reconciliation the gate at `lib/stop.sh` actually checks, nothing
# more. This section pins that the reorder mechanics are gone from the rendered surface and
# that the removal does not grow it.
#
# HERMETIC. Reads the committed rendered final by path.

# 154: AC-3.1 — the mechanical reorder is gone: no rendered surface still tells the model to
# invent fresh TaskCreate copies to fake chronological order.
DISPATCH_REORDER_HITS="$(grep -c 'chronological' "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
DISPATCH_REORDER_HITS="${DISPATCH_REORDER_HITS:-0}"
expect_eq "154: AC-3.1 — dispatch.md carries no 'chronological' reorder text (fails-when: the reorder prose survives)" \
  "0" "$DISPATCH_REORDER_HITS"

# 155: the second half of the same fails-when clause — the specific mechanism phrase, not
# just the word "chronological", in case a future edit renames the ordering without removing
# the TaskCreate-copy machinery it drove.
DISPATCH_TASKCREATE_HITS="$(grep -Fc 'TaskCreate fresh copies' "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
DISPATCH_TASKCREATE_HITS="${DISPATCH_TASKCREATE_HITS:-0}"
expect_eq "155: AC-3.1 — dispatch.md carries no 'TaskCreate fresh copies' text (fails-when: the reorder mechanism survives under a new name)" \
  "0" "$DISPATCH_TASKCREATE_HITS"

# 156: bytes go down, never up. 34,993 B is dispatch.md's own measured size at wave-15's
# base commit (59456ce), before this task's cut — the fails-when clause is "its byte count
# rises above 34,993", so strictly-under is the passing direction and equal-to is a miss
# (a render that dropped the prose but re-added equal bytes elsewhere would not be a cut).
DISPATCH_BYTES_156="$(wc -c < "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
if [ -n "$DISPATCH_BYTES_156" ] && [ "$DISPATCH_BYTES_156" -lt 34993 ] 2>/dev/null; then
  ok "156: AC-3.1 — dispatch.md is smaller than its 34,993 B pre-cut baseline ($DISPATCH_BYTES_156 B < 34993 B)"
else
  no "156: AC-3.1 — dispatch.md is smaller than its 34,993 B pre-cut baseline" \
     "${DISPATCH_BYTES_156:-unreadable} B"
fi

# Anti-vacuity: the two grep-based assertions above must actually discriminate. A copy of
# dispatch.md with the reorder text reinstated must read back over 0.
AC3_MUT_DIR="$TMP/ac3-reorder"; mkdir -p "$AC3_MUT_DIR"
AC3_MUT="$AC3_MUT_DIR/dispatch-with-reorder.md"
printf 'chronological display order, TaskCreate fresh copies of every entry\n' >> "$AC3_MUT" 2>/dev/null
cat "$DISPATCH_MD" >> "$AC3_MUT" 2>/dev/null
AC3_MUT_HITS="$(grep -c 'chronological' "$AC3_MUT" 2>/dev/null | tr -cd '0-9')"
AC3_MUT_HITS="${AC3_MUT_HITS:-0}"
if [ "$AC3_MUT_HITS" -gt 0 ] 2>/dev/null; then
  ok "157: a dispatch.md with the reorder text reinstated reads back over 0 (154 is not vacuous, $AC3_MUT_HITS hit(s))"
else
  no "157: a dispatch.md with the reorder text reinstated reads back over 0 (154 is not vacuous)" \
     "mutated copy still read 0"
fi

section "Section 29: T3 — rendered docs for wave-16-fixit-183 (REQ-1/REQ-4/REQ-8/REQ-10, AC-1.8/AC-4.1/AC-4.2/AC-8.3/AC-10.5)"
#
# WHAT THIS SECTION OWNS. Five doc-side acceptance criteria of bionic 1.8.3's declared-runs
# repair, all rendered from agents-src/ by agents-src/render.sh: (1) the `Re-executes:` label
# reaches the auditor role file, the dispatch reference and the Step-5 step file (AC-1.8's
# docs half — the hook-side lift and the roster field are T1's, and the cross-gate
# scaffold-verbatim pin that ties the two together lives in tests/cross-gate-agreement.test.sh,
# not here); (2) the wave-scale `## Tasks` table, undocumented anywhere before this task
# (research R2 finding 13), is now named in steps/3.md with its eleven columns, its `deps`
# and status vocabulary, and the `working-branch:` key (AC-4.1); (3) the aggregate byte cap
# of Section 18 still holds after this task's additions (AC-4.2 — no new pin, that section's
# own arms cover it); (4) SKILL.md's Step-8 wipe sentence names owner liveness rather than
# file name (AC-8.3); (5) the dead `hooks/patrol-duties-gate.sh` name is gone from every
# rendered surface and the patrol prompt reads ListAgents before it ticks (AC-10.5).
#
# HERMETIC. Reads the committed rendered finals by path; doctored copies live under this
# file's own mktemp dir.

AUDITOR_MD="${REPO}/agents/auditor.md"

# --- AC-1.8 (docs half): Re-executes reaches the auditor role file, dispatch.md, steps/5.md ---

RE_EXEC_AUDITOR="$(grep -c 'Re-executes' "$AUDITOR_MD" 2>/dev/null | tr -cd '0-9')"
RE_EXEC_AUDITOR="${RE_EXEC_AUDITOR:-0}"
if [ "$RE_EXEC_AUDITOR" -ge 1 ] 2>/dev/null; then
  ok "158: AC-1.8 — agents/auditor.md carries 'Re-executes' ($RE_EXEC_AUDITOR hit(s))"
else
  no "158: AC-1.8 — agents/auditor.md carries 'Re-executes'" "file: $AUDITOR_MD"
fi

RE_EXEC_DISPATCH="$(grep -c 'Re-executes' "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
RE_EXEC_DISPATCH="${RE_EXEC_DISPATCH:-0}"
if [ "$RE_EXEC_DISPATCH" -ge 1 ] 2>/dev/null; then
  ok "159: AC-1.8 — dispatch.md carries 'Re-executes' ($RE_EXEC_DISPATCH hit(s))"
else
  no "159: AC-1.8 — dispatch.md carries 'Re-executes'" "file: $DISPATCH_MD"
fi

RE_EXEC_STEP5="$(grep -c 'Re-executes' "$STEP5_MD" 2>/dev/null | tr -cd '0-9')"
RE_EXEC_STEP5="${RE_EXEC_STEP5:-0}"
if [ "$RE_EXEC_STEP5" -ge 1 ] 2>/dev/null; then
  ok "160: AC-1.8 — steps/5.md carries 'Re-executes' ($RE_EXEC_STEP5 hit(s))"
else
  no "160: AC-1.8 — steps/5.md carries 'Re-executes'" "file: $STEP5_MD"
fi

# Anti-vacuity: a copy of the auditor role file with the line stripped must read 0.
AC158_MUT="$TMP/auditor-no-reexec.md"
grep -v 'Re-executes' "$AUDITOR_MD" > "$AC158_MUT" 2>/dev/null
expect_eq "161: a stripped copy of agents/auditor.md reads 0 'Re-executes' hits (158 is not vacuous)" \
  "0" "$(grep -c 'Re-executes' "$AC158_MUT" 2>/dev/null | tr -cd '0-9')"

# --- AC-4.1: the wave-scale Tasks table, its columns, deps, status vocabulary, no 'done' ---
#
# A-orch-9 (2026-09-19): the full documentation lives in operational-rules.md, a PLAIN file
# AC-1b.4's own aggregate cap excludes by name (Section 18's own comment) — steps/3.md, which
# IS inside that cap, carries only a one-sentence pointer to it. So the detail pins below read
# operational-rules.md; steps/3.md is checked only for the pointer.

WAVE_SECTION="$(sed -n '/### The wave-scale `## Tasks` table/,/^## /p' "$OPRULES" 2>/dev/null)"
# wave-16 T21 (walk-2c882be.md §11): the header used to print `worktree | status`, transposed
# relative to units.sh:127-129's contract order. Harmless in practice — `_units_read` matches
# header cells by NAME, not position — but the two documents disagreed, and this pin read the
# corrected order.
#
# RE-PINNED AT TWELVE (epic-23 wave-17 T35, critic C10). This wave added `base` (REQ-2,
# ADR-032) and repaired the refusal that names the columns (R7, lib/walls.sh) without
# touching the document that teaches them, so the eleven-column order above outlived the
# table it described. The order here is the one the live plans and the wall's fix line both
# write; Section 31 pins the same header AGAINST that wall line, so a future column can only
# land in one of the two places before an arm goes red.
WAVE_COLS='id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status'

if [ -n "$WAVE_SECTION" ]; then
  case "$WAVE_SECTION" in
    *"$WAVE_COLS"*)
      ok "162: AC-4.1 — operational-rules.md names all twelve wave-scale columns verbatim" ;;
    *)
      no "162: AC-4.1 — operational-rules.md names all twelve wave-scale columns verbatim" "file: $OPRULES" ;;
  esac
else
  no "162: AC-4.1 — operational-rules.md names all twelve wave-scale columns verbatim" \
     "no 'wave-scale ## Tasks table' section found in $OPRULES"
fi

case "$WAVE_SECTION" in
  *'pending | active | landed | dropped'*)
    ok "163: AC-4.1 — operational-rules.md's wave-scale section names the status vocabulary 'pending | active | landed | dropped'" ;;
  *)
    no "163: AC-4.1 — operational-rules.md's wave-scale section names the status vocabulary 'pending | active | landed | dropped'" \
       "section: ${WAVE_SECTION:-<absent>}" ;;
esac

# NOT a bare grep for the word "done": the correct prose (163's positive pin) explains
# `done`'s absence using the word itself ("a row that has landed is `landed`, not `done`"),
# which would make a naive `grep -c 'done'` self-defeating on the very sentence that
# documents the fix. The real fails-when shape is `done` surviving INSIDE the pipe-delimited
# status vocabulary — so this checks for that shape specifically.
case "$WAVE_SECTION" in
  *'pending | active | done'*|*'active | done | dropped'*)
    no "164: AC-4.1 — 'done' does not survive inside the wave-scale status vocabulary" \
       "section: ${WAVE_SECTION:-<absent>}" ;;
  *)
    ok "164: AC-4.1 — 'done' does not survive inside the wave-scale status vocabulary" ;;
esac

if has_pin "$OPRULES" 'working-branch'; then
  ok "165: AC-4.1 — operational-rules.md names 'working-branch:' as the landing gate's key"
else
  no "165: AC-4.1 — operational-rules.md names 'working-branch:' as the landing gate's key" "file: $OPRULES"
fi

# steps/3.md itself: a one-sentence pointer into operational-rules.md, inside the aggregate
# cap, naming the wave-scale table's variance from the task-scale ledger it documents inline.
if has_pin "$STEP3_MD" 'Wave-scale variant' && has_pin "$STEP3_MD" 'operational-rules.md'; then
  ok "165b: AC-4.1 — steps/3.md points to operational-rules.md for the wave-scale table"
else
  no "165b: AC-4.1 — steps/3.md points to operational-rules.md for the wave-scale table" "file: $STEP3_MD"
fi

# Anti-vacuity: a copy of the wave-scale columns string missing one column must not match.
AC162_MUT_COLS='id | step | kind | task | agent | deps | size | serves | worktree | status'
case "$WAVE_SECTION" in
  *"$AC162_MUT_COLS"*)
    no "166: a columns string with 'Files' dropped does not falsely match (162 is not vacuous)" \
       "the shorter, wrong string still matched"
    ;;
  *)
    ok "166: a columns string with 'Files' dropped does not falsely match (162 is not vacuous)"
    ;;
esac

# --- AC-8.3: SKILL.md's Step-8 wipe sentence names owner liveness, not file name ---

SKILL_SPARE_BY_NAME="$(grep -c 'spares by name' "$SKILL_MD" 2>/dev/null | tr -cd '0-9')"
SKILL_SPARE_BY_NAME="${SKILL_SPARE_BY_NAME:-0}"
expect_eq "167: AC-8.3 — SKILL.md no longer says the Step-8 wipe 'spares by name'" \
  "0" "$SKILL_SPARE_BY_NAME"

if has_pin "$SKILL_MD" 'owner liveness'; then
  ok "168: AC-8.3 — SKILL.md's wipe description names owner liveness"
else
  no "168: AC-8.3 — SKILL.md's wipe description names owner liveness" "file: $SKILL_MD"
fi

# Anti-vacuity: a copy with the retired sentence reinstated must read back over 0.
AC167_MUT="$TMP/skill-spare-by-name.md"
{ printf 'the wipe spares by name\n'; cat "$SKILL_MD"; } > "$AC167_MUT" 2>/dev/null
AC167_MUT_HITS="$(grep -c 'spares by name' "$AC167_MUT" 2>/dev/null | tr -cd '0-9')"
AC167_MUT_HITS="${AC167_MUT_HITS:-0}"
if [ "$AC167_MUT_HITS" -gt 0 ] 2>/dev/null; then
  ok "169: a SKILL.md with 'spares by name' reinstated reads back over 0 (167 is not vacuous)"
else
  no "169: a SKILL.md with 'spares by name' reinstated reads back over 0 (167 is not vacuous)" \
     "mutated copy still read 0"
fi

# --- AC-10.5: no dead hook name; ListAgents precedes the tick in the patrol prompt's reads ---

# A-orch-9 (2026-09-19): this tree also carries a hand-composed, unrendered diagram
# (skills/canonical-sdlc/diagrams/hook-chain.svg, SKILL.md.tmpl:197: "hand-composed text, no
# paired drawing file") that drew a box for this retired hook name; entry 13's label, its
# data-hook attribute and its subtitle were re-pointed at stop.sh/lib/stop.sh (Files widened)
# so the eval design's own literal instrument, unscoped, now reads zero across every surface.
AC10_5_HITS="$(grep -rn 'patrol-duties-gate.sh' "${REPO}/skills" "${REPO}/agents" 2>/dev/null || true)"
expect_eq "170: AC-10.5 — no surface under skills/ or agents/ still names hooks/patrol-duties-gate.sh" \
  "" "$AC10_5_HITS"

LISTAGENTS_LINE="$(grep -n 'ListAgents' "$DISPATCH_MD" 2>/dev/null | head -1 | cut -d: -f1)"
TICK_LINE="$(grep -n -- '\*\*Tick the poker\.\*\*' "$DISPATCH_MD" 2>/dev/null | head -1 | cut -d: -f1)"
if [ -n "$LISTAGENTS_LINE" ] && [ -n "$TICK_LINE" ] && [ "$LISTAGENTS_LINE" -lt "$TICK_LINE" ] 2>/dev/null; then
  ok "171: AC-10.5 — dispatch.md's patrol prompt reads ListAgents (line $LISTAGENTS_LINE) before it ticks (line $TICK_LINE)"
else
  no "171: AC-10.5 — dispatch.md's patrol prompt reads ListAgents before it ticks" \
     "ListAgents line=${LISTAGENTS_LINE:-absent} tick line=${TICK_LINE:-absent}"
fi

# Anti-vacuity: a copy of dispatch.md with the dead hook name reinstated must read back over 0.
AC170_MUT="$TMP/dispatch-with-dead-hook.md"
{ printf 'hooks/patrol-duties-gate.sh\n'; cat "$DISPATCH_MD"; } > "$AC170_MUT" 2>/dev/null
AC170_MUT_HITS="$(grep -c 'patrol-duties-gate.sh' "$AC170_MUT" 2>/dev/null | tr -cd '0-9')"
AC170_MUT_HITS="${AC170_MUT_HITS:-0}"
if [ "$AC170_MUT_HITS" -gt 0 ] 2>/dev/null; then
  ok "172: a dispatch.md with the dead hook name reinstated reads back over 0 (170 is not vacuous)"
else
  no "172: a dispatch.md with the dead hook name reinstated reads back over 0 (170 is not vacuous)" \
     "mutated copy still read 0"
fi

# ============================================================
section "Section 30: T9 — the scaffold span rule, cell shapes and the two counters (epic-23 wave-17-fixit-184, REQ-5/REQ-7/REQ-10, AC-5.5/AC-7.1/AC-10.3)"
# ============================================================
#
# WHAT THIS SECTION OWNS. Three doc-side acceptance criteria of bionic 1.8.4's gates-judge-
# the-tree-in-hand repair, all rendered from agents-src/ by agents-src/render.sh except
# operational-rules.md (a PLAIN file, never rendered, edited directly): (1) the stale
# "blank line" rule for a brief label's span (research R2 §B4: the parser has read to the
# next LABELLED line since commit 9bf75d7, but the scaffold and dispatch.md still taught the
# old blank-line rule) is gone from every rendered surface and the "next labelled line" fact
# is on the record (AC-7.1); (2) the four authoring-time cell shapes research R2 §B2 found
# undocumented outside historical version bullets — the per-row evidence line, the one-path
# `evidence:` cell, the bare `CONFIRMED` token, and the `base` column beside `worktree` — are
# now stated at the authoring section beside the wave-scale `## Tasks` table, not buried in a
# `v11`/`D7` bullet (AC-5.5); (3) the two Step-5 counters research R4 §D2.5 designed —
# `pass:`/`total:` gate rows only, `advisory-exceeded:` is recorded and never judged — are
# named in both steps/5.md and operational-rules.md (AC-10.3). The aggregate byte cap of
# Section 18 still holds after this task's edits — no new pin, that section's own arms cover
# it (measured before this task's edits: 109,997 B against the 110,000 B cap, a 3 B margin;
# the fix nets negative — the retired "own paragraph"/"blank line" prose is longer than the
# span-rule and cell-shape sentences that replace it).
#
# HERMETIC. Reads the committed rendered finals and the plain operational-rules.md file by
# path; doctored copies live under this file's own mktemp dir.

# --- AC-7.1: the stale span-rule wording is gone from every rendered surface, and the ---
# --- true rule ("next labelled line") is on the record somewhere a dispatcher reads.  ---

AC7_1_SURFACES="$SKILL_MD $DISPATCH_MD"
for _rf in "${REPO}"/agents/*.md; do
  [ -f "$_rf" ] && AC7_1_SURFACES="$AC7_1_SURFACES $_rf"
done

AC7_1_STALE=""
for _sf in $AC7_1_SURFACES; do
  [ -f "$_sf" ] || { AC7_1_STALE="${AC7_1_STALE} missing:${_sf}"; continue; }
  if has_pin "$_sf" 'own paragraph'; then
    AC7_1_STALE="${AC7_1_STALE} ${_sf##*/}(own paragraph)"
  fi
  if has_pin "$_sf" 'only to the next blank line'; then
    AC7_1_STALE="${AC7_1_STALE} ${_sf##*/}(only to the next blank line)"
  fi
done
if [ -z "$AC7_1_STALE" ]; then
  ok "173: AC-7.1 — no rendered surface (SKILL.md, dispatch.md, agents/*.md) still teaches 'own paragraph' or 'only to the next blank line'"
else
  no "173: AC-7.1 — no rendered surface still teaches the stale span rule" "found:${AC7_1_STALE}"
fi

if has_pin "$DISPATCH_MD" 'next labelled line'; then
  ok "174: AC-7.1 — dispatch.md states the true rule: a label's span ends at the next labelled line"
else
  no "174: AC-7.1 — dispatch.md states the true rule ('next labelled line')" "file: $DISPATCH_MD"
fi

# Anti-vacuity: a copy of dispatch.md with the retired wording reinstated must read back over 0
# on has_pin, proving 173's absence check actually discriminates.
AC173_MUT="$TMP/dispatch-with-stale-span-rule.md"
{ printf 'since the wall reads a label only to the next blank line, on its own paragraph\n'; cat "$DISPATCH_MD"; } \
  > "$AC173_MUT" 2>/dev/null
if has_pin "$AC173_MUT" 'own paragraph' && has_pin "$AC173_MUT" 'only to the next blank line'; then
  ok "175: a dispatch.md with the stale span rule reinstated reads back positive (173 is not vacuous)"
else
  no "175: a dispatch.md with the stale span rule reinstated reads back positive (173 is not vacuous)" \
     "mutated copy still read 0 on has_pin"
fi

# --- AC-5.5: the four cell shapes, at authoring time, beside the wave-scale table ---
# --- section — not inside a historical (v11/D7) version bullet.                   ---

CELL_SHAPES_SECTION="$(sed -n '/### The wave-scale `## Tasks` table/,/^## /p' "$OPRULES" 2>/dev/null)"

case "$CELL_SHAPES_SECTION" in
  *'one `- T<n>:` line per'*)
    ok "176: AC-5.5 — operational-rules.md's authoring section states 'one \`- T<n>:\` line per' (## Tasks row, inside ## SDLC State)" ;;
  *)
    no "176: AC-5.5 — operational-rules.md's authoring section states 'one \`- T<n>:\` line per'" \
       "section: ${CELL_SHAPES_SECTION:-<absent>}" ;;
esac

case "$CELL_SHAPES_SECTION" in
  *'exactly one path under `record/`'*)
    ok "177: AC-5.5 — …and 'exactly one path under \`record/\`' for the matrix evidence: cell" ;;
  *)
    no "177: AC-5.5 — …and 'exactly one path under \`record/\`' for the matrix evidence: cell" \
       "section: ${CELL_SHAPES_SECTION:-<absent>}" ;;
esac

case "$CELL_SHAPES_SECTION" in
  *'bare token `CONFIRMED`'*)
    ok "178: AC-5.5 — …and 'bare token \`CONFIRMED\`' for the auditor cell" ;;
  *)
    no "178: AC-5.5 — …and 'bare token \`CONFIRMED\`' for the auditor cell" \
       "section: ${CELL_SHAPES_SECTION:-<absent>}" ;;
esac

# NOT inside a historical version bullet: the three shapes above must land in the
# authoring-time "Cell shapes" paragraph this task adds beside the wave-scale table, never
# inside a "v11"/"D7 " prefixed historical bullet, which the file's own line 17 already
# frames as "historical record only" — a reader would never find an authoring rule there.
case "$CELL_SHAPES_SECTION" in
  *'**Cell shapes'*)
    ok "179: AC-5.5 — the three shapes ride in a 'Cell shapes' authoring paragraph, not a historical version bullet" ;;
  *)
    no "179: AC-5.5 — the three shapes ride in a 'Cell shapes' authoring paragraph" \
       "no '**Cell shapes' heading found beside the wave-scale table section" ;;
esac

case "$CELL_SHAPES_SECTION" in
  *'`base`** (optional, ADR-032) — rides beside `worktree`'*)
    ok "180: AC-5.5 — the optional \`base\` column beside \`worktree\` is documented in the same section" ;;
  *)
    no "180: AC-5.5 — the optional \`base\` column beside \`worktree\` is documented in the same section" \
       "section: ${CELL_SHAPES_SECTION:-<absent>}" ;;
esac

# Anti-vacuity: a plan section carrying none of the three shape strings reads back negative
# on all three, proving 176-178 discriminate rather than passing on any prose.
AC176_MUT="$TMP/cell-shapes-blank-section.md"
printf '### The wave-scale `## Tasks` table\n\nNothing to see here.\n\n## Design section authoring\n' \
  > "$AC176_MUT" 2>/dev/null
AC176_MUT_SECTION="$(sed -n '/### The wave-scale `## Tasks` table/,/^## /p' "$AC176_MUT" 2>/dev/null)"
case "$AC176_MUT_SECTION" in
  *'one `- T<n>:` line per'*|*'exactly one path under `record/`'*|*'bare token `CONFIRMED`'*)
    no "181: a blank wave-scale section reads back negative on all three shape strings (176-178 are not vacuous)" \
       "mutated section unexpectedly matched" ;;
  *)
    ok "181: a blank wave-scale section reads back negative on all three shape strings (176-178 are not vacuous)" ;;
esac

# --- AC-10.3: the two Step-5 counters, named in BOTH the runner-facing step file and ---
# --- the authoring reference.                                                       ---

if has_pin "$STEP5_MD" 'advisory-exceeded:'; then
  ok "182: AC-10.3 — steps/5.md names 'advisory-exceeded:'"
else
  no "182: AC-10.3 — steps/5.md names 'advisory-exceeded:'" "file: $STEP5_MD"
fi

if has_pin "$OPRULES" 'advisory-exceeded:'; then
  ok "183: AC-10.3 — operational-rules.md names 'advisory-exceeded:' too"
else
  no "183: AC-10.3 — operational-rules.md names 'advisory-exceeded:' too" "file: $OPRULES"
fi

# steps/5.md also carries the one-path sentence for the evidence: cell (AC-5.5's other half:
# the runner-facing step file, not just the authoring reference).
if has_pin "$STEP5_MD" 'record/` path per cell'; then
  ok "184: AC-5.5 — steps/5.md carries the one-path evidence: sentence too"
else
  no "184: AC-5.5 — steps/5.md carries the one-path evidence: sentence too" "file: $STEP5_MD"
fi

# Anti-vacuity: a stripped copy of steps/5.md loses both 182 and 184's hits.
AC182_MUT="$TMP/step5-no-counters.md"
grep -v 'advisory-exceeded:' "$STEP5_MD" > "$AC182_MUT" 2>/dev/null
if has_pin "$AC182_MUT" 'advisory-exceeded:'; then
  no "185: a steps/5.md stripped of 'advisory-exceeded:' reads back negative (182 is not vacuous)" \
     "mutated copy still matched"
else
  ok "185: a steps/5.md stripped of 'advisory-exceeded:' reads back negative (182 is not vacuous)"
fi

# --- AC-4.2 (unchanged, restated): the aggregate byte cap still holds after this task's ---
# --- edits. Section 18's own arms (111-117) already re-measure the committed finals on  ---
# --- every run; this is a comment, not a new pin, matching Section 29's own precedent.  ---
# (operational-rules.md is excluded from that cap by AC-1b.4's own wording — nothing tells
# the model to read it — so Section 31's edits below spend none of the 110,000 B budget.)

# ============================================================
section "Section 31: T35 — the ## Tasks header render carries every column the plan writes (epic-23 wave-17-fixit-184, critic C10)"
# ============================================================
#
# WHAT THIS SECTION OWNS. The wave added a column (REQ-2, `base`) and repaired the refusal
# that names the columns (R7, walls.sh), and the one SHIPPED DOCUMENT that teaches the
# columns was touched by neither: operational-rules.md rendered ten-plus-one in a different
# order, carried `base` in its bullet list and nowhere in its header, and so sent an author
# repairing a refused row to a table the refusal contradicts (critic C10).
#
# THE PIN IS AN AGREEMENT, NOT A TRANSCRIPTION. The expected header is DERIVED from the
# wall's own fix line in lib/walls.sh — the sentence the author is actually reading when
# they go looking for this table — so the two cannot drift apart again without one of these
# arms going red. A literal header copied into this file would only pin the doc to itself.
#
# HERMETIC. Reads the committed walls.sh and the plain operational-rules.md by path.

T35_WALL_COLS="$(/usr/bin/grep -m1 -o 'the columns are id |[^.]*' "${REPO}/payload/scripts/lib/walls.sh" 2>/dev/null \
  | sed 's/^the columns are //')"
T35_WALL_HEADER="| ${T35_WALL_COLS} |"
T35_WALL_N=0
[ -z "$T35_WALL_COLS" ] || T35_WALL_N=$(printf '%s' "$T35_WALL_COLS" | awk -F'|' '{print NF}')

# 186 guards the derivation itself: an arm that compares against an empty string passes on
# everything, so the source sentence has to be found and has to name twelve columns first.
if [ "$T35_WALL_N" = "12" ]; then
  ok "186: the twelve-column list is readable from lib/walls.sh's own fix line (the pins below have a source)"
else
  no "186: the twelve-column list is readable from lib/walls.sh's own fix line" \
     "read ${T35_WALL_N} columns from: ${T35_WALL_COLS:-<absent>}"
fi

T35_SECTION="$(sed -n '/### The wave-scale `## Tasks` table/,/^## /p' "$OPRULES" 2>/dev/null)"
T35_DOC_HEADER="$(printf '%s\n' "$T35_SECTION" | /usr/bin/grep -m1 '^| id |')"

if [ -n "$T35_WALL_COLS" ] && [ "$T35_DOC_HEADER" = "$T35_WALL_HEADER" ]; then
  ok "187: operational-rules.md renders the ## Tasks header in the wall's own column order, byte for byte"
else
  no "187: operational-rules.md renders the ## Tasks header in the wall's own column order" \
     "doc: ${T35_DOC_HEADER:-<absent>} / wall: ${T35_WALL_HEADER}"
fi

case "$T35_DOC_HEADER" in
  *'| base |'*)
    ok "188: …and the rendered header carries \`base\`, the column this wave added (REQ-2, ADR-032)" ;;
  *)
    no "188: …and the rendered header carries \`base\`, the column this wave added" \
       "header: ${T35_DOC_HEADER:-<absent>}" ;;
esac

# The COUNT the same paragraph states, which is the half a reader meets before the fence.
case "$T35_SECTION" in
  *'twelve columns: ten required, plus the optional `worktree` and `base`'*)
    ok "189: …and the sentence above it counts twelve — ten required, plus the two optional" ;;
  *)
    no "189: …and the sentence above it counts twelve — ten required, plus the two optional" \
       "section: ${T35_SECTION:-<absent>}" ;;
esac

# The optional `reads` column (wave-26 T2): each wall's Fix line says so after the twelve, and
# the section above names it, so a table that carries it is not read as the wrong header.
for _t35_src in "payload/scripts/lib/walls.sh" "hooks/canonical-sdlc-governing-skill.sh"; do
  if /usr/bin/grep -F 'base | status. A reads column is optional and may sit anywhere in the header.' \
       "${REPO}/${_t35_src}" >/dev/null 2>&1; then
    ok "189b: ${_t35_src}'s Fix line says the reads column is optional"
  else
    no "189b: ${_t35_src}'s Fix line says the reads column is optional" "absent from ${_t35_src}"
  fi
done
case "$T35_SECTION" in
  *'the optional `reads` (below)'*)
    ok "189c: …and operational-rules.md's sentence names the optional reads column beside the twelve" ;;
  *)
    no "189c: …and operational-rules.md's sentence names the optional reads column beside the twelve" \
       "section: ${T35_SECTION:-<absent>}" ;;
esac

# Anti-vacuity: the pre-1.8.4 header (ten-plus-one, `status` before `worktree`, no `base`)
# must read back UNEQUAL against the same derived expectation, and must fail 188's test —
# proving 187/188 discriminate rather than passing on any pipe-delimited line.
T35_OLD_HEADER="| id | step | kind | task | agent | deps | size | serves | Files | status | worktree |"
if [ "$T35_OLD_HEADER" != "$T35_WALL_HEADER" ]; then
  case "$T35_OLD_HEADER" in
    *'| base |'*) no "190: the pre-1.8.4 eleven-column header reads back negative (187/188 are not vacuous)" \
                     "the old header unexpectedly carried base" ;;
    *)            ok "190: the pre-1.8.4 eleven-column header reads back negative (187/188 are not vacuous)" ;;
  esac
else
  no "190: the pre-1.8.4 eleven-column header reads back negative (187/188 are not vacuous)" \
     "the old header equals the wall's list — the comparison cannot discriminate"
fi

# ── T9 (wave-21-fixit-188, D9; AC-1.4 dispatch half, AC-2.2, AC-4.4, AC-7.1) ──────────────────
# dispatch.md says what is true after this wave. Four facts, one pin each, all read from the
# rendered file through _flatten so a wrapped sentence still matches. Every pin carries its
# paired control: the sentence is present AND its stale predecessor is absent, so neither a
# vacuous "absent" nor a vacuous "present" can pass.
T9_FLAT="$(_flatten "$DISPATCH_MD")"

# 191 — the arming sentence names the line session-start printed, and CronList comes before
# CronCreate in what follows it (the arm is CronList-first for a fresh run and a resume alike).
T9_ARM='run the arm line session-start printed — it begins with CronList, so a fresh run and a resume read one sentence'
T9_REST="${T9_FLAT#*"$T9_ARM"}"
T9_PRE_LIST="${T9_ARM}${T9_REST}"; T9_PRE_LIST="${T9_PRE_LIST%%CronList*}"
if [ "$T9_REST" != "$T9_FLAT" ] && case "$T9_REST" in *CronList*) true ;; *) false ;; esac \
   && case "$T9_PRE_LIST" in *CronCreate*) false ;; *) true ;; esac \
   && case "$T9_FLAT" in *'On a `/clear`+resume session-start prints no arm line'*) true ;; *) false ;; esac; then
  ok "191: AC-1.4 — dispatch.md's arming sentence names the arm line session-start printed, CronList before CronCreate, and says the /clear+resume path prints none"
else
  no "191: AC-1.4 — dispatch.md's arming sentence names the arm line session-start printed, CronList before CronCreate, and says the /clear+resume path prints none" \
     "sentence present: $([ "$T9_REST" != "$T9_FLAT" ] && echo yes || echo no)"
fi

# 192 — the registry resolver and its false pin claim are gone; one sentence names the line.
T9_BAD=""
case "$T9_FLAT" in *installed_plugins.json*) T9_BAD="$T9_BAD installed_plugins.json" ;; esac
case "$T9_FLAT" in *'held byte-identical'*)  T9_BAD="$T9_BAD held-byte-identical" ;; esac
case "$T9_FLAT" in *'`<plugin-root>` is the absolute plugin path the printed arm line carries'*) T9_ROOT=yes ;; *) T9_ROOT=no ;; esac
if [ -z "$T9_BAD" ] && [ "$T9_ROOT" = yes ]; then
  ok "192: AC-2.2 — dispatch.md has no installed_plugins.json expression and no 'held byte-identical' claim, and names the printed line as the root's source"
else
  no "192: AC-2.2 — dispatch.md has no installed_plugins.json expression and no 'held byte-identical' claim, and names the printed line as the root's source" \
     "stale:${T9_BAD:- none}; root sentence present: $T9_ROOT"
fi

# 193 — a CI or PR wait is a backgrounded command carrying a Subprocess claim: line; the
# stale "no bionic machinery relies on it existing" is gone.
T9_CI='A CI or PR wait is such a backgrounded command, and its brief carries a `Subprocess claim:` line'
if has_pin "$DISPATCH_MD" "$T9_CI" && ! has_pin "$DISPATCH_MD" 'no bionic machinery relies on it existing'; then
  ok "193: AC-7.1 — dispatch.md names a CI or PR wait as a backgrounded command with a Subprocess claim: line, and the stale 'no machinery relies on it' sentence is gone"
else
  no "193: AC-7.1 — dispatch.md names a CI or PR wait as a backgrounded command with a Subprocess claim: line, and the stale 'no machinery relies on it' sentence is gone" \
     "ci sentence: $(has_pin "$DISPATCH_MD" "$T9_CI" && echo present || echo absent); stale: $(has_pin "$DISPATCH_MD" 'no bionic machinery relies on it existing' && echo present || echo absent)"
fi

# 194 — SKILL.md's Known-holes paragraph says both ledger facts, the second WITH ITS CONDITION
# (wave-21 T13; audit-3b45d05 finding 3). "An `active` row needs no evidence line." was true only
# when the row's agent cell names a row on the session's roster; with no roster the gate still
# demands the line from an agent-named active row. The unconditional sentence is gone.
T13_ACT='An `active` row whose agent the session'"'"'s roster names needs no evidence line'
T13_NOR='with no roster, an agent-named one still does.'
if has_pin "$SKILL_MD" 'Task-scale ledgers have no write-time check.' \
   && has_pin "$SKILL_MD" "$T13_ACT" && has_pin "$SKILL_MD" "$T13_NOR" \
   && ! has_pin "$SKILL_MD" 'An `active` row needs no evidence line.'; then
  ok "194: AC-4.4 — SKILL.md's Known holes says task-scale ledgers have no write-time check, and an active row needs no evidence line only when the roster names its agent"
else
  no "194: AC-4.4 — SKILL.md's Known holes says task-scale ledgers have no write-time check, and an active row needs no evidence line only when the roster names its agent" \
     "check sentence: $(has_pin "$SKILL_MD" 'Task-scale ledgers have no write-time check.' && echo present || echo absent); roster sentence: $(has_pin "$SKILL_MD" "$T13_ACT" && echo present || echo absent); no-roster clause: $(has_pin "$SKILL_MD" "$T13_NOR" && echo present || echo absent); unconditional sentence: $(has_pin "$SKILL_MD" 'An `active` row needs no evidence line.' && echo present || echo absent)"
fi

# 195 — the ledger text says the agent cell carries the ROSTER NAME (A-T5.5), in all three homes.
# THE THIRD HOME IS THE ONE THAT DEFINES THE COLUMN (wave-21 T14; critic-4e6d4a9 I1).
# operational-rules.md's column list still said "the `subagent_type` this row dispatches to", and
# the 1.8.8 gate refuses an `active` row whose agent cell names no roster row — so a plan authored
# from the reference, or one mid-run at upgrade, was refused at its writers' next commit. The
# definition carries dispatch.md's sentence, the upgrade step for a pre-1.8.8 row, and never the
# old role wording.
T9_AG='carries the ROSTER NAME the dispatch gave the agent'
T9_AG2='carries the agent'"'"'s ROSTER NAME'
T14_MIG='A row dispatched before 1.8.8 with a role in this cell is refused by the 1.8.8 commit gate once a roster exists'
T14_OLD='the `subagent_type` this row dispatches to'
if has_pin "$DISPATCH_MD" "$T9_AG" && has_pin "$SKILL_MD" "$T9_AG2" && has_pin "$OPRULES" "$T9_AG" \
   && has_pin "$OPRULES" "$T14_MIG" && ! has_pin "$OPRULES" "$T14_OLD"; then
  ok "195: A-T5.5 — dispatch.md, SKILL.md and operational-rules.md say a ledger row's agent cell carries the roster name, never the role"
else
  no "195: A-T5.5 — dispatch.md, SKILL.md and operational-rules.md say a ledger row's agent cell carries the roster name, never the role" \
     "dispatch.md: $(has_pin "$DISPATCH_MD" "$T9_AG" && echo present || echo absent); SKILL.md: $(has_pin "$SKILL_MD" "$T9_AG2" && echo present || echo absent); operational-rules.md: $(has_pin "$OPRULES" "$T9_AG" && echo present || echo absent); migration: $(has_pin "$OPRULES" "$T14_MIG" && echo present || echo absent); role wording: $(has_pin "$OPRULES" "$T14_OLD" && echo present || echo absent)"
fi

# 195b — the `deps` definition admits the `ext:<slug>` token T4 added beside the task ids; "bare
# task ids only" is no longer the whole grammar the validator accepts.
T14_EXT='or an external prerequisite `ext:<slug>`'
T14_BARE='bare task ids only'
if has_pin "$OPRULES" "$T14_EXT" && ! has_pin "$OPRULES" "$T14_BARE"; then
  ok "195b: wave-21 T4 — operational-rules.md's deps definition admits ext:<slug> beside the task ids"
else
  no "195b: wave-21 T4 — operational-rules.md's deps definition admits ext:<slug> beside the task ids" \
     "ext sentence: $(has_pin "$OPRULES" "$T14_EXT" && echo present || echo absent); bare-ids sentence: $(has_pin "$OPRULES" "$T14_BARE" && echo present || echo absent)"
fi

# ---------------------------------------------------------------------------
section "Section UB: wave-23 T1 — the fallback is announced and never acted on, in the contract text (REQ-1, AC-1.4; D1)"
#
# WHAT THIS OWNS. AC-1.4's fails-when: "exactly as before" survives in the fill gate's facts
# docblock (payload/scripts/lib/stop.sh, `stop_turn_facts`), in `session_run`'s consumer
# contract (payload/scripts/lib/run.sh), or in any of the five suites that pinned "unbound
# falls back exactly as before", or a doctored copy stays green. The contract an unbound
# session lives under changed (Chris 2026-10-02, spec D1): the newest-plan fallback is
# announced and never acted on. A comment still promising the old behaviour is how the old
# behaviour comes back, so each carrier must say the new sentence and none the old one.
#
# SPANS, NOT WHOLE FILES, for the two libraries: stop.sh says "exactly as before" once more,
# about the fill's own numbers (`stop_turn_facts`'s ledger read), which is not this contract.
# Each span is extracted by its own opening and closing lines, so a span that moved is an
# empty span and fails here rather than passing on nothing.
UB_PIN_NEW="announced and never acted on"
UB_PIN_OLD="exactly as before"
UB_STOP_LIB="${REPO}/payload/scripts/lib/stop.sh"
UB_RUN_LIB="${REPO}/payload/scripts/lib/run.sh"

ub_span() {  # <file> <first-line ERE> <stop-line ERE> -> the span on stdout (start inclusive)
  awk -v a="$2" -v b="$3" '$0 ~ a { on = 1 } on && $0 ~ b { exit } on { print }' "$1"
}
ub_carrier_ok() {  # <file> -> 0 when it carries the new sentence and not the old one
  [ -s "$1" ] || return 1
  grep -qF "$UB_PIN_NEW" "$1" || return 1
  if grep -qiF "$UB_PIN_OLD" "$1"; then return 1; fi
  return 0
}
ub_check() {  # <label> <file>
  if ub_carrier_ok "$2"; then ok "$1"; else
    no "$1" "new=$(grep -cF "$UB_PIN_NEW" "$2" 2>/dev/null) old=$(grep -ciF "$UB_PIN_OLD" "$2" 2>/dev/null) lines=$(wc -l < "$2" 2>/dev/null)"
  fi
}

ub_span "$UB_STOP_LIB" '^# ─── stop_turn_facts and stop_fill_ledger' '^SCAN_WINDOW_LINES=' > "$TMP/ub-stop-facts.txt"
ub_span "$UB_RUN_LIB" '^# session_run <root> <sid> -> ONE line' '^session_run\(\) \{' > "$TMP/ub-run-contract.txt"
expect_true "UB0: the two spans were found (non-empty)" \
  test -s "$TMP/ub-stop-facts.txt" -a -s "$TMP/ub-run-contract.txt"
ub_check "UB1: stop.sh's stop_turn_facts docblock says the fallback is announced and never acted on" "$TMP/ub-stop-facts.txt"
ub_check "UB2: run.sh's session_run consumer contract says it too" "$TMP/ub-run-contract.txt"
for _ub_suite in context-spend patrol-duties-gate patrol-revive dispatch-preflight cross-gate-agreement; do
  ub_check "UB3: tests/${_ub_suite}.test.sh carries the new contract and not the old one" \
    "${REPO}/tests/${_ub_suite}.test.sh"
done

# THE PINS DISCRIMINATE, three ways: the old phrase planted back into a span, the new phrase
# removed from a suite, and the run.sh span emptied by a renamed heading.
sed 's/announced and never acted on/announced, then followed exactly as before/' \
  "$TMP/ub-stop-facts.txt" > "$TMP/ub-doctored-stop.txt"
if ub_carrier_ok "$TMP/ub-doctored-stop.txt"; then
  no "UB4: a doctored stop_turn_facts docblock goes red" "the doctored copy still passed — the pin is vacuous"
else ok "UB4: a doctored stop_turn_facts docblock goes red"; fi
grep -vF "$UB_PIN_NEW" "${REPO}/tests/patrol-revive.test.sh" > "$TMP/ub-doctored-suite.txt"
if ub_carrier_ok "$TMP/ub-doctored-suite.txt"; then
  no "UB5: a suite with the new sentence removed goes red" "the doctored copy still passed — the pin is vacuous"
else ok "UB5: a suite with the new sentence removed goes red"; fi
sed 's/^# session_run <root> <sid> -> ONE line/# session_run, renamed/' "$UB_RUN_LIB" > "$TMP/ub-doctored-run.sh"
ub_span "$TMP/ub-doctored-run.sh" '^# session_run <root> <sid> -> ONE line' '^session_run\(\) \{' > "$TMP/ub-doctored-run.txt"
if ub_carrier_ok "$TMP/ub-doctored-run.txt"; then
  no "UB6: a span that cannot be found is red, never green on nothing" "an empty span passed"
else ok "UB6: a span that cannot be found is red, never green on nothing"; fi

section "Section RH: wave-23 T3 — the reasons live beside the code, and no citation names a memory file (REQ-4, AC-4.1 to AC-4.4; D3)"
#
# WHAT THIS OWNS. The memory tier is retired, so a rule's reason has to sit in the file that
# enforces it: the two named test-harness rules, the env.sh census, the stop.sh and units.sh
# comments that used to cite a slug, the operational-rules and agent-discipline doctrine lines,
# and the four provenance lines. Each pin says what the file CARRIES and what it must no longer
# say, and each is proven against two doctored copies: the carried phrase removed (the pin must
# go red) and the retired phrase planted (the pin must go red). A pin that only reads files
# already in agreement could be an extractor bug, so the doctored arms run on every run.
#
# Text is flattened first (comment markers dropped, newlines to spaces) because a phrase wraps
# across lines in prose and in comments. Spans are cut by their own opening and closing lines, as
# in §UB, and the first assertion of each span proves it is non-empty.
RH_STOP_LIB="${REPO}/payload/scripts/lib/stop.sh"
RH_UNITS_LIB="${REPO}/payload/scripts/lib/units.sh"
RH_ENV_LIB="${REPO}/payload/scripts/lib/env.sh"
RH_RULES="${REPO}/.claude/rules"
RH_OPS="${REPO}/skills/canonical-sdlc/operational-rules.md"
# The retired phrases are spelled in two halves so this file does not itself match AC-4.1's grep.
RH_N=n; RH_B=b; RH_M=m

rh_flat() {  # <file> -> the text on stdout, shell comment markers dropped, one line
  case "$1" in
    *.md) tr '\n' ' ' < "$1" | tr -s ' ' ;;  # markdown keeps its own # headings
    *) sed -e 's/^[[:space:]]*#[[:space:]]\{0,1\}//' "$1" | tr '\n' ' ' | tr -s ' ' ;;
  esac
}
rh_verdict() {  # <flat-file> <must carry> <must not carry, may be empty> -> 0 when the pin is satisfied
  [ -s "$1" ] || return 1
  grep -qF -- "$2" "$1" || return 1
  if [ -n "$3" ] && grep -qF -- "$3" "$1"; then return 1; fi
  return 0
}
rh_remove() {  # <flat-file> <phrase> -> the file with every copy of the phrase cut out, on stdout
  awk -v p="$2" '{ while ((i = index($0, p)) > 0) $0 = substr($0, 1, i - 1) substr($0, i + length(p)) } 1' "$1"
}
rh_pin() {  # <label> <flat-file> <must carry> <must not carry, may be empty>
  local label="$1" flat="$2" has="$3" hasnot="$4" n
  n="${label//[^A-Za-z0-9]/_}"
  if rh_verdict "$flat" "$has" "$hasnot"; then ok "$label"; else
    no "$label" "carries=$(grep -cF -- "$has" "$flat" 2>/dev/null) retired=$([ -n "$hasnot" ] && grep -cF -- "$hasnot" "$flat" 2>/dev/null) bytes=$(wc -c < "$flat" 2>/dev/null)"
  fi
  rh_remove "$flat" "$has" > "$TMP/rh-doc-a-$n.txt"
  if rh_verdict "$TMP/rh-doc-a-$n.txt" "$has" "$hasnot"; then
    no "$label — doctored: carried phrase removed goes red" "the doctored copy still passed — the pin is vacuous"
  else ok "$label — doctored: carried phrase removed goes red"; fi
  if [ -n "$hasnot" ]; then
    { cat "$flat"; printf ' %s\n' "$hasnot"; } > "$TMP/rh-doc-b-$n.txt"
    if rh_verdict "$TMP/rh-doc-b-$n.txt" "$has" "$hasnot"; then
      no "$label — doctored: retired phrase planted goes red" "the doctored copy still passed — the pin is vacuous"
    else ok "$label — doctored: retired phrase planted goes red"; fi
  fi
}

# RH1/RH2 — the shared rules and the census.
rh_flat "$RH_RULES/test-harness.md" > "$TMP/rh-harness.txt"
rh_pin "RH1a: test-harness.md carries the named rule \"Fixture fidelity\"" "$TMP/rh-harness.txt" "## Fixture fidelity" ""
rh_pin "RH1b: test-harness.md carries the named rule \"Anti-vacuity\"" "$TMP/rh-harness.txt" "## Anti-vacuity" ""
rh_flat "$RH_ENV_LIB" > "$TMP/rh-env.txt"
rh_pin "RH2: env.sh carries the task-tools census" "$TMP/rh-env.txt" "a census of session transcripts" ""

# RH3 — stop.sh's walls comment states its measurement; its task-list comment points at the census.
ub_span "$RH_STOP_LIB" 'WHY A WALL AND NOT BETTER WORDING' 'is the one channel that can ask it' > "$TMP/rh-stop-walls-raw.txt"
expect_true "RH3-0: stop.sh's walls span was found (non-empty)" test -s "$TMP/rh-stop-walls-raw.txt"
rh_flat "$TMP/rh-stop-walls-raw.txt" > "$TMP/rh-stop-walls.txt"
rh_pin "RH3a: stop.sh's walls comment carries its measurement, with no memory/ citation" "$TMP/rh-stop-walls.txt" "were measured not to bind" "memory/"
ub_span "$RH_STOP_LIB" 'THE TASK-LIST FALLBACK IS NOT A CONVENIENCE' 'discharges' > "$TMP/rh-stop-fallback-raw.txt"
expect_true "RH3-1: stop.sh's task-list fallback span was found (non-empty)" test -s "$TMP/rh-stop-fallback-raw.txt"
rh_flat "$TMP/rh-stop-fallback-raw.txt" > "$TMP/rh-stop-fallback.txt"
rh_pin "RH3b: stop.sh's task-list comment points at env.sh, with no memory/ citation" "$TMP/rh-stop-fallback.txt" "payload/scripts/lib/env.sh" "memory/"

# RH4 — units.sh's projector comment states its reason.
ub_span "$RH_UNITS_LIB" 'THE PROJECTOR UNDER `task-add`' '1\. THE ROW' > "$TMP/rh-units-raw.txt"
expect_true "RH4-0: units.sh's projector span was found (non-empty)" test -s "$TMP/rh-units-raw.txt"
rh_flat "$TMP/rh-units-raw.txt" > "$TMP/rh-units.txt"
rh_pin "RH4: units.sh's projector comment carries its reason, with no retired note citation" "$TMP/rh-units.txt" "it refuses the WRITER, not the author of the row" "memory ${RH_N}ote"

# RH5 — operational-rules.md doctrine lines.
rh_flat "$RH_OPS" > "$TMP/rh-ops.txt"
rh_pin "RH5a: operational-rules.md names CLAUDE.md and .claude/rules/, not the retired always-loaded store" "$TMP/rh-ops.txt" 'CLAUDE.md and `.claude/rules/`' "fact ${RH_B}ank"
rh_pin "RH5b: operational-rules.md says the rationale stays in this file, not in the retired tier" "$TMP/rh-ops.txt" "stays in this file" "stays here in ${RH_M}emory"

# RH6 — agent-discipline.md: auto-memory is off, and no subagent receives MEMORY.md.
rh_flat "$RH_RULES/agent-discipline.md" > "$TMP/rh-discipline.txt"
rh_pin "RH6a: agent-discipline.md says auto-memory is off by bionic's setup, with no \"legitimate destination\"" "$TMP/rh-discipline.txt" "off by bionic's setup" "legitimate destination"
rh_pin "RH6b: agent-discipline.md says a dispatched subagent never receives MEMORY.md" "$TMP/rh-discipline.txt" "never receives MEMORY.md" ""

# RH7 — the four provenance lines name the retired tier and no path.
for _rh_rule in agent-discipline git-worktree-docs hook-authoring test-harness; do
  rh_flat "$RH_RULES/${_rh_rule}.md" > "$TMP/rh-prov-${_rh_rule}.txt"
  rh_pin "RH7: ${_rh_rule}.md's provenance line names the retired memory tier, not .bionic/memory/" "$TMP/rh-prov-${_rh_rule}.txt" "retired memory tier" ".bionic/memory/"
done

section "Section D2: wave-23 T18 — every landed candidate rule is in its owner file and pinned (REQ-5, AC-5.2; D2)"
#
# WHAT THIS OWNS. T8 landed the D2 candidate rules in their owner files: the repo CLAUDE.md, the
# four path-scoped rule files, the orchestrator-dispatch block and the test-runner template. T3's
# section RH pins the re-homed reasons; nothing pinned the landings themselves, so an edit that
# dropped a rule would pass. One pin per landed row plus the card-format rule in
# plan-authoring.md. The report-contract row was declined (A-T3.1) and has no pin; the hand
# dry-run row was cut by wave-26 T1 (the advance verb dry-commits), and §W26-6 pins its absence.
#
# Each pin asserts the row's key phrase is in its owner file, and for the block and the template
# also in the rendered surface a session loads (dispatch.md; agents/test-runner.md). Each is proven
# against a doctored copy with the phrase cut out, which must go red (the section RH helpers).
# Phrases carry no retired-store wording, so this file cannot match AC-4.1's grep. The table goes
# to a file, not a command substitution: bash 3.2 mis-parses apostrophes in a heredoc inside one.
D2_ROWS_FILE="$TMP/d2-rows.tsv"
cat > "$D2_ROWS_FILE" <<'D2P'
CLAUDE.md	No consumer-project names, tools or incidents appear in anything it ships
CLAUDE.md	Ready tasks dispatch up to capacity without asking
CLAUDE.md	Deleting dead code the user has ruled on is a few-line commit by the orchestrator
CLAUDE.md	becomes a fixit in a fresh canonical-sdlc run
.claude/rules/test-harness.md	Scripted deletion of assertions leaves scars
.claude/rules/test-harness.md	tests that check behavior are good
.claude/rules/test-harness.md	Pin the obligation span or the normative literal
.claude/rules/test-harness.md	A seam that substitutes the very value under test
.claude/rules/test-harness.md	Sourced into zsh, `git cat-file -e` can spuriously return nonzero
.claude/rules/test-harness.md	Verify time-driven machinery at an accelerated cadence
.claude/rules/test-harness.md	`tests/run.sh` prints nothing until its queue drains
.claude/rules/test-harness.md	a plugin dependency is keyed by `name@marketplace`
.claude/rules/hook-authoring.md	A rule binds only as a wall
.claude/rules/hook-authoring.md	A bad escalation is a generation-time failure
.claude/rules/hook-authoring.md	A threshold is the smallest value consistent with telemetry
.claude/rules/agent-discipline.md	An absence claim needs `/usr/bin/grep`
.claude/rules/agent-discipline.md	Removing a file is the easy half
.claude/rules/agent-discipline.md	snapshotted once at session start
.claude/rules/agent-discipline.md	prefix-match the literal command string
.claude/rules/agent-discipline.md	A skill is routed only when something loads it
.claude/rules/agent-discipline.md	Steps 0-3 need a human present
.claude/rules/agent-discipline.md	Run `git log -1` before every `git commit --amend`
.claude/rules/plan-authoring.md	Provenance is one short clause
.claude/rules/plan-authoring.md	A tune row's numeric target is a round number, not a gate
.claude/rules/plan-authoring.md	the named size reduction is the acceptance criterion
.claude/rules/plan-authoring.md	check what it actually carries
agents-src/blocks/orchestrator-dispatch.md	stop-orders.sh stopped <name>` closes the row of an agent already stopped with TaskStop
agents-src/blocks/orchestrator-dispatch.md	Any TaskUpdate on a task a named agent owns resumes that agent
agents-src/blocks/orchestrator-dispatch.md	read only when that call returns
agents-src/blocks/orchestrator-dispatch.md	Split a task that spans many files across writers at dispatch time
agents-src/blocks/orchestrator-dispatch.md	A final review with a settled `head` read covers cross-task problems
agents-src/blocks/orchestrator-dispatch.md	On a model-tier outage, hold
agents-src/templates/test-runner.md.tmpl	A revert-and-watch stubs the production file only
.claude/rules/plan-authoring.md	The Step-2 card parses decisions only as
D2P
d2_i=0
while IFS=$'\t' read -r _d2_file _d2_phrase; do
  [ -n "$_d2_file" ] || continue
  d2_i=$((d2_i + 1))
  rh_flat "${REPO}/${_d2_file}" > "$TMP/d2-own-${d2_i}.txt"
  rh_pin "D2.${d2_i}: ${_d2_file} carries \"${_d2_phrase}\"" "$TMP/d2-own-${d2_i}.txt" "$_d2_phrase" ""
  _d2_rend=""
  case "$_d2_file" in
    agents-src/blocks/orchestrator-dispatch.md) _d2_rend="skills/canonical-sdlc/dispatch.md" ;;
    agents-src/templates/test-runner.md.tmpl) _d2_rend="agents/test-runner.md" ;;
  esac
  if [ -n "$_d2_rend" ]; then
    rh_flat "${REPO}/${_d2_rend}" > "$TMP/d2-rend-${d2_i}.txt"
    rh_pin "D2.${d2_i}r: rendered ${_d2_rend} carries \"${_d2_phrase}\"" "$TMP/d2-rend-${d2_i}.txt" "$_d2_phrase" ""
  fi
done < "$D2_ROWS_FILE"
expect_true "D2-count: every row of the table was read ($d2_i)" \
  test "$d2_i" -gt 0 -a "$d2_i" -eq "$(grep -c . "$D2_ROWS_FILE")"

section "Section HOLD: wave-24 T7 — the stand-down's standing answer is named where the duty is (REQ-4, AC-4.12; D1, D5)"
#
# `hold` that only the usage text knew would be a verb nobody runs: the duty is met where it is
# read — the dispatch doctrine (source and render) and the Patrol prompt the cron job carries.
# The stand-down refusal's own text is the stop wall's (payload/scripts/lib/stop.sh), pinned with
# that file's owner.
# ONE wording for the doctrine and the prompt (wave-24 T27/T29, critic I4): NAME and a quoted
# reason, because a bare `<name>` or `<reason>` pastes as a redirect from a file of that name.
PIN_HOLD_VERB="session-poker.sh hold NAME 'why it stays up'"
PIN_HOLD_LIST='`ListAgents` only when the roster has an open row'
HOLD_BLOCK="${REPO}/agents-src/blocks/orchestrator-dispatch.md"
for _hold_f in "$DISPATCH_MD" "$HOLD_BLOCK"; do
  if has_pin "$_hold_f" "$PIN_HOLD_VERB"; then
    ok "HOLD-a: ${_hold_f#"$REPO"/} names the hold verb beside the stand-down duty"
  else
    no "HOLD-a: ${_hold_f#"$REPO"/} names the hold verb beside the stand-down duty" "file: $_hold_f"
  fi
  if has_pin "$_hold_f" "$PIN_HOLD_LIST"; then
    ok "HOLD-b: ${_hold_f#"$REPO"/} asks for ListAgents only with an open row"
  else
    no "HOLD-b: ${_hold_f#"$REPO"/} asks for ListAgents only with an open row" "file: $_hold_f"
  fi
done
HOLD_PROMPT="$(CLAUDE_CODE_SESSION_ID=0123456789abcdef bash "$POKER_SH" prompt 2>/dev/null)"
expect_nonempty "HOLD-c precondition: the poker printed its Patrol prompt" "$HOLD_PROMPT"
# THE PROMPT'S HOLD LINE PASTES AS ONE COMMAND (wave-24 T27; critic I4): the reason is a quoted
# placeholder, never a bare `<reason>` a shell reads as a redirect. The doctrine (HOLD-a) prints
# the same words since w24-T29, so one pin serves both.
expect_contains "HOLD-c: the Patrol prompt names the hold verb, its reason a quoted placeholder" "$PIN_HOLD_VERB" "$HOLD_PROMPT"
# The retired ask must be gone from the doctrine too: "ListAgents, before the tick" every tick.
expect_eq "HOLD-d: the unconditional 'before the tick' ListAgents line is gone from dispatch.md" "0" \
  "$(grep -c 'ListAgents`, before the tick, for a fresh answer' "$DISPATCH_MD" 2>/dev/null | tr -cd '0-9')"
expect_eq "HOLD-d2: …and the pattern finds the shape it targets" "1" \
  "$(printf -- '- **List the panel.** `ListAgents`, before the tick, for a fresh answer.\n' | grep -c 'ListAgents`, before the tick, for a fresh answer' | tr -cd '0-9')"

section "Section VERB: wave-24 T15 — the steps name the plan-row verbs where they told a hand edit (REQ-9, AC-9.8; D14)"
#
# A verb only the usage text knew would be a verb nobody types: the step that tells the run to
# move `current:`, write a step line, set a row's cells or ledger a dispatch names the verb that
# does it, in the template and in its render. Each retired hand-edit sentence is gone, with a
# control that its pattern finds the shape it targets, and each verb the doctrine names is one
# the poker accepts — a renamed verb fails here rather than in a run.
VERB_BLOCK="${REPO}/agents-src/blocks/orchestrator-dispatch.md"
VERB_S3_TMPL="${REPO}/agents-src/templates/skills/canonical-sdlc/steps/3.md.tmpl"
VERB_S5_TMPL="${REPO}/agents-src/templates/skills/canonical-sdlc/steps/5.md.tmpl"
verb_pin() {  # <id> <needle> <file>…
  local id="$1" needle="$2" f; shift 2
  for f in "$@"; do
    if has_pin "$f" "$needle"; then ok "$id: ${f#"$REPO"/} names $needle"
    else no "$id: ${f#"$REPO"/} names $needle" "file: $f"; fi
  done
}
verb_pin VERB-a '`task-set`' "$DISPATCH_MD" "$VERB_BLOCK"
verb_pin VERB-b '`step-line`' "$DISPATCH_MD" "$VERB_BLOCK"
verb_pin VERB-c '`current <N>`' "$DISPATCH_MD" "$VERB_BLOCK"
verb_pin VERB-d '`ledger-add`' "$DISPATCH_MD" "$VERB_BLOCK"
verb_pin VERB-e '`ledger-set`' "$DISPATCH_MD" "$VERB_BLOCK"
verb_pin VERB-f '`session-poker.sh current <N>`' "$STEP3_MD" "$VERB_S3_TMPL"
verb_pin VERB-g '`task-set <id> worktree=<tree>`' "$STEP3_MD" "$VERB_S3_TMPL"
verb_pin VERB-g2 '`step-line <N> <text>`' "$STEP3_MD" "$VERB_S3_TMPL"
verb_pin VERB-h '`session-poker.sh current 6`' "$STEP5_MD" "$VERB_S5_TMPL"
# The retired sentences, each beside a control that its pattern matches the sentence it was.
verb_gone() {  # <id> <needle> <the old sentence> <file>
  expect_eq "$1: ${4#"$REPO"/} no longer tells the hand edit" "0" \
    "$(_flatten "$4" | grep -cF -- "$2" | tr -cd '0-9')"
  expect_eq "$1c: …and the pattern finds the shape it targets" "1" \
    "$(printf '%s\n' "$3" | grep -cF -- "$2" | tr -cd '0-9')"
}
verb_gone VERB-i 'bump `current:` and replace the line in place' \
  'one `Step N: <evidence>` line per step; bump `current:` and replace the line in place when advancing.' "$STEP3_MD"
verb_gone VERB-j "Write the tree's name into the row's" \
  "Write the tree's name into the row's \`worktree\` cell as you create the tree." "$STEP3_MD"
verb_gone VERB-k "Write the unit's row the moment you dispatch it" \
  "Write the unit's row the moment you dispatch it, status \`active\`." "$DISPATCH_MD"
verb_gone VERB-l 'Probe it before advancing with' \
  'Probe it before advancing with `git commit --dry-run --allow-empty`: every wall runs, nothing is written.' "$STEP5_MD"
for _vv in task-set step-line current ledger-add ledger-set; do
  _vout="$(CLAUDE_CODE_SESSION_ID=0123456789abcdef bash "$POKER_SH" "$_vv" 2>&1)"
  expect_nonempty "VERB-m precondition: the poker answered $_vv" "$_vout"
  expect_absent "VERB-m: the poker accepts the documented verb $_vv" "unknown verb" "$_vout"
done

section "Section SEMVER: wave-24 T18 — one versioning policy, in identical lines, in CLAUDE.md and the CHANGELOG header; the newest entry is plugin.json's version (REQ-11, AC-11.1/AC-11.2; D19)"
#
# WHAT THIS OWNS. From 1.9.0 bionic versions by semver, and the policy is stated twice: in the
# repo CLAUDE.md, which a session working here reads, and in the CHANGELOG's header, which a user
# reads. AC-11.2 fails when either lacks it or the two disagree, so the block is extracted from
# each file by one reader and compared byte for byte. The block opens on its lead line and runs to
# the first blank line. The CHANGELOG is also a version surface (AC-11.1): its newest entry's
# heading must name plugin.json's version, which Section 1 and AC-17 do not read.
SEMVER_CLAUDE="${REPO}/CLAUDE.md"
SEMVER_CHANGELOG="${REPO}/CHANGELOG.md"
# semver_block <file> -> the policy lines, from "Versioning follows semver" to the first blank line.
semver_block() { awk '/^Versioning follows semver/ { p = 1 } p && /^$/ { exit } p' "$1" 2>/dev/null; }
# changelog_head_version <file> -> the version on the first "## <version> — <date>" heading.
changelog_head_version() { awk '/^## [0-9]/ { print $2; exit }' "$1" 2>/dev/null; }
# first_line_of <file> <ERE> -> the line number of the first match, empty when none.
first_line_of() { grep -nE -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; }

SV_CLAUDE="$(semver_block "$SEMVER_CLAUDE")"
SV_CHANGELOG="$(semver_block "$SEMVER_CHANGELOG")"
expect_nonempty "SEMVER-1: CLAUDE.md carries the versioning policy block" "$SV_CLAUDE"
expect_nonempty "SEMVER-2: CHANGELOG.md carries the versioning policy block" "$SV_CHANGELOG"
SV_FLAT="$(printf '%s\n' "$SV_CLAUDE" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g')"
for _sv in \
  '**MAJOR** for a change that breaks a documented contract a user or project already relies on' \
  'a removed verb or field, a `canonical_sdlc_version` bump, an artifact a user must migrate' \
  '**MINOR** for new capability or a behaviour a user notices, including a newly refused action or an upgrade step' \
  '**PATCH** for a fix within existing behaviour'; do
  expect_contains "SEMVER-3: the policy says: $_sv" "$_sv" "$SV_FLAT"
done
expect_eq "SEMVER-4: CLAUDE.md and the CHANGELOG header state the policy in identical lines" \
  "$SV_CLAUDE" "$SV_CHANGELOG"
SV_AT="$(first_line_of "$SEMVER_CHANGELOG" '^Versioning follows semver')"
SV_FIRST_ENTRY="$(first_line_of "$SEMVER_CHANGELOG" '^## [0-9]')"
expect_nonempty "SEMVER-5 precondition: the CHANGELOG has a release entry" "$SV_FIRST_ENTRY"
expect_true "SEMVER-5: the CHANGELOG's policy sits in its header, above the first release entry" \
  test "${SV_AT:-999999}" -lt "${SV_FIRST_ENTRY:-0}"
expect_eq "SEMVER-6: the CHANGELOG's newest entry is plugin.json's version" \
  "$(plugin_version_of "$PLUGIN_JSON")" "$(changelog_head_version "$SEMVER_CHANGELOG")"
# Anti-vacuity: one word changed in one file's block must read as a disagreement, through the
# same reader, while that reader still finds the doctored block.
anchor "$SEMVER_CLAUDE" 'or an upgrade step' 1
sed 's/or an upgrade step/or a new setting/' "$SEMVER_CLAUDE" > "$TMP/semver-claude-doctored.md"
SV_DOCTORED="$(semver_block "$TMP/semver-claude-doctored.md")"
expect_nonempty "SEMVER-7 precondition: the doctored CLAUDE.md still has a policy block" "$SV_DOCTORED"
expect_ne "SEMVER-7: a one-word change in CLAUDE.md's policy reads as a disagreement (pin discriminates)" \
  "$SV_CHANGELOG" "$SV_DOCTORED"
awk '!d && /^## [0-9]/ { $2 = "0.0.0-mismatch"; d = 1 } 1' "$SEMVER_CHANGELOG" \
  > "$TMP/semver-changelog-doctored.md"
expect_eq "SEMVER-8: a doctored newest heading reads as its own version (pin discriminates)" \
  "0.0.0-mismatch" "$(changelog_head_version "$TMP/semver-changelog-doctored.md")"

section "Section PB: wave-25 T6 — the permission boundary is declared on the Step-0 card, in every role, in the dispatch doctrine and in the shipped docs (REQ-3 AC-3.4, REQ-6 AC-6.2, REQ-8 AC-8.2; D10, D11)"
#
# WHAT THIS OWNS. An engaged run answers the platform's permission questions itself, so it
# must say so where the user approves the run (the Step-0 card's Gates block), teach every
# agent the route the platform never refuses (one line in the shared role block, rendered
# into all six roles), have the dispatcher name the agent when it creates its tree (the
# workspace record reads that name), and tell a user the whole contract in the shipped
# operational rules. The card line is paid for inside the skill's byte cap: rows 111-115 and
# 125 above are this section's other half, and they do not move.
#
# HERMETIC. Reads the committed rendered files, the block source and operational-rules.md by
# path; doctored copies live under $TMP.
PB_STEP0="${REPO}/skills/canonical-sdlc/steps/0.md"
PB_DISPATCH="${REPO}/skills/canonical-sdlc/dispatch.md"
PB_OPS="${REPO}/skills/canonical-sdlc/operational-rules.md"
PB_BLOCK="${REPO}/agents-src/blocks/dispatch-rules.md"
PB_LINE="    permissions   answered from the run's workspace | off"
PB_RULE='run as `bash <file>`'
# pb_gates <file> -> the lines under the layout's `  Gates` heading, to the first blank line.
pb_gates() { awk '/^  Gates$/ { g = 1; next } g && /^$/ { exit } g' "$1" 2>/dev/null; }
# pb_after_interview <file> -> the Gates line that directly follows the `interview` line.
pb_after_interview() { pb_gates "$1" | awk 'p { print; exit } /^    interview /{ p = 1 }'; }
# pb_ops_section <file> -> the `## Permission answers` section, to the next `## ` heading.
pb_ops_section() { awk '/^## Permission answers/ { p = 1; print; next } p && /^## / { exit } p' "$1" 2>/dev/null; }

PB_GATES="$(pb_gates "$PB_STEP0")"
expect_contains "PB-a precondition: the Gates block of steps/0.md reads (it carries the walk line)" \
  "    walk          <required | exempt>" "$PB_GATES"
expect_eq "PB-a: AC-6.2 — the Gates line after interview is the permissions line, in the layout" \
  "$PB_LINE" "$(pb_after_interview "$PB_STEP0")"
expect_contains "PB-a2: AC-6.2 — the step names the off switch beside the consent" \
  'permission-answers: false' "$(cat "$PB_STEP0" 2>/dev/null)"
anchor "$PB_STEP0" "$PB_LINE" 1
grep -vF -- "$PB_LINE" "$PB_STEP0" > "$TMP/pb-step0-doctored.md" 2>/dev/null
expect_contains "PB-a3 precondition: the doctored card still has its Gates block" \
  "    walk          <required | exempt>" "$(pb_gates "$TMP/pb-step0-doctored.md")"
expect_ne "PB-a3: a card with the line removed fails PB-a (the pin discriminates)" \
  "$PB_LINE" "$(pb_after_interview "$TMP/pb-step0-doctored.md")"

PB_ROLES=0
PB_ROLE_MISS=""
for _rf in "${REPO}"/agents/*.md; do
  [ -f "$_rf" ] || continue
  PB_ROLES=$((PB_ROLES + 1))
  grep -qF -- "$PB_RULE" "$_rf" || PB_ROLE_MISS="${PB_ROLE_MISS} ${_rf##*/}"
done
# RE-POINTED (wave-27 T11): was `"6" = $PB_ROLES`; 111a's relation, which names no count.
expect_eq "PB-b precondition: the role files are the roles render.sh renders (the loop read them all)" \
  "yes" "$(role_files_are_roles "${REPO}/agents" "$ROLES_DECLARED")"
expect_eq "PB-b: AC-3.4 — every role file carries the script-in-a-file rule (missing in:${PB_ROLE_MISS:- none})" \
  "" "$PB_ROLE_MISS"
expect_eq "PB-b2: AC-3.4 — the rule lives once in the shared role block" \
  "1" "$(grep -cF -- "$PB_RULE" "$PB_BLOCK" 2>/dev/null | tr -cd '0-9')"
expect_contains "PB-b3: AC-3.4 — the rule names the inline form it replaces" \
  "never inline as \`bash -c '…'\`" "$(tr '\n' ' ' < "$PB_BLOCK" 2>/dev/null | sed 's/  */ /g')"
anchor "${REPO}/agents/researcher.md" "$PB_RULE" 1
grep -vF -- "$PB_RULE" "${REPO}/agents/researcher.md" > "$TMP/pb-role-doctored.md" 2>/dev/null
expect_contains "PB-b4 precondition: the doctored role file still carries the shared block's other rules" \
  'Spell each suite literally' "$(cat "$TMP/pb-role-doctored.md")"
expect_eq "PB-b4: a role file with the rule's line removed reads as missing it (the pin discriminates)" \
  "0" "$(grep -cF -- "$PB_RULE" "$TMP/pb-role-doctored.md" | tr -cd '0-9')"

PB_SPAWN="$(grep -F 'Parallel writers work in spawned worktrees' "$PB_DISPATCH" 2>/dev/null)"
expect_contains "PB-c precondition: dispatch.md's spawned-worktree paragraph reads" \
  'spawn-worktree.sh' "$PB_SPAWN"
expect_contains "PB-c: the dispatcher passes the agent's name to create with --for" \
  '`--for <name>`' "$PB_SPAWN"

PB_OPS_SEC="$(pb_ops_section "$PB_OPS")"
expect_contains "PB-d precondition: operational-rules.md has its Permission answers section" \
  '## Permission answers' "$PB_OPS_SEC"
for _pb in \
  '**The platform decides what it decides.**' \
  '**An engaged run answers what the platform asks.**' \
  '**Reserved categories go to the human.**' \
  '`leaves-the-machine`' '`credentials`' '`production-infrastructure`' '`billing`' \
  'permission-answers: false' 'permission-answers.log'; do
  expect_contains "PB-d: AC-8.2 — the shipped docs state: $_pb" "$_pb" "$PB_OPS_SEC"
done
anchor "$PB_OPS" 'permission-answers: false' 1
sed 's/permission-answers: false/permission-answers: (unset)/' "$PB_OPS" > "$TMP/pb-ops-doctored.md"
PB_OPS_DOCTORED="$(pb_ops_section "$TMP/pb-ops-doctored.md")"
expect_contains "PB-d2 precondition: the doctored docs still have the section" \
  '## Permission answers' "$PB_OPS_DOCTORED"
expect_absent "PB-d2: docs with the off switch removed fail PB-d (the pin discriminates)" \
  'permission-answers: false' "$PB_OPS_DOCTORED"


section "Section W26: wave-26 T1 — nothing is ordered twice (REQ-1, AC-1.1, 1.2, 1.3, 1.5, 1.6, AC-1.4 doctrine half; D15)"
#
# WHAT THIS OWNS. Wave-26 removes work the doctrine ordered twice: a second auditor pass, six
# reviewers where one does, a critic re-doing the reviewer's and the auditor's checks, duties
# stated twice with different values, and steps the tool already performs. Each arm asserts an
# absence over the shipped doctrine, beside a positive on the same extractor and file, and a
# doctored copy (or, for W26-3, a mutant render) proves the arm goes red when the cut text is
# back. HERMETIC: reads the committed finals by path; doctored copies live under $TMP.
W26_DOCTRINE="$(ls "${SKILL_DIR}"/SKILL.md "${SKILL_DIR}"/dispatch.md "${SKILL_DIR}"/operational-rules.md \
  "${SKILL_DIR}"/steps/*.md "${REPO}"/agents/*.md "${REPO}"/payload/context/survival.md 2>/dev/null)"
W26_ROLES="$(ls "${REPO}"/agents/*.md 2>/dev/null)"
# w26_hits <fixed string> <file>… -> the files whose flattened text carries it, one per line.
w26_hits() {
  local needle="$1" f; shift
  for f in "$@"; do has_pin "$f" "$needle" && printf '%s\n' "${f#"$REPO"/}"; done
}
# w26_doctor <file> <text> -> a copy of the file with the text appended, its path on stdout.
w26_doctor() {
  local out; out="$TMP/w26-$(printf '%s' "$1$2" | cksum | tr -cd '0-9').md"
  { cat "$1"; printf '\n%s\n' "$2"; } > "$out" 2>/dev/null
  printf '%s' "$out"
}

# W26-1 (AC-1.1): no shipped doctrine file names a second auditor pass.
# shellcheck disable=SC2086  # word-split on purpose: one path per line, none with spaces
expect_nonempty "W26-1 precondition: the extractor finds a phrase every doctrine set carries (the auditor)" \
  "$(w26_hits 'auditor' $W26_DOCTRINE)"
# shellcheck disable=SC2086
expect_eq "W26-1: AC-1.1 — no shipped doctrine file names a second pass" "" \
  "$(w26_hits 'second pass' $W26_DOCTRINE)"
W26_D1="$(w26_doctor "$DISPATCH_MD" "Only the auditor's second pass waits for the floor.")"
expect_nonempty "W26-1m: a dispatch.md that keeps \"the auditor's second pass\" is caught" \
  "$(w26_hits 'second pass' "$W26_D1")"

# W26-2 (AC-1.2): one reviewer, and the two flags that add another.
expect_nonempty "W26-2: AC-1.2 — steps/6.md names one reviewer for the six axes" \
  "$(w26_hits 'One reviewer takes all six axes' "$STEP6_MD")"
expect_nonempty "W26-2b: …and the security or performance flag that adds one" \
  "$(w26_hits 'A security or performance flag adds one reviewer' "$STEP6_MD")"
expect_eq "W26-2c: …and no longer runs the axes in parallel" "" \
  "$(w26_hits 'Run the axes in parallel' "$STEP6_MD")"
W26_D2="$(w26_doctor "$STEP6_MD" 'Run the axes in parallel.')"
expect_nonempty "W26-2m: a steps/6.md that keeps \"Run the axes in parallel\" is caught" \
  "$(w26_hits 'Run the axes in parallel' "$W26_D2")"

# W26-3 (AC-1.3): the critic carries neither the reviewer's duplication axis nor the auditor's
# evidence check. The mutant is a real render: a clone whose critic template injects the block
# again, so the arm proves it reads what the renderer writes, not a hand-made copy.
W26_CRITIC="${REPO}/agents/critic.md"
expect_nonempty "W26-3 precondition: agents/critic.md carries its checks pointer" \
  "$(w26_hits 'Checks: payload/context/checks-<question>.md' "$W26_CRITIC")"
expect_eq "W26-3: AC-1.3 — agents/critic.md carries no duplication axis" "" \
  "$(w26_hits 'Duplication axis' "$W26_CRITIC")"
expect_eq "W26-3b: …and no fabricated-evidence check" "" \
  "$(w26_hits 'fabricated evidence' "$W26_CRITIC")"
W26_CLONE="$TMP/w26-clone"
if clone_render_tree "$W26_CLONE" \
   && printf '\n<!-- INJECT: duplication-axis -->\n' >> "$W26_CLONE/agents-src/templates/critic.md.tmpl" \
   && bash "$W26_CLONE/agents-src/render.sh" >/dev/null 2>&1; then
  expect_nonempty "W26-3m precondition: the mutant render wrote a critic role file" \
    "$(w26_hits 'Checks: payload/context/checks-<question>.md' "$W26_CLONE/agents/critic.md")"
  expect_nonempty "W26-3m: a critic template that still injects the duplication block is caught" \
    "$(w26_hits 'Duplication axis' "$W26_CLONE/agents/critic.md")"
else
  no "W26-3m: a critic template that still injects the duplication block is caught" \
     "the mutant clone did not render: $W26_CLONE"
fi

# W26-5 (AC-1.5): one suite timeout and one capture recipe; the closing-message and
# foreground duties once per role file. The timeout and the capture recipe the tooling
# enforces live in the dispatch terms (the wall raises a smaller timeout to
# BASH_MAX_TIMEOUT_MS; its refusal's remedy prints `2>&1 | tee`), so no role file states its own.
W26_SURV="${REPO}/payload/context/survival.md"
expect_nonempty "W26-5 precondition: the dispatch terms state the timeout by the harness maximum" \
  "$(w26_hits 'BASH_MAX_TIMEOUT_MS' "$W26_SURV")"
# RE-POINTED (wave-26 T20, review-2 F1): the kept recipe writes the exit code into the log,
# because `tee` alone leaves it only in the call's status and PIPESTATUS is empty under zsh.
# The orchestrator gets no dispatch terms, so dispatch.md carries the same line.
# RE-SHAPED (wave-26 T58): `land` reads the stamp the booking shim writes from the exit code of
# the WHOLE command, and a recipe whose last segment is the `echo` always exits 0 — a red suite
# captured as taught was stamped green. The recipe now ends `exit $rc`.
W26_RECIPE='2>&1 | tee "$LOG"; rc=$?; echo "rc=$rc" >> "$LOG"; exit $rc'
for _w26_f in "$W26_SURV" "$DISPATCH_MD"; do
  expect_nonempty "W26-5b: the capture recipe in ${_w26_f#"$REPO"/} writes rc=\$? into the log" \
    "$(w26_hits "$W26_RECIPE" "$_w26_f")"
  expect_nonempty "W26-5p precondition: ${_w26_f#"$REPO"/} bans PIPESTATUS" \
    "$(w26_hits 'never `PIPESTATUS`' "$_w26_f")"
done
# W26-5r: no doctrine file teaches the old recipe, whose last segment is the `echo` of the code.
# The positive on the same extractor and files is W26-5b above (the new recipe is found).
W26_OLD_RECIPE='echo "rc=$?" >> "$LOG"'
# shellcheck disable=SC2086
expect_eq "W26-5r: no shipped doctrine ends a suite capture in echo \"rc=\$?\" (the command would exit 0)" "" \
  "$(w26_hits "$W26_OLD_RECIPE" $W26_DOCTRINE)"
W26_D5R="$(w26_doctor "$W26_SURV" "set -o pipefail; <command> 2>&1 | tee \"\$LOG\"; $W26_OLD_RECIPE")"
expect_nonempty "W26-5rm: a survival.md that teaches the old capture recipe is caught" \
  "$(w26_hits "$W26_OLD_RECIPE" "$W26_D5R")"
# w26_pipestatus_outside_ban <file>… -> the files that name PIPESTATUS anywhere but the ban.
w26_pipestatus_outside_ban() {
  local f flat
  for f in "$@"; do
    flat="$(_flatten "$f")"; flat="${flat//never \`PIPESTATUS\`/}"
    case "$flat" in *PIPESTATUS*) printf '%s\n' "${f#"$REPO"/}" ;; esac
  done
}
# shellcheck disable=SC2086
expect_eq "W26-5p: …and no doctrine names PIPESTATUS except in that ban" "" \
  "$(w26_pipestatus_outside_ban $W26_DOCTRINE)"
W26_D5P="$(w26_doctor "$W26_SURV" 'echo "rc=${PIPESTATUS[0]}" >> "$LOG"')"
expect_nonempty "W26-5pm: a survival.md that teaches PIPESTATUS beside the ban is caught" \
  "$(w26_pipestatus_outside_ban "$W26_D5P")"
# shellcheck disable=SC2086
expect_eq "W26-5: AC-1.5 — no role file states a suite timeout of its own" "" \
  "$(w26_hits '600000 ms' $W26_ROLES)"
# shellcheck disable=SC2086
expect_eq "W26-5c: …and no shipped text gives the second capture recipe" "" \
  "$(w26_hits 'echo "rc=$?"; } > log 2>&1' $W26_DOCTRINE)"
W26_D5="$(w26_doctor "${REPO}/agents/test-runner.md" 'parameter set to 600000 ms')"
expect_nonempty "W26-5m: a test-runner.md that keeps \"600000 ms\" beside the 30-minute text is caught" \
  "$(w26_hits '600000 ms' "$W26_D5")"
# w26_count <ERE> <file> -> the lines of the file that match, as a number.
w26_count() { /usr/bin/grep -cE -- "$1" "$2" 2>/dev/null | tr -cd '0-9'; }
W26_CLOSE='SendMessage'
W26_FG='[Ff][Oo][Rr][Ee][Gg][Rr][Oo][Uu][Nn][Dd]'
# RE-SHAPED (wave-26 T20, review-2 F3): 5e/5g were exact-count pins on a word ("at most one
# line says SendMessage"), red the moment any text adds the word and blind to a duplicate
# phrased without it. They are now absences of the copies T1 cut, the shape of W26-5c.
W26_CLOSE_NONE=""; W26_FG_NONE=""
for _w26_r in $W26_ROLES; do
  _w26_c="$(w26_count "$W26_CLOSE" "$_w26_r")"; _w26_f="$(w26_count "$W26_FG" "$_w26_r")"
  [ "${_w26_c:-0}" -ge 1 ] || W26_CLOSE_NONE="$W26_CLOSE_NONE ${_w26_r##*/}"
  [ "${_w26_f:-0}" -ge 1 ] || W26_FG_NONE="$W26_FG_NONE ${_w26_r##*/}"
done
expect_eq "W26-5d precondition: every role file carries the closing-message duty (missing in:${W26_CLOSE_NONE:- none})" \
  "" "$W26_CLOSE_NONE"
# shellcheck disable=SC2086
expect_eq "W26-5e: …and no doctrine keeps the cut second copy of it" "" \
  "$(w26_hits 'Completion-by-artifact: your closing SendMessage' $W26_DOCTRINE)"
expect_eq "W26-5f precondition: every role file carries the foreground duty (missing in:${W26_FG_NONE:- none})" \
  "" "$W26_FG_NONE"
# shellcheck disable=SC2086
expect_eq "W26-5g: …and no doctrine keeps either cut second copy of it" "" \
  "$(w26_hits 'Suites run FOREGROUND' $W26_DOCTRINE; w26_hits 'Otherwise stay in the foreground' $W26_DOCTRINE)"
W26_D5E="$(w26_doctor "${REPO}/agents/implementor.md" '- Completion-by-artifact: your closing SendMessage names the artifact path(s) this task produced.')"
expect_nonempty "W26-5em: an implementor.md that keeps the second closing-message copy is caught" \
  "$(w26_hits 'Completion-by-artifact: your closing SendMessage' "$W26_D5E")"
W26_D5F="$(w26_doctor "${REPO}/agents/implementor.md" 'Suites run FOREGROUND with the Bash tool `timeout` parameter.')"
expect_nonempty "W26-5gm precondition: the doctored implementor.md still carries its dispatch rules" \
  "$(w26_hits 'DISPATCH-RULES-BEGIN' "$W26_D5F")"
expect_nonempty "W26-5gm: an implementor.md carrying the cut foreground copy is caught" \
  "$(w26_hits 'Suites run FOREGROUND' "$W26_D5F")"
W26_D5G="$(w26_doctor "$W26_SURV" 'Otherwise stay in the foreground and do not stop.')"
expect_nonempty "W26-5gn: a survival.md carrying the cut fallback foreground copy is caught" \
  "$(w26_hits 'Otherwise stay in the foreground' "$W26_D5G")"

# W26-6 (AC-1.6, and AC-1.4's doctrine half): no doctrine orders a step the tool already
# performs. Each absence sits beside a positive on the same file through the same extractor.
W26_PLANRULE="${REPO}/.claude/rules/plan-authoring.md"
expect_nonempty "W26-6 precondition: operational-rules.md reads (a kept heading)" \
  "$(w26_hits '## Permission answers' "$OPRULES")"
expect_eq "W26-6a: AC-1.6 — no skill re-invocation on resume" "" \
  "$(w26_hits 'Re-invocation after ANY resume' "$OPRULES")"
expect_eq "W26-6b: …and no probe dispatch, in operational-rules.md or dispatch.md" "" \
  "$(w26_hits 'healthy probe' "$OPRULES"; w26_hits 'throwaway dispatch carrying no deliverable' "$DISPATCH_MD")"
W26_D6="$(w26_doctor "$OPRULES" 'Re-invocation after ANY resume is standing practice, not a repair.')"
expect_nonempty "W26-6am: an operational-rules.md that keeps \"Re-invocation after ANY resume\" is caught" \
  "$(w26_hits 'Re-invocation after ANY resume' "$W26_D6")"
expect_nonempty "W26-6c precondition: plan-authoring.md reads (a kept rule)" \
  "$(w26_hits 'A tune target never blocks a wave' "$W26_PLANRULE")"
expect_eq "W26-6c: …no hand dry-run before a step advance" "" \
  "$(w26_hits 'pipe a synthetic commit payload' "$W26_PLANRULE")"
expect_nonempty "W26-6d precondition: dispatch.md reads (the ledger rule it keeps)" \
  "$(w26_hits 'Ledger the dispatch, not the return' "$DISPATCH_MD")"
expect_eq "W26-6d: …no reconcile at every turn end" "" \
  "$(w26_hits 'Before ending a turn, reconcile' "$DISPATCH_MD")"
# shellcheck disable=SC2086
expect_nonempty "W26-6e precondition: the role files read (the cd guard they keep)" \
  "$(w26_hits 'guards the WHOLE command' $W26_ROLES)"
# shellcheck disable=SC2086
expect_eq "W26-6e: …no writer enumerating suites beyond its own" "" \
  "$(w26_hits 'enumerated every test entry point' $W26_ROLES)"
expect_nonempty "W26-6f precondition: operational-rules.md keeps the refactor evidence key" \
  "$(w26_hits '`behavior-preservation:`' "$OPRULES")"
expect_eq "W26-6f: …no separate post run for a refactor" "" \
  "$(w26_hits 'baseline + post runs' "$OPRULES")"
expect_nonempty "W26-6g precondition: dispatch.md keeps the roster as the launch record" \
  "$(w26_hits 'is the authoritative launch record' "$DISPATCH_MD")"
expect_eq "W26-6g: AC-1.4 doctrine half — no hand task-set/ledger-add at dispatch" "" \
  "$(w26_hits '`ledger-add` as you dispatch it' "$DISPATCH_MD")"
expect_eq "W26-6h: …and no manual check of a deliverable the landing verdict found" "" \
  "$(w26_hits 'verify that the named artifact exists before believing the report' "$DISPATCH_MD")"

# ── §W26-7, W26-13, W26-14 (wave-26 T19; REQ-2 AC-2.1, REQ-7 AC-7.2/7.3, REQ-5's doc; D12, D13)
#
# WHAT THIS OWNS. The design is approved once, on the Step-2 card that closes the interview;
# Step 3 approves the plan and the matrix only; the planner cuts the plan for width; a run
# re-plans by verb on five named triggers; operational-rules.md documents the `reads` column
# and the `approve` and `proof-add` verbs. Every absence sits beside a positive through the
# same extractor on the same file, and a doctored copy proves each arm goes red when the old
# text is back or a needed clause is gone. HERMETIC: committed finals by path; copies in $TMP.

# W26-7 (AC-2.1): steps/2.md closes the interview on the card; no text approves the design at Step 3.
expect_nonempty "W26-7 precondition: steps/2.md carries the Step-2 card's question" \
  "$(w26_hits 'Do you approve this design?' "$STEP2_MD")"
expect_nonempty "W26-7: AC-2.1 — steps/2.md closes the interview by presenting the Step-2 card" \
  "$(w26_hits 'then present the Step-2 card below' "$STEP2_MD")"
expect_nonempty "W26-7b: …and names that card's approval the one approval of the design" \
  "$(w26_hits 'the one approval of the design' "$STEP2_MD")"
W26_T19_STEP3_DESIGN="approves design, plan, and matrix together
fails the Step-3 approval
approved at the Step-3 approval alongside everything else
the path the Step-3 approval display prints
the pointer is what the Step-3 approval display prints"
w26_t19_step3_design() {  # <file>… -> each file carrying any retired Step-3 design approval
  local n
  while IFS= read -r n; do
    # shellcheck disable=SC2068
    w26_hits "$n" $@
  done <<< "$W26_T19_STEP3_DESIGN"
}
# shellcheck disable=SC2086
expect_eq "W26-7c: …and no shipped doctrine approves the design at Step 3" "" \
  "$(w26_t19_step3_design $W26_DOCTRINE)"
W26_D7="$(w26_doctor "$STEP3_MD" 'The binding approval approves design, plan, and matrix together.')"
expect_nonempty "W26-7cm: a steps/3.md that approves the design again is caught" \
  "$(w26_t19_step3_design "$W26_D7")"
expect_eq "W26-7d: …and the design no longer goes back whole before the spec is written" "" \
  "$(w26_hits 'goes back whole' "$STEP2_MD")"
expect_nonempty "W26-7e precondition: Question 1 still approves the frame" \
  "$(w26_hits '**Question 1 approves the frame**' "$STEP2_MD")"
expect_eq "W26-7e: …and does not re-approve the problem and context Step 1 approved" "" \
  "$(w26_hits 'Context and Problem' "$STEP2_MD")"
W26_D7E="$(w26_doctor "$STEP2_MD" '**Question 1 approves the frame, Context and Problem first**; nothing is walked until it holds.')"
expect_nonempty "W26-7em: a steps/2.md whose Question 1 re-approves Context and Problem is caught" \
  "$(w26_hits 'Context and Problem' "$W26_D7E")"
expect_nonempty "W26-7f: steps/3.md says Step 3 approves the plan and the matrix only" \
  "$(w26_hits 'Step 3 approves the plan and the matrix only' "$STEP3_MD")"

# W26-13 (AC-7.2): steps/3.md carries both width instructions, not only the split.
W26_SPLIT='Split a task on the longest chain wherever it can be split'
W26_SHORT='gets one short first task'
expect_nonempty "W26-13: AC-7.2 — steps/3.md tells the planner to split the longest chain" \
  "$(w26_hits "$W26_SPLIT" "$STEP3_MD")"
expect_nonempty "W26-13b: …and gives a file two tasks write, when it cannot be merged, one short first task" \
  "$(w26_hits "$W26_SHORT" "$STEP3_MD")"
expect_nonempty "W26-13c: …and otherwise lets the two run side by side and reconcile on landing" \
  "$(w26_hits 'run side by side and reconcile on landing' "$STEP3_MD")"
expect_nonempty "W26-13d: …and a row declares a read only where another row writes it" \
  "$(w26_hits 'A row declares what it reads only where it reads what another row writes' "$STEP3_MD")"
W26_D13="$TMP/w26-step3-split-only.md"
sed "s/${W26_SHORT}//" "$STEP3_MD" > "$W26_D13" 2>/dev/null
expect_nonempty "W26-13m precondition: the split-only copy keeps the split instruction" \
  "$(w26_hits "$W26_SPLIT" "$W26_D13")"
expect_eq "W26-13m: …and a steps/3.md carrying only the split instruction is caught" "" \
  "$(w26_hits "$W26_SHORT" "$W26_D13")"

# W26-14 (AC-7.3): the five re-plan triggers and the verbs, in steps/3.md; the schema's doc in
# operational-rules.md.
W26_TRIGGERS='a finding, a red test, an approved scope change, a task overrunning its size, a report naming follow-up work'
expect_nonempty "W26-14: AC-7.3 — steps/3.md names the five re-plan triggers" \
  "$(w26_hits "$W26_TRIGGERS" "$STEP3_MD")"
expect_nonempty "W26-14b: …and re-plans by the verbs, never by editing the table by hand" \
  "$(w26_hits '`task-add` and `task-set`, never by editing the table by hand' "$STEP3_MD")"
W26_D14="$TMP/w26-step3-four-triggers.md"
sed 's/a red test, //' "$STEP3_MD" > "$W26_D14" 2>/dev/null
expect_nonempty "W26-14m precondition: the four-trigger copy keeps the verbs" \
  "$(w26_hits '`task-add` and `task-set`' "$W26_D14")"
expect_eq "W26-14m: …and a steps/3.md missing one trigger is caught" "" \
  "$(w26_hits "$W26_TRIGGERS" "$W26_D14")"
for _w26_iface in \
  'comma-separated: a path in the `Files` grammar · `head` · `record` · `proof:<kind>` · `approval:<name>` · `ext:<slug>`; a live read is `live:<artifact>`; empty takes the kind default' \
  'build `approval:plan` · verify `approval:plan, head` · review `approval:plan, live:head` · doc `approval:plan, head`, and at Step 7 or later an `approval:` read written out (`approval:release` for the release) · integrate `proof:floor, proof:review, head` · close the integrate row'"'"'s merge' \
  'a table without it reads each id as "wait for that task to land"' \
  'a `Files` entry ending in `!`' \
  'session-poker.sh approve <name> '"'"'<reply>'"'"'' \
  'approved: <name> by <who> <ISO-UTC> "<reply>"' \
  'session-poker.sh proof-add <kind> <evidence path>' \
  'proved: kind=<floor\|review\|task\|check> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>' \
  '`release-check: <command>` in `.bionic/config.yaml`; run with `BIONIC_CHECK_BASE` and `BIONIC_CHECK_HEAD` in its environment; exit 0 passes' \
  '`session-poker.sh release-check`' \
  '`record/<wave>/release-check-<head>.log`, its first line `head=<40-hex> rc=0`' \
  'refuses `why=release-check`' \
  'a reading adds ` question=<q> reader=<roster name> result=<pass\|flag\|fail> scope=<piece\|whole>`' \
  'session-poker.sh proof-add review <record> --question <q> --reader <name>' \
  'flush-left lines `reviewed: <a>..<b>`, `question: <q>`, `result: <pass\|flag\|fail>`, `scope: <piece\|whole>`; for `structure`, one line `check: <id> <PASS\|FLAG\|FAIL\|n/a> <reason>` per check id'; do
  expect_nonempty "W26-14c: REQ-5 — operational-rules.md documents: ${_w26_iface%%;*}" \
    "$(w26_hits "$_w26_iface" "$OPRULES")"
done

# ============================================================
# W26-15 (wave-26 T21, AC-8.2): the rule for test authors — no exact count of things in the
# shipped tree — is written in the test-harness rules file, with both allowed forms.
# ============================================================
W26_15_RULES="${REPO}/.claude/rules/test-harness.md"
W26_15_SENTENCE='No test pins an exact count of things in the shipped tree.'
W26_15_REL='**A relation.**'
W26_15_CEIL='**A ceiling.**'
W26_15_OWN='exact number is fine when the number IS the behaviour'
expect_nonempty "W26-15 precondition: the extractor reads the rules file (it carries its Anti-vacuity heading)" \
  "$(w26_hits '## Anti-vacuity' "$W26_15_RULES")"
expect_nonempty "W26-15: AC-8.2 — test-harness.md states the rule" \
  "$(w26_hits "$W26_15_SENTENCE" "$W26_15_RULES")"
expect_nonempty "W26-15b: …and names the relation form" "$(w26_hits "$W26_15_REL" "$W26_15_RULES")"
expect_nonempty "W26-15c: …and names the ceiling form" "$(w26_hits "$W26_15_CEIL" "$W26_15_RULES")"
expect_nonempty "W26-15d: …and says when an exact number stands" "$(w26_hits "$W26_15_OWN" "$W26_15_RULES")"
anchor "$W26_15_RULES" "$W26_15_CEIL" 1
DOCTORED_W26_15="$TMP/w26-15-no-ceiling.md"
grep -vF -- "$W26_15_CEIL" "$W26_15_RULES" > "$DOCTORED_W26_15" 2>/dev/null
expect_nonempty "W26-15m precondition: the doctored copy keeps the rule's sentence" \
  "$(w26_hits "$W26_15_SENTENCE" "$DOCTORED_W26_15")"
expect_eq "W26-15m: …and a rules file naming no ceiling form is caught" "" \
  "$(w26_hits "$W26_15_CEIL" "$DOCTORED_W26_15")"

section "Section W26b: wave-26 T20 — one moment for the full run, the minimal forms (REQ-3 AC-3.1 static, AC-3.6; REQ-4 AC-4.2, 4.3, 4.4; D15)"
#
# WHAT THIS OWNS. The doctrine names one moment for the full suite (the head being released),
# drops every order to run it to land or to commit, models the shortest landed line the commit
# gate accepts, lets a report cite a saved log, and marks the scaffold's progress lines as
# needed from fifteen minutes. Each absence sits beside a positive on the same extractor and
# file; a doctored copy proves the arm goes red when the old text is back. HERMETIC.
W26_CLAUDE="${REPO}/CLAUDE.md"
W26_STEP4="${SKILL_DIR}/steps/4.md"
W26_STEP5="${SKILL_DIR}/steps/5.md"
W26_CORE="${SKILL_DIR}/SKILL.md"
W26_MOMENT='The full suite runs once, on the head being released; after that pass a later change is proved by its affected suites, and a second full run is needed only when the change cannot be bounded'

# W26-8 (AC-3.1 static): no doctrine requires a full run to land or to commit.
expect_nonempty "W26-8 precondition: the dispatch terms still name the full-suite runner" \
  "$(w26_hits 'tests/run.sh' "$W26_SURV")"
# shellcheck disable=SC2086
expect_eq "W26-8: AC-3.1 — no doctrine gives the full run to a Step-5 runner row" "" \
  "$(w26_hits 'belongs to the Step-5 runner' $W26_DOCTRINE)"
expect_eq "W26-8a: …and dispatch.md keeps no one-row-per-run order for it" "" \
  "$(w26_hits 'belongs on one row per run' "$DISPATCH_MD")"
expect_nonempty "W26-8b: the dispatch terms say a task lands on its affected suites" \
  "$(w26_hits 'A task lands on the suites its change affects.' "$W26_SURV")"
W26_D8="$(w26_doctor "$W26_SURV" 'one full-tree regression per run belongs to the Step-5 runner, not to a writer')"
expect_nonempty "W26-8m: a survival.md that keeps the Step-5 runner order is caught" \
  "$(w26_hits 'belongs to the Step-5 runner' "$W26_D8")"
# The no-ceremony rule lives in the orchestrator's doctrine and nowhere a writer reads.
W26_RULE='earns its place only if it can fail in a way nothing already run can'
expect_nonempty "W26-8c: the skill core carries the no-ceremony rule" "$(w26_hits "$W26_RULE" "$W26_CORE")"
# shellcheck disable=SC2086
expect_eq "W26-8d: …and no role file carries it" "" "$(w26_hits "$W26_RULE" $W26_ROLES)"
expect_nonempty "W26-8r precondition: the resume ritual still runs adopt" \
  "$(w26_hits 'session-poker.sh adopt` before its first dispatch' "$DISPATCH_MD")"
expect_eq "W26-8r: …and orders no second hand ledger of what adopt prints" "" \
  "$(w26_hits 'Ledger every row it prints' "$DISPATCH_MD")"
# The patrol prompt's last bullet continues the run only when something is ready or changed.
expect_nonempty "W26-8w: dispatch.md says a WAITING or unchanged tick owes nothing" \
  "$(w26_hits 'A `poker: WAITING` or unchanged tick owes nothing' "$DISPATCH_MD")"
expect_eq "W26-8x: …and no longer continues after every tick unconditionally" "" \
  "$(w26_hits 'Then continue toward the goal until a wall.' "$DISPATCH_MD")"

# W26-9 (AC-3.6): one moment, the same words, in every place that names the full run.
for _w26_f in "$W26_STEP5" "$W26_SURV" "$DISPATCH_MD" "$W26_CLAUDE"; do
  expect_nonempty "W26-9: AC-3.6 — ${_w26_f#"$REPO"/} names the released head as the full run's moment" \
    "$(w26_hits "$W26_MOMENT" "$_w26_f")"
done
# shellcheck disable=SC2086
expect_eq "W26-9a: …and no doctrine or CLAUDE.md says \"integration close\"" "" \
  "$(w26_hits 'integration close' $W26_DOCTRINE "$W26_CLAUDE")"
# shellcheck disable=SC2086
expect_eq "W26-9b: …or \"before any commit\"" "" \
  "$(w26_hits 'before any commit' $W26_DOCTRINE "$W26_CLAUDE")"
# shellcheck disable=SC2086
expect_eq "W26-9c: …or a regression-cause line" "" \
  "$(w26_hits 'regression-cause' $W26_DOCTRINE "$W26_CLAUDE")"
expect_eq "W26-9d: …and Step 5 runs no whole-suite floor on every change" "" \
  "$(w26_hits 'whole-suite floor' "$W26_STEP5")"
expect_nonempty "W26-9e: CLAUDE.md asks only the affected suites before a commit" \
  "$(w26_hits 'Before a commit, the suites the change affects are green.' "$W26_CLAUDE")"
W26_D9="$(w26_doctor "$W26_CLAUDE" 'Must be green before any commit.')"
expect_nonempty "W26-9m: a CLAUDE.md that keeps \"before any commit\" is caught" \
  "$(w26_hits 'before any commit' "$W26_D9")"

# W26-9h..9k (AC-3.6, the hooks' half; wave-26 T5): the full-run refusals in the dispatch wall
# and the Bash wall name the released head, and nothing in hooks/ or payload/scripts/ says
# "integration close" or offers a regression-cause: line as the fix. The absence rows read the
# same file list the precondition proves the extractor finds the new wording in.
W26_DP_HOOK="${REPO}/hooks/dispatch-preflight.sh"
W26_HOOK_MOMENT='The full suite runs once, on the head being released'
for _w26_f in "$W26_DP_HOOK" "${REPO}/payload/scripts/lib/walls.sh"; do
  expect_nonempty "W26-9h: ${_w26_f#"$REPO"/} names the released head as the full run's moment" \
    "$(w26_hits "$W26_HOOK_MOMENT" "$_w26_f")"
done
W26_CODE="$(/usr/bin/find "${REPO}/hooks" "${REPO}/payload/scripts" -type f 2>/dev/null | sort)"
# shellcheck disable=SC2086
expect_nonempty "W26-9i precondition: the code scan reads files that carry the released-head wording" \
  "$(w26_hits "$W26_HOOK_MOMENT" $W26_CODE)"
# shellcheck disable=SC2086
expect_eq "W26-9i: no hook or script says \"integration close\"" "" \
  "$(w26_hits 'integration close' $W26_CODE)"
# shellcheck disable=SC2086
expect_eq "W26-9j: …or names a regression-cause line" "" \
  "$(w26_hits 'regression-cause' $W26_CODE)"
anchor "$W26_DP_HOOK" "$W26_HOOK_MOMENT" 1
DOCTORED_W26_HOOK="$TMP/w26-dispatch-preflight-doctored.sh"
sed 's/on the head being released/at integration close/' "$W26_DP_HOOK" > "$DOCTORED_W26_HOOK"
expect_nonempty "W26-9k: a dispatch wall that says \"integration close\" again is caught" \
  "$(w26_hits 'integration close' "$DOCTORED_W26_HOOK")"

# W26-10 (AC-4.2): the shortest landed line is modelled, and it passes the gate's own check.
# The shape check is the gate's function, lifted out of walls.sh, never a copy of its rule.
W26_PROOF_FN="$(/usr/bin/awk '/^is_proof_shaped\(\) \{/ { on = 1 } on { print } on && /^\}/ { exit }' \
  "${REPO}/payload/scripts/lib/walls.sh" 2>/dev/null)"
expect_nonempty "W26-10 precondition: the gate's is_proof_shaped is readable from walls.sh" "$W26_PROOF_FN"
w26_shaped() { ( eval "$W26_PROOF_FN"; is_proof_shaped "$1" ) >/dev/null 2>&1 && echo yes || echo no; }
W26_LINE="$(/usr/bin/grep -o '`- T[0-9][0-9]*: [^`]*`' "$W26_STEP4" 2>/dev/null | head -1 | tr -d '`')"
expect_nonempty "W26-10: AC-4.2 — steps/4.md carries a one-line \`- T<n>:\` example" "$W26_LINE"
expect_true "W26-10a: …of 80 characters or fewer" test "${#W26_LINE}" -le 80 -a "${#W26_LINE}" -gt 0
expect_eq "W26-10b: …that the commit gate's shape check accepts" "yes" "$(w26_shaped "${W26_LINE#*: }")"
expect_true "W26-10c: …and that names the auditor verdict a done row owes at peer-reviewed rigor" \
  /usr/bin/grep -Ewq 'auditor' <<< "$W26_LINE"
expect_eq "W26-10m: a prose line is refused by the same check (the check discriminates)" "no" \
  "$(w26_shaped 'done, all green')"
W26_S0="$(/usr/bin/grep -m1 '^\*\*Evidence:\*\* `Step 0:' "$STEP0_MD" 2>/dev/null)"
expect_nonempty "W26-10d precondition: steps/0.md carries the Step-0 evidence template" "$W26_S0"
expect_absent "W26-10d: …which does not repeat the frontmatter's integration branch" "integration-branch=" "$W26_S0"
expect_absent "W26-10e: …or its parallel budget" "parallel-budget=" "$W26_S0"

# W26-11 (AC-4.3): a report may cite a saved log in place of pasted output.
W26_RC_OLD="carries the command that proves it and that command's output, or the explicit label"
for _w26_f in $W26_ROLES "$DISPATCH_MD"; do
  expect_nonempty "W26-11: AC-4.3 — ${_w26_f#"$REPO"/} names a saved log as proof" \
    "$(w26_hits 'the path of a saved log' "$_w26_f")"
  expect_eq "W26-11a: …and ${_w26_f#"$REPO"/} no longer asks for pasted output alone" "" \
    "$(w26_hits "$W26_RC_OLD" "$_w26_f")"
done
# shellcheck disable=SC2086
expect_eq "W26-11b: …and no surface makes every unverified label a re-check" "" \
  "$(w26_hits 'obligates the orchestrator to re-check before' $W26_ROLES "$DISPATCH_MD")"
W26_D11="$(w26_doctor "${REPO}/agents/researcher.md" "Every claim carries the command that proves it and that command's output, or the explicit label \`unverified\`.")"
expect_nonempty "W26-11m: a role file that keeps the pasted-output form is caught" \
  "$(w26_hits "that command's output, or the explicit label" "$W26_D11")"

# W26-12 (AC-4.4): both scaffold lines carry the fifteen-minute mark on every surface — the
# six role files (the reader block), dispatch.md and SKILL.md (the author block).
W26_MARK='(tasks of 15 min or more)'
w26_label_line() { /usr/bin/grep -m1 "^$1:" "$2" 2>/dev/null; }
for _w26_f in $W26_ROLES "$DISPATCH_MD" "$W26_CORE"; do
  for _w26_l in 'Progress artifact' 'Cadence'; do
    _w26_v="$(w26_label_line "$_w26_l" "$_w26_f")"
    expect_nonempty "W26-12 precondition: ${_w26_f#"$REPO"/} has its ${_w26_l}: line" "$_w26_v"
    expect_contains "W26-12: AC-4.4 — ${_w26_f#"$REPO"/} marks ${_w26_l}: as needed from 15 minutes" \
      "$W26_MARK" "$_w26_v"
  done
done
_w26_body="$(cat "${REPO}/agents/auditor.md" 2>/dev/null)"
anchor "${REPO}/agents/auditor.md" "$W26_MARK" 2
DOCTORED_W26_12="$TMP/w26-12-doctored.md"
printf '%s\n' "${_w26_body// "$W26_MARK"/}" > "$DOCTORED_W26_12"
expect_nonempty "W26-12m precondition: the doctored auditor.md still has its Cadence: line" \
  "$(w26_label_line 'Cadence' "$DOCTORED_W26_12")"
expect_absent "W26-12m: a role file whose Cadence: line lost the mark is caught" \
  "$W26_MARK" "$(w26_label_line 'Cadence' "$DOCTORED_W26_12")"

# ── §W26-T57 (wave-26 final review S1, S2, N4): three doctrine sentences made true to the code ──
#
# WHAT THIS OWNS. S1: the `proof verb` row names the head the evidence attests, not the
# checkout's HEAD. S2: steps/5.md tells the orchestrator to record the floor proof after the
# full run. N4: dispatch.md says only a passing disturbed run is `void`. Each absence sits
# beside a positive through the same extractor on the same file, and a doctored copy that has
# the old text back proves the absence arm goes red. HERMETIC: committed finals; copies in $TMP.
W26_T57_S1_NEW='the head the evidence names: a run log'"'"'s `head=` header, a review'"'"'s `reviewed: a..b` end; never an operand'
W26_T57_S1_OLD='the head is `git rev-parse HEAD` of the working branch'"'"'s checkout'
expect_nonempty "W26-T57a: S1 — the proof verb row names the head the evidence attests" \
  "$(w26_hits "$W26_T57_S1_NEW" "$OPRULES")"
expect_eq "W26-T57b: …and no longer calls it the checkout's HEAD" "" \
  "$(w26_hits "$W26_T57_S1_OLD" "$OPRULES")"
W26_T57_D1="$(w26_doctor "$OPRULES" "| proof verb | \`session-poker.sh proof-add <kind> <evidence path>\`; $W26_T57_S1_OLD, never an operand |")"
expect_nonempty "W26-T57bm: an operational-rules.md that keeps the checkout-HEAD sentence is caught" \
  "$(w26_hits "$W26_T57_S1_OLD" "$W26_T57_D1")"
expect_nonempty "W26-T57c: S2 — steps/5.md tells the orchestrator to record the floor proof" \
  "$(w26_hits 'then record it: `session-poker.sh proof-add floor <log>`' "$STEP5_MD")"
W26_T57_N4_NEW='a disturbed passing run reports `void`; a failing one is a failure'
expect_nonempty "W26-T57d: N4 — dispatch.md says a disturbed passing run is void and a failing one a failure" \
  "$(w26_hits "$W26_T57_N4_NEW" "$DISPATCH_MD")"
expect_eq "W26-T57e: …and no longer says a disturbed run is never a failure" "" \
  "$(w26_hits 'not a failure, when the machine was disturbed' "$DISPATCH_MD")"
W26_T57_D4="$(w26_doctor "$DISPATCH_MD" 'It reports `void`, not a failure, when the machine was disturbed.')"
expect_nonempty "W26-T57em: a dispatch.md that keeps the old void sentence is caught" \
  "$(w26_hits 'not a failure, when the machine was disturbed' "$W26_T57_D4")"

# ── §W27-111 / §W27-112 (wave-27 T13, REQ-11 AC-11.1, AC-11.2; D20): the task list is rebuilt at plan approval ──
#
# WHAT THIS OWNS. The approval block of steps/3.md carries the delete-and-recreate rule, the
# `task-add` paragraph names the entry a new row gets and the recreated order, and steps/0.md's
# format section points to Step 3. Each absence sits beside a positive through the same
# extractor (`w26_hits`, a whitespace-normalised fixed-string find) on the same file, and a
# doctored copy that has the old text back proves the pin goes red. HERMETIC: committed finals.
W27_111_RULE='On approval, rebuild the task list from the plan before the first dispatch: delete every pending entry and recreate them in execution order'
W27_111_ORDER='in the order the Step-3 card'"'"'s batches print'
W27_111_APPEND='The task tool appends, so adding entries without recreating the later ones leaves the list out of order.'
W27_111_PROGRESS="Mark a row's entry in progress in the turn it is dispatched."
expect_nonempty "W27-111 precondition: the extractor finds the approval line on steps/3.md" \
  "$(w26_hits 'approved-by: <user> <ISO-UTC>' "$STEP3_MD")"
expect_nonempty "W27-111: AC-11.1 — steps/3.md carries the delete-and-recreate rule at approval" \
  "$(w26_hits "$W27_111_RULE" "$STEP3_MD")"
expect_nonempty "W27-111a: …in the card's batch order, naming one entry per ## Tasks row" \
  "$(w26_hits "$W27_111_ORDER" "$STEP3_MD")"
expect_nonempty "W27-111b: …and why the later entries are recreated" \
  "$(w26_hits "$W27_111_APPEND" "$STEP3_MD")"
expect_nonempty "W27-111c: …and marks a row's entry in progress when it is dispatched" \
  "$(w26_hits "$W27_111_PROGRESS" "$STEP3_MD")"
expect_nonempty "W27-111d: …and it sits after the approved-by block, before the card" \
  "$(awk '/^approved-by: <user>/ { a = 1 } a && /On approval, rebuild the task list/ { r = 1 } r && /^Step 3 · Plan/ { print "ok"; exit } /^Step 3 · Plan/ { exit }' "$STEP3_MD")"
expect_nonempty "W27-111e: steps/0.md's format section points to it" \
  "$(w26_hits 'The per-task expansion happens at plan approval; see Step 3.' "$STEP0_MD")"
expect_nonempty "W27-112: AC-11.2 — the task-add paragraph says a new row gets its task-list entry the same turn" \
  "$(w26_hits 'A row added by `task-add` gets its task-list entry the same turn, and the entries after it are recreated to keep the order.' "$STEP3_MD")"
expect_nonempty "W27-112a: …inside the paragraph that locks the wave shape at approval" \
  "$(awk '/Wave shape locks at approval/ { p = 1 } p && /gets its task-list entry the same turn/ { print "ok"; exit }' "$STEP3_MD")"
section "Section W27-reuse: wave-27 T12 — a writer looks for an existing site first, and a design names what it reuses (REQ-4 AC-4.1, AC-4.2; D8)"
#
# WHAT THIS OWNS. §W27-41: the implementor-mechanics block, and so both writer role files, carry
# the search duty and the `reuse:` report line in both of its forms. §W27-42: the Step-2 ownership
# line and the operational-rules exemplar carry the `reuses` column, in the one column order.
# Each pin sits beside a doctored copy with the text gone, which proves the arm goes red. HERMETIC.
W27_DUTY='before adding a function, file, type or configuration key, search for an existing site that does the job'
W27_LINE_A="\`reuse: searched '<pattern>' in <paths> · reused <site>\`"
W27_LINE_B="\`reuse: searched '<pattern>' in <paths> · none fits: <why>\`"
W27_BLOCK="${REPO}/agents-src/blocks/implementor-mechanics.md"
for _w27_f in "$W27_BLOCK" "${REPO}/agents/implementor.md" "${REPO}/agents/senior-implementor.md"; do
  _w27_n="${_w27_f#"$REPO"/}"
  expect_nonempty "W27-41a: $_w27_n carries the search duty" "$(w26_hits "$W27_DUTY" "$_w27_f")"
  expect_nonempty "W27-41b: $_w27_n carries the reused form of the reuse: line" "$(w26_hits "$W27_LINE_A" "$_w27_f")"
  expect_nonempty "W27-41c: $_w27_n carries the none-fits form of the reuse: line" "$(w26_hits "$W27_LINE_B" "$_w27_f")"
done
for _w27_f in "${REPO}/agents/auditor.md" "${REPO}/agents/researcher.md"; do
  expect_eq "W27-41d: ${_w27_f#"$REPO"/}, which writes no code, carries no search duty" "" "$(w26_hits "$W27_DUTY" "$_w27_f")"
done
W27_DOC41="$TMP/w27-41-doctored.md"
tr '\n' ' ' < "$W27_BLOCK" | sed 's/search[[:space:]]*for[[:space:]]*an existing site that does the job/search/' > "$W27_DOC41"
expect_eq "W27-41m: a block that lost the search duty is caught" "" "$(w26_hits "$W27_DUTY" "$W27_DOC41")"
expect_nonempty "W27-41mp precondition: the doctored block still carries the reuse: line" "$(w26_hits "$W27_LINE_A" "$W27_DOC41")"

W27_COLS='`concept → owning module (SSoT) → reuses → rendering surfaces → agreement test`'
W27_GLOSS='`reuses` names the existing site reused, or `none fits: <why>`'
W27_HDR='| concept | owning module (SSoT) | reuses | rendering surfaces | agreement test |'
expect_nonempty "W27-42a: steps/2.md's ownership line carries the reuses column in order" "$(w26_hits "$W27_COLS" "$STEP2_MD")"
expect_nonempty "W27-42b: …and says what the cell holds" "$(w26_hits "$W27_GLOSS" "$STEP2_MD")"
expect_nonempty "W27-42c: operational-rules.md's exemplar header carries the reuses column" "$(w26_hits "$W27_HDR" "$OPRULES")"
expect_nonempty "W27-42d: …and an exemplar row names a reused site or none fits" "$(w26_hits '| none fits:' "$OPRULES")"
W27_DOC42="$TMP/w27-42-doctored.md"
sed 's/ → reuses → / → /' "$STEP2_MD" > "$W27_DOC42"
expect_eq "W27-42m: a steps/2.md whose ownership line lost the column is caught" "" "$(w26_hits "$W27_COLS" "$W27_DOC42")"
expect_nonempty "W27-42mp precondition: the doctored copy still carries the ownership line" \
  "$(w26_hits '**Ownership table** — `concept → owning module (SSoT) → rendering surfaces → agreement test`' "$W27_DOC42")"

# ── §W27-T8 (wave-27 T8; REQ-3 AC-3.2, REQ-4 AC-4.3/4.4, REQ-1 AC-1.6, REQ-5 AC-5.1; D5, D9, D10) ──
#
# WHAT THIS OWNS. The three checks files a reader is pushed at start, one per reading question,
# each rendered from its block. Pinned here: each fits its cap; the rendered span is its block;
# every structure check id carries its failing case; no id is named in two files (the file half
# of §W27-32 — the role-file half is the reader-roles row's); the two code files end their checks
# with the whole-read section and its "not a second read" sentence (§W27-6); the evidence file is
# the auditor mandate and the adversarial file the critic template, minus the self-review notes and
# plus the sentence that the reader sees no other verdict. Each absence sits beside a positive on
# the same extractor and file, and a doctored copy proves each arm goes red. HERMETIC: committed
# finals by path; doctored copies under $TMP.
W27_CHECKS_DIR="${REPO}/payload/context"
W27_STRUCT="${W27_CHECKS_DIR}/checks-structure.md"
W27_QUESTIONS="evidence adversarial structure"
W27_IDS="reuse one-site single-job open-closed substitution narrow-interface dependency-direction"
W27_CAP=4500
W27_WHOLE='this is not a second read of each piece'
# w27_ids_in <file> -> the structure check ids the file names as whole words, one per line.
w27_ids_in() {
  local id
  for id in $W27_IDS; do _flatten "$1" | grep -qwF -- "$id" && printf '%s\n' "$id"; done
}
# w27_check_line <file> <id> -> the file's check line for the id, in the interface form.
w27_check_line() { grep -F -- "- **$2** — " "$1" 2>/dev/null | head -1; }
# w27_cap_verdict <file> -> "within" when the file is at most the cap, "over" when past it or unreadable.
w27_cap_verdict() {
  local n; n="$(wc -c < "$1" 2>/dev/null | tr -cd '0-9')"
  if [ "${n:-99999}" -le "$W27_CAP" ]; then printf 'within'; else printf 'over'; fi
}
# w27_record_form <file> -> the lines of the fenced block in the file's last section, when that
# section is `## The record`; nothing when another section follows it.
w27_record_form() {
  awk '/^## / { last = $0; body = ""; fence = 0; next }
       last == "## The record" && /^```/ { fence = !fence; next }
       last == "## The record" && fence { body = body $0 "\n" }
       END { if (last == "## The record") printf "%s", body }' "$1" 2>/dev/null
}
# w27_form_want <question> -> the record form the Interfaces table gives that question, in order.
w27_form_want() {
  printf 'reviewed: <a>..<b>\nquestion: %s\nresult: <pass|flag|fail>\nscope: <piece|whole>' "$1"
  [ "$1" = structure ] && printf '\ncheck: <id> <PASS|FLAG|FAIL|n/a> <reason>'
  return 0
}

for _q in $W27_QUESTIONS; do
  _f="${W27_CHECKS_DIR}/checks-${_q}.md"
  _bytes="$(wc -c < "$_f" 2>/dev/null | tr -cd '0-9')"
  expect_true "W27-T8a: AC-5.1 — payload/context/checks-${_q}.md is rendered and non-empty" test -s "$_f"
  expect_eq "W27-T8b: …and fits the ${W27_CAP}-byte cap (${_bytes:-missing} B)" "within" "$(w27_cap_verdict "$_f")"
  _upper="$(printf 'checks-%s' "$_q" | tr '[:lower:]' '[:upper:]')"
  same_everywhere "W27-T8c-${_q}" "the ${_q} checks are one text in the block and the rendered file" \
    "${BLOCK_DIR}/checks-${_q}.md" "$_upper" "$_f"
  expect_eq "W27-T8d: …and the file ends with the record form, every line in order" \
    "$(w27_form_want "$_q")" "$(w27_record_form "$_f")"
done
# W27-T8bm: the cap verdict T8b reads, at the boundary. The sizes are the Interfaces table's
# 4,500 bytes typed here, not read from W27_CAP, so a raised cap or a removed check goes red.
W27_AT_CAP="$TMP/w27-at-cap.md"; W27_PAST_CAP="$TMP/w27-past-cap.md"
head -c 4500 /dev/zero | tr '\0' 'x' > "$W27_AT_CAP"
head -c 4501 /dev/zero | tr '\0' 'x' > "$W27_PAST_CAP"
expect_eq "W27-T8bm precondition: a file of exactly 4,500 bytes reads within the cap" "within" "$(w27_cap_verdict "$W27_AT_CAP")"
expect_eq "W27-T8bm: a file of 4,501 bytes, one past the cap, is caught" "over" "$(w27_cap_verdict "$W27_PAST_CAP")"
# W27-T8dm: the record form cut, reordered, or followed by another section is caught.
W27_FORM_CUT="$TMP/w27-form-cut.md"; W27_FORM_SWAP="$TMP/w27-form-swap.md"; W27_FORM_TAIL="$TMP/w27-form-tail.md"
anchor "$W27_STRUCT" 'scope: <piece|whole>' 1
grep -vxF 'scope: <piece|whole>' "$W27_STRUCT" > "$W27_FORM_CUT" 2>/dev/null
awk '$0 == "result: <pass|flag|fail>" { held = $0; next } { print } held != "" && $0 == "scope: <piece|whole>" { print held; held = "" }' \
  "$W27_STRUCT" > "$W27_FORM_SWAP" 2>/dev/null
{ cat "$W27_STRUCT"; printf '\n## Notes\n\nAnything.\n'; } > "$W27_FORM_TAIL" 2>/dev/null
expect_nonempty "W27-T8dm precondition: the cut copy still has a record form" "$(w27_record_form "$W27_FORM_CUT")"
expect_ne "W27-T8dm: a record form with its scope line cut is caught" "$(w27_form_want structure)" "$(w27_record_form "$W27_FORM_CUT")"
expect_nonempty "W27-T8dm precondition: the reordered copy still has a record form" "$(w27_record_form "$W27_FORM_SWAP")"
expect_ne "W27-T8dm: a record form with result and scope swapped is caught" "$(w27_form_want structure)" "$(w27_record_form "$W27_FORM_SWAP")"
expect_ne "W27-T8dm: a record section followed by another section is caught" "$(w27_form_want structure)" "$(w27_record_form "$W27_FORM_TAIL")"

# AC-4.3 text half: every structure id has its check line, and the line names its failing case.
for _id in $W27_IDS; do
  _line="$(w27_check_line "$W27_STRUCT" "$_id")"
  expect_nonempty "W27-T8e: checks-structure.md carries the \`${_id}\` check in the interface form" "$_line"
  expect_contains "W27-T8f: …and its line names the case it fails on" "Fails when " "$_line"
done
W27_NOFAIL="$TMP/w27-nofail.md"
anchor "$W27_STRUCT" '- **single-job** — ' 1
sed '/^- \*\*single-job\*\* — /s/Fails when /Wrong when /' "$W27_STRUCT" > "$W27_NOFAIL" 2>/dev/null
expect_nonempty "W27-T8fm precondition: the doctored copy still has the single-job line" \
  "$(w27_check_line "$W27_NOFAIL" single-job)"
expect_absent "W27-T8fm: a single-job line with no failing case is caught" \
  "Fails when " "$(w27_check_line "$W27_NOFAIL" single-job)"
expect_contains "W27-T8g: the structure record form has one check line per id" \
  'check: <id> <PASS|FLAG|FAIL|n/a> <reason>' "$(cat "$W27_STRUCT" 2>/dev/null)"
expect_contains "W27-T8h: AC-4.4 text half — with no design table, the reader searches the codebase" \
  'search the codebase' "$(_flatten "$W27_STRUCT")"
expect_contains "W27-T8i: the agreement-test duty sits under one-site" \
  'A pair with no named test is a FLAG' "$(_flatten "$W27_STRUCT")"

# §W27-32, file half (AC-3.2): each id is named in exactly one checks file, the structure one.
for _id in $W27_IDS; do
  _homes=""
  for _q in $W27_QUESTIONS; do
    # Captured first: `grep -q` on a live pipe closes it early, and under pipefail the
    # writer's SIGPIPE fails the match.
    _named="$(w27_ids_in "${W27_CHECKS_DIR}/checks-${_q}.md")"
    printf '%s\n' "$_named" | grep -xF -- "$_id" >/dev/null && _homes="${_homes} checks-${_q}.md"
  done
  expect_eq "W27-32: AC-3.2 — \`${_id}\` is named in one checks file only" " checks-structure.md" "$_homes"
done
W27_ADV_DOCTORED="$(w26_doctor "${W27_CHECKS_DIR}/checks-adversarial.md" 'Also ask whether one-site holds.')"
expect_contains "W27-32m: a checks-adversarial.md that names one-site is caught" \
  "one-site" "$(w27_ids_in "$W27_ADV_DOCTORED")"

# §W27-6 (AC-1.6 text half): the two code files end with the whole read; the evidence file has none.
for _q in adversarial structure; do
  _f="${W27_CHECKS_DIR}/checks-${_q}.md"
  expect_contains "W27-6: AC-1.6 — checks-${_q}.md has its whole-read section" \
    '## A whole read' "$(cat "$_f" 2>/dev/null)"
  expect_nonempty "W27-6b: …saying the whole read is not a second read of each piece" \
    "$(w26_hits "$W27_WHOLE" "$_f")"
done
expect_contains "W27-6c precondition: checks-evidence.md has its record section" \
  'question: evidence' "$(cat "${W27_CHECKS_DIR}/checks-evidence.md" 2>/dev/null)"
expect_absent "W27-6c: …and no whole read: evidence is not a code question" \
  '## A whole read' "$(cat "${W27_CHECKS_DIR}/checks-evidence.md" 2>/dev/null)"
W27_NOWHOLE="$TMP/w27-nowhole.md"
anchor "${W27_CHECKS_DIR}/checks-structure.md" "$W27_WHOLE" 1
sed "s/$W27_WHOLE/it may also re-read each piece/" "$W27_STRUCT" > "$W27_NOWHOLE" 2>/dev/null
expect_contains "W27-6m precondition: the doctored copy keeps its whole-read section" \
  '## A whole read' "$(cat "$W27_NOWHOLE" 2>/dev/null)"
expect_eq "W27-6m: a whole read that drops the sentence is caught" "" "$(w26_hits "$W27_WHOLE" "$W27_NOWHOLE")"

# The moved texts: evidence is the auditor mandate; adversarial is the critic template, edited twice.
W27_EVID="${W27_CHECKS_DIR}/checks-evidence.md"
W27_ADV="${W27_CHECKS_DIR}/checks-adversarial.md"
expect_nonempty "W27-T8j: checks-evidence.md opens the auditor mandate" \
  "$(w26_hits "Your job is to falsify the claim that this wave's requirements were faithfully implemented **and proven**" "$W27_EVID")"
expect_nonempty "W27-T8j2: …and closes it" \
  "$(w26_hits 'a factual claim carrying neither its proving command with output nor the label "unverified" is itself a finding.' "$W27_EVID")"
expect_nonempty "W27-T8k: checks-adversarial.md carries the critic template" \
  "$(w26_hits 'Your job is to find what went wrong in this change.' "$W27_ADV")"
expect_eq "W27-T8k2: …without the self-review notes" "" "$(w26_hits '6-axis self-review notes' "$W27_ADV")"
expect_nonempty "W27-T8k3: …and tells the reader it sees no other reader's verdict" \
  "$(w26_hits "You are shown no other reader's verdict" "$W27_ADV")"
W27_ADV_NOTES="$(w26_doctor "$W27_ADV" 'You have the 6-axis self-review notes.')"
expect_nonempty "W27-T8k2m: a checks-adversarial.md that hands over the notes again is caught" \
  "$(w26_hits '6-axis self-review notes' "$W27_ADV_NOTES")"


# ── §W27-T11 (wave-27 T11; REQ-3 AC-3.2 role half, REQ-5 AC-5.1 role half, D5, D6) ──
#
# WHAT THIS OWNS. The reader role files carry stance and output form; their checks are the files
# pushed at start (§W27-T8). Pinned here: each reader role file points at its checks and carries
# none of their text (the role-file half of §W27-32); each injects the three shared reader blocks
# and disallows Write, Edit, NotebookEdit and Agent. The absence sits beside the pointer on the
# same file, and a real render of a critic template that injects a checks block again goes red.
W27_READERS="auditor critic reviewer"
W27_POINTER='Checks: payload/context/checks-<question>.md'
# w27_check_text_in <file> -> what of a check list the file carries, one item per line: a checks
# or critic-template marker, a checks file's opening sentence, or a structure check line.
w27_check_text_in() {
  local id
  /usr/bin/grep -oE '<!-- (CHECKS-[A-Z]+|CRITIC-TEMPLATE)-BEGIN -->' "$1" 2>/dev/null
  has_pin "$1" 'Your job is to find what went wrong in this change.' && echo 'adversarial opening'
  has_pin "$1" "Your job is to falsify the claim that this wave's requirements" && echo 'evidence opening'
  for id in $W27_IDS; do [ -n "$(w27_check_line "$1" "$id")" ] && echo "check line $id"; done
  return 0
}
# The extractor reads each checks file's own text: a role file copying any of them is visible.
for _q in $W27_QUESTIONS; do
  expect_nonempty "W27-T11 precondition: the extractor finds checks-${_q}.md's own check text" \
    "$(w27_check_text_in "${W27_CHECKS_DIR}/checks-${_q}.md")"
done
for _r in $W27_READERS; do
  _rf="${REPO}/agents/${_r}.md"
  expect_nonempty "W27-T11a: AC-5.1 — agents/${_r}.md points at the checks delivered at start" \
    "$(w26_hits "$W27_POINTER" "$_rf")"
  expect_eq "W27-32: AC-3.2 — agents/${_r}.md carries no check list" "" "$(w27_check_text_in "$_rf")"
  for _m in REPORT-CONTRACT BRIEF-SCAFFOLD-READER DISPATCH-RULES; do
    expect_nonempty "W27-T11b: agents/${_r}.md injects ${_m}" "$(w26_hits "<!-- ${_m}-BEGIN -->" "$_rf")"
  done
  _dis="$(/usr/bin/awk 'NR == 1 && /^---$/ { fm = 1; next } fm && /^---$/ { exit }
                       fm && /^disallowedTools:/ { sub(/^disallowedTools:[ \t]*/, ""); print }' "$_rf" 2>/dev/null)"
  expect_eq "W27-T11c: agents/${_r}.md is a reader: it disallows Write, Edit, NotebookEdit and Agent" \
    "Write, Edit, NotebookEdit, Agent" "$_dis"
done
W27_CLONE="$TMP/w27-t11-clone"
if clone_render_tree "$W27_CLONE" \
   && printf '\n<!-- INJECT: checks-adversarial -->\n' >> "$W27_CLONE/agents-src/templates/critic.md.tmpl" \
   && bash "$W27_CLONE/agents-src/render.sh" >/dev/null 2>&1; then
  expect_nonempty "W27-32m precondition: the mutant render wrote a critic role file with its pointer" \
    "$(w26_hits "$W27_POINTER" "$W27_CLONE/agents/critic.md")"
  expect_nonempty "W27-32m: a critic template that injects its checks again is caught" \
    "$(w27_check_text_in "$W27_CLONE/agents/critic.md")"
else
  no "W27-32m: a critic template that injects its checks again is caught" \
     "the mutant clone did not render: $W27_CLONE"
fi

section "Section W27P: wave-27 T7 — the working principles: one source, capped, general (REQ-9, AC-9.5/AC-9.6; D16)"
#
# WHAT THIS OWNS. The text setup offers for a user's own CLAUDE.md. §W27-95: one template
# renders it, and the rendered file stays at or under 2,500 bytes. §W27-96: the text is general
# — no command line, no notification service, no first person. Each absence sits beside a
# positive through the same extractor on the same file, and a doctored copy proves each arm can
# go red. Render agreement itself is Section 7's (`render.sh --check`). HERMETIC: the committed
# final by path; doctored copies under $TMP.
W27P_FINAL="${REPO}/payload/context/working-principles.md"
W27P_TMPL_REL="agents-src/templates/context/working-principles.md.tmpl"
W27P_CAP=2500
# w27p_body <file> -> the lines between the principles markers.
w27p_body() {
  awk 'index($0, "<!-- bionic:principles:end -->") == 1 { inside = 0 }
       inside { print }
       index($0, "<!-- bionic:principles:start -->") == 1 { inside = 1 }' "$1" 2>/dev/null
}
# w27p_over_cap <file> -> "over" when the file exceeds the cap, "within" otherwise.
w27p_over_cap() {
  local n; n="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
  if [ "${n:-0}" -gt "$W27P_CAP" ]; then printf 'over'; else printf 'within'; fi
}
# w27p_general <file> -> the first forbidden form its body carries, or nothing.
w27p_general() {
  local body; body="$(w27p_body "$1")"
  case "$body" in
    *'```'*)                 printf 'a fenced code block' ;;
    *curl\ *|*wget\ *)       printf 'a fetch command' ;;
    *ntfy*|*slack*|*Slack*)  printf 'a notification service' ;;
    *'$ '*|*'source '*)      printf 'a shell command line' ;;
    *' I '*|*' me '*|*' my '*|*'My '*) printf 'a first-person preference' ;;
  esac
}

# W27-95 (AC-9.5): one template, and the final names it; the final is within the cap.
expect_true "W27-95 precondition: the template exists" test -f "${REPO}/${W27P_TMPL_REL}"
expect_nonempty "W27-95a: the rendered final names its one template in its generated header" \
  "$(grep -F "$W27P_TMPL_REL" "$W27P_FINAL" 2>/dev/null)"
expect_eq "W27-95b: no other template renders a working-principles final" "1" \
  "$(ls "${REPO}"/agents-src/templates/*/working-principles*.tmpl "${REPO}"/agents-src/templates/working-principles*.tmpl 2>/dev/null | wc -l | tr -d ' ')"
expect_nonempty "W27-95 precondition: the final carries a non-empty principles block" "$(w27p_body "$W27P_FINAL")"
expect_eq "W27-95c: the rendered final is at most ${W27P_CAP} bytes" "within" "$(w27p_over_cap "$W27P_FINAL")"
W27P_FAT="$TMP/w27p-fat.md"
{ cat "$W27P_FINAL" 2>/dev/null; head -c "$W27P_CAP" /dev/zero | tr '\0' 'x'; } > "$W27P_FAT"
expect_eq "W27-95m: a final one cap's worth longer is caught" "over" "$(w27p_over_cap "$W27P_FAT")"

# W27-96 (AC-9.6): the text is general. The positive: the extractor sees each principle.
for w27p_name in 'Correctness over expedience' 'Unproven means unfinished' 'Stay free' 'No ceremony' \
                 'what the reader needs to decide' 'Decide what is yours' 'Ask first'; do
  expect_contains "W27-96 precondition: the body carries \"${w27p_name}\"" "$w27p_name" "$(w27p_body "$W27P_FINAL")"
done
expect_eq "W27-96: the body carries no command line, no notification service and no first person" "" \
  "$(w27p_general "$W27P_FINAL")"
W27P_CURL="$TMP/w27p-curl.md"
awk 'index($0, "<!-- bionic:principles:end -->") == 1 { print "curl -s -d \"done\" https://example.invalid/topic" } { print }' \
  "$W27P_FINAL" > "$W27P_CURL" 2>/dev/null
expect_nonempty "W27-96m precondition: the doctored copy still has its block" "$(w27p_body "$W27P_CURL")"
expect_eq "W27-96m: a body that carries a curl line is caught" "a fetch command" "$(w27p_general "$W27P_CURL")"

section "Section W27-T33: wave-27 T33 — the checks say what a reader can act on (REQ-3 AC-3.2, REQ-4 AC-4.1/AC-4.3; D5, D9, D10)"
#
# WHAT THIS OWNS. Seven wording fixes from review passes 3 and 4, one pin group per fix: (1) each
# structure check fails only code the change adds or edits; (2) `dependency-direction` asks in
# plain words and gives a failing case; (3) the agreement duty has a verdict a read-only reader
# reaches; (4) the adversarial whole read covers interaction, the structure one duplication, so
# no check has two owners; (5) the evidence record says which `scope` to write; (6) the writer's
# `reuse:` line names the pattern and the paths, so the search can be re-run; (7) the writer duty
# and the structure reader name the same kinds of new site. The rebuilt W27-T8d and W27-T8bm are
# in §W27-T8. Each absence sits beside a positive on the same extractor and file. HERMETIC:
# committed blocks and finals by path; doctored copies under $TMP.
# w27t33_fails <file> <id> -> the failing case of the id's check line: the text after "Fails when ".
w27t33_fails() { w27_check_line "$1" "$2" | sed -n 's/.*Fails when //p'; }
# w27t33_whole <file> -> the file's whole-read section, flattened to one line.
w27t33_whole() {
  awk '/^## / { p = ($0 == "## A whole read"); next } p' "$1" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g'
}
# w27t33_kinds <file>… -> each distinct list of new-site kinds the files name, one per line.
w27t33_kinds() {
  local f
  for f in "$@"; do _flatten "$f" | grep -oE 'function, [a-z ,]+ key'; done | sort -u
}

# (1) every structure check fails only code the change adds or edits.
expect_nonempty "W27-T33-1: checks-structure.md says old code the change did not write never fails a check" \
  "$(w26_hits 'Old code the change did not write never fails a check' "$W27_STRUCT")"
for _id in $W27_IDS; do
  _case="$(w27t33_fails "$W27_STRUCT" "$_id")"
  expect_nonempty "W27-T33-1 precondition: the \`${_id}\` line has a failing case" "$_case"
  expect_nonempty "W27-T33-1: the \`${_id}\` failing case names code the change adds, edits or writes" \
    "$(printf '%s' "$_case" | grep -E 'the change (adds|edits|writes)')"
done

# (2) dependency-direction asks in plain words and names a case a reader can see in a diff.
W27T33_DD="$(w27_check_line "$W27_STRUCT" dependency-direction)"
expect_contains "W27-T33-2: dependency-direction asks its question in plain words" \
  'Does the code that makes a decision stay apart from the details it acts on?' "$W27T33_DD"
expect_contains "W27-T33-2a: …and gives one failing case a reader can recognise" \
  'Example: a function that decides whether a run passed also opens' "$W27T33_DD"
expect_absent "W27-T33-2b: …and no longer asks it as a slogan" 'Does detail depend on policy' "$W27T33_DD"

# (3) the agreement duty's verdict is one a reader that cannot run a suite or edit a file reaches.
expect_nonempty "W27-T33-3: the agreement duty tells the reader it cannot run the test" \
  "$(w26_hits 'You cannot run it; read it.' "$W27_STRUCT")"
expect_nonempty "W27-T33-3a: …says what counts as seen to fail" \
  "$(w26_hits 'It has been seen to fail when it has an arm that doctors one surface and asserts red, or a record cites a red run.' "$W27_STRUCT")"
expect_nonempty "W27-T33-3b: …and gives a named test seen to fail neither way its verdict" \
  "$(w26_hits 'A pair with no named test is a FLAG, and so is a test seen to fail neither way.' "$W27_STRUCT")"

# (4) one owner per whole-read question: interaction is adversarial's, duplication structure's.
W27T33_ADVW="$(w27t33_whole "$W27_ADV")"
W27T33_STRW="$(w27t33_whole "$W27_STRUCT")"
expect_contains "W27-T33-4: the adversarial whole read covers only how the pieces interact" \
  'read only how the pieces interact;' "$W27T33_ADVW"
expect_absent "W27-T33-4a: …and asks nothing about duplication" 'duplicate between them' "$W27T33_ADVW"
expect_absent "W27-T33-4b: …nor about two pieces that solved one problem" 'same problem' "$W27T33_ADVW"
expect_contains "W27-T33-4c: the structure whole read covers only what the pieces duplicate" \
  'read only what the pieces duplicate between them;' "$W27T33_STRW"
expect_absent "W27-T33-4d: …and asks nothing about how they interact" 'read only how the pieces interact' "$W27T33_STRW"
expect_absent "W27-T33-4e: …nor about a caller one piece changed under another" 'changed under another' "$W27T33_STRW"

# (5) the evidence record says which scope to write.
expect_nonempty "W27-T33-5: checks-evidence.md says scope is whole for the run's matrix and piece for one fix" \
  "$(w26_hits '`scope` is `whole` when you audit the run'"'"'s matrix and `piece` when you audit one fix.' "$W27_EVID")"

# (6) the reuse: line names the pattern and the paths searched, in the block and both writer roles.
# The two line forms themselves are W27-41b/c's, whose literals carry `<pattern>` and `<paths>`.
for _w27_f in "$W27_BLOCK" "${REPO}/agents/implementor.md" "${REPO}/agents/senior-implementor.md"; do
  _w27_n="${_w27_f#"$REPO"/}"
  expect_nonempty "W27-T33-6: $_w27_n says the line names the pattern and paths so a reader can re-run it" \
    "$(w26_hits 'naming the pattern and the paths searched, so a reader can re-run the search' "$_w27_f")"
done

# (7) the writer duty and the structure reader name the same kinds of new site, and all four.
W27T33_KIND_FILES="$W27_BLOCK ${REPO}/agents/implementor.md ${REPO}/agents/senior-implementor.md ${BLOCK_DIR}/checks-structure.md $W27_STRUCT"
# shellcheck disable=SC2086  # word-split on purpose: one path per word, none with spaces
W27T33_KINDS="$(w27t33_kinds $W27T33_KIND_FILES)"
expect_nonempty "W27-T33-7 precondition: the extractor finds a list of new-site kinds" "$W27T33_KINDS"
expect_eq "W27-T33-7: the writer duty and the structure reader name one list: function, file, type, configuration key" \
  "function, file, type or configuration key" "$W27T33_KINDS"
W27T33_DOC7="$TMP/w27t33-kinds.md"
_flatten "$W27_BLOCK" | sed 's/function, file, type or configuration key/function, file or configuration key/' > "$W27T33_DOC7"
expect_nonempty "W27-T33-7m precondition: the doctored duty still names a list" "$(w27t33_kinds "$W27T33_DOC7")"
# shellcheck disable=SC2086
expect_eq "W27-T33-7m: a writer duty that drops a kind is caught as a second list" "2" \
  "$(w27t33_kinds "$W27T33_DOC7" ${BLOCK_DIR}/checks-structure.md | wc -l | tr -d ' ')"

# ── §W27-144 (wave-27 T31; REQ-14 AC-14.4, D23): the planning rule for a red by design, and its two labels ──
# AC-14.4: dispatch.md tells a planner to put a proof that needs an owner-gated or external step in a
# row of its own behind that step's token. The brief scaffold carries the two labels a row declares
# its red with; the scaffold's own line, pasted unfilled, declares nothing, while a filled one is
# lifted (the label's behaviour, through the one lift).
W27_144_RULE="A proof that needs an owner-gated or external step is planned as its own row behind that step's token."
expect_nonempty "W27-144: AC-14.4 — dispatch.md carries the planning sentence" "$(w26_hits "$W27_144_RULE" "$DISPATCH_MD")"
expect_nonempty "W27-144b: …and the scaffold the Lands-red: line" \
  "$(w26_hits 'Lands-red: <suite> until <ext:slug | approval:name>' "$DISPATCH_MD")"
expect_nonempty "W27-144c: …and the Red-evidence: line" "$(w26_hits 'Red-evidence: <path under record/>' "$DISPATCH_MD")"
W27_144_DOC="$TMP/w27-144-norule.md"
_flatten "$DISPATCH_MD" | sed "s/$W27_144_RULE//" > "$W27_144_DOC"
expect_nonempty "W27-144m precondition: the doctored copy keeps the scaffold" \
  "$(w26_hits 'Red-evidence: <path under record/>' "$W27_144_DOC")"
expect_eq "W27-144m: …and a dispatch.md missing the sentence is caught" "" "$(w26_hits "$W27_144_RULE" "$W27_144_DOC")"
W27_144_LIFT() { bash -c '. "$1/payload/scripts/lib/brief.sh" 2>/dev/null || exit 9; lift_contract_fields "$2" | grep "^lands_red="' _ "$REPO" "$1"; }
expect_eq "W27-144d: a filled Lands-red: line lifts as the declaration" "lands_red=widget.test.sh until approval:release" \
  "$(W27_144_LIFT 'Lands-red: widget.test.sh until approval:release')"
expect_nonempty "W27-144e0 precondition: the scaffold's Lands-red: line is extracted from dispatch.md" \
  "$(_flatten "$DISPATCH_MD" | grep -o 'Lands-red: <suite> until <ext:slug | approval:name>')"
expect_eq "W27-144e: …and the scaffold's own line, pasted unfilled, lifts nothing" "" \
  "$(W27_144_LIFT "$(_flatten "$DISPATCH_MD" | grep -o 'Lands-red: <suite> until <ext:slug | approval:name>')")"

finish
