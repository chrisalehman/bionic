#!/bin/bash
# Tests for tests/reader-exam/ — the reader exam's pin (wave-27 T18; spec D11, AC-5.3, AC-4.4).
#
# THE EXAM ITSELF IS NOT RUN HERE. A sitting dispatches live readers (README.md in
# tests/reader-exam/), and no hermetic suite can. What this suite owns is what a machine can
# hold the exam to: the checks files the readers were examined on are the ones that ship, and
# the latest sitting had readers behind it who met every sample. Seven sections:
#
#   §PIN      `exam_pin` on planted sittings: the latest sitting, by file order, has the
#             three `sha256` lines equal to the files' digests, a `result` line for every
#             sample, and no `missed`; otherwise the verdict is red and names why. A checks
#             file edited after its sitting turns it red.
#   §OWED     until the first sitting, `sittings.md` carries the owed line; that line alone
#             passes, neither it nor a sitting is red, and both together are red.
#   §KEY      `exam_key` on planted keys: three lines for `clean`, four for every other
#             sample, the fourth a `names:` line.
#   §SCORE    `exam_score`, README step 4, on the real keys: a record is met only with the
#             key's result, one of its tokens and its `names:` identifier.
#   §DEST     materialize.sh refuses a destination whose path names the sample.
#   §SAMPLES  every sample has its answer key in shape and materializes into a two-commit
#             repository that the key does not travel into.
#   §SHIPPED  the shipped `sittings.md` against the shipped checks files.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"): §PIN and
# §OWED run the suite's own `exam_pin` — the same function §SHIPPED runs on the real files —
# over planted `sittings.md` files and a planted root holding three checks files of made-up
# text and two sample directories. SYNTHESIZED: the checks text and the hashes written into
# the planted sittings, which are taken by the same digest function the verdict uses, or
# deliberately wrong; the `result` lines. §KEY plants keys; §SAMPLES runs the same `exam_key`
# on the real ones. §SCORE plants reader records against the REAL keys. §DEST and §SAMPLES
# run the real samples through the real materialize.sh into real git repositories.
#
# ANTI-VACUITY (declared, per the same file, "Anti-vacuity"): every red verdict sits beside a
# green one from the same function on a fixture one edit away; the digest function is proved
# to return a 64-hex digest on every shipped checks file before any comparison reads it.
#
# Usage: bash tests/reader-exam.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO="${BIONIC_SCRIPTS_DIR}"
EXAM="${REPO}/tests/reader-exam"
# The digest: the one sha256 reader the payload already carries (reuse, not a fourth copy).
. "${REPO}/payload/scripts/lib/detect.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reader-exam-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

# The checks files, root-relative. Spelled out from the root, not built from the question
# names: tests/lib/impact.sh finds a suite's reach by the paths it names, and an edited checks
# file must reach this suite.
EXAM_CHECKS=""
for f in "${REPO}/payload/context/checks-evidence.md" "${REPO}/payload/context/checks-adversarial.md" \
         "${REPO}/payload/context/checks-structure.md"; do
  EXAM_CHECKS="${EXAM_CHECKS:+$EXAM_CHECKS }${f#"$REPO"/}"
done
EXAM_OWED_LINE="first-sitting: owed by wave-27 T22"

# exam_samples <root> — the sample names under <root>, one per line.
exam_samples() {
  (cd "$1/tests/reader-exam/samples" 2>/dev/null && for d in */; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done)
}

