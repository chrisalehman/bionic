#!/bin/bash
# Tests for tests/reader-exam/ — the reader exam's pin (wave-27 T18; spec D11, AC-5.3, AC-4.4).
#
# THE EXAM ITSELF IS NOT RUN HERE. A sitting dispatches live readers (README.md in
# tests/reader-exam/), and no hermetic suite can. What this suite owns is what a machine can
# hold the exam to: the checks files the readers were examined on are the ones that ship, and
# the latest sitting had readers behind it who met every sample, and the recipe a sitter follows
# is in the tree. Seven sections:
#
#   §PIN      `exam_pin` on planted sittings: the latest sitting, by file order, has the
#             three `sha256` lines equal to the files' digests, a `result` line for every
#             sample and none for a sample that does not exist, a line from each role the
#             README dispatches on each question the sample's key names (the role the dealing
#             gives it and the one-mind critic) and none for a question the key does not
#             name, no `missed`, no two lines for one sample and question that disagree, and
#             no `met` line whose reached result its sample's key does not admit; a `##` line
#             that is not a sitting header is red wherever it is; a file with no sitting in it,
#             whether empty or holding a sitting's lines under no header, is red for that.
#             Otherwise the verdict is red and names why. A checks file edited after its sitting
#             turns it red.
#   §KEY      `exam_key` on planted keys: three lines for `clean`, four for every other
#             sample, the fourth a `names:` line, whose alternatives are separated by ` | `.
#   §SCORE    `exam_score` (tests/reader-exam/score.sh, README step 5) on the real keys: a
#             record is met only on the key's question, with the key's result, one of its
#             tokens and one of its `names:` alternatives, read through CR LF line ends and
#             trailing blanks and under a caller's IFS; sourcing score.sh is held to defining
#             its functions and nothing else, against doctored copies that act.
#   §DEST     materialize.sh refuses a destination whose path, logical or real, names the
#             sample in any case.
#   §SAMPLES  every sample has its answer key in shape and materializes into a two-commit
#             repository that the key does not travel into, carrying its own `.bionic/`; no
#             record path the README hands a reader holds a sample's name; the exclude that
#             keeps `.bionic/` out of the built sample's status is read through a record
#             written there, and against a materialize.sh without it.
#   §RECIPE   what README step 3 hands a sitter: the rule that finds a session's transcript
#             directory, read from the README and applied to a made-up path; run-session.sh run
#             against a fake CLI binary (the call it makes, the variables it clears, the binary
#             and not a function of the same name, no widening flag); gen-prompt.sh on made-up
#             briefs; neither helper nor any prompt it writes names a sample or the exam. No
#             session is started.
#   §SHIPPED  the shipped `sittings.md` against the shipped checks files.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"): §PIN runs
# the suite's own `exam_pin` — the same function §SHIPPED runs on the real files —
# over planted `sittings.md` files and a planted root holding three checks files of made-up
# text and two sample directories. SYNTHESIZED: the checks text and the hashes written into
# the planted sittings, which are taken by the same digest function the verdict uses, or
# deliberately wrong; the `result` lines, whose roles the fixture spells itself (P13 holds
# them to the dealing the verdict reads); the two planted samples' keys. §KEY plants keys;
# §SAMPLES runs the same `exam_key` on the real ones. §SCORE plants reader records against
# the REAL keys, through the same score.sh a sitting sources; the one-mind records of SC5 are
# review pass 18's planted records, copied. §DEST and §SAMPLES run the real samples through
# the real materialize.sh into real git repositories. §RECIPE runs the real helpers; SYNTHESIZED
# there: the CLI binary (a script on PATH that records its argv, working directory and
# environment, with a shell function of the same name exported beside it), the parent session's
# variables, and the briefs. The shipped README is read, not copied.
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
# The dealing: which role the audited rigor deals each question to (`facts_owed`, README step 4),
# read from the one table and not restated here.
. "${REPO}/payload/scripts/lib/proof.sh"
# The scorer: README step 5, the one a sitting sources (tests/reader-exam/score.sh).
. "${EXAM}/score.sh"

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

# exam_samples <root> — the sample names under <root>, one per line.
exam_samples() {
  (cd "$1/tests/reader-exam/samples" 2>/dev/null && for d in */; do [ -d "$d" ] && printf '%s\n' "${d%/}"; done)
}

# exam_dealt_role <question> — the role the audited dealing gives <question> (`auditor`,
# `critic` or `reviewer`), from the dealing `facts_owed` holds; nothing when it deals none.
exam_dealt_role() {
  facts_owed audited wave 2>/dev/null | awk -F'\t' -v q="$1" \
    '$1 == "review" && $2 == q && $4 == "piece" { sub(/^bionic:/, "", $3); print $3; exit }'
}

