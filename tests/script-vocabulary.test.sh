#!/usr/bin/env bash
# SCRIPT DISPLAY VOCABULARY — epic-17 wave-06 slice S4 (spec R3, AC-6; design ledger D-C).
#
# WHAT THIS SUITE OWNS. The words the three payload scripts PRINT. AC-6 has two halves and
# tests/voice-contract.test.sh owns the other one: that suite lints the four command files
# the model reads, this one lints every line `setup.sh`, `doctor.sh` and `remove.sh` put on
# the user's terminal. Both read the SAME list —
# `tests/fixtures/banned-display-vocabulary.txt` — because the ownership table names "one
# list file under tests/" precisely so the two lints cannot drift to two opinions about what
# counts as internal (D-C; Chris, 2026-08-20: "This concept of 'lane' and in particular
# references to '3b' are very confusing. Why are we exposing this to the user?").
#
# WHAT IT DOES NOT OWN. The list's contents (S1 authored it and the fixture's own header
# states the format), the four command files (voice-contract.test.sh), and anything about
# what the scripts DO. A script may name a lane in a comment, a variable, or a function all
# day long; this suite only ever judges text that reaches a terminal.
#
# ─────────────────────────────────────────────────────────────────────────────────────────
# HOW "WHAT THE SCRIPT PRINTS" IS DECIDED, and why it is not simply "every string literal".
#
# A bash script's literals are a mix of display text and machinery — `[ "$lane" != "3a" ]`
# is a comparison, not a sentence, and a lint that failed on it would push the internal
# taxonomy out of the CODE, which is not what anybody asked for. So the extractor
# (`display_text` below) takes literals from exactly two contexts:
#
#   1. a DISPLAY VERB at command position — `say`, `echo`, `printf`, `action`, `consent`,
#      and the four `_rm_*` reporters plus the two `*_consent` prompts. Those are every
#      sink through which these three scripts reach a terminal; a prompt counts because the
#      user reads the question before answering it.
#   2. a SELF-APPENDING ACCUMULATOR — `VAR="${VAR}…"`. A string appended to itself exists
#      to be printed later, and it is where two of the real defects lived: doctor's
#      DEGRADATION lines and setup's action lines are built this way, never echoed in
#      place. A verb-only extractor is green on both.
#
# From a display line it takes the quoted literals AND the bare word arguments — `printf
# '%-5s %s\n' lane name` prints the word `lane`, and only the format string is quoted.
#
# What it blanks out, on purpose: `$(command substitutions)`, `${parameter}` expansions and
# `$bare` variables. A function or variable NAME is not text the user reads; the VALUE is,
# and no source lint can see a value. Shell comments are dropped by the same scanner that
# tracks quote state, so a comment mentioning a lane is not a leak of it.
#
# THIS LEAVES ONE HONEST BLIND SPOT, stated rather than hidden: a banned token that only
# ever appears as a runtime VALUE is invisible here. doctor's dependency table prints
# `3a`/`3b` in its first column because `dep_field <row> lane` returns them, and no
# source-text lint can catch that. It is recorded as a finding against S6 (which owns
# doctor's display; tests/doctor.test.sh:437-439 and plan assumption A-4.S3.7 already
# assign it) and as the second exemption below.
#
# EXEMPTIONS ARE PINNED TO THEIR OWN GAP. Section D asserts every exemption still MATCHES
# something. The day the exempted line is fixed or deleted, this suite fails and the
# exemption has to be removed with it — the same shape S3 used for the `motion` consumer
# gap, and the reason an exemption here cannot quietly become permanent.
#
# HERMETIC. Reads committed files; the mutation arm in Section E writes only into a scratch
# copy. No network, no `claude`, nothing under payload/ opened for writing.
#
# ASSERTION-HELPER RACE. Pipe-free by construction (tests/assert-helper-race.test.sh):
# containment is bash `[[ == * ]]` in-process, and every grep runs against a FILE argument.
#
# Usage: bash tests/script-vocabulary.test.sh
# Registered by name in tests/run.sh (tests/*.test.sh is NOT auto-globbed).

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
BANNED_LIST="${REPO}/tests/fixtures/banned-display-vocabulary.txt"
SCRIPTS="setup.sh doctor.sh remove.sh"

PASS=0; FAIL=0; TOTAL=0
ok() { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && echo "      $2"; return 0; }