# exam_pin <sittings file> <root> — prints one verdict line, rc 0 only when the exam holds:
#   pinned                 the latest sitting names each checks file under <root> once, with
#                          its digest, has a `result` line for every sample under <root>,
#                          and every `result` line reads `met`
#   owed                   no sitting and the owed line (RE-AUTHORED BY T22: this arm goes
#                          when the first sitting is recorded)
#   red <reason>           anything else
# A sitting is a section headed `## <YYYY-MM-DD>…`; the latest is the last in the file, by
# file order and not by date.
exam_pin() {
  local file="$1" root="$2" sittings owed latest f lines want have s samples bad
  [ -r "$file" ] || { echo "red: $file cannot be read"; return 1; }
  sittings="$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$file")"
  owed="$(grep -cxF -- "$EXAM_OWED_LINE" "$file")"
  if [ "$sittings" -eq 0 ]; then
    [ "$owed" -gt 0 ] && { echo "owed"; return 0; }
    echo "red: no sitting is recorded and no line says the first is owed"; return 1
  fi
  [ "$owed" -eq 0 ] || { echo "red: a sitting is recorded and the owed line still says none is"; return 1; }
  latest="$(awk '/^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$file")"
  for f in $EXAM_CHECKS; do
    lines="$(printf '%s' "$latest" | awk -v f="$f" '$1 == "sha256" && $2 == f { print $3 }')"
    case "$(printf '%s' "$lines" | awk 'END { print NR }')" in
      1) want="$lines" ;;
      0) echo "red: the latest sitting has no sha256 line for $f"; return 1 ;;
      *) echo "red: the latest sitting has more than one sha256 line for $f"; return 1 ;;
    esac
    have="$(_detect_sha256 "$root/$f")" || { echo "red: $f cannot be digested"; return 1; }
    [ "$want" = "$have" ] || { echo "red: $f is $have, the latest sitting read $want — sit the exam again"; return 1; }
  done
  # A hash with no readers behind it is the pin lying: every sample was sat, and met.
  samples="$(exam_samples "$root")"
  [ -n "$samples" ] || { echo "red: $root has no samples"; return 1; }
  for s in $samples; do
    printf '%s\n' "$latest" | awk -v s="$s" '$1 == "result" && $2 == s { f = 1 } END { exit !f }' \
      || { echo "red: the latest sitting has no result line for $s"; return 1; }
  done
  bad="$(printf '%s\n' "$latest" | awk '$1 == "result" && $6 != "met" { print $2 " " $6; exit }')"
  case "$bad" in
    "") ;;
    *" missed") echo "red: the latest sitting missed ${bad% *} — send its checks file to a fix row and sit the exam again"; return 1 ;;
    *) echo "red: the latest sitting has a result line for ${bad%% *} that reads neither met nor missed"; return 1 ;;
  esac
  echo "pinned"
}

# exam_key <sample> <key file> — prints `key` when the answer key is in shape, else one red
# line. Three lines for `clean` (question, result, token); four for every other sample, the
# fourth `names: <one identifier>`: the one string that shows the record named the planted
# defect, which `clean` has none of.
exam_key() {
  local name="$1" key="$2" n want
  [ -r "$key" ] || { echo "red: $key cannot be read"; return 1; }
  sed -n 1p "$key" | grep -Eq '^question: (evidence|adversarial|structure)(, (evidence|adversarial|structure))*$' \
    || { echo "red: $name's key line 1 is not a question line"; return 1; }
  sed -n 2p "$key" | grep -Eq '^result: (pass|flag|fail)$' \
    || { echo "red: $name's key line 2 is not a result line"; return 1; }
  sed -n 3p "$key" | grep -Eq '^token: [^ ].*$' \
    || { echo "red: $name's key line 3 is not a token line"; return 1; }
  if [ "$name" = clean ]; then
    want=3
    ! grep -q '^names:' "$key" || { echo "red: clean's key has a names: line, and clean has no defect to name"; return 1; }
  else
    want=4
    sed -n 4p "$key" | grep -Eq '^names: [^ ]' || { echo "red: $name's key has no names: line"; return 1; }
    ! sed -n 4p "$key" | grep -qF ' | ' || { echo "red: $name's names: line holds more than one identifier"; return 1; }
  fi
  n="$(awk 'END { print NR }' "$key")"
  [ "$n" = "$want" ] || { echo "red: $name's key has $n lines, not $want"; return 1; }
  echo "key"
}

# exam_score <sample> <key file> <record> — README step 4: prints `met` or `missed`. Met when
# the record's first flush-left `result:` line is the key's result (on `clean`, `pass` or
# `flag`), one of the key's tokens (alternatives separated by ` | `) is in the record, and so
# is the key's `names:` identifier when it has one.
exam_score() {
  local name="$1" key="$2" rec="$3" want got toks tok hit=0 ident
  want="$(sed -n 's/^result: //p' "$key")"
  got="$(sed -n 's/^result: //p' "$rec" | head -n 1)"
  if [ "$name" = clean ]; then
    case "$got" in pass|flag) ;; *) echo "missed"; return 1 ;; esac
  else
    [ -n "$want" ] && [ "$got" = "$want" ] || { echo "missed"; return 1; }
  fi
  toks="$(sed -n 's/^token: //p' "$key")"
  while [ -n "$toks" ]; do
    tok="${toks%% | *}"
    [ "$tok" = "$toks" ] && toks="" || toks="${toks#* | }"
    grep -qF -- "$tok" "$rec" && hit=1
  done
  [ "$hit" = 1 ] || { echo "missed"; return 1; }
  ident="$(sed -n 's/^names: //p' "$key")"
  [ -z "$ident" ] || grep -qF -- "$ident" "$rec" || { echo "missed"; return 1; }
  echo "met"
}