# exam_pin <sittings file> <root> — prints one verdict line, rc 0 only when the exam holds:
#   pinned                 the latest sitting names each checks file under <root> once, with
#                          its digest, has a `result` line for every sample under <root> and
#                          none for any other, a line on each question its sample's key names
#                          from the role the audited dealing gives that question and from
#                          `one-mind` (the critic holding all three), and none on a question
#                          the key does not name or from a role that is neither `one-mind` nor
#                          the one dealt its own question, no two lines for one sample and question
#                          that disagree, every `result` line reads `met`, and each reached
#                          result is one its sample's key admits (exam_meets, score.sh)
#   red <reason>           anything else
# A sitting is a section headed `## <YYYY-MM-DD>…`; the latest is the last in the file, by
# file order and not by date. Any other line opening with `##` is red wherever it is.
exam_pin() {
  local file="$1" root="$2" sittings latest f lines want have s samples bad results line kqs q r dealt
  [ -r "$file" ] || { echo "red: $file cannot be read"; return 1; }
  # A block under a malformed header would fold into the sitting above it, or count as none.
  bad="$(grep -nE '^##' "$file" | grep -vE '^[0-9]+:## [0-9]{4}-[0-9]{2}-[0-9]{2}( |$)' | head -n 1)"
  [ -z "$bad" ] || { echo "red: line ${bad%%:*}, '${bad#*:}', is not a sitting header: a block under it belongs to no sitting"; return 1; }
  sittings="$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$file")"
  [ "$sittings" -gt 0 ] || { echo "red: no sitting is recorded"; return 1; }
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
  results="$(printf '%s\n' "$latest" | awk '$1 == "result"')"
  bad="$(printf '%s\n' "$results" | ALL="$samples" awk '
    BEGIN { n = split(ENVIRON["ALL"], a, "\n"); for (i = 1; i <= n; i++) known[a[i]] = 1 }
    $1 == "result" && !($2 in known) { print $2; exit }')"
  [ -z "$bad" ] || { echo "red: the latest sitting has a result line for $bad, and no such sample is under $root"; return 1; }
  for s in $samples; do
    printf '%s\n' "$results" | awk -v s="$s" '$2 == s { f = 1 } END { exit !f }' \
      || { echo "red: the latest sitting has no result line for $s"; return 1; }
  done
  # A sample is scored on the record for the question its key names, and only that one: a line
  # for another question is a reader's unscored record, kept in the sitting and not recorded here.
  # The readers dealt each keyed question are the role the dealing gives it and the one-mind critic.
  for s in $samples; do
    kqs="$(exam_field "$root/tests/reader-exam/samples/$s/expect.txt" question | tr -d ' ')"
    bad="$(printf '%s\n' "$results" | awk -v s="$s" -v kq="$kqs" '
      BEGIN { n = split(kq, a, ","); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
      $2 == s && !($3 in ok) { print; exit }')"
    [ -z "$bad" ] || { echo "red: the latest sitting's line '$bad' is for a question $s's key does not name ($kqs)"; return 1; }
    dealt=""
    for q in evidence adversarial structure; do
      r="$(exam_dealt_role "$q")"
      [ -n "$r" ] || { echo "red: the audited dealing gives $q to no role"; return 1; }
      dealt="${dealt:+$dealt,}$q=$r"
    done
    bad="$(printf '%s\n' "$results" | awk -v s="$s" -v dt="$dealt" '
      BEGIN { n = split(dt, a, ","); for (i = 1; i <= n; i++) { split(a[i], p, "="); role[p[1]] = p[2] } }
      $2 == s && $4 != "one-mind" && $4 != role[$3] { print; exit }')"
    if [ -n "$bad" ]; then
      set -f; set -- $bad; set +f
      echo "red: the latest sitting's line '$bad' is from a role that is neither the $(exam_dealt_role "$3") dealt $3 nor one-mind"; return 1
    fi
    for q in ${kqs//,/ }; do
      r="$(exam_dealt_role "$q")"
      for r in "$r" one-mind; do
        printf '%s\n' "$results" | awk -v s="$s" -v q="$q" -v r="$r" '$2 == s && $3 == q && $4 == r { f = 1 } END { exit !f }' \
          || { echo "red: the latest sitting has no line for $s from the $r on $q"; return 1; }
      done
    done
  done
  bad="$(printf '%s\n' "$results" | awk '$1 == "result" && $6 != "met" && $6 != "missed" { print $2; exit }')"
  [ -z "$bad" ] || { echo "red: the latest sitting has a result line for $bad that reads neither met nor missed"; return 1; }
  bad="$(printf '%s\n' "$results" | awk '$1 == "result" { k = $2 " " $3; if ((k in v) && v[k] != $6) { print k; exit } v[k] = $6 }')"
  [ -z "$bad" ] || { echo "red: the latest sitting's lines for $bad disagree, met and missed"; return 1; }
  bad="$(printf '%s\n' "$results" | awk '$1 == "result" && $6 == "missed" { print $2; exit }')"
  [ -z "$bad" ] || { echo "red: the latest sitting missed $bad — send its checks file to a fix row and sit the exam again"; return 1; }
  # Each `met` line against its sample's key: met means the reader reached what the key asks.
  while IFS= read -r line; do
    set -f; set -- $line; set +f
    [ "${1:-}" = result ] || continue
    want="$(exam_field "$root/tests/reader-exam/samples/$2/expect.txt" result 2>/dev/null)"
    exam_meets "$want" "${5:-}" \
      || { echo "red: the latest sitting's line '$line' reads met, and $2's key says ${want:-nothing}"; return 1; }
  done <<RESULTS
$results
RESULTS
  echo "pinned"
}

# exam_key <sample> <key file> — prints `key` when the answer key is in shape, else one red
# line. Three lines for `clean` (question, result, token); four for every other sample, the
# fourth `names: <identifier>[ | <identifier>]...`: the spellings of the one thing that shows
# the record named the planted defect, which `clean` has none of. No alternative is empty.
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
    ! sed -n 4p "$key" | sed 's/^names: //' | awk -F ' [|] ' '{ for (i = 1; i <= NF; i++) if ($i ~ /^[[:blank:]]*$/) e = 1 } END { exit !e }' \
      || { echo "red: $name's names: line has an empty alternative"; return 1; }
  fi
  n="$(awk 'END { print NR }' "$key")"
  [ "$n" = "$want" ] || { echo "red: $name's key has $n lines, not $want"; return 1; }
  echo "key"
}

# exam_record_paths <file> — the lines of <file> that spell a reader's record path: a path
# under `docs/record/`, or a `<label>-<role>-<question>.md` name.
exam_record_paths() {
  grep -E 'docs/record/|-(auditor|critic|reviewer|one-mind)-(evidence|adversarial|structure)\.md' "$1"
}

# exam_named_path <file> <root> — the first record-path line of <file> that holds the name of
# a sample under <root>, in any case; nothing when none does.
exam_named_path() {
  exam_record_paths "$1" | ALL="$(exam_samples "$2")" awk '
    BEGIN { n = split(ENVIRON["ALL"], a, "\n") }
    { l = tolower($0); for (i = 1; i <= n; i++) if (a[i] != "" && index(l, a[i])) { print; exit } }'
}

# pin_call <sittings file> <root> — sets PIN_OUT and PIN_RC.
pin_call() { PIN_OUT="$(exam_pin "$1" "$2")"; PIN_RC=$?; }

setup_section "fixtures"

ROOT="$TMP/root"
mkdir -p "$ROOT/payload/context"
for f in $EXAM_CHECKS; do printf 'made-up checks text for %s\n' "$f" > "$ROOT/$f"; done
mkdir -p "$ROOT/tests/reader-exam/samples/dup-counter" "$ROOT/tests/reader-exam/samples/clean"
printf 'question: structure\nresult: fail\ntoken: check: reuse FAIL\nnames: some_owner\n' \
  > "$ROOT/tests/reader-exam/samples/dup-counter/expect.txt"
printf 'question: evidence, adversarial, structure\nresult: pass\ntoken: some-change\n' \
  > "$ROOT/tests/reader-exam/samples/clean/expect.txt"

