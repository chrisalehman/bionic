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
# ANTI-VACUITY, per tests/cross-gate-agreement.test.sh §N.1's differential-control pattern (that
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
#   (d) the `/clear` paragraph, which lives in TWO channels by design (a rules file
#       lands on the next read, a role file on the next session — CLAUDE.md §Path-scoped
#       rules). Two copies of a paragraph is exactly the drift a pin exists for, so the
#       two are compared BYTE FOR BYTE rather than each being spot-checked.
#
# ANTI-VACUITY, same discriminate-a-doctored-copy pattern §1 uses: every extractor here
# is re-run against a mutated copy and must report the mutation.
#
# HERMETIC. Reads committed files by path; doctored copies live under $TMP.

echo ""
echo "=== Section 2: the WALLS instruction-surface pins (AC-14, AC-26) ==="

SKILL_MD="${REPO}/payload/skills/canonical-sdlc/SKILL.md"
SURVIVAL_BLOCK="${REPO}/agents-src/blocks/survival.md"
AGENT_RULES="${REPO}/.claude/rules/agent-discipline.md"

# The four pinned strings, spelled here exactly as they must appear on disk.
PIN_PROBE='`resources_probe` and `resources_budget` from `<plugin-root>/scripts/lib/resources.sh` yield the run'"'"'s `parallel-budget:` — one string, recorded verbatim in plan frontmatter, printed in the display, and never re-derived downstream.'
PIN_FILL='every slice with no unmet dependency dispatches in one batch up to `writers`; sequence only for shared state or when the batch would exceed the budget'
PIN_JOBS='**Each brief in the batch points the writer at the rung:** `take your test width from pressure_level at suite start; the ceiling is this header'"'"'s test_jobs`.'

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

if has_pin "$SKILL_MD" "$PIN_PROBE"; then
  ok "9: SKILL.md Step 0 carries the resources-probe sentence verbatim"
else
  no "9: SKILL.md Step 0 carries the resources-probe sentence verbatim" "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_FILL"; then
  ok "10: SKILL.md carries the 'fill the budget' dispatch rule verbatim"
else
  no "10: SKILL.md carries the 'fill the budget' dispatch rule verbatim" "file: $SKILL_MD"
fi

if has_pin "$SURVIVAL_BLOCK" "$PIN_JOBS"; then
  ok "11: agents-src/blocks/survival.md carries the rung-pointer sentence verbatim (AC-18)"
else
  no "11: agents-src/blocks/survival.md carries the rung-pointer sentence verbatim (AC-18)" \
     "file: $SURVIVAL_BLOCK"
fi

# The render is the delivery mechanism; asserting the block alone would pass on a repo
# whose agents/ was never re-rendered, which is the state a dispatched writer meets.
PINS_JOBS_MISSING=""
for role in auditor critic implementor researcher senior-implementor test-runner; do
  has_pin "${REPO}/agents/${role}.md" "$PIN_JOBS" || PINS_JOBS_MISSING="${PINS_JOBS_MISSING} ${role}"
done
if [ -z "$PINS_JOBS_MISSING" ]; then
  ok "12: all six rendered agents/*.md carry the rung-pointer sentence (render is current, AC-18)"
else
  no "12: all six rendered agents/*.md carry the rung-pointer sentence (render is current, AC-18)" \
     "missing in:${PINS_JOBS_MISSING} — run 'bash agents-src/render.sh'"
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
if [ -n "$CLEAR_RULES" ]; then
  ok "14: .claude/rules/agent-discipline.md carries the same paragraph"
else
  no "14: .claude/rules/agent-discipline.md carries the same paragraph" "file: $AGENT_RULES"
fi
expect_eq "15: the two copies of the '/clear' paragraph are byte-identical" \
  "$CLEAR_BLOCK" "$CLEAR_RULES"

PINS_CLEAR_MISSING=""
for role in auditor critic implementor researcher senior-implementor test-runner; do
  [ "$(clear_paragraph "${REPO}/agents/${role}.md")" = "$CLEAR_BLOCK" ] \
    || PINS_CLEAR_MISSING="${PINS_CLEAR_MISSING} ${role}"
done
if [ -z "$PINS_CLEAR_MISSING" ]; then
  ok "16: all six rendered agents/*.md carry that paragraph byte-identically"