# pin_call <sittings file> <root> — sets PIN_OUT and PIN_RC.
pin_call() { PIN_OUT="$(exam_pin "$1" "$2")"; PIN_RC=$?; }

setup_section "fixtures"

ROOT="$TMP/root"
mkdir -p "$ROOT/payload/context"
for f in $EXAM_CHECKS; do printf 'made-up checks text for %s\n' "$f" > "$ROOT/$f"; done
mkdir -p "$ROOT/tests/reader-exam/samples/dup-counter" "$ROOT/tests/reader-exam/samples/clean"

# sitting_block <date> [<question> <wrong hash>] — a sitting section for $ROOT, the hash of
# checks-<question>.md optionally replaced, with one `met` result line per sample.
sitting_block() {
  local f h s
  printf '## %s\n\n' "$1"
  for f in $EXAM_CHECKS; do
    h="$(_detect_sha256 "$ROOT/$f")"
    [ "$f" = "payload/context/checks-${2:-}.md" ] && h="${3}"
    printf 'sha256 %s %s\n' "$f" "$h"
  done
  printf '\n'
  for s in $(exam_samples "$ROOT"); do
    printf 'result %s structure reviewer fail met exam-sitting.md#%s\n' "$s" "$s"
  done
  printf '\n'
}
# with_result <file> <sample> <sixth field> — the file with that sample's result lines rewritten.
with_result() {
  awk -v s="$2" -v v="$3" '$1 == "result" && $2 == s { $6 = v } { print }' "$1"
}
WRONG="0000000000000000000000000000000000000000000000000000000000000000"

section "§PIN — the latest sitting's hashes against the checks files"

sitting_block 2026-10-05 > "$TMP/right.md"
pin_call "$TMP/right.md" "$ROOT"
expect_eq "P1: a sitting with the three right hashes is pinned" "pinned" "$PIN_OUT"
expect_status "P1: rc 0" 0 "$PIN_RC"

sitting_block 2026-10-05 structure "$WRONG" > "$TMP/wrong.md"
pin_call "$TMP/wrong.md" "$ROOT"
expect_contains "P2: one wrong hash is red and names its file" "red: payload/context/checks-structure.md is" "$PIN_OUT"
expect_status "P2: rc 1" 1 "$PIN_RC"

{ sitting_block 2026-10-05 evidence "$WRONG"; sitting_block 2026-10-06; } > "$TMP/old-wrong.md"
pin_call "$TMP/old-wrong.md" "$ROOT"
expect_eq "P3: an older wrong sitting under a right latest one is pinned" "pinned" "$PIN_OUT"
{ sitting_block 2026-10-05; sitting_block 2026-10-06 evidence "$WRONG"; } > "$TMP/new-wrong.md"
pin_call "$TMP/new-wrong.md" "$ROOT"
expect_contains "P3: a right older sitting does not excuse a wrong latest one" "red: payload/context/checks-evidence.md is" "$PIN_OUT"

grep -v 'checks-adversarial' "$TMP/right.md" > "$TMP/missing.md"
pin_call "$TMP/missing.md" "$ROOT"
expect_eq "P4: a sitting with no line for a checks file is red" \
  "red: the latest sitting has no sha256 line for payload/context/checks-adversarial.md" "$PIN_OUT"
{ cat "$TMP/right.md"; grep 'checks-evidence' "$TMP/right.md"; } > "$TMP/twice.md"
pin_call "$TMP/twice.md" "$ROOT"
expect_eq "P4: a sitting naming a checks file twice is red" \
  "red: the latest sitting has more than one sha256 line for payload/context/checks-evidence.md" "$PIN_OUT"