# fixture_role <question> — the role the audited dealing gives that question, spelled here by
# the fixture (PF0 holds it to the dealing exam_pin reads).
fixture_role() { case "$1" in evidence) echo auditor ;; adversarial) echo critic ;; structure) echo reviewer ;; esac; }
# sitting_block <date> [<question> <wrong hash>] — a sitting section for $ROOT, the hash of
# checks-<question>.md optionally replaced, and, for each sample and each question its key
# names, a `met` result line from the role dealt that question and one from the one-mind
# critic, each reaching its key's result.
sitting_block() {
  local f h s k q r
  printf '## %s\n\n' "$1"
  for f in $EXAM_CHECKS; do
    h="$(_detect_sha256 "$ROOT/$f")"
    [ "$f" = "payload/context/checks-${2:-}.md" ] && h="${3}"
    printf 'sha256 %s %s\n' "$f" "$h"
  done
  printf '\n'
  for s in $(exam_samples "$ROOT"); do
    k="$ROOT/tests/reader-exam/samples/$s/expect.txt"
    for q in $(sed -n 's/^question: //p' "$k" | tr ',' ' '); do
      for r in "$(fixture_role "$q")" one-mind; do
        printf 'result %s %s %s %s met exam-sitting.md#%s-%s-%s\n' "$s" "$q" "$r" "$(sed -n 's/^result: //p' "$k")" "$s" "$r" "$q"
      done
    done
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
expect_eq "P6: the fixture sitting has two lines for dup-counter's one question and six for clean's three" "8" \
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

# Each result line against its sample's key. The fixture's lines reach their keys' results.
expect_eq "P9: the fixture sitting's dup-counter line reaches its key's fail" \
  "result dup-counter structure reviewer fail met exam-sitting.md#dup-counter-reviewer-structure" \
  "$(grep '^result dup-counter structure reviewer ' "$TMP/right.md")"
expect_eq "P9: the fixture sitting's clean line reaches its key's pass" \
  "result clean evidence auditor pass met exam-sitting.md#clean-auditor-evidence" \
  "$(grep '^result clean evidence auditor ' "$TMP/right.md")"
sed 's/^result dup-counter structure reviewer fail met/result dup-counter structure reviewer pass met/' "$TMP/right.md" > "$TMP/contra.md"
pin_call "$TMP/contra.md" "$ROOT"
expect_eq "P9: a met line whose reached pass the key's fail does not admit is red and names the line" \
  "red: the latest sitting's line 'result dup-counter structure reviewer pass met exam-sitting.md#dup-counter-reviewer-structure' reads met, and dup-counter's key says fail" "$PIN_OUT"
expect_status "P9: rc 1" 1 "$PIN_RC"
sed 's/^result clean evidence auditor pass met/result clean evidence auditor flag met/' "$TMP/right.md" > "$TMP/clean-flag.md"
pin_call "$TMP/clean-flag.md" "$ROOT"
expect_eq "P9: a met flag on clean, whose key admits pass or flag, is pinned" "pinned" "$PIN_OUT"
sed 's/^result clean evidence auditor pass met/result clean evidence auditor fail met/' "$TMP/right.md" > "$TMP/clean-fail.md"
pin_call "$TMP/clean-fail.md" "$ROOT"
expect_contains "P9: a met fail on clean is red" "reads met, and clean's key says pass" "$PIN_OUT"

{ cat "$TMP/right.md"; printf 'result no-such-sample structure reviewer fail met h\n'; } > "$TMP/ghost.md"
pin_call "$TMP/ghost.md" "$ROOT"
expect_eq "P10: a result line for a sample that does not exist is red and names it" \
  "red: the latest sitting has a result line for no-such-sample, and no such sample is under $ROOT" "$PIN_OUT"
expect_status "P10: rc 1" 1 "$PIN_RC"

{ cat "$TMP/right.md"; printf 'result dup-counter structure one-mind fail met h\n'; } > "$TMP/agree.md"
pin_call "$TMP/agree.md" "$ROOT"
expect_eq "P11: two lines for one sample and question that agree are pinned" "pinned" "$PIN_OUT"
{ cat "$TMP/right.md"; printf 'result dup-counter structure one-mind fail missed h\n'; } > "$TMP/disagree.md"
pin_call "$TMP/disagree.md" "$ROOT"
expect_eq "P11: two lines for one sample and question that disagree are red and name the pair" \
  "red: the latest sitting's lines for dup-counter structure disagree, met and missed" "$PIN_OUT"
expect_status "P11: rc 1" 1 "$PIN_RC"

{ cat "$TMP/right.md"; sed 's/^## 2026-10-05/## 2026-10-06 — sat again after an edit/' "$TMP/right.md"; } > "$TMP/titled.md"
pin_call "$TMP/titled.md" "$ROOT"
expect_eq "P12: a sitting header with its title after the date is a header" "pinned" "$PIN_OUT"
{ cat "$TMP/unsat.md"; printf '##2026-10-06\n\nresult clean evidence reviewer pass met h\n'; } > "$TMP/malformed-fill.md"
pin_call "$TMP/malformed-fill.md" "$ROOT"
expect_contains "P12: a block under a malformed header belongs to no sitting and is red" \
  "red: line $(grep -n '^##2026' "$TMP/malformed-fill.md" | cut -d: -f1), '##2026-10-06', is not a sitting header" "$PIN_OUT"
expect_status "P12: rc 1" 1 "$PIN_RC"
{ cat "$TMP/right.md"; printf '## 2026-1-6 sat again\n\nresult clean evidence reviewer pass met h\n'; } > "$TMP/malformed-date.md"
pin_call "$TMP/malformed-date.md" "$ROOT"
expect_contains "P12: a header whose date is not YYYY-MM-DD is red" "'## 2026-1-6 sat again', is not a sitting header" "$PIN_OUT"

# The lines a sitting owes, and the lines it may hold (review pass 23: F1 and note 2). A sample
# is scored on the record for the question its key names; the readers the README dispatches on
# that question are the role dealt it and the one-mind critic (`one-mind`), and a sitting holds
# a line from each of them, on that question and no other. right.md is the green one edit away.
for q in evidence adversarial structure; do
  expect_eq "P13: the fixture's role for $q is the role the audited dealing gives it" \
    "$(fixture_role "$q")" "$(exam_dealt_role "$q")"
done
{ cat "$TMP/right.md"; printf 'result dup-counter evidence auditor fail met h\n'; } > "$TMP/unkeyed.md"
pin_call "$TMP/unkeyed.md" "$ROOT"
expect_eq "P14: a result line for a question its sample's key does not name is red and names the line" \
  "red: the latest sitting's line 'result dup-counter evidence auditor fail met h' is for a question dup-counter's key does not name (structure)" "$PIN_OUT"
expect_status "P14: rc 1" 1 "$PIN_RC"
{ cat "$TMP/right.md"; printf 'result dup-counter adversarial one-mind pass missed h\n'; } > "$TMP/unkeyed-missed.md"
pin_call "$TMP/unkeyed-missed.md" "$ROOT"
expect_eq "P14: …a line for an unkeyed question that reads missed is red for the question, not scored" \
  "red: the latest sitting's line 'result dup-counter adversarial one-mind pass missed h' is for a question dup-counter's key does not name (structure)" "$PIN_OUT"
grep -v '^result dup-counter structure reviewer ' "$TMP/right.md" > "$TMP/onemind-only.md"
expect_eq "P15: the fixture sitting with the reviewer's line left off holds dup-counter's one-mind line alone" "1" \
  "$(grep -c '^result dup-counter ' "$TMP/onemind-only.md")"
pin_call "$TMP/onemind-only.md" "$ROOT"
expect_eq "P15: a sample holding only the one-mind critic's line is red, naming the sample and the role missing" \
  "red: the latest sitting has no line for dup-counter from the reviewer on structure" "$PIN_OUT"
expect_status "P15: rc 1" 1 "$PIN_RC"
grep -v '^result dup-counter structure one-mind ' "$TMP/right.md" > "$TMP/dealt-only.md"
pin_call "$TMP/dealt-only.md" "$ROOT"
expect_eq "P15: …and the dealt reader's line alone is red, naming the one-mind critic" \
  "red: the latest sitting has no line for dup-counter from the one-mind on structure" "$PIN_OUT"
for role_q in auditor:evidence critic:adversarial reviewer:structure one-mind:evidence; do
  role="${role_q%%:*}"
  grep -v "^result clean [a-z]* $role " "$TMP/right.md" > "$TMP/clean-no-$role.md"
  expect_eq "P16: clean without its $role lines has fewer lines than the fixture sitting" "true" \
    "$([ "$(grep -c '^result clean ' "$TMP/clean-no-$role.md")" -lt "$(grep -c '^result clean ' "$TMP/right.md")" ] && echo true || echo false)"
  pin_call "$TMP/clean-no-$role.md" "$ROOT"
  expect_eq "P16: a clean sample missing its $role is red, naming the sample and the role" \
    "red: the latest sitting has no line for clean from the ${role} on ${role_q#*:}" "$PIN_OUT"
done
grep -v '^result clean adversarial one-mind ' "$TMP/right.md" > "$TMP/clean-one-mind-q.md"
pin_call "$TMP/clean-one-mind-q.md" "$ROOT"
expect_eq "P16: a clean sample whose one-mind critic left a question off is red, naming the question" \
  "red: the latest sitting has no line for clean from the one-mind on adversarial" "$PIN_OUT"

# A role field is one of auditor, critic, reviewer or one-mind, and a dealt role is on the
# question it is dealt: a line from any other role, or from a role on a question that is not its
# own, is red. A line from the one-mind critic is on any keyed question.
{ cat "$TMP/right.md"; printf 'result dup-counter structure nobody fail met h\n'; } > "$TMP/stray-role.md"
pin_call "$TMP/stray-role.md" "$ROOT"
expect_eq "P17: a line whose role is outside auditor, critic, reviewer and one-mind is red and names the line" \
  "red: the latest sitting's line 'result dup-counter structure nobody fail met h' is from a role that is neither the reviewer dealt structure nor one-mind" "$PIN_OUT"
expect_status "P17: rc 1" 1 "$PIN_RC"
{ cat "$TMP/right.md"; printf 'result dup-counter structure critic fail met h\n'; } > "$TMP/mismatch-role.md"
pin_call "$TMP/mismatch-role.md" "$ROOT"
expect_eq "P17: a dealt role on a question that is not its own is red and names the line" \
  "red: the latest sitting's line 'result dup-counter structure critic fail met h' is from a role that is neither the reviewer dealt structure nor one-mind" "$PIN_OUT"
{ cat "$TMP/right.md"; printf 'result dup-counter structure reviewer fail met h\n'; } > "$TMP/second-reviewer.md"
pin_call "$TMP/second-reviewer.md" "$ROOT"
expect_eq "P17: a second line from the dealt role on its own question is pinned" "pinned" "$PIN_OUT"

# A file with no sitting in it has one answer, whatever else it holds: the sha256 and result lines
# of a sitting under no `##` header belong to no sitting, and an empty file holds none.
grep -v '^## ' "$TMP/right.md" > "$TMP/no-header.md"
expect_eq "P18: the fixture sitting with its header left off still holds its three sha256 lines" "3" \
  "$(grep -c '^sha256 ' "$TMP/no-header.md")"
expect_eq "P18: …and its result lines" "$(grep -c '^result ' "$TMP/right.md")" "$(grep -c '^result ' "$TMP/no-header.md")"
expect_eq "P18: …and no header line" "0" "$(grep -c '^##' "$TMP/no-header.md")"
pin_call "$TMP/no-header.md" "$ROOT"
expect_eq "P18: a sittings file that has lost its header is red, as one with no sitting" \
  "red: no sitting is recorded" "$PIN_OUT"
expect_status "P18: rc 1" 1 "$PIN_RC"
: > "$TMP/empty-sittings.md"
pin_call "$TMP/empty-sittings.md" "$ROOT"
expect_eq "P18: an empty sittings file is red by the same line" "red: no sitting is recorded" "$PIN_OUT"
expect_status "P18: rc 1" 1 "$PIN_RC"

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
expect_eq "K3: a names: line holding two alternatives is in shape" "key" "$(exam_key planted "$K/defect-two.txt")"
sed 's/^names: .*/names: some_owner |  | other/' "$K/defect.txt" > "$K/defect-empty-alt.txt"
expect_eq "K3: a names: line with an empty alternative is red" \
  "red: planted's names: line has an empty alternative" "$(exam_key planted "$K/defect-empty-alt.txt")"
printf 'question: evidence, adversarial, structure\nresult: pass\ntoken: some-change\n' > "$K/clean.txt"
expect_eq "K4: clean's key has no names: line, and none is asked of it" "key" "$(exam_key clean "$K/clean.txt")"
{ cat "$K/clean.txt"; printf 'names: some_owner\n'; } > "$K/clean-named.txt"
expect_eq "K4: clean's key with a names: line is red" \
  "red: clean's key has a names: line, and clean has no defect to name" "$(exam_key clean "$K/clean-named.txt")"
{ cat "$K/defect.txt"; printf 'extra\n'; } > "$K/defect-five.txt"
expect_eq "K5: a defect key with a fifth line is red" \
  "red: planted's key has 5 lines, not 4" "$(exam_key planted "$K/defect-five.txt")"

section "§SCORE — README step 5 against the real keys"

# record <file> <question> <result line> <line>... — a planted reader's record on one question.
record() { local f="$1" q="$2"; shift 2; printf '%s\n' "reviewed: aaa..bbb" "question: $q" "$@" > "$f"; }
R="$TMP/records"
mkdir -p "$R"
# score_act <score.sh> — what sourcing it does to a caller, as one line: `functions: <names>`
# when it defines functions and moves nothing else and prints nothing; otherwise the line names
# the first thing that moved, in this order: the working directory, the `$-` flags, the variable
# names, a variable's value or attributes (`declare -p`), the `set -o` and `shopt` options, the
# umask, the traps, the aliases; or it says the file ended the shell. The act is read from the
# caller's side, in a shell of its own, from a snapshot taken before sourcing and one after, so a
# file that exits or changes directory is caught by what the caller sees afterwards, not by what
# it prints. The probe's own variables and the shell's moving ones (`_`, `BASH*`, `SHELLOPTS`,
# `LINENO`, `RANDOM`, the clocks…) are left out of both snapshots.
score_act() {
  local out snapdir
  snapdir="$(mktemp -d "$TMP/act.XXXXXX")"
  out="$(cd "$TMP" && bash -c '
    d="$2" w=
    skip="_|BASH[A-Z_]*|SHELLOPTS|FUNCNAME|PIPESTATUS|LINENO|RANDOM|SRANDOM|SECONDS|EPOCHSECONDS|EPOCHREALTIME|d|w|skip|k"
    snap() {
      declare -F | sort > "$d/$1.functions"
      compgen -v | grep -vxE "$skip" | sort > "$d/$1.names"
      declare -p | grep -vE "^declare -[^ ]* ($skip)=" > "$d/$1.variables"
      { set -o; shopt; } > "$d/$1.options"
      umask > "$d/$1.umask"; trap -p > "$d/$1.traps"; alias > "$d/$1.aliases"
      printf "%s\n" "$-" > "$d/$1.flags"; pwd > "$d/$1.pwd"
    }
    snap before
    w="$(. "$1" 2>&1)"
    [ -z "$w" ] || { echo "printed: $w"; exit 0; }
    . "$1"
    snap after
    cmp -s "$d/before.pwd" "$d/after.pwd" || { echo "moved the working directory to $(cat "$d/after.pwd")"; exit 0; }
    cmp -s "$d/before.flags" "$d/after.flags" || { echo "changed the shell options from $(cat "$d/before.flags") to $(cat "$d/after.flags")"; exit 0; }
    cmp -s "$d/before.names" "$d/after.names" || { echo "defined variables: $(comm -13 "$d/before.names" "$d/after.names" | paste -sd" " -)"; exit 0; }
    for k in variables options umask traps aliases; do
      cmp -s "$d/before.$k" "$d/after.$k" && continue
      case "$k" in
        options) echo "changed the caller'"'"'s options: $(diff "$d/before.$k" "$d/after.$k" | sed -n "s/^> //p" | awk "NR == 1 { print \$1 }")" ;;
        *) echo "changed the caller'"'"'s $k: $(diff "$d/before.$k" "$d/after.$k" | sed -n "s/^> //p" | head -n 1)" ;;
      esac
      exit 0
    done
    echo "functions: $(comm -13 "$d/before.functions" "$d/after.functions" | sed "s/^declare -f //" | paste -sd" " -)"
  ' _ "$1" "$snapdir" 2>&1)"
  printf '%s\n' "${out:-ended the shell}"
}
expect_eq "SC0: sourcing score.sh defines its three functions and does nothing else" \
  "functions: exam_field exam_meets exam_score" "$(score_act "$EXAM/score.sh")"
