#!/bin/bash
# THE DIAGRAM PINS — epic-17 wave-04 slice S8 (spec AC-6, design D4).
#
# WHAT THE MODEL IS. The two canonical-sdlc diagrams are composed SVG, and the SVG
# is the SOLE source: no .excalidraw beside it, no PNG export, nothing that can be
# stale relative to it. That choice is what makes this suite possible — the picture
# is text, so the claims it makes about the system are greppable, and a diagram that
# outlives the code it draws goes red here instead of quietly misleading a reader.
#
# The pins are agreement tests in the Step-6 sense: each one names ONE concept whose
# owner lives in code or doctrine, and the diagram is a second rendering surface.
#
#   concept                    owner (SSoT)                          this suite's arm
#   ------------------------   -----------------------------------   ----------------
#   SDLC contract version      hooks' SUPPORTED_SDLC_VERSION          (B) 4 renderings
#   always-on hook wiring      hooks/hooks.json                       (C) 6 entries
#   the ten lifecycle steps    SKILL.md ## Steps table                (D) 10 steps
#   skill-armed hook set       SKILL.md frontmatter hooks: block      (E) set equality
#   every hook the SVGs name   the files in hooks/                    (F) no phantoms
#
# HOW THE SVG CARRIES ITS PINS. Three element classes, each with data-* attributes
# that ARE the comparison (the visible text is prose; the attributes are the claim):
#
#   <text class="version-pin"  data-pin="...">                 ...one per rendering
#   <text class="hook-entry"   data-event data-matcher data-guard data-hook>
#   <text class="step"         data-step data-step-name>
#   <text class="armed-entry"  data-hook>
#
# Comments inside each SVG mention those class names in prose, so every extractor
# below runs over svg_body() — the file with its XML comments stripped — rather than
# over the raw bytes. A pin that counted its own documentation would be a pin that
# cannot go red.
#
# SECTION G IS THE META-EVIDENCE, and it is the durable half of this file. RED counts
# taken before the SVGs existed die the moment they exist and cannot be audited later
# (memory: RED evidence is perishable). So every arm above is re-run in G against a
# DOCTORED copy — of the diagram AND, where there are two sides, of the source — and
# the arm is required to fail there. That is the proof these pins discriminate, and it
# is re-proven on every run rather than quoted from a report.
#
# HERMETIC. Reads the two SVGs, hooks/hooks.json, the hook scripts and SKILL.md by
# path; doctored copies live in a mktemp dir that is removed on exit. Nothing in the
# repo tree is mutated.
#
# Usage: bash tests/diagrams.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
SKILL_DIR="${BIONIC_SKILLS_DIR}/canonical-sdlc"
DIAGRAMS="${SKILL_DIR}/diagrams"
LIFECYCLE="${DIAGRAMS}/lifecycle.svg"
HOOKCHAIN="${DIAGRAMS}/hook-chain.svg"
SKILL="${SKILL_DIR}/SKILL.md"
HOOKS_JSON="${BIONIC_HOOKS_DIR}/hooks.json"
EVIDENCE_GATE_HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-evidence-gate.sh"
GOVERNING_SKILL_HOOK="${BIONIC_HOOKS_DIR}/canonical-sdlc-governing-skill.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected '$2', got '$3'"; fi; }
expect_true() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else no "$l"; fi; }
expect_false() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then no "$l"; else ok "$l"; fi; }

# ============================================================
# extraction
# ============================================================