# The failure the pin exists for: a checks file changes and no one sits the exam again.
cp -R "$ROOT" "$TMP/edited"
printf 'one sharpened sentence\n' >> "$TMP/edited/payload/context/checks-adversarial.md"
pin_call "$TMP/right.md" "$TMP/edited"
expect_contains "P5: a checks file edited after its sitting turns the pin red" "red: payload/context/checks-adversarial.md is" "$PIN_OUT"
expect_status "P5: rc 1" 1 "$PIN_RC"
pin_call "$TMP/right.md" "$ROOT"
expect_eq "P5: the same sitting over the unedited files stays pinned" "pinned" "$PIN_OUT"

# A hash with no readers behind it: the right hashes, and a sample nobody sat or a reader who
# missed. right.md is the green one edit away from each.
expect_eq "P6: the fixture sitting has a result line for each of its two samples" "2" \
  "$(awk '$1 == "result"' "$TMP/right.md" | awk 'END { print NR }')"
grep -v '^result clean ' "$TMP/right.md" > "$TMP/unsat.md"
pin_call "$TMP/unsat.md" "$ROOT"
expect_eq "P6: a sitting with the right hashes and no result line for one sample is red and names it" \
  "red: the latest sitting has no result line for clean" "$PIN_OUT"
expect_status "P6: rc 1" 1 "$PIN_RC"
grep -v '^result ' "$TMP/right.md" > "$TMP/noreaders.md"
pin_call "$TMP/noreaders.md" "$ROOT"
expect_contains "P6: a sitting with the right hashes and no result line at all is red" \
  "red: the latest sitting has no result line for" "$PIN_OUT"

with_result "$TMP/right.md" clean missed > "$TMP/missed.md"
pin_call "$TMP/missed.md" "$ROOT"
expect_eq "P7: a sitting with the right hashes and a missed sample is red and names it" \
  "red: the latest sitting missed clean — send its checks file to a fix row and sit the exam again" "$PIN_OUT"
expect_status "P7: rc 1" 1 "$PIN_RC"
with_result "$TMP/right.md" clean mett > "$TMP/garbled.md"
pin_call "$TMP/garbled.md" "$ROOT"
expect_eq "P7: a result line reading neither met nor missed is red" \
  "red: the latest sitting has a result line for clean that reads neither met nor missed" "$PIN_OUT"

# "Latest" is the last sitting in the file, by file order: not the newest date.
{ sed 's/^## 2026-10-05/## 2026-10-04/' "$TMP/missed.md"; cat "$TMP/right.md"; } > "$TMP/order-resat.md"
pin_call "$TMP/order-resat.md" "$ROOT"
expect_eq "P8: the latest sitting, by file order: a miss sat again below it is pinned" "pinned" "$PIN_OUT"
{ cat "$TMP/right.md"; sed 's/^## 2026-10-05/## 2026-10-06/' "$TMP/unsat.md"; } > "$TMP/order-unsat.md"
pin_call "$TMP/order-unsat.md" "$ROOT"
expect_eq "P8: the latest sitting, by file order: a complete sitting above does not excuse an unsat sample" \
  "red: the latest sitting has no result line for clean" "$PIN_OUT"
{ sed 's/^## 2026-10-05/## 2026-10-06/' "$TMP/right.md"; cat "$TMP/missed.md"; } > "$TMP/order-date.md"
pin_call "$TMP/order-date.md" "$ROOT"
expect_eq "P8: the latest sitting, by file order: the last block governs though an earlier block has the later date" \
  "red: the latest sitting missed clean — send its checks file to a fix row and sit the exam again" "$PIN_OUT"

section "§OWED — before the first sitting"

printf '%s\n' "$EXAM_OWED_LINE" > "$TMP/owed.md"
pin_call "$TMP/owed.md" "$ROOT"
expect_eq "O1: the owed line and no sitting is owed" "owed" "$PIN_OUT"
expect_status "O1: rc 0" 0 "$PIN_RC"

: > "$TMP/neither.md"
pin_call "$TMP/neither.md" "$ROOT"
expect_eq "O2: neither the owed line nor a sitting is red" \
  "red: no sitting is recorded and no line says the first is owed" "$PIN_OUT"
expect_status "O2: rc 1" 1 "$PIN_RC"