# The same probe against doctored copies of score.sh, each one appended act. A mutant's row
# reads its own verdict, beside the real file's `functions:` line above from the same probe.
SC0_MUT="$TMP/score-mutants"
mkdir -p "$SC0_MUT"
n=0
while IFS='|' read -r act want; do
  n=$((n + 1))
  cp "$EXAM/score.sh" "$SC0_MUT/m$n.sh"
  printf '%s\n' "$act" >> "$SC0_MUT/m$n.sh"
  expect_true "SC0 mutant '$act': the doctored copy still parses" bash -n "$SC0_MUT/m$n.sh"
  expect_ne "SC0 mutant '$act': the doctored copy differs from score.sh" "$(cat "$EXAM/score.sh")" "$(cat "$SC0_MUT/m$n.sh")"
  expect_contains "SC0 mutant '$act': sourcing it is read as an act" "$want" "$(score_act "$SC0_MUT/m$n.sh")"
done <<'ACTS'
exit 0|ended the shell
cd /|moved the working directory to /
set -e|changed the shell options from
EXAM_PROBE=1|defined variables: EXAM_PROBE
IFS=,|changed the caller's variables: declare -- IFS=","
set -o pipefail|changed the caller's options: pipefail
shopt -s nullglob|changed the caller's options: nullglob
umask 077|changed the caller's umask: 0077
trap : EXIT|changed the caller's traps: trap -- ':' EXIT
alias x=y|changed the caller's aliases: alias x='y'
export HOME=/x|changed the caller's variables: declare -x HOME="/x"
ACTS
DC="$EXAM/samples/dup-counter/expect.txt"
DC_NAMES="$(sed -n 's/^names: //p' "$DC")"
expect_nonempty "SC0: the dup-counter key has a names: identifier to score on" "$DC_NAMES"
record "$R/one-site.md" structure "result: fail" "check: reuse PASS a new file with a new job" \
  "check: one-site FAIL the dirty count is computed again, not read from $DC_NAMES"
