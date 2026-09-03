#!/bin/bash
# tests/doctor-reads.test.sh — the facts doctor gathered and never printed, and
# the pnpm-store diagnosis (bionic 1.4.0, wave-bionic-1.4.0-update slice DOCTOR
# handoff 4.6, spec AC-23).
#
# THE TWO CONTRACTS UNDER TEST.
#
#   (a) pnpm-store, UNREADABLE-INDEX DIAGNOSIS. `_dep_check_pnpm_store` answers
#       `unknown` in exactly three situations — pnpm is not on PATH, the store
#       path did not resolve, or the store holds no `index.db` — and doctor
#       answered all three with one sentence: "a cache, no presence surface".
#       That sentence stopped being true at the commit that gave the store a
#       surface (its index names every cached `<name>@<version>`), and a reader
#       told a cache has no surface cannot act, while a reader told which file
#       could not be read can.
#
#   (b) COMPUTED, NEVER PRINTED. Four probes ran on every doctor invocation and
#       reached no reader: the installed agent copies and their drift, the
#       legacy hook files on disk, the duplicate-registry scan, and the path of
#       the legacy installed skill copy. A probe nobody renders is a cost with no
#       benefit and, worse, a fact this machine HAD and did not tell anyone.
#
# HERMETIC. Every fixture is built under one mktemp root: a claude-home whose
# `agents/`, `hooks/` and `skills/` hold planted leftovers, a plugin registry
# written by hand, and a pnpm shim on a prepended PATH so the store branch can be
# driven without this machine's own pnpm.
#
# ASSERTION-HELPER RACE. No `printf | grep -q` anywhere below.
#
# Usage: bash tests/doctor-reads.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
PAYLOAD="${REPO}/payload"
DOCTOR_SH="${PAYLOAD}/scripts/doctor.sh"

command -v jq >/dev/null 2>&1 || { echo "doctor-reads.test.sh: jq is required"; exit 1; }

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }
expect_true()  { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then ok "$label"; else no "$label" "no match for '$pattern' in: $(printf '%.700s' "$actual")"; fi
}
expect_no_match() {
  local label="$1" pattern="$2" actual="$3"
  # shellcheck disable=SC2053  # RHS is a glob on purpose
  if [[ "$actual" == $pattern ]]; then no "$label" "unexpected match for '$pattern'"; else ok "$label"; fi
}

# A SHORT ROOT ON PURPOSE. macOS hands `mktemp -d` a ~50-character path under
# /var/folders, and two of the rows below print a PATH inside a 100-column row —
# a fixture path half again longer than a real `~/.claude` would be measures the
# truncator rather than the row. `/tmp/...` is the shape a real machine has.
TMP="$(mktemp -d /tmp/bionic-doctor-reads.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

CHOME="${TMP}/claude-home"
mkdir -p "${CHOME}/plugins"
FIXTURE_RC="${TMP}/dot.zshrc"
: > "$FIXTURE_RC"

# A pnpm that answers nothing: the store path comes from BIONIC_PNPM_STORE in
# every case below, so the shim exists only to make `command -v pnpm` true.
SHIMS="${TMP}/bin"
mkdir -p "$SHIMS"
printf '#!/bin/sh\nexit 0\n' > "${SHIMS}/pnpm"
chmod +x "${SHIMS}/pnpm"

run_doctor() {  # [extra env assignments as NAME=VALUE ...]
  ( cd "$REPO" && env "$@" \
      PATH="${SHIMS}:${PATH}" HOME="$TMP" BIONIC_SHELL_RC="$FIXTURE_RC" \
      BIONIC_CLAUDE_HOME="$CHOME" BIONIC_PLUGIN_ROOT="$PAYLOAD" \
      BIONIC_DOCTOR_PROBE_SECONDS=3 \
      bash "$DOCTOR_SH" < /dev/null 2>&1 )
}

echo "=== Section 1: pnpm-store — the cause names the file that could not be read ==="

# A store directory with no index.db. `_dep_check_pnpm_store` answers `unknown`
# here, and the row's cause is what this section is about.
EMPTY_STORE="${TMP}/pnpm-store-empty"
mkdir -p "$EMPTY_STORE"

OUT1="$(run_doctor "BIONIC_PNPM_STORE=${EMPTY_STORE}")"
ROW1="$(printf '%s\n' "$OUT1" | awk '/motion/')"