# svg_body <svg>: the file with XML comment blocks removed. Every extractor reads
# through this, so the class names documented in each SVG's header never count as
# elements.
svg_body() { awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$1"; }

# attr <element-string> <name>: the attribute's value, empty when absent or empty.
attr() { printf '%s' "$1" | grep -oE "$2=\"[^\"]*\"" | head -1 | cut -d'"' -f2; }

# elements <svg> <class>: one line per matching <text> element, opening tag only.
elements() { svg_body "$1" | grep -oE "<text class=\"$2\"[^>]*>"; }

# version_pins <svg>: "<data-pin>|<digits found in the rendered text>" per pin.
# The digit set is the assertion: these lines are written to contain the version
# number and nothing else numeric, so a stale pin cannot hide behind a coordinate.
version_pins() {
  svg_body "$1" | grep -oE '<text class="version-pin"[^>]*>[^<]*' | while IFS= read -r el; do
    printf '%s|%s\n' \
      "$(attr "$el" data-pin)" \
      "$(printf '%s' "${el#*>}" | grep -oE '[0-9]+' | sort -u | tr '\n' ',')"
  done
}

# svg_hook_entries <svg>: "event|matcher|guard|hook", sorted.
svg_hook_entries() {
  elements "$1" hook-entry | while IFS= read -r el; do
    printf '%s|%s|%s|%s\n' \
      "$(attr "$el" data-event)" "$(attr "$el" data-matcher)" \
      "$(attr "$el" data-guard)" "$(attr "$el" data-hook)"
  done | sort
}

# json_hook_entries <hooks.json>: the same tuple shape, read from the wiring itself.
# A chained command ("guard.sh wall.sh") yields guard=first, hook=last; a bare
# command yields an empty guard.
json_hook_entries() {
  python3 - "$1" <<'PY'
import json, os, sys
doc = json.load(open(sys.argv[1]))
rows = []
for event, groups in doc.get("hooks", {}).items():
    for group in groups:
        matcher = group.get("matcher", "")
        for hook in group.get("hooks", []):
            names = [os.path.basename(p) for p in hook.get("command", "").split()]
            if not names:
                continue
            guard = names[0] if len(names) > 1 else ""
            rows.append("%s|%s|%s|%s" % (event, matcher, guard, names[-1]))
for row in sorted(rows):
    print(row)
PY
}

# svg_steps <svg>: "N|Name" per class="step" element, sorted.
svg_steps() {
  elements "$1" step | while IFS= read -r el; do
    printf '%s|%s\n' "$(attr "$el" data-step)" "$(attr "$el" data-step-name)"
  done | sort
}

# skill_steps <SKILL.md>: "N|Name" per row of the ## Steps table, sorted.
skill_steps() {
  awk '/^## Steps/{f=1; next} /^### /{f=0} f' "$1" \
    | grep -E '^\| *[0-9]+ ' \
    | sed -E 's/^\| *([0-9]+) +([^ |]+) *\|.*/\1|\2/' \
    | sort
}

# svg_armed_hooks <svg>: the distinct hook basenames the armed lane names.
svg_armed_hooks() {
  elements "$1" armed-entry | while IFS= read -r el; do attr "$el" data-hook; done | sort -u
}

# skill_frontmatter_hooks <SKILL.md>: the distinct hook basenames registered in the
# YAML frontmatter's hooks: block. Bounded to the frontmatter on purpose — the body
# names hook scripts in prose, and prose is not a registration.
skill_frontmatter_hooks() {
  awk 'NR==1 && /^---[[:space:]]*$/{f=1; next} f && /^---[[:space:]]*$/{exit} f' "$1" \
    | grep -oE 'hooks/[A-Za-z0-9._-]+\.sh' | sed 's|^hooks/||' | sort -u
}

# supported_version <hook>: the SUPPORTED_SDLC_VERSION the hook pins.
supported_version() {
  grep -oE '^SUPPORTED_SDLC_VERSION=[0-9]+' "$1" | head -1 | cut -d= -f2
}

# ---------- the checks, as functions, so section G can re-run them doctored ----------

# check_versions <version> <hook-chain-svg> <lifecycle-svg> -> 0 when every pin agrees
check_versions() {
  local want="$1" hc="$2" lc="$3" line pin digits n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pin="${line%%|*}"; digits="${line#*|}"
    [ "$digits" = "${want}," ] || { echo "pin '$pin' renders '${digits%,}', want '$want'" >&2; return 1; }
    n=$((n + 1))
  done <<EOF
$(version_pins "$hc"; version_pins "$lc")
EOF
  [ "$n" -eq 4 ] || { echo "expected 4 version renderings, found $n" >&2; return 1; }
}

# check_hook_entries <hook-chain-svg> <hooks.json>
check_hook_entries() {
  local a b
  a="$(svg_hook_entries "$1")"; b="$(json_hook_entries "$2")"
  [ "$(printf '%s\n' "$b" | grep -c .)" -eq 6 ] || { echo "hooks.json no longer holds six entries" >&2; return 1; }
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") >&2; return 1; }
}

# check_steps <lifecycle-svg> <SKILL.md>
check_steps() {
  local a b
  a="$(svg_steps "$1")"; b="$(skill_steps "$2")"
  [ "$(printf '%s\n' "$b" | grep -c .)" -eq 10 ] || { echo "the ## Steps table no longer holds ten steps" >&2; return 1; }
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") >&2; return 1; }
}

# check_armed <hook-chain-svg> <SKILL.md>
check_armed() {
  local a b
  a="$(svg_armed_hooks "$1")"; b="$(skill_frontmatter_hooks "$2")"
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") >&2; return 1; }
}

# ============================================================
echo "=== A — the sole-source rule: two SVGs, and nothing else in diagrams/ ==="
# ============================================================

expect_true "lifecycle.svg exists" [ -f "$LIFECYCLE" ]
expect_true "hook-chain.svg exists" [ -f "$HOOKCHAIN" ]
expect_true "lifecycle.svg is well-formed XML" \
  python3 -c "import sys,xml.etree.ElementTree as E; E.parse(sys.argv[1])" "$LIFECYCLE"
expect_true "hook-chain.svg is well-formed XML" \
  python3 -c "import sys,xml.etree.ElementTree as E; E.parse(sys.argv[1])" "$HOOKCHAIN"

# The point of D4: one artifact per diagram. A .png or .excalidraw reappearing here
# re-creates the is-the-export-current relationship the SVG exists to abolish.
_strays="$(find "$DIAGRAMS" -maxdepth 1 \( -name '*.png' -o -name '*.excalidraw' \) 2>/dev/null | tr '\n' ' ')"
expect_eq "diagrams/ holds no .png and no .excalidraw (the SVG is the sole source)" "" "$_strays"

_extras="$(find "$DIAGRAMS" -maxdepth 1 -type f ! -name '*.svg' 2>/dev/null | tr '\n' ' ')"
expect_eq "diagrams/ holds nothing but .svg files" "" "$_extras"

# ============================================================
echo ""
echo "=== B — the four version renderings agree with the hooks' constant ==="
# ============================================================

VERSION="$(supported_version "$EVIDENCE_GATE_HOOK")"
expect_true "SUPPORTED_SDLC_VERSION is readable from the evidence-gate hook" [ -n "$VERSION" ]
expect_eq "both hooks pin the same SUPPORTED_SDLC_VERSION" \
  "$VERSION" "$(supported_version "$GOVERNING_SKILL_HOOK")"

expect_eq "hook-chain.svg carries exactly three version renderings" \
  "3" "$(version_pins "$HOOKCHAIN" | grep -c .)"
expect_eq "lifecycle.svg carries exactly one version rendering" \
  "1" "$(version_pins "$LIFECYCLE" | grep -c .)"
expect_true "all four version renderings equal SUPPORTED_SDLC_VERSION=${VERSION}" \
  check_versions "$VERSION" "$HOOKCHAIN" "$LIFECYCLE"

# ============================================================
echo ""
echo "=== C — hook-chain's always-on lane is hooks.json, entry for entry ==="
# ============================================================

expect_eq "hook-chain.svg draws exactly six always-on entries" \
  "6" "$(svg_hook_entries "$HOOKCHAIN" | grep -c .)"
expect_true "every drawn entry matches hooks.json on event, matcher, guard and hook" \
  check_hook_entries "$HOOKCHAIN" "$HOOKS_JSON"

# ============================================================
echo ""
echo "=== D — lifecycle's ten steps are SKILL.md's ## Steps table ==="
# ============================================================

expect_eq "lifecycle.svg draws exactly ten steps" "10" "$(svg_steps "$LIFECYCLE" | grep -c .)"
expect_true "every drawn step matches the ## Steps table on number and name" \
  check_steps "$LIFECYCLE" "$SKILL"

# ============================================================
echo ""
echo "=== E — hook-chain's armed lane is SKILL.md's frontmatter, both directions ==="
# ============================================================

expect_true "the armed lane names exactly the hooks the frontmatter registers" \
  check_armed "$HOOKCHAIN" "$SKILL"

# ============================================================
echo ""
echo "=== F — no phantom hooks: every script either diagram names exists ==="
# ============================================================

_missing=""
for _svg in "$HOOKCHAIN" "$LIFECYCLE"; do
  for _name in $(svg_body "$_svg" | grep -oE '[A-Za-z0-9._-]+\.sh' | sort -u); do
    case "$_name" in
      *.test.sh) continue ;;                       # suites, not hooks
      claude-bootstrap.sh|claude-reset.sh) continue ;;
    esac
    [ -f "${BIONIC_HOOKS_DIR}/${_name}" ] || _missing="${_missing}${_name} "
  done