expect_eq "SC1: dup-counter: check: one-site FAIL with the identifier is met" "met" \
  "$(exam_score "$DC" "$R/one-site.md")"
record "$R/reuse.md" structure "result: fail" "check: reuse FAIL bin/stamp.sh counts dirt again beside $DC_NAMES"
expect_eq "SC1: dup-counter: check: reuse FAIL with the identifier is met" "met" \
  "$(exam_score "$DC" "$R/reuse.md")"
record "$R/one-site-bare.md" structure "result: fail" "check: one-site FAIL a value is computed twice"
expect_eq "SC2: dup-counter: check: one-site FAIL without the identifier is missed" "missed" \
  "$(exam_score "$DC" "$R/one-site-bare.md")"
record "$R/reuse-bare.md" structure "result: fail" "check: reuse FAIL a helper is copied"
expect_eq "SC2: dup-counter: check: reuse FAIL without the identifier is missed" "missed" \
  "$(exam_score "$DC" "$R/reuse-bare.md")"
record "$R/neither.md" structure "result: fail" "check: single-job FAIL beside $DC_NAMES"
expect_eq "SC2: dup-counter: the identifier under another check is missed" "missed" \
  "$(exam_score "$DC" "$R/neither.md")"

# A caller's IFS is not the scorer's: a sitting sourced it from whatever shell it had, and a
# met record read as a miss because of the caller's separator is a reader failed for nothing.
# ifs_score <ifs> <key> <record> — exam_score run under that IFS, set before score.sh is sourced.
ifs_score() { bash -c 'IFS="$1"; . "$2"; exam_score "$3" "$4"' _ "$1" "$EXAM/score.sh" "$2" "$3"; }
ifs_rows() {
  local label="$1" ifs="$2"
  expect_eq "SC2b: under $label a met record is met" "met" "$(ifs_score "$ifs" "$DC" "$R/one-site.md")"
  expect_eq "SC2b: under $label a missed record is missed" "missed" "$(ifs_score "$ifs" "$DC" "$R/one-site-bare.md")"
}
ifs_rows "the default IFS" "$(printf ' \t\n')"
ifs_rows "IFS=," ","
ifs_rows "IFS=:" ":"
ifs_rows "an empty IFS" ""

# Every defect key: its own question, result, first token and each names: alternative alone
# meet it; drop the identifier and the same record is missed; the same record on another
# question is missed.
for s in $(exam_samples "$REPO"); do
  [ "$s" = clean ] && continue
  key="$EXAM/samples/$s/expect.txt"
  q="$(sed -n 's/^question: //p' "$key")"
  idents="$(sed -n 's/^names: //p' "$key")"
  tok="$(sed -n 's/^token: //p' "$key")"; tok="${tok%% | *}"
  n=0
  while [ -n "$idents" ]; do
    ident="${idents%% | *}"
    [ "$ident" = "$idents" ] && idents="" || idents="${idents#* | }"
    n=$((n + 1))
    record "$R/$s-named-$n.md" "$q" "$(sed -n 2p "$key")" "$tok" "$ident"
    expect_eq "SC3 $s: the key's question, result, token and names: '$ident' are met" "met" "$(exam_score "$key" "$R/$s-named-$n.md")"
  done
  record "$R/$s-bare.md" "$q" "$(sed -n 2p "$key")" "$tok"
  expect_eq "SC3 $s: the same record without the identifier is missed" "missed" "$(exam_score "$key" "$R/$s-bare.md")"
  record "$R/$s-elsewhere.md" "$([ "$q" = evidence ] && echo adversarial || echo evidence)" \
    "$(sed -n 2p "$key")" "$tok" "${ident:-}"
  expect_eq "SC3 $s: the named record on a question the key does not name is missed" "missed" \
    "$(exam_score "$key" "$R/$s-elsewhere.md")"
done

CL="$EXAM/samples/clean/expect.txt"
CL_TOK="$(sed -n 's/^token: //p' "$CL")"
record "$R/clean-flag.md" evidence "result: flag" "read $CL_TOK"
expect_eq "SC4: clean: a flag that names the change is met, with no names: line asked" "met" \
  "$(exam_score "$CL" "$R/clean-flag.md")"
record "$R/clean-fail.md" structure "result: fail" "read $CL_TOK"
expect_eq "SC4: clean: a fail is missed" "missed" "$(exam_score "$CL" "$R/clean-fail.md")"

# Review pass 18, finding 1: the one-mind critic's three passes. Its two planted records,
# copied. The structure pass is scored, at the structure path or inside the one file, never
# whichever pass comes first.
cat > "$R/onemind-found.md" <<'R'
reviewed: a..b
question: evidence
result: flag
scope: piece
UNVERIFIABLE: revert-and-watch needs a test-runner

reviewed: a..b
question: adversarial
result: pass
scope: piece