else
  no "16: all six rendered agents/*.md carry that paragraph byte-identically" \
     "differs or missing in:${PINS_CLEAR_MISSING} — run 'bash agents-src/render.sh'"
fi

# --- Anti-vacuity: the same extractors must report a mutation ---

DOCTORED_SKILL="$TMP/skill-mutated.md"
sed 's/never re-derived downstream/re-derived wherever convenient/' "$SKILL_MD" > "$DOCTORED_SKILL"
if has_pin "$DOCTORED_SKILL" "$PIN_PROBE"; then
  no "17: a doctored SKILL.md fails the probe pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "17: a doctored SKILL.md fails the probe pin (pin discriminates)"
fi

DOCTORED_BLOCK="$TMP/survival-mutated.md"
sed 's/the ceiling is this header'"'"'s test_jobs/the ceiling is a number pinned once/' \
  "$SURVIVAL_BLOCK" > "$DOCTORED_BLOCK"
if cmp -s "$SURVIVAL_BLOCK" "$DOCTORED_BLOCK"; then
  no "18: a doctored survival.md fails the BIONIC_TEST_JOBS pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_BLOCK" "$PIN_JOBS"; then
  no "18: a doctored survival.md fails the BIONIC_TEST_JOBS pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "18: a doctored survival.md fails the BIONIC_TEST_JOBS pin (pin discriminates)"
fi

DOCTORED_RULES="$TMP/rules-mutated.md"
sed 's/the address that survives/the address that dies/' "$AGENT_RULES" > "$DOCTORED_RULES"
expect_ne "19: a doctored agent-discipline.md reads as a different paragraph (pin discriminates)" \
  "$CLEAR_BLOCK" "$(clear_paragraph "$DOCTORED_RULES")"

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
# APPENDED, NEVER REWRITTEN: §1 is RELEASE's and §2 is WALLS's, and a slice that edited
# another slice's pins would be a slice deciding what that slice owns.

echo ""
echo "=== Section 3: the SCHED Patrol-text pins (AC-30, AC-38) ==="

PIN_THROTTLE='**the tick reads pressure to throttle, never to re-derive the budget** — the ceiling is the plan header'"'"'s `parallel-budget:`, written once by Step 0 from the probe, and no live reading ever raises or lowers it.'
PIN_QUIET='**An armed session that has dispatched nothing yet decides QUIET, never REFUSED** — `poker: QUIET — armed, nothing dispatched yet on this session`, stamp kept — because arming precedes dispatch by design'

if has_pin "$SKILL_MD" "$PIN_THROTTLE"; then
  ok "20: SKILL.md carries the pressure-throttles-never-re-derives sentence verbatim"
else
  no "20: SKILL.md carries the pressure-throttles-never-re-derives sentence verbatim" \
     "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_QUIET"; then
  ok "21: SKILL.md carries the AC-38 QUIET sentence verbatim"
else
  no "21: SKILL.md carries the AC-38 QUIET sentence verbatim" "file: $SKILL_MD"
fi

# The two rungs, the tick's rung line and the fill duty are named in the same section —
# asserted as presence rather than byte-for-byte, because their wording is prose the next
# editor may improve while the two sentences above are contracts. NARROW retired from this
# list at S10 (S8's report: "docs-pins.test.sh:327 still pins the token in SKILL.md and is
# S10's to retire" — NARROW is gone from hooks/session-poker.sh entirely).
PINS_RUNGS_MISSING=""
for token in 'EMERGENCY' 'HOLD' 'rung=<n>/<ceiling>' 'FILL <ids>' 'fill-declined: <reason>'; do
  has_pin "$SKILL_MD" "$token" || PINS_RUNGS_MISSING="${PINS_RUNGS_MISSING} ${token}"
done
if [ -z "$PINS_RUNGS_MISSING" ]; then
  ok "22: SKILL.md's Patrol section names both rungs, the tick's rung line, the FILL line and the decline"
else
  no "22: SKILL.md's Patrol section names both rungs, the tick's rung line, the FILL line and the decline" \
     "missing:${PINS_RUNGS_MISSING}"
fi

# --- Anti-vacuity: the same extractor must report a mutation ---