expect_match "1: the row names the missing store index" \
  "*motion*no store index at*" "$ROW1"
expect_no_match "2: the retired 'no presence surface' sentence is gone from the motion row" \
  "*motion*no presence surface*" "$ROW1"

echo ""
echo "=== Section 2: pnpm-store — a readable index answers, and says nothing extra ==="

FULL_STORE="${TMP}/pnpm-store-full"
mkdir -p "$FULL_STORE"
# `_dep_check_pnpm_store` runs `strings` over the index and matches
# `<name>@<version>`; a plain file carrying that token is enough of an index.
printf 'some binary-ish preamble\nmotion@12.3.4\nmore\n' > "${FULL_STORE}/index.db"

OUT2="$(run_doctor "BIONIC_PNPM_STORE=${FULL_STORE}")"
ROW2="$(printf '%s\n' "$OUT2" | awk '/motion/')"

expect_match "3: a readable index reports the cached version" "*motion*12.3.4*" "$ROW2"
expect_no_match "4: and carries no unreadable-index cause" "*index.db*" "$ROW2"

echo ""
echo "=== Section 3: the installed agent copies, and their drift, reach the page ==="

# A payload agent copied into the claude-home and then EDITED: the probe's
# `drift` count is exactly this, and nothing rendered it.
mkdir -p "${CHOME}/agents"
_first_agent="$(ls "${PAYLOAD}/agents/"*.md 2>/dev/null | head -1)"
expect_true "5: the payload ships agents to compare against" test -n "$_first_agent"
_agent_name="${_first_agent##*/}"
cp "$_first_agent" "${CHOME}/agents/${_agent_name}"
printf '\n# a local edit\n' >> "${CHOME}/agents/${_agent_name}"

OUT3="$(run_doctor "BIONIC_PNPM_STORE=${FULL_STORE}")"

expect_match "6: the drifted installed copy is named" \
  "*installed agent*${_agent_name}*" "$OUT3"
expect_match "7: and it carries a repair" "*installed agent*/bionic:setup*" "$OUT3"

echo ""
echo "=== Section 4: legacy hook files on disk reach the page ==="

mkdir -p "${CHOME}/hooks"
cp "${PAYLOAD}/hooks/protect-main.sh" "${CHOME}/hooks/protect-main.sh" 2>/dev/null
cp "${PAYLOAD}/hooks/stop-guard.sh" "${CHOME}/hooks/stop-guard.sh" 2>/dev/null

OUT4="$(run_doctor "BIONIC_PNPM_STORE=${FULL_STORE}")"

expect_match "8: the count of legacy hook FILES is printed" "*legacy hook file*2*" "$OUT4"
expect_match "9: and it carries a repair" "*legacy hook file*/bionic:setup*" "$OUT4"

echo ""
echo "=== Section 5: the legacy skill copy names its path ==="

mkdir -p "${CHOME}/skills/canonical-sdlc"
printf -- "---\nname: canonical-sdlc\n---\n" > "${CHOME}/skills/canonical-sdlc/SKILL.md"

OUT5="$(run_doctor "BIONIC_PNPM_STORE=${FULL_STORE}")"

# HOME-RELATIVE, which is both what fits the row and what a reader would type.
# `run_doctor` sets HOME=$TMP and the claude-home under it, so the row reads
# `~/claude-home/skills/canonical-sdlc`.
expect_match "10: the row names the directory a reader has to go to" \
  "*legacy installed skill copy*~/claude-home/skills/canonical-sdlc*" "$OUT5"

echo ""
echo "=== Section 6: the duplicate-registry scan reaches the page ==="

# One plugin registered twice under two marketplaces — the state the probe was
# written for, and whose consolidation command it already computes.
jq -nc '{plugins:{
    "bionic@bionic":[{installPath:"/nonexistent/a", gitCommitSha:"deadbeef"}],
    "bionic@my-fork":[{installPath:"/nonexistent/b", gitCommitSha:"cafebabe"}]
  }}' > "${CHOME}/plugins/installed_plugins.json"

OUT6="$(run_doctor "BIONIC_PNPM_STORE=${FULL_STORE}")"

expect_match "11: the duplicate is named" "*duplicate*bionic*" "$OUT6"
expect_match "12: with the consolidation command the probe computed" \
  "*claude plugin uninstall bionic@my-fork*" "$OUT6"