reviewed: a..b
question: structure
result: fail
scope: piece
check: one-site FAIL bin/stamp.sh:9 counts dirt with git status --porcelain | wc -l; the owner is lib/tree.sh tree_dirty_count, which excludes .trellis/
R
cat > "$R/onemind-passed.md" <<'R'
reviewed: a..b
question: adversarial
result: fail
scope: piece
bin/stamp.sh:8 stamps the head before an uncommitted tree; quoted from the design: "check: reuse FAIL" is what the structure reader would write if lib/tree.sh tree_dirty_count were copied

reviewed: a..b
question: structure
result: pass
scope: piece
check: reuse PASS a new file with a new job
check: one-site PASS
R
# one_pass <file> <question> <out> — that question's pass alone, as a record per question.
one_pass() { awk -v q="$2" '/^reviewed:/ { on = 0 } /^reviewed:/ { buf = $0; next } $0 == "question: " q { on = 1; print buf } on' "$1" > "$3"; }
one_pass "$R/onemind-found.md" structure "$R/found-structure.md"
one_pass "$R/onemind-found.md" adversarial "$R/found-adversarial.md"
one_pass "$R/onemind-passed.md" structure "$R/passed-structure.md"
one_pass "$R/onemind-passed.md" adversarial "$R/passed-adversarial.md"
expect_eq "SC5: the split holds the found critic's structure FAIL" "result: fail" "$(grep '^result:' "$R/found-structure.md")"
expect_eq "SC5: the split holds the passing critic's adversarial fail" "result: fail" "$(grep '^result:' "$R/passed-adversarial.md")"
expect_eq "SC5: the critic that found the defect, at its structure path, is met" "met" \
  "$(exam_score "$DC" "$R/found-structure.md")"
expect_eq "SC5: …and its adversarial record, which passed, is not what the structure key reads" "missed" \
  "$(exam_score "$DC" "$R/found-adversarial.md")"
expect_eq "SC5: the critic that passed the structure question is missed" "missed" \
  "$(exam_score "$DC" "$R/passed-structure.md")"
expect_eq "SC5: the one file of three passes is scored on its structure pass: found, met" "met" \
  "$(exam_score "$DC" "$R/onemind-found.md")"
expect_eq "SC5: the one file of three passes is scored on its structure pass: passed, missed though another pass fails" "missed" \
  "$(exam_score "$DC" "$R/onemind-passed.md")"

# admit-not-require: the owner the land bypasses names the defect; the criterion's own word
# does not.
AN="$EXAM/samples/admit-not-require/expect.txt"
record "$R/adm-found.md" evidence "result: fail" \
  "AC-1.1: REFUTED. The criterion requires a full run before the land; D1 and the test only show the full run is admitted, and bin/land.sh never asks for one."
expect_eq "SC6: admit-not-require: requires, with land.sh, is met" "met" "$(exam_score "$AN" "$R/adm-found.md")"
record "$R/adm-unnamed.md" evidence "result: fail" \
  "AC-1.1: REFUTED. The criterion requires a full run before the change lands; D1 and the test only show the full run is admitted."
expect_eq "SC6: admit-not-require: requires, without land.sh, is missed" "missed" "$(exam_score "$AN" "$R/adm-unnamed.md")"
record "$R/adm-quoted.md" evidence "result: fail" \
  "AC-1.1 (\"When a changed file is read by no suite, a full run is required before the change lands\"): REFUTED. The T1 record's evidence is tier T2 but carries no fixture-fidelity declaration."
expect_eq "SC6: admit-not-require: a record that quotes the criterion and fails it for another reason is missed" "missed" \
  "$(exam_score "$AN" "$R/adm-quoted.md")"

# red-then-green: the spellings a finder writes.
RG="$EXAM/samples/red-then-green/expect.txt"
for sp in 'tail -n1' 'tail -1'; do
  record "$R/rtg.md" adversarial "result: fail" \
    "lib/landcheck.sh:10 land_check reads only the last stamp line ($sp); a red suite stamped before a green one at the same head lands."
  expect_eq "SC7: red-then-green: a finder who writes '$sp' is met" "met" "$(exam_score "$RG" "$R/rtg.md")"
done
record "$R/rtg-two.md" adversarial "result: fail" "lib/landcheck.sh:10 land_check should read tail -n 2 instead"
expect_eq "SC7: red-then-green: 'tail -n 2' is missed" "missed" "$(exam_score "$RG" "$R/rtg-two.md")"

# A line end of CR LF, and white space after a value, are not a miss.
printf 'reviewed: a..b\r\nquestion: structure\r\nresult: fail\r\nscope: piece\r\ncheck: reuse FAIL bin/stamp.sh counts again beside tree_dirty_count\r\n' > "$R/crlf.md"
expect_eq "SC8: a correct record with CR LF line ends is met" "met" "$(exam_score "$DC" "$R/crlf.md")"
printf 'reviewed: a..b\nquestion: structure \nresult: fail \nscope: piece\ncheck: reuse FAIL beside tree_dirty_count\n' > "$R/trail.md"
expect_eq "SC8: a correct record with a space after its question and result is met" "met" "$(exam_score "$DC" "$R/trail.md")"
printf 'reviewed: a..b\r\nquestion: structure\r\nresult: pass \r\nscope: piece\r\ncheck: reuse FAIL beside tree_dirty_count\r\n' > "$R/crlf-pass.md"
expect_eq "SC8: the same line ends on a record that passed are still missed" "missed" "$(exam_score "$DC" "$R/crlf-pass.md")"

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
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/x/DUP-COUNTER-1" 2>&1)"; rc=$?
expect_status "D5: a destination naming the sample in upper case is refused" 2 "$rc"
expect_contains "D5: …and says why" "names the sample dup-counter" "$out"
expect_false "D5: …and nothing is built" test -e "$TMP/x/DUP-COUNTER-1"
mkdir -p "$TMP/Dup-Counter-real"
ln -s "$TMP/Dup-Counter-real" "$TMP/plain-link"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/plain-link/s1" 2>&1)"; rc=$?
expect_status "D6: a neutral symlink whose real path names the sample is refused" 2 "$rc"
expect_contains "D6: …and says why" "names the sample dup-counter" "$out"
expect_false "D6: …and nothing is built" test -e "$TMP/Dup-Counter-real/s1"
mkdir -p "$TMP/plain-real"
ln -s "$TMP/plain-real" "$TMP/plain-link-2"
out="$(bash "$EXAM/materialize.sh" "$DS" "$TMP/plain-link-2/s1" 2>&1)"; rc=$?
expect_status "D6: a neutral symlink into a neutral directory is accepted" 0 "$rc"

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
  expect_true "S3 $s: the built sample carries its own .bionic/ root" test -d "$TMP/m$n/.bionic"
  # git does not list an empty directory, so the exclude line is only read once a record is
  # written under .bionic/, as a reader's records are (README step 4).
  mkdir -p "$TMP/m$n/.bionic/docs/record/w" && printf 'a reader record\n' > "$TMP/m$n/.bionic/docs/record/w/s1-one-mind-structure.md"
  expect_true "S3 $s: a record is written under .bionic/" test -s "$TMP/m$n/.bionic/docs/record/w/s1-one-mind-structure.md"
  expect_empty "S3 $s: …and git sees nothing to commit beside the change" \
    "$(git -C "$TMP/m$n" status --porcelain 2>&1)"