{ printf '%s\n\n' "$EXAM_OWED_LINE"; cat "$TMP/right.md"; } > "$TMP/both.md"
pin_call "$TMP/both.md" "$ROOT"
expect_eq "O3: a sitting beside the owed line is red" \
  "red: a sitting is recorded and the owed line still says none is" "$PIN_OUT"

section "§KEY — an answer key names its defect"

K="$TMP/keys"
mkdir -p "$K"
printf 'question: structure\nresult: fail\ntoken: check: reuse FAIL\nnames: some_owner\n' > "$K/defect.txt"
expect_eq "K1: a defect key with a names: line is in shape" "key" "$(exam_key planted "$K/defect.txt")"
sed '$d' "$K/defect.txt" > "$K/defect-unnamed.txt"
expect_eq "K2: a defect key with no names: line is red" \
  "red: planted's key has no names: line" "$(exam_key planted "$K/defect-unnamed.txt")"
expect_status "K2: rc 1" 1 "$(exam_key planted "$K/defect-unnamed.txt" >/dev/null; echo $?)"
sed 's/^names: .*/names: some_owner | other/' "$K/defect.txt" > "$K/defect-two.txt"
expect_eq "K3: a names: line holding two identifiers is red" \
  "red: planted's names: line holds more than one identifier" "$(exam_key planted "$K/defect-two.txt")"
printf 'question: evidence, adversarial, structure\nresult: pass\ntoken: some-change\n' > "$K/clean.txt"
expect_eq "K4: clean's key has no names: line, and none is asked of it" "key" "$(exam_key clean "$K/clean.txt")"
{ cat "$K/clean.txt"; printf 'names: some_owner\n'; } > "$K/clean-named.txt"
expect_eq "K4: clean's key with a names: line is red" \
  "red: clean's key has a names: line, and clean has no defect to name" "$(exam_key clean "$K/clean-named.txt")"
{ cat "$K/defect.txt"; printf 'extra\n'; } > "$K/defect-five.txt"
expect_eq "K5: a defect key with a fifth line is red" \
  "red: planted's key has 5 lines, not 4" "$(exam_key planted "$K/defect-five.txt")"

section "§SCORE — README step 4 against the real keys"

# record <file> <result line> <line>... — a planted reader's record.
record() { local f="$1"; shift; printf '%s\n' "reviewed: aaa..bbb" "question: q" "$@" > "$f"; }
R="$TMP/records"
mkdir -p "$R"
DC="$EXAM/samples/dup-counter/expect.txt"
DC_NAMES="$(sed -n 's/^names: //p' "$DC")"
expect_nonempty "SC0: the dup-counter key has a names: identifier to score on" "$DC_NAMES"
record "$R/one-site.md" "result: fail" "check: reuse PASS a new file with a new job" \
  "check: one-site FAIL the dirty count is computed again, not read from $DC_NAMES"
expect_eq "SC1: dup-counter: check: one-site FAIL with the identifier is met" "met" \
  "$(exam_score dup-counter "$DC" "$R/one-site.md")"
record "$R/reuse.md" "result: fail" "check: reuse FAIL bin/stamp.sh counts dirt again beside $DC_NAMES"
expect_eq "SC1: dup-counter: check: reuse FAIL with the identifier is met" "met" \
  "$(exam_score dup-counter "$DC" "$R/reuse.md")"
record "$R/one-site-bare.md" "result: fail" "check: one-site FAIL a value is computed twice"
expect_eq "SC2: dup-counter: check: one-site FAIL without the identifier is missed" "missed" \
  "$(exam_score dup-counter "$DC" "$R/one-site-bare.md")"
record "$R/reuse-bare.md" "result: fail" "check: reuse FAIL a helper is copied"
expect_eq "SC2: dup-counter: check: reuse FAIL without the identifier is missed" "missed" \
  "$(exam_score dup-counter "$DC" "$R/reuse-bare.md")"
record "$R/neither.md" "result: fail" "check: single-job FAIL beside $DC_NAMES"
expect_eq "SC2: dup-counter: the identifier under another check is missed" "missed" \
  "$(exam_score dup-counter "$DC" "$R/neither.md")"