DOCTORED_SCHED="$TMP/skill-sched-mutated.md"
sed 's/never to re-derive the budget/and to re-derive the budget/' "$SKILL_MD" > "$DOCTORED_SCHED"
if has_pin "$DOCTORED_SCHED" "$PIN_THROTTLE"; then
  no "23: a doctored SKILL.md fails the throttle pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "23: a doctored SKILL.md fails the throttle pin (pin discriminates)"
fi

DOCTORED_SCHED2="$TMP/skill-sched-mutated-2.md"
sed 's/decides QUIET, never REFUSED/is REFUSED/' "$SKILL_MD" > "$DOCTORED_SCHED2"
if has_pin "$DOCTORED_SCHED2" "$PIN_QUIET"; then
  no "24: a doctored SKILL.md fails the QUIET pin (pin discriminates)" \
     "the mutated copy still matched — the pin is vacuous"
else
  ok "24: a doctored SKILL.md fails the QUIET pin (pin discriminates)"
fi

echo ""
echo "--- SECTION 4 — the Patrol tick literal, one string in two files (step-6 review R-8) ---"
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

TICK_GATE="${REPO}/hooks/patrol-duties-gate.sh"

# tick_literal_doc <SKILL.md> -> the prefix as documented, placeholder stripped.
# Fails LOUD rather than empty: an unmatched sed leaves the whole line, which no
# comparison below can mistake for agreement.
tick_literal_doc() {
  /usr/bin/grep -m1 '^\*\*The patrol prompt\.\*\*' "$1" 2>/dev/null \
    | sed 's/.*its first token `\([^`]*\)`.*/\1/' \
    | sed 's/<session-id\[0:8\]>$//'
}
# tick_literal_code <patrol-duties-gate.sh> -> the prefix the hook builds.
tick_literal_code() {
  /usr/bin/grep -m1 '^TICK_MARK=' "$1" 2>/dev/null \
    | sed 's/^TICK_MARK="//' \
    | sed 's/\${SID:0:8}"$//'
}

TICK_DOC=$(tick_literal_doc "$SKILL_MD")
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
TICK_FLAT=$(_flatten "$SKILL_MD")
case "$TICK_FLAT" in
  *"$TICK_RESUME_NEEDLE"*)
    ok "27: SKILL.md's resume ritual names the same marker it tells the prompt to carry" ;;
  *)
    no "27: SKILL.md's resume ritual names the same marker it tells the prompt to carry" \
       "file: $SKILL_MD" ;;
esac

# --- Anti-vacuity: the same extractors must report a mutation, from either side ---

DOCTORED_TICK_DOC="$TMP/skill-tick-mutated.md"
sed 's/its first token `bionic-patrol session=/its first token `bionic patrol session=/' \
  "$SKILL_MD" > "$DOCTORED_TICK_DOC"
if cmp -s "$SKILL_MD" "$DOCTORED_TICK_DOC"; then
  no "28: a reworded SKILL.md token breaks the pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
else
  expect_ne "28: a reworded SKILL.md token breaks the pin (pin discriminates)" \
    "$TICK_CODE" "$(tick_literal_doc "$DOCTORED_TICK_DOC")"
fi

DOCTORED_TICK_CODE="$TMP/patrol-duties-gate-mutated.sh"
sed 's/^TICK_MARK="bionic-patrol session=/TICK_MARK="bionic-patrol sid=/' \
  "$TICK_GATE" > "$DOCTORED_TICK_CODE"
if cmp -s "$TICK_GATE" "$DOCTORED_TICK_CODE"; then
  no "29: a renamed hook-side literal breaks the pin (pin discriminates)" \
     "the sed target matched nothing — the assignment moved"
else
  expect_ne "29: a renamed hook-side literal breaks the pin (pin discriminates)" \
    "$TICK_DOC" "$(tick_literal_code "$DOCTORED_TICK_CODE")"
fi

echo ""
echo "--- SECTION 5 — the session-bound run, and the bind step in the resume ritual (wave-session-bound-run, A4/AC-5/AC-8) ---"
#
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
# APPENDED, NEVER REWRITTEN: §1-§4 belong to earlier slices.

echo ""
echo "=== Section 5: the session-bound run and the resume-ritual bind step ==="

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