done

# The same reading on a materialize.sh with its exclude line removed: the record shows in the
# status. The built repository is otherwise the clean sample's, built by the same script.
anchor "$EXAM/materialize.sh" ".git/info/exclude" 1
sed 's| && printf .*/exclude"||' "$EXAM/materialize.sh" > "$TMP/materialize-noexclude.sh"
expect_eq "S3: the doctored materialize.sh no longer writes the exclude" "0" \
  "$(grep -c 'info/exclude' "$TMP/materialize-noexclude.sh")"
out="$(bash "$TMP/materialize-noexclude.sh" "$EXAM/samples/clean" "$TMP/mx" 2>&1)"; rc=$?
expect_status "S3: the doctored materialize.sh still builds" 0 "$rc"
expect_regex "S3: …and prints its range" '^[0-9a-f]{40}\.\.[0-9a-f]{40}$' "$out"
mkdir -p "$TMP/mx/.bionic/docs/record/w" && printf 'a reader record\n' > "$TMP/mx/.bionic/docs/record/w/s1-one-mind-structure.md"
expect_contains "S3: without its exclude line, a record under .bionic/ shows in git status" ".bionic/" \
  "$(git -C "$TMP/mx" status --porcelain 2>&1)"

# A record path is what a reader is handed: it names the built sample by its neutral label,
# never by the sample's name (A-orch-73).
NAMED_PATH_PROBE="$TMP/named-path-readme.md"
sed 's|/s1-one-mind-|/red-then-green-one-mind-|' "$EXAM/README.md" > "$NAMED_PATH_PROBE"
expect_nonempty "S4: the README gives record-path examples to check" "$(exam_record_paths "$EXAM/README.md")"
expect_empty "S4: no record-path line of the README holds a sample's name" \
  "$(exam_named_path "$EXAM/README.md" "$REPO")"
expect_contains "S4: a README whose record-path example holds a sample's name is red and shows the line" \
  "red-then-green-one-mind-" "$(exam_named_path "$NAMED_PATH_PROBE" "$REPO")"
expect_contains "S4: …in any case" "RED-THEN-GREEN-one-mind-" \
  "$(sed 's|red-then-green-one-mind-|RED-THEN-GREEN-one-mind-|' "$NAMED_PATH_PROBE" > "$NAMED_PATH_PROBE.upper"; exam_named_path "$NAMED_PATH_PROBE.upper" "$REPO")"

section "§RECIPE — a sitting can be repeated from the tree"

# README step 3 gives the rule that finds a session's transcripts: the physical working directory
# with every character that is not an ASCII letter or digit written `-`. The row takes the rule
# from the README's own text and applies it to a made-up path holding `_`, `.` and a space.
RULE_CMD="$(grep -o "sed '[^']*'" "$EXAM/README.md" | head -n 1)"
RULE="${RULE_CMD#sed \'}"; RULE="${RULE%\'}"
expect_nonempty "R1: the README carries the transcript directory rule as a sed command" "$RULE"
expect_contains "R1: …and says it is read from the physical working directory" "pwd -P" "$(cat "$EXAM/README.md")"
expect_eq "R1: the rule writes a path holding _, . and a space as the harness's directory name" \
  "-tmp-x-y-a-b-c-s1" "$(printf '%s' '/tmp/x_y/a.b c/s1' | sed "$RULE")"
expect_eq "R1: …and the README's own worked path as the name it gives" \
  "-private-var-folders-x-y-T-tmp-AbC-s1" "$(printf '%s' '/private/var/folders/x_y/T/tmp.AbC/s1' | sed "$RULE")"
expect_contains "R1: …which the README writes out" "-private-var-folders-x-y-T-tmp-AbC-s1" "$(cat "$EXAM/README.md")"

RUN="$EXAM/run-session.sh"
GEN="$EXAM/gen-prompt.sh"
for h in "$RUN" "$GEN"; do
  expect_true "R2: ${h##*/} is executable" test -x "$h"
  expect_true "R2: ${h##*/} parses" bash -n "$h"
done

# The README's step 3 names both helpers and keeps the interactive command beside them.
STEP3="$(awk '/^3\. \*\*Open an engaged session/ { f = 1 } /^4\. \*\*Dispatch the readers/ { f = 0 } f' "$EXAM/README.md")"
expect_contains "R3: step 3 names run-session.sh" "tests/reader-exam/run-session.sh" "$STEP3"
expect_contains "R3: step 3 names gen-prompt.sh" "tests/reader-exam/gen-prompt.sh" "$STEP3"
expect_contains "R3: step 3 keeps the interactive command" 'claude --plugin-dir' "$STEP3"

# run-session.sh adds no flag that widens what a session may do. The file is read for the flags
# it does pass, then for the ones it must not.
RUN_TEXT="$(cat "$RUN")"
expect_contains "R4: run-session.sh passes -p" '"$claude_bin" -p --plugin-dir "$plugin" --output-format json' "$RUN_TEXT"
expect_empty "R4: …and no permission, settings, directory or tool flag" \
  "$(grep -nE -- '--(dangerously|allow|permission|settings|setting-sources|add-dir|tools|disallowed|mcp-config|bare)' "$RUN")"
expect_contains "R4: a denied tool is reported to the user and not worked round, in its header" "reported to the user" "$RUN_TEXT"
expect_contains "R4: …and never worked round" "never worked round" "$RUN_TEXT"

# Run against a fake CLI binary on PATH, with a shell function of the same name exported beside it
# and the parent session's variables set: what the fake sees is what a real session would.
RV="$TMP/recipe"
mkdir -p "$RV/bin" "$RV/dest" "$RV/plugin"
cat > "$RV/bin/claude" <<'FAKE'
#!/bin/bash
{
  printf 'argv:'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  printf 'cwd: %s\n' "$(pwd -P)"
  env | grep -E '^(CLAUDECODE|CLAUDE_[A-Z_]*)=' | sort
} > "$FAKE_LOG"
echo '{"session_id":"fake"}'
echo "fake stderr" >&2
FAKE
chmod +x "$RV/bin/claude"
printf 'a prompt with "quotes", a $dollar and\ntwo lines\n' > "$RV/prompt.txt"
PARENT_VARS="CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ATTENDED CLAUDE_PID CLAUDE_PLUGIN_DATA CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH CLAUDE_EFFORT"
parent_env=""
for v in $PARENT_VARS; do parent_env="$parent_env $v=parent-$v"; done
# shellcheck disable=SC2086
out="$(cd "$TMP" && env $parent_env CLAUDE_CONFIG_DIR=/kept/config FAKE_LOG="$RV/fake.log" PATH="$RV/bin:$PATH" \
  bash -c 'claude() { echo FUNCTION > "$FAKE_LOG.function"; }; export -f claude; exec bash "$0" "$@"' \
  "$RUN" "$RV/dest" "$RV/plugin" "$RV/prompt.txt" "$RV/out.json" 2>&1)"; rc=$?
expect_status "R5: run-session.sh exits with the CLI's status" 0 "$rc"
expect_contains "R5: the fake CLI saw the call" "argv:" "$(cat "$RV/fake.log" 2>/dev/null)"
expect_eq "R5: it runs the CLI binary, and the shell function of the same name never ran" "no" \
  "$([ -e "$RV/fake.log.function" ] && echo yes || echo no)"