done
expect_eq "every hook script named in either diagram exists in hooks/" "" "$_missing"

# ============================================================
echo ""
echo "=== G — meta-evidence: each pin goes RED against a doctored copy ==="
# ============================================================

# G1. diagram-side version drift — the version rendering moves alone.
sed 's/canonical_sdlc_version == 14/canonical_sdlc_version == 99/' "$HOOKCHAIN" > "$TMP/hc-version-drift.svg"
expect_false "meta: a diagram-side version drift is detected" \
  check_versions "$VERSION" "$TMP/hc-version-drift.svg" "$LIFECYCLE"

# G2. code-side version drift — the hook moves and the diagram does not.
expect_false "meta: a code-side version bump the diagrams missed is detected" \
  check_versions "99999" "$HOOKCHAIN" "$LIFECYCLE"

# G3. a dropped version rendering — deletion is the drift nobody notices.
grep -v 'data-pin="lifecycle-title"' "$LIFECYCLE" > "$TMP/lc-pin-dropped.svg"
expect_false "meta: a deleted version rendering is detected" \
  check_versions "$VERSION" "$HOOKCHAIN" "$TMP/lc-pin-dropped.svg"

# G4. diagram-side hook drift — a drawn entry names the wrong script.
sed 's/data-hook="landing-gate.sh"/data-hook="stop-guard.sh"/' "$HOOKCHAIN" > "$TMP/hc-hook-drift.svg"
expect_false "meta: a mis-drawn hook entry is detected" \
  check_hook_entries "$TMP/hc-hook-drift.svg" "$HOOKS_JSON"