# Every defect key: its own result, first token and identifier meet it; drop the identifier
# and the same record is missed.
for s in $(exam_samples "$REPO"); do
  [ "$s" = clean ] && continue
  key="$EXAM/samples/$s/expect.txt"
  ident="$(sed -n 's/^names: //p' "$key")"
  tok="$(sed -n 's/^token: //p' "$key")"; tok="${tok%% | *}"
  record "$R/$s-named.md" "$(sed -n 2p "$key")" "$tok" "$ident"
  record "$R/$s-bare.md" "$(sed -n 2p "$key")" "$tok"
  expect_eq "SC3 $s: the key's result, token and names: identifier are met" "met" "$(exam_score "$s" "$key" "$R/$s-named.md")"
  expect_eq "SC3 $s: the same record without the identifier is missed" "missed" "$(exam_score "$s" "$key" "$R/$s-bare.md")"
done

CL="$EXAM/samples/clean/expect.txt"
CL_TOK="$(sed -n 's/^token: //p' "$CL")"
record "$R/clean-flag.md" "result: flag" "read $CL_TOK"
expect_eq "SC4: clean: a flag that names the change is met, with no names: line asked" "met" \
  "$(exam_score clean "$CL" "$R/clean-flag.md")"
record "$R/clean-fail.md" "result: fail" "read $CL_TOK"
expect_eq "SC4: clean: a fail is missed" "missed" "$(exam_score clean "$CL" "$R/clean-fail.md")"

section "§DEST — a destination that names its sample is refused"

DS="$EXAM/samples/dup-counter"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/dup-counter-run" 2>&1)"; rc=$?
expect_status "D1: a destination named for the sample is refused" 2 "$rc"
expect_contains "D1: …and says why" "names the sample dup-counter" "$out"
expect_false "D1: …and nothing is built" test -e "$TMP/x/dup-counter-run"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/dup-counter/s1" 2>&1)"; rc=$?
expect_status "D2: a destination under a directory named for the sample is refused" 2 "$rc"
expect_contains "D2: …and says why" "names the sample dup-counter" "$out"
mkdir -p "$TMP/in-dup-counter"
out="$(cd "$TMP/in-dup-counter" && bash "$EXAM/materialize.sh" "$DS" s1 2>&1)"; rc=$?
expect_status "D3: a relative destination is read from where it is run, and refused there" 2 "$rc"
expect_false "D3: …and nothing is built" test -e "$TMP/in-dup-counter/s1"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/s1" 2>&1)"; rc=$?
expect_status "D4: a neutral destination is accepted" 0 "$rc"
expect_regex "D4: …and prints its range" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"

section "§SAMPLES — every answer key in shape, every sample materializes"

SAMPLES="$(exam_samples "$REPO")"
expect_nonempty "S0: the exam has samples" "$SAMPLES"
expect_true "S0: one of them is the clean sample" test -d "$EXAM/samples/clean"

n=0
for s in $SAMPLES; do
  n=$((n + 1))
  key="$EXAM/samples/$s/expect.txt"
  expect_eq "S1 $s: the answer key is in shape" "key" "$(exam_key "$s" "$key")"
  out="$(bash "$EXAM/materialize.sh" "$EXAM/samples/$s" "$TMP/m$n" 2>&1)"; rc=$?
  expect_status "S2 $s: materializes" 0 "$rc"
  expect_regex "S2 $s: prints the range a..b" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"
  expect_eq "S2 $s: the range is the two commits the repository holds" \
    "$out" "$(git -C "$TMP/m$n" rev-parse HEAD~1 2>/dev/null)..$(git -C "$TMP/m$n" rev-parse HEAD 2>/dev/null)"
  expect_nonempty "S2 $s: the change commit changes files" "$(git -C "$TMP/m$n" diff --name-only HEAD~1 HEAD 2>/dev/null)"
  expect_false "S2 $s: the answer key does not travel" test -e "$TMP/m$n/expect.txt"
done

section "§SHIPPED — the shipped sittings against the shipped checks files"

for f in $EXAM_CHECKS; do
  expect_regex "SH0: the digest reads $f" '^[0-9a-f]{64}$' "$(_detect_sha256 "$REPO/$f")"
done
pin_call "$EXAM/sittings.md" "$REPO"
if [ "$PIN_OUT" = "owed" ]; then
  ok "RE-AUTHORED BY T22: the first sitting is owed by wave-27 T22 (sittings.md carries the owed line and no sitting)"
else
  expect_eq "SH1: the latest sitting read the checks files that ship" "pinned" "$PIN_OUT"
fi

finish