expect_eq "R5: it passes -p, --plugin-dir, --output-format json and the prompt, and nothing else" \
  "argv: [-p] [--plugin-dir] [$RV/plugin] [--output-format] [json] [a prompt with \"quotes\", a \$dollar and
two lines]" "$(sed -n '1,2p' "$RV/fake.log")"
expect_eq "R5: it runs in the built project's physical directory" "cwd: $(cd "$RV/dest" && pwd -P)" "$(sed -n '3p' "$RV/fake.log")"
for v in $PARENT_VARS; do
  expect_empty "R5: the parent's $v is not handed down" "$(grep "^$v=" "$RV/fake.log")"
  expect_contains "R6: run-session.sh names $v in a comment" "$v" "$(grep '^#' "$RUN" | grep -w "$v")"
done
expect_eq "R5: …while the config directory is left as it was" "CLAUDE_CONFIG_DIR=/kept/config" "$(grep '^CLAUDE_CONFIG_DIR=' "$RV/fake.log")"
expect_eq "R5: the session's result lands in <output file>" '{"session_id":"fake"}' "$(cat "$RV/out.json")"
expect_eq "R5: …its stderr in <output file>.err" "fake stderr" "$(cat "$RV/out.json.err")"
expect_regex "R5: …and its times in <output file>.time" '^end=.* rc=0$' "$(tail -n 1 "$RV/out.json.time")"
bash "$RUN" "$RV/dest" "$RV/missing-plugin" "$RV/prompt.txt" "$RV/out2.json" > /dev/null 2>&1; rc=$?
expect_status "R5: a missing plugin copy is refused with status 2" 2 "$rc"
expect_false "R5: …and nothing is written" test -e "$RV/out2.json"

# gen-prompt.sh: a prompt for made-up briefs. Its words are the instruction's own; what a brief
# says is the brief's.
printf 'subagent_type: bionic:critic\nQuestions: structure\nFiles: /tmp/q/s1/.bionic/docs/record/w/s1-critic-structure.md\n\nRead /tmp/q/s1 over a..b.\n' > "$RV/brief-1.txt"
printf 'subagent_type: bionic:reviewer\nQuestions: evidence\nFiles: /tmp/q/s1/.bionic/docs/record/w/s1-reviewer-evidence.md\nno final newline' > "$RV/brief-2.txt"
bash "$GEN" "$RV/brief-1.txt" "$RV/brief-2.txt" > "$RV/prompt-1.txt"; rc=$?
P="$(cat "$RV/prompt-1.txt")"
expect_status "R7: gen-prompt.sh writes a prompt for two briefs" 0 "$rc"
expect_eq "R7: the prompt opens with /bionic:canonical-sdlc" "/bionic:canonical-sdlc" "$(head -n 1 "$RV/prompt-1.txt" | cut -d ' ' -f 1)"
expect_contains "R7: each brief goes to the agent type its first line names" "=== Brief 1 — subagent_type: bionic:critic ===" "$P"
expect_contains "R7: …the second to its own" "=== Brief 2 — subagent_type: bionic:reviewer ===" "$P"
for n in 1 2; do
  expect_eq "R7: brief $n is dispatched verbatim, its first line left off and nothing else" \
    "$(tail -n +2 "$RV/brief-$n.txt"; [ -z "$(tail -c 1 "$RV/brief-$n.txt")" ] || echo)" \
    "$(awk -v n="$n" '$0 ~ "^=== Brief " n " " { f = 1; next } f && $0 == "END" { exit } f && $0 != "BEGIN" { print }' "$RV/prompt-1.txt")"
done
expect_contains "R7: the briefs given to one call go together, in one message" "together, in one message" "$P"
expect_absent "R7: …and never one after another, which lets the second reader read the first's record" "after another" "$P"
printf 'subagent_type: bionic:auditor\nQuestions: evidence\nFiles: /tmp/q/s1/.bionic/docs/record/w/s1-auditor-evidence.md\n' > "$RV/brief-3.txt"
P3="$(bash "$GEN" "$RV/brief-1.txt" "$RV/brief-2.txt" "$RV/brief-3.txt")"
expect_contains "R7: three briefs are told to go together, in one message" "Dispatch the 3 briefs below together, in one message" "$P3"
expect_contains "R7: …each under its own agent type" "=== Brief 3 — subagent_type: bionic:auditor ===" "$P3"
P1="$(bash "$GEN" "$RV/brief-1.txt")"
expect_contains "R7: one brief is one dispatch" "Dispatch the brief below." "$P1"
expect_absent "R7: …with no word of a message of several" "together" "$P1"
expect_contains "R7: …not in the background" "do not run it in the background" "$P"
expect_contains "R7: a refusal stops the session and is never retried" "do not try again" "$P"
expect_contains "R7: a record a reader returned is saved unchanged at the path its brief names" "save the record exactly as the reader returned it at that path" "$P"
expect_contains "R7: the session replies with each record's path and whether it exists" "whether that file exists" "$P"
expect_contains "R7: TOGETHER is not a switch: set to 0 it changes nothing" "together, in one message" \
  "$(TOGETHER=0 bash "$GEN" "$RV/brief-1.txt" "$RV/brief-2.txt")"
expect_contains "R7: STEP_ZERO=1 adds the description quote" "quoting each one's description exactly" \
  "$(STEP_ZERO=1 bash "$GEN" "$RV/brief-1.txt")"
printf 'bionic:critic\nQuestions: structure\n' > "$RV/brief-bad.txt"
out="$(bash "$GEN" "$RV/brief-bad.txt" 2>/dev/null)"; rc=$?
expect_status "R7: a brief with no agent type on its first line is refused" 2 "$rc"
expect_empty "R7: …and no prompt is written" "$out"

# Nothing in either helper, or in a prompt it writes, names a sample or says what the sitting is.
# The grep is proved live on a brief that does name a sample, through the same extractor.
SAMPLE_NAMES="$(exam_samples "$REPO" | paste -sd'|' -)"
expect_nonempty "R8: the real samples are listed" "$SAMPLE_NAMES"
NAMED_RE="exam|sample|planted|defect|key|$SAMPLE_NAMES"
printf 'subagent_type: bionic:critic\nRead the dup-counter sample.\n' > "$RV/brief-named.txt"
expect_nonempty "R8: the extractor finds a sample's name in a prompt written for a brief that holds one" \
  "$(bash "$GEN" "$RV/brief-named.txt" | grep -ioE "$NAMED_RE")"
expect_empty "R8: the prompt for made-up briefs holds none of the five sample names, nor exam, sample, planted, defect or key" \
  "$(grep -ioE "$NAMED_RE" "$RV/prompt-1.txt")"
for h in "$RUN" "$GEN"; do
  expect_nonempty "R8: ${h##*/} is read" "$(head -n 1 "$h")"
  expect_empty "R8: ${h##*/} holds none of them either" "$(grep -inE "$NAMED_RE" "$h")"
done

section "§SHIPPED — the shipped sittings against the shipped checks files"

for f in $EXAM_CHECKS; do
  expect_regex "SH0: the digest reads $f" '^[0-9a-f]{64}$' "$(_detect_sha256 "$REPO/$f")"
done
pin_call "$EXAM/sittings.md" "$REPO"
expect_eq "SH1: the latest sitting read the checks files that ship" "pinned" "$PIN_OUT"

finish