expect_true()     { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }
expect_eq()       { local label="$1" want="$2" got="$3"; if [ "$got" = "$want" ]; then ok "$label"; else no "$label" "expected='${want}' actual='${got}'"; fi; }
expect_contains() { local label="$1" needle="$2" hay="$3"; if [[ "$hay" == *"$needle"* ]]; then ok "$label"; else no "$label" "expected to contain '${needle}'"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# EXEMPTIONS — <script>|<needle>|<why>
#
# A display line whose text contains <needle> is not judged. Two, both with a named owner
# and both pinned live by Section D. Adding a third is a decision, not a convenience: an
# exemption is a hole in a wall, and the only thing that keeps it honest is that it is
# written here in full where a reviewer reads it.
# ---------------------------------------------------------------------------

EXEMPTIONS="$(cat <<'EXEMPT'
doctor.sh|set -o pipefail; curl|the half-uninstalled SUMMARY prints a command for the user to PASTE, and the wrapper is the fix half of a real error: without it `curl … | bash` reports bash's status, so a 404 leaves a command that looked like it worked and removed nothing (doctor.sh's own note above the line). The fixture's header excludes "the fix half of a real error message" from what the list is for; dropping the wrapper would change what the command does, not how it reads.
EXEMPT
)"

# ---------------------------------------------------------------------------
# The extractor. Written to a file so the same awk program serves every arm and
# the mutation arm in Section E measures the production one, not a variant.
# ---------------------------------------------------------------------------