if has_pin "$SKILL_MD" "$PIN_BOUND_RUN"; then
  ok "30: SKILL.md states that the run is a property of the session, verbatim"
else
  no "30: SKILL.md states that the run is a property of the session, verbatim" "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_FALLBACK"; then
  ok "31: …and that ONLY an unbound session takes the newest-plan fallback"
else
  no "31: …and that ONLY an unbound session takes the newest-plan fallback" "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_BIND_STEP"; then
  ok "32: SKILL.md's resume ritual carries the bind step verbatim (A4: exactly one added step)"
else
  no "32: SKILL.md's resume ritual carries the bind step verbatim (A4: exactly one added step)" \
     "file: $SKILL_MD"
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

BIND_DOC=$(bind_verb_doc "$SKILL_MD")
BIND_CODE=$(bind_verb_code "$POKER_SH")

expect_eq "33: SKILL.md tells the operator to type the verb the poker publishes" \
  "$BIND_CODE" "$BIND_DOC"
expect_eq "34: …and the verb both sides name is 'session-poker.sh bind <plan>'" \
  'session-poker.sh bind <plan>' "$BIND_DOC"

# --- Anti-vacuity: the same extractors and pins must report a mutation ---

DOCTORED_BOUND="$TMP/skill-bound-run-mutated.md"
sed 's/Only an UNBOUND session falls back/Every session falls back/' "$SKILL_MD" > "$DOCTORED_BOUND"
if cmp -s "$SKILL_MD" "$DOCTORED_BOUND"; then
  no "35: a doctored SKILL.md fails the fallback pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_BOUND" "$PIN_FALLBACK"; then
  no "35: a doctored SKILL.md fails the fallback pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "35: a doctored SKILL.md fails the fallback pin (pin discriminates)"
fi

DOCTORED_BIND="$TMP/skill-bind-step-mutated.md"
sed 's/binds its run before it adopts anything/adopts before it binds anything/' \
  "$SKILL_MD" > "$DOCTORED_BIND"
if cmp -s "$SKILL_MD" "$DOCTORED_BIND"; then
  no "36: a reordered resume ritual fails the bind-step pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_BIND" "$PIN_BIND_STEP"; then
  no "36: a reordered resume ritual fails the bind-step pin (pin discriminates)" \
     "the pin matched a copy that puts adopt first"
else
  ok "36: a reordered resume ritual fails the bind-step pin (pin discriminates)"
fi

DOCTORED_BIND_VERB="$TMP/session-poker-verb-mutated.sh"
sed 's/session-poker\.sh bind <plan>/session-poker.sh bindrun <plan>/' "$POKER_SH" > "$DOCTORED_BIND_VERB"
if cmp -s "$POKER_SH" "$DOCTORED_BIND_VERB"; then
  no "37: a renamed poker verb splits from the doc (pin discriminates)" \
     "the sed target matched nothing — the usage line moved"
else
  expect_ne "37: a renamed poker verb splits from the doc (pin discriminates)" \
    "$BIND_DOC" "$(bind_verb_code "$DOCTORED_BIND_VERB")"
fi

if has_pin "$SKILL_MD" "$PIN_SCOPE_PAIR"; then
  ok "38: SKILL.md's two-facts sentence names the SESSION's bound run, not the project's"
else
  no "38: SKILL.md's two-facts sentence names the SESSION's bound run, not the project's" \
     "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_SCOPE_OLD"; then
  no "39: …and the pre-wave project-scoped clause is gone from the paragraph" \
     "SKILL.md still states the rule this wave deleted: '$PIN_SCOPE_OLD'"
else
  ok "39: …and the pre-wave project-scoped clause is gone from the paragraph"
fi

# Anti-vacuity for 38, same pattern as 35/36: the extractor must report a doctored copy.
DOCTORED_SCOPE="$TMP/skill-scope-mutated.md"
sed 's/which run this SESSION is bound to/whether this PROJECT has an OPEN run/' \
  "$SKILL_MD" > "$DOCTORED_SCOPE"