# G5. diagram-side structural loss — a whole entry vanishes from the lane.
grep -v 'data-hook="protect-database.sh"' "$HOOKCHAIN" > "$TMP/hc-entry-dropped.svg"
expect_false "meta: a missing hook entry is detected" \
  check_hook_entries "$TMP/hc-entry-dropped.svg" "$HOOKS_JSON"

# G6. code-side hook drift — hooks.json gains a registration the diagram never drew.
python3 - "$HOOKS_JSON" "$TMP/hooks-extra.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
doc["hooks"].setdefault("PreToolUse", []).append(
    {"matcher": "Read", "hooks": [{"type": "command", "command": "x/hooks/newcomer.sh", "timeout": 10}]})
json.dump(doc, open(sys.argv[2], "w"))
PY
expect_false "meta: a new hooks.json registration the diagram never drew is detected" \
  check_hook_entries "$HOOKCHAIN" "$TMP/hooks-extra.json"

# G7. diagram-side step drift — a step is renamed in the picture only.
sed 's/data-step-name="Verify"/data-step-name="Validate"/' "$LIFECYCLE" > "$TMP/lc-step-drift.svg"
expect_false "meta: a renamed step in the diagram is detected" \
  check_steps "$TMP/lc-step-drift.svg" "$SKILL"

# G8. doctrine-side step drift — SKILL.md renames a step and the diagram does not.
sed 's/^| 7 Document |/| 7 Record |/' "$SKILL" > "$TMP/skill-step-drift.md"
expect_false "meta: a step renamed in SKILL.md the diagram missed is detected" \
  check_steps "$LIFECYCLE" "$TMP/skill-step-drift.md"

# G9. armed-lane drift — the frontmatter registers a hook the diagram never drew.
awk 'NR==1 && /^---/{print; print "  SessionStart:"; print "    - hooks:";
     print "        - type: command"; print "          command: ${CLAUDE_PLUGIN_ROOT}/hooks/newcomer.sh"; next} {print}' \
     "$SKILL" > "$TMP/skill-armed-drift.md"
expect_false "meta: a newly armed hook the diagram never drew is detected" \
  check_armed "$HOOKCHAIN" "$TMP/skill-armed-drift.md"

# G10. the comment-blindness guarantee itself: each SVG's header documents the class
# names, and svg_body() is what keeps that documentation from counting as elements.
expect_true "hook-chain.svg's header does mention class=\"hook-entry\" in prose" \
  grep -q 'class="hook-entry"' "$HOOKCHAIN"
expect_eq "…and the extractor still sees exactly six entries, not seven" \
  "6" "$(svg_hook_entries "$HOOKCHAIN" | grep -c .)"

# G11. the twice-regressed critic bullet (review F-6 → rfold fix → rfold2 revert,
# delta-audit D-1): free prose in a node is invisible to every structural pin, and
# this one string has now been broken twice — so it gets its own literal pin.
# "(audited)" is the reviewed fix; "at audited" is the dangling-adjective defect.
expect_true "lifecycle.svg names the independent critic with '(audited)', the reviewed form" \
  grep -q 'independent critic (audited)' "$LIFECYCLE"
expect_false "…and the dangling-adjective regression 'critic at audited' is absent" \
  grep -q 'independent critic at audited' "$LIFECYCLE"

# ============================================================
echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