echo ""
echo "=== Section 7: nothing this file gathers is left unrendered ==="

# THE STRUCTURAL HALF, and it is the one that keeps this class of defect from
# coming back: a top-level assignment in doctor.sh whose name is never read
# anywhere else in the file is a probe that ran for nobody. Four such reads are
# what this slice was dispatched about; the assertion is that the count does not
# GROW, which is what a hardcoded allow-list gives and a bare zero would not
# (the roster-footprint block and the dependency tallies are dead too, are out of
# this slice, and are named here so the wall is honest about what it tolerates).
# WHAT THIS WALL DELIBERATELY TOLERATES, and it is a bigger list than the four
# reads this slice was dispatched about. `DEP_ROWS` is the whole DEPENDENCIES
# table and `ROSTER_ROWS` the whole roster-footprint table: both are built row by
# row on every invocation and NEITHER IS EVER PRINTED — doctor's own header still
# describes "three tables", and only two of them reach the page. The five
# dependency tallies and `TODO_STATE` are dead beside them. Rendering or deleting
# those is a decision about what the report IS, not a cosmetic read, so this slice
# names them here rather than settling them quietly (DOCTOR report, concerns).
KNOWN_DEAD="N_PRESENT N_ABSENT N_UNKNOWN N_VIOLATION N_ABSENT_WHEN_NEEDED ROSTER_TOTAL ROSTER_TOTAL_KNOWN ROSTER_ZERO TODO_STATE DEP_ROWS ROSTER_ROWS"
if ! command -v python3 >/dev/null 2>&1; then
  no "13: python3 is needed for the never-read sweep"
else
  UNREAD="$(python3 - "$PAYLOAD/scripts/doctor.sh" "$KNOWN_DEAD" <<'PY'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
allowed = set(sys.argv[2].split())
names = set(re.findall(r'^([A-Z_][A-Z0-9_]*)=', src, re.M))
names |= set(re.findall(r';\s*([A-Z_][A-Z0-9_]*)=', src))
# STATEMENTS, NOT LINES. `FACT="$(probe)"; STATE="${FACT#...}"` is two statements
# on one line, and at line granularity the second one's read of FACT is masked by
# the first one's assignment to it.
stmts = [st for ln in src.splitlines() for st in ln.split(';')]
dead = []
for n in sorted(names):
    if n in allowed:
        continue
    # Every line that ASSIGNS to n is dropped first, so `n=$((n + 1))` — a
    # counter incrementing itself — does not count as somebody reading it.
    read_somewhere = False
    for ln in stmts:
        targets = set(re.findall(r'(?:^|;|\s)([A-Z_][A-Z0-9_]*)=', ln))
        # `$n` / `${n}` is a read wherever it appears; a BARE `n` counts only on
        # a line that does not assign to n, which is what tells a counter
        # incrementing itself apart from somebody else consuming it.
        if re.search(r'\$\{?' + n + r'\b', ln) and n not in targets:
            read_somewhere = True; break
        if n not in targets and re.search(r'\b' + n + r'\b', ln):
            read_somewhere = True; break
    if not read_somewhere:
        dead.append(n)
print(' '.join(dead))
PY
)"
  if [ -z "$UNREAD" ]; then ok "13: every fact doctor gathers is read by something"
  else no "13: a fact is computed and never read" "$UNREAD"; fi
fi

echo ""
echo "=== Section 8: registration, and the column budget ==="

expect_true "14: tests/run.sh names doctor-reads.test.sh" \
  grep -q 'run "doctor-reads.test.sh" bash tests/doctor-reads.test.sh' "${REPO}/tests/run.sh"

too_wide() {
  printf '%s\n' "$1" | awk '
    { s = $0
      gsub(/✓|✗|–|—|≥|…|·|→|•/, ".", s)
      if (length(s) > 100) print length(s) ": " $0 }'
}
_over="$(too_wide "$OUT6")"
if [ -z "$_over" ]; then ok "15: every line of the fullest run fits 100 columns"
else no "15: a line exceeds 100 columns" "$_over"; fi

echo ""
echo "========================================"
echo "doctor-reads: $PASS/$TOTAL passed"
echo "========================================"

[ "$FAIL" -eq 0 ] || exit 1