EXTRACT="$TMP/display-text.awk"
cat > "$EXTRACT" <<'AWK'
# Blank every $-expansion out of one literal and print what is left.
function emit(t) {
  gsub(/\$\([^)]*\)/, " ", t)          # $(cmd) closed on this line
  gsub(/\$\(.*/, " ", t)               # $(cmd continued on the next line
  gsub(/\$\{[^}]*\}/, " ", t)          # ${param}
  gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, " ", t)   # $bare
  if (t ~ /[^ \t]/) print NR "\t" t          # source line number, then the text
}
{
  line = $0; n = length(line); i = 1
  inq = ""; seg = ""; segs = ""; bare = ""; prev = ""
  # One pass, tracking quote state: collect quoted spans, collect the unquoted
  # remainder, and stop at a comment `#` that is not inside quotes.
  while (i <= n) {
    c = substr(line, i, 1)
    if (inq == "") {
      if (c == "#" && (prev == "" || prev == " " || prev == "\t" || prev == ";")) break
      if (c == "'" || c == "\"") { inq = c; seg = "" }
      else if (c == "\\") { i++ }
      else bare = bare c
    } else if (c == inq) {
      segs = segs seg "\n"; inq = ""; bare = bare " "
    } else if (inq == "\"" && c == "\\") {
      seg = seg substr(line, i + 1, 1); i++
    } else {
      seg = seg c
    }
    prev = c; i++
  }
  if (inq != "") segs = segs seg "\n"   # a literal continued onto the next line

  isprint = (line ~ /(^|[ \t;&|(]|\{)(say|echo|printf|action|consent|_dep_consent|_rm_consent|_rm_removed|_rm_clean|_rm_skipped|_rm_leftover)[ \t]/)

  # A self-appending accumulator: VAR=…${VAR}… — built to be printed later. The
  # assignment is looked for at any command position, not just at the start of
  # the line: `action() { SETUP_ACTIONS="${SETUP_ACTIONS}${1}"; }` is a one-line
  # function whose whole body is the append, and a start-anchored match misses
  # exactly the accumulator that carries setup's action lines.
  isacc = 0
  if (match(line, /(^|[ \t;&|{(])[A-Za-z_][A-Za-z0-9_]*=/)) {
    v = substr(line, RSTART, RLENGTH)
    sub(/^[^A-Za-z_]+/, "", v); sub(/=$/, "", v)
    if (line ~ ("\\$\\{?" v "\\}?")) isacc = 1
  }
  if (!isprint && !isacc) next

  m = split(segs, parts, "\n")
  for (k = 1; k <= m; k++) if (parts[k] != "") emit(parts[k])

  # Bare word arguments to a print verb are printed too (printf '%s' lane name).
  if (isprint) {
    sub(/^[ \t]*/, "", bare)
    nb = split(bare, bw, /[ \t]+/)
    for (k = 2; k <= nb; k++) if (bw[k] ~ /^[A-Za-z][A-Za-z0-9_-]*$/) print NR "\t" bw[k]
  }
}
AWK

display_text() { awk -f "$EXTRACT" "$1"; }

# banned_tokens: the fixture's tokens, comments and blank lines dropped. The format rule is
# the fixture's own (`#` comments, blank lines ignored, case-insensitive SUBSTRING match);
# this is the same reader tests/voice-contract.test.sh uses, deliberately.
banned_tokens() {
  awk '
    { sub(/^[[:space:]]+/, "") }
    /^#/ { next }
    /^$/ { next }
    { print }
  ' "$BANNED_LIST"
}

# exempt <script> <source-file> <lineno>: 0 when THE SOURCE LINE the display text came from
# is covered by an exemption. The needle is matched against the source line, not against
# the extracted text: one source line can yield several display strings (a printf's format
# and each of its bare-word arguments), and an exemption is a statement about the line.
exempt() {
  local script="$1" src="$2" lineno="$3" row s needle srcline
  srcline="$(awk -v n="$lineno" 'NR == n { print; exit }' "$src")"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    s="${row%%|*}"
    [ "$s" = "$script" ] || continue
    needle="${row#*|}"; needle="${needle%%|*}"
    [[ "$srcline" == *"$needle"* ]] && return 0
  done <<< "$EXEMPTIONS"
  return 1
}

# lint_file <script-name> <source-file> <extracted-text-file>: `<token>  <display line>`
# per hit, exemptions already applied. Silence is the passing state.
lint_file() {
  local script="$1" src="$2" text="$3" tok row lineno line
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      lineno="${row%%	*}"; line="${row#*	}"
      exempt "$script" "$src" "$lineno" && continue
      printf '%s\t%s:%s\t%s\n' "$tok" "$script" "$lineno" "$line"
    done < <(grep -iF -- "$tok" "$text" 2>/dev/null)
  done < "$TMP/banned-tokens.txt"
}

# banned_hits <script>: the production lint for one payload script.
banned_hits() {  # <script-basename>
  # Two statements, not one `local`: a builtin's arguments are word-expanded BEFORE the
  # assignments take effect, so `text="$TMP/text.${script}"` on the same line reads an
  # unset `script` and (under `set -u`) leaves the extraction empty — a lint that silently
  # judges nothing. It did exactly that on this file's first run.
  local script="$1"
  local src="${REPO}/payload/scripts/${script}" text="$TMP/text.${script}"
  display_text "$src" > "$text"
  lint_file "$script" "$src" "$text"
}

banned_tokens > "$TMP/banned-tokens.txt"

# ---------------------------------------------------------------------------
echo ""
echo "=== A — the sources exist ==="
# ---------------------------------------------------------------------------

expect_true "the banned-vocabulary list exists and is non-empty" test -s "$BANNED_LIST"
for s in $SCRIPTS; do
  expect_true "payload/scripts/${s} exists" test -f "${REPO}/payload/scripts/${s}"
done
expect_true "the list carries at least one token" \
  bash -c '[ "$(wc -l < "$1" | tr -d " ")" -gt 0 ]' _ "$TMP/banned-tokens.txt"

# The two lints read ONE list. A second copy of the tokens anywhere under tests/ is the
# drift the ownership table exists to prevent, so the path is asserted, not just the file.
expect_contains "the list is the one tests/voice-contract.test.sh reads" \
  "tests/fixtures/banned-display-vocabulary.txt" \
  "$(grep -c 'banned-display-vocabulary' "${REPO}/tests/voice-contract.test.sh" >/dev/null && echo 'tests/fixtures/banned-display-vocabulary.txt')"

# ---------------------------------------------------------------------------
echo ""
echo "=== B — the extractor finds real display text ==="
# ---------------------------------------------------------------------------
#
# A lint that extracts nothing passes everything. Each script's extracted text is asserted
# non-trivial and asserted to contain a line only that script prints — so a broken
# extractor fails loudly here rather than going quietly green in Section C.

for s in $SCRIPTS; do
  display_text "${REPO}/payload/scripts/${s}" > "$TMP/text.check.${s}"
  expect_true "${s}: the extractor yields more than 40 display lines" \
    bash -c '[ "$(wc -l < "$1" | tr -d " ")" -gt 40 ]' _ "$TMP/text.check.${s}"
done

expect_true "setup.sh: a step header is extracted" \
  grep -qF "1. Plugin" "$TMP/text.check.setup.sh"
expect_true "setup.sh: an action line built by the accumulator is extracted" \
  grep -qF "claude plugin install" "$TMP/text.check.setup.sh"
expect_true "doctor.sh: a section header is extracted" \
  grep -qF "=== DEPENDENCIES ===" "$TMP/text.check.doctor.sh"
expect_true "doctor.sh: a DEGRADATION line built by the accumulator is extracted" \
  grep -qF "run /bionic:setup" "$TMP/text.check.doctor.sh"
expect_true "remove.sh: a reporter line is extracted" \
  grep -qiF "already clean" "$TMP/text.check.remove.sh"

# A comment is not display text, and neither is a variable name. Both are checked against
# text that really is in the file, so the exclusions are measured and not assumed.
expect_true "a shell comment is not treated as display text" \
  bash -c '! grep -qF "Executed, never sourced" "$1"' _ "$TMP/text.check.setup.sh"
expect_true "a function name inside a command substitution is not display text" \
  bash -c '! grep -qF "_dep_settings_file" "$1"' _ "$TMP/text.check.setup.sh"

# ---------------------------------------------------------------------------
echo ""
echo "=== C — the lint: no internal vocabulary reaches a terminal (AC-6) ==="
# ---------------------------------------------------------------------------

for s in $SCRIPTS; do
  HITS="$(banned_hits "$s")"
  expect_eq "${s} prints no banned display vocabulary" "" "$HITS"
done

# ---------------------------------------------------------------------------
echo ""
echo "=== D — every exemption still covers a live line ==="
# ---------------------------------------------------------------------------
#
# An exemption that stops matching is an exemption nobody removed. Each is asserted to
# match at least one extracted display line TODAY, so closing the gap it names turns this
# arm red and forces the exemption out with the defect.

while IFS= read -r row; do
  [ -n "$row" ] || continue
  ex_script="${row%%|*}"
  ex_needle="${row#*|}"; ex_needle="${ex_needle%%|*}"
  expect_true "exemption is live: ${ex_script} still carries the line '${ex_needle}'" \
    grep -qF -- "$ex_needle" "${REPO}/payload/scripts/${ex_script}"
done <<< "$EXEMPTIONS"

expect_eq "there is exactly one exemption (the lane header exemption retired when S6 landed the class column)" "1" \
  "$(printf '%s\n' "$EXEMPTIONS" | grep -c '|')"

# ---------------------------------------------------------------------------
echo ""
echo "=== E — the lint discriminates (mutation and restore) ==="
# ---------------------------------------------------------------------------
#
# Section C is an assertion of ABSENCE, and an absence proves nothing about the machinery
# that looked for it. Each arm below plants one defect into a scratch copy of setup.sh in a
# DIFFERENT display context and requires the lint to find it — then the production file is
# re-linted to show it is still clean.

mutate_and_lint() {  # <label> <sed-program>
  local label="$1" program="$2" hits
  sed "$program" "${REPO}/payload/scripts/setup.sh" > "$TMP/mutated.sh"
  display_text "$TMP/mutated.sh" > "$TMP/text.mutated"
  hits="$(lint_file "setup.sh" "$TMP/mutated.sh" "$TMP/text.mutated")"
  if [ -n "$hits" ]; then ok "MUTATED (${label}): the lint catches it"
  else no "MUTATED (${label}): the lint catches it" "no banned token found in the mutated copy"; fi
}

# 1 — a quoted literal handed straight to `say`.
mutate_and_lint "say with a lane in a quoted header" \
  's|say "1. Plugin"|say "1. Plugin — lane 3a"|'
# 2 — a bare word argument to printf, the shape a column header takes.
mutate_and_lint "printf with a bare-word column header" \
  "s|^say \"bionic setup|printf '  %s\\\\n' lane\nsay \"bionic setup|"
# 3 — a self-appending accumulator, the shape an action line takes. The defect
# is planted INSIDE the append so the mutated line is still an accumulator; a
# plain assignment would not be one, and would prove nothing about this arm.
mutate_and_lint "an action line built by the accumulator" \
  's|SETUP_ACTIONS="${SETUP_ACTIONS}${1}"|SETUP_ACTIONS="${SETUP_ACTIONS}lane 3b: ${1}"|'

RESTORED="$(banned_hits setup.sh)"
expect_eq "RESTORED (production setup.sh): still clean" "" "$RESTORED"
expect_true "production setup.sh still parses after the mutation arms" \
  bash -n "${REPO}/payload/scripts/setup.sh"

# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