if cmp -s "$SKILL_MD" "$DOCTORED_SCOPE"; then
  no "40: a doctored SKILL.md fails the scope pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_SCOPE" "$PIN_SCOPE_PAIR"; then
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
PIN_TASKLIST='**The resume ritual rebuilds the task list after it binds:** run `TaskList`; if it is empty and the bound plan has `## SDLC State`, recreate one entry per step (and per slice at the current step) from the plan, statuses from the step lines.'
PIN_RUNG='The tick prints the current rung as one line, `poker: rung=<n>/<ceiling>`; NARROW and RELAX are retired — regulation is the rung'"'"'s, read by every consumer at the moment of use, never a tick'"'"'s advice.'

if has_pin "$SKILL_MD" "$PIN_TASKLIST"; then
  ok "48: SKILL.md's resume ritual rebuilds the task list after it binds, verbatim"
else
  no "48: SKILL.md's resume ritual rebuilds the task list after it binds, verbatim" \
     "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_RUNG"; then
  ok "49: SKILL.md's Patrol prompt names the rung line and retires NARROW/RELAX, verbatim"
else
  no "49: SKILL.md's Patrol prompt names the rung line and retires NARROW/RELAX, verbatim" \
     "file: $SKILL_MD"
fi

DOCTORED_TASKLIST="$TMP/skill-tasklist-mutated.md"
sed 's/recreate one entry per step/recreate one entry per slice only/' "$SKILL_MD" > "$DOCTORED_TASKLIST"
if cmp -s "$SKILL_MD" "$DOCTORED_TASKLIST"; then
  no "50: a doctored SKILL.md fails the task-list pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_TASKLIST" "$PIN_TASKLIST"; then
  no "50: a doctored SKILL.md fails the task-list pin (pin discriminates)" \
     "the pin matched a doctored copy"
else
  ok "50: a doctored SKILL.md fails the task-list pin (pin discriminates)"
fi

DOCTORED_RUNG="$TMP/skill-rung-mutated.md"
sed 's/NARROW and RELAX are retired/NARROW and RELAX still apply/' "$SKILL_MD" > "$DOCTORED_RUNG"
if cmp -s "$SKILL_MD" "$DOCTORED_RUNG"; then
  no "51: a doctored SKILL.md fails the rung pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_RUNG" "$PIN_RUNG"; then
  no "51: a doctored SKILL.md fails the rung pin (pin discriminates)" \
     "the pin matched a doctored copy"
else
  ok "51: a doctored SKILL.md fails the rung pin (pin discriminates)"
fi

echo ""
echo "=== Section 6: Step 8's tmp wipe spares session-keyed state ==="
#
# THE DEFECT THIS PINS (critic C-2, remediated at S10b). Step 8 said `wipe .bionic/tmp/*`,
# unqualified. `.bionic/tmp/` is where EVERY session in the root keeps its engagement
# marker, its roster, its Patrol stamp, its preflight attestation and its sweeper state —
# all keyed by session id. A blanket wipe therefore destroys the live state of every OTHER
# session working that root, which is precisely the two-run scenario this wave exists for,
# and it contradicts the same file's own sentence that "the marker is never removed during
# the session once written". The Step 8 line now names what it spares.
#
# THE FIELD NAME `tmp-wiped:` IS DELIBERATELY UNTOUCHED (§Evidence, step 8 row). It is an
# evidence key the gate parses, not prose; renaming it would be an interface change and is
# not what the finding asked for.
PIN_TMP_SPARE='sparing every session-keyed file — `engaged-*.state`, `roster-*.state`, `patrol-*.state*`, `preflight-*.state`, `sweeper-*.state`'
PIN_TMP_BLANKET='wipe `.bionic/tmp/*`;'

if has_pin "$SKILL_MD" "$PIN_TMP_SPARE"; then
  ok "41: SKILL.md's Step 8 names the session-keyed files its wipe spares"
else
  no "41: SKILL.md's Step 8 names the session-keyed files its wipe spares" "file: $SKILL_MD"
fi

if has_pin "$SKILL_MD" "$PIN_TMP_BLANKET"; then
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
DOCTORED_TMP="$TMP/skill-tmp-wipe-mutated.md"
sed 's/sparing every session-keyed file/taking every file/' "$SKILL_MD" > "$DOCTORED_TMP"
if cmp -s "$SKILL_MD" "$DOCTORED_TMP"; then
  no "44: a doctored SKILL.md fails the spare-list pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_TMP" "$PIN_TMP_SPARE"; then
  no "44: a doctored SKILL.md fails the spare-list pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "44: a doctored SKILL.md fails the spare-list pin (pin discriminates)"
fi

echo ""
echo "=== Section 7: bind's operand takes the spelling session-start prints ==="
#
# THE PAIR THIS PINS (S10b phase 2). hooks/session-start.sh prints the open-run listing
# DOCS-root-relative, so an operator copies `plans/<epic>/<wave>.md` out of it. That is the
# one spelling `bind` used to reject, because a relative operand was resolved against the
# PROJECT root only. The verb now tries the docs root when the project-relative spelling is
# not a regular file, and this section is the doc half of that agreement: the paragraph a
# reader learns the verb from must name all three spellings the verb accepts.
PIN_BIND_OPERAND='its operand may be absolute, project-root-relative, or docs-root-relative — the spelling session-start'"'"'s own listing prints'

if has_pin "$SKILL_MD" "$PIN_BIND_OPERAND"; then
  ok "45: SKILL.md names all three spellings bind accepts"
else
  no "45: SKILL.md names all three spellings bind accepts" "file: $SKILL_MD"
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
DOCTORED_OPERAND="$TMP/skill-bind-operand-mutated.md"
sed 's/its operand may be absolute, project-root-relative, or docs-root-relative/its operand must be absolute/' \
  "$SKILL_MD" > "$DOCTORED_OPERAND"
if cmp -s "$SKILL_MD" "$DOCTORED_OPERAND"; then
  no "47: a doctored SKILL.md fails the operand pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_OPERAND" "$PIN_BIND_OPERAND"; then
  no "47: a doctored SKILL.md fails the operand pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "47: a doctored SKILL.md fails the operand pin (pin discriminates)"
fi

# Anti-vacuity for 46: a poker with the fallback line deleted must fail the same regex, so
# assertion 46 is proven to discriminate rather than matching everything by accident.
DOCTORED_POKER_NO_FALLBACK="$TMP/session-poker-no-docs-fallback.sh"
/usr/bin/grep -v 'BIND_DOCS_TRY=' "$POKER_SH" > "$DOCTORED_POKER_NO_FALLBACK"
if cmp -s "$POKER_SH" "$DOCTORED_POKER_NO_FALLBACK"; then
  no "52: a poker with the docs-root fallback deleted fails assertion 46's check (pin discriminates)" \
     "the grep -v target matched nothing — the fallback line moved"
elif /usr/bin/grep -Eq "$BIND_DOCS_FALLBACK_RE" "$DOCTORED_POKER_NO_FALLBACK"; then
  no "52: a poker with the docs-root fallback deleted fails assertion 46's check (pin discriminates)" \
     "the regex matched a copy with the fallback line removed"
else
  ok "52: a poker with the docs-root fallback deleted fails assertion 46's check (pin discriminates)"
fi

echo ""
echo "=== Section 8: SKILL.md carries its OWN copy of the rung-pointer sentence (AC-18) ==="
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

if has_pin "$SKILL_MD" "$PIN_JOBS_SKILL"; then
  ok "53: SKILL.md carries its own copy of the rung-pointer sentence (AC-18)"
else
  no "53: SKILL.md carries its own copy of the rung-pointer sentence (AC-18)" "file: $SKILL_MD"
fi

# Anti-vacuity, same 47-style shape: a doctored SKILL.md must fail the pin above.
DOCTORED_SKILL_JOBS="$TMP/skill-jobs-mutated.md"
sed 's/Each brief in the batch points the writer at the rung/Each brief in the batch reads the frozen literal/' \
  "$SKILL_MD" > "$DOCTORED_SKILL_JOBS"
if cmp -s "$SKILL_MD" "$DOCTORED_SKILL_JOBS"; then
  no "54: a doctored SKILL.md fails the rung-pointer pin (pin discriminates)" \
     "the sed target matched nothing — the sentence moved"
elif has_pin "$DOCTORED_SKILL_JOBS" "$PIN_JOBS_SKILL"; then
  no "54: a doctored SKILL.md fails the rung-pointer pin (pin discriminates)" \
     "the pin matched a copy that says the opposite"
else
  ok "54: a doctored SKILL.md fails the rung-pointer pin (pin discriminates)"
fi

echo ""
echo "========================================"
echo "docs-pins: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
