#!/bin/bash
# payload/scripts/lib/proof.sh — the proof record (epic-23 wave-26 T4; REQ-3, D5).
#
# WHAT IT OWNS. One fact per proof: which commit a test pass or a review read. A proof is a
# line inside the plan's `## SDLC State`:
#
#     proved: kind=<floor|review|task|check> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>
#
# written only by `session-poker.sh proof-add <kind> <evidence>` through the plan verbs'
# transaction, and read by `proof_last`. A `check` (wave-27 T16; D12) is the one exception: its line
# is written only by `session-poker.sh release-check`, the verb that runs the project's declared
# command, and its evidence is that verb's log. A READING (wave-27 T2; D1) is a review proof that adds
# four fields, ` question=<q> reader=<roster name> result=<pass|flag|fail> scope=<piece|whole>`,
# written by `proof-add review <record> --question <q> --reader <name>`; every reader keyed by
# kind alone reads it as the review proof it is. What is unproved is the difference since the head a
# proof names; `proof_state` (T5, beside these) is the reader that judges that difference.
#
# THE HEAD IS NEVER AN OPERAND, AND IT IS THE HEAD THE EVIDENCE READ (wave-26 T14; review 7 F1).
# `proof_attested` reads it out of the evidence itself — a full run's `head=<sha> dirty=<n>`
# header, or a review's `reviewed: <a>..<b>` line — and holds it against the checkout of the
# plan's `working-branch:`: a run must have read that checkout's head on a clean tree, a review
# a commit on its history. So a proof never names a head nobody tested, a dirty tree, or one
# that landed between the run and the verb, and a caller cannot type the head it wishes it had
# read.
#
# Sourced, never executed. Defines functions and one constant; reads nothing at load time.
# bash 3.2: no associative arrays, no `${var,,}`.

PROOF_KINDS="floor review task check"
# The questions a reading answers, the values its result and scope take, and the answers a
# structure check takes (the Interfaces table of wave-27).
PROOF_QUESTIONS="evidence adversarial structure"
PROOF_RESULTS="pass flag fail"
PROOF_SCOPES="piece whole"
PROOF_CHECK_ANSWERS="PASS FLAG FAIL n/a"
# The roles a reading may be registered for: a reader's roster row carries one of these as its
# `subagent_type=`, never a writer's (D7).
PROOF_READER_ROLES="bionic:auditor bionic:critic"
# THE DEALING (wave-27 T9; D2, D6; wave-30 T11, D1): the reader role that answers each question at
# each rigor, one role per question, in PROOF_QUESTIONS' order,
# `<rigor>=<evidence>,<adversarial>,<structure>`. Two levels, keyed by lib/run.sh `rigor_level`'s
# words: `single`, the critic holds every question; `double`, the auditor takes `evidence` and the
# critic the rest. The structure reader `bionic:reviewer` is retired (wave-30 T20) and is no
# role. `facts_owed` is its one reader.
PROOF_DEALING="single=bionic:critic,bionic:critic,bionic:critic double=bionic:auditor,bionic:critic,bionic:critic"
# The questions that read the code; at wave scale each also owes one read of the whole (D10).
PROOF_CODE_QUESTIONS="adversarial structure"
# THE SEVERITY SCALE'S TWO CLOSED SETS AND ITS TABLE (wave-28 T15; D19, AC-8.1, AC-8.3): a finding's
# severity and reach, and the one priority each pair gives, `<S>:<reach>=<fix|defer|note>`. This
# is the table's one definition: `proof_priority` reads it, and every awk that rates a finding is
# handed it whole through its environment.
PROOF_SEVERITIES="S1 S2 S3 S4"
PROOF_REACHES="on off"
PROOF_PRIORITY="S1:on=fix S1:off=fix S2:on=fix S2:off=defer S3:on=defer S3:off=note S4:on=note S4:off=note"
# THE DEBT TABLE'S KINDS (wave-30 T22; D2, AC-11.1): the kinds a `debt:` line names, in the order the
# table in payload/context/severity.md lists them. tests/units.test.sh §DEBT holds the two to one list.
PROOF_DEBT_KINDS="duplicate unpinned-pair one-case-abstraction"

# proof_kind_ok <kind> -> 0 when <kind> is one of PROOF_KINDS.
proof_kind_ok() {
  case " $PROOF_KINDS " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac
}

# proof_question_ok <question> -> 0 when <question> is one of PROOF_QUESTIONS.
proof_question_ok() {
  case " $PROOF_QUESTIONS " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac
}

# proof_line <kind> <head> <at> <evidence> [<question> <reader> <result> <scope>] -> the one proof
# line, newline-terminated; a reading's four fields follow the evidence when a question is given.
proof_line() {
  if [ -n "${5:-}" ]; then
    printf 'proved: kind=%s head=%s at=%s evidence=%s question=%s reader=%s result=%s scope=%s\n' \
      "$1" "$2" "$3" "$4" "$5" "${6:-}" "${7:-}" "${8:-}"
  else
    printf 'proved: kind=%s head=%s at=%s evidence=%s\n' "$1" "$2" "$3" "$4"
  fi
}

# proof_floor_line <head> <at> <evidence> [<owed>] -> the floor's proof line, newline-terminated: proof_line's,
# and ` owed=<suite>[,<suite>]` after the evidence when the whole run it cites left suites red (wave-35 T9; D8,
# AC-1.3). THE REDS RIDE ON THE LINE: `proof-add floor` writes what `proof_floor_owed` read from the log it
# judged, and the judge (`_proof_floor_judge`) reads the field, never the log again, so a floor line with no
# `owed=` is a green whole run's, as every line written before 1.18.0 is.
proof_floor_line() {
  if [ -n "${4:-}" ]; then
    printf 'proved: kind=floor head=%s at=%s evidence=%s owed=%s\n' "$1" "$2" "$3" "$4"
  else
    proof_line floor "$1" "$2" "$3"
  fi
}

# proof_floor_owed <whole-run log> -> the suites the log's LAST run left red, comma-joined on one line, each
# by its file name (wave-35 T9; D8, AC-1.3); nothing for a green run. Read from the runner's own `Failed:`
# block (tests/run.sh), the lines `    - <suite>[ (<why>)]` after the last `Gating:` verdict that follows the
# last `head=<sha> dirty=<n>` header, so a log with an earlier run in it is judged by its last. A LOG THAT ENDS
# `rc=0` OWES NOTHING (wave-36 T35; AC-7.10): its run passed, whatever a block above its close says.
proof_floor_owed() {
  awk '
    NF { last = $0 }
    /^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { seen = 1; o = ""; inf = 0; next }
    !seen { next }
    /^Gating: [0-9]+ passed, [0-9]+ failed$/ { o = ""; inf = 0; v = 1; next }
    v && $0 == "Failed:" { inf = 1; next }
    inf && /^    - [^ ]/ { s = substr($0, 7); sub(/ .*$/, "", s); sub(/.*\//, "", s); o = o (o == "" ? "" : ",") s; next }
    inf { inf = 0 }
    END { if (o != "" && last !~ /^rc=0[ \t\r]*$/) print o }' "${1:-/dev/null}" 2>/dev/null
}

# proof_inherited_lines <plan> -> each `inherited: <suite> base=<sha> head=<sha> …` line of the plan's unfenced
# `## SDLC State`, whole and as written, one per line (wave-35 T9; D8, AC-1.6): THE ONE READER of the inherited-debt
# lines, written by `session-poker.sh proof-add inherited <suite>` once the suite ran red at the base. The judge
# reads their suites (`proof_inherited`); close-out carries the lines into the continuation (wave-35 T10; A-orch-18).
proof_inherited_lines() {
  [ -f "${1:-}" ] || return 0
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^inherited:[ \t]+[^ \t]/ && / base=[0-9a-f]+/ && / head=[0-9a-f]+/' "$1"
}

# proof_inherited <plan> -> the suites the plan carries as inherited debt, comma-joined on one line, each once by
# its file name, read off `proof_inherited_lines`. The floor's judge owes nothing for a suite named here, and
# stands on the rest.
proof_inherited() {
  proof_inherited_lines "${1:-}" | awk '
    { split($0, w, /[ \t]+/); s = w[2]; sub(/.*\//, "", s)
      if (!(s in seen)) { seen[s] = 1; o = o (o == "" ? "" : ",") s } }
    END { if (o != "") print o }'
}

# proof_approved <plan> <name> -> 0 when the plan's unfenced `## SDLC State` carries an `approved: <name> by …`
# line, the user's act `session-poker.sh approve <name>` writes; 1 otherwise.
proof_approved() {
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 1
  awk -v n="$2" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^approved:[ \t]/ { split($0, w, /[ \t]+/); if (w[2] == n && w[3] == "by") { f = 1; exit } }
    END { exit !f }' "$1"
}

# proof_waiver_line <question> <head> <who> <at> <reason> -> the one waiver line, newline-terminated:
# the user's act, covering <question> up to <head> (wave-27 T9; written by `session-poker.sh waive`).
proof_waiver_line() {
  printf 'waived: question=%s head=%s by %s %s "%s"\n' "$1" "$2" "$3" "$4" "$5"
}

# proof_reading <record> <question> [<checks file>] -> `<result> <scope> <from>` read from a reading
# record, exit 0, <from> the start of its range as written; or exit 1 with one sentence saying what
# the record lacks and what to write (the verb's refusal). ONE PASS (wave-27 T41; review pass 10
# F1; T45, review pass 16): a reading record holds one pass, from its `reviewed: <a>..<b>` line —
# the line proof_attested takes its range from — to the end, and a record with a second flush-left
# `reviewed:` line is refused; a key missing from the pass refuses, and a key given twice in it
# refuses. (A plain review proof, read by proof_attested alone, keeps its first-line rule.) In that pass, the
# first of each flush-left line: `question: <q>` equal to <question>, `result:` one of
# PROOF_RESULTS, `scope:` one of PROOF_SCOPES, each value matched whole against its set (F2: a
# value holding a space or a `|` is no word of the set, and never fills another field). For
# `structure`, <checks file> names the check ids as `- **<id>**` items, and the pass answers each
# with `check: <id> <answer> <reason>`, the answer one of PROOF_CHECK_ANSWERS: a checks file that
# cannot be read, or names no id, refuses. Its result is one the checks bear out (F6): `pass`
# beside no FLAG or FAIL check, `flag` beside no FAIL.
# THE FINDINGS (wave-28 T15; D19): with <severity> 1 — the reader's roster row says it was pushed
# the severity scale (`proof_pushed_severity`) — the pass must also carry its findings in the form
# `proof_findings` reads, and its result is the one they derive (`proof_findings_result`). Without
# it the record is read as 1.12.0 read it, every finding line ignored (AC-8.8).
proof_reading() {
  local rec="$1" q="$2" ck="${3:-}" sev="${4:-}" span got rv rq rr rs ids miss worst
  span="$(awk '/^reviewed:[ \t]/ { if (n++) exit } n' "$rec" 2>/dev/null)"
  [ -n "$span" ] || { printf 'the reading %s carries no reviewed: <a>..<b> line; write the range it read' "$rec"; return 1; }
  # A READING RECORD IS ONE PASS, AND A KEY IS GIVEN ONCE IN IT (wave-27 T45; review pass 16
  # findings 1, 3). A second flush-left `reviewed:` line is a second pass, whatever it holds, so a
  # record of two is refused rather than read from its top; and a pass that states question:,
  # result:, scope: or one check id twice is refused, rather than taken at its first value.
  got="$(awk '/^reviewed:[ \t]/ { n++ } END { print n + 0 }' "$rec" 2>/dev/null)"
  [ "$got" -le 1 ] \
    || { printf 'the reading %s holds %s passes (%s flush-left reviewed: lines); a reading record holds one pass, so write each pass as a record of its own' "$rec" "$got" "$got"; return 1; }
  got="$(printf '%s\n' "$span" | awk '
    /^(question|result|scope):/ { k = $0; sub(/:.*$/, ":", k); if (seen[k]++) { print k; exit } }
    /^check:[ \t]/ { m = split($0, f, /[ \t]+/); if (m >= 2) { k = "check: " f[2]; if (seen[k]++) { print k; exit } } }')"
  [ -z "$got" ] \
    || { printf 'the reading %s gives %s twice in its pass; a key is given once, so keep the line the reader meant' "$rec" "$got"; return 1; }
  got="$(printf '%s\n' "$span" | awk '
    function val(s) { sub(/^[a-z]+:[ \t]*/, "", s); sub(/[ \t]+$/, "", s); return s }
    NR == 1 { rv = $0; sub(/^reviewed:[ \t]+/, "", rv); sub(/[ \t].*$/, "", rv); sub(/\.\..*$/, "", rv) }
    /^question:/ && !hq { hq = 1; q = val($0) }
    /^result:/ && !hr { hr = 1; r = val($0) }
    /^scope:/ && !hs { hs = 1; s = val($0) }
    END { printf "%s\n%s\n%s\n%s\n", rv, q, r, s }')"
  { IFS= read -r rv; IFS= read -r rq; IFS= read -r rr; IFS= read -r rs; } <<PROOF_READING
$got
PROOF_READING
  [ -n "$rq" ] || { printf 'the reading %s carries no question: <q> line; write question: %s (a reading record holds exactly one pass; a second is refused)' "$rec" "$q"; return 1; }
  proof_word_in "$rq" "$PROOF_QUESTIONS" \
    || { printf 'the reading %s says question: '"'"'%s'"'"', which is not one of evidence, adversarial or structure; write the question it answers' "$rec" "$rq"; return 1; }
  [ "$rq" = "$q" ] \
    || { printf 'the reading %s says question: %s, but the proof is for %s; register it under the question it answers' "$rec" "$rq" "$q"; return 1; }
  [ -n "$rr" ] || { printf 'the reading %s carries no result: line; write result: pass, flag or fail (a reading record holds exactly one pass; a second is refused)' "$rec"; return 1; }
  proof_word_in "$rr" "$PROOF_RESULTS" \
    || { printf 'the reading %s says result: '"'"'%s'"'"', which is not one of pass, flag or fail; write the result the reader gave' "$rec" "$rr"; return 1; }
  [ -n "$rs" ] || { printf 'the reading %s carries no scope: line; write scope: piece or whole (a reading record holds exactly one pass; a second is refused)' "$rec"; return 1; }
  proof_word_in "$rs" "$PROOF_SCOPES" \
    || { printf 'the reading %s says scope: '"'"'%s'"'"', which is not one of piece or whole; write the scope the reader read' "$rec" "$rs"; return 1; }
  if [ "$q" = structure ]; then
    [ -n "$ck" ] && [ -f "$ck" ] && [ -r "$ck" ] \
      || { printf 'the structure checks file %s cannot be read, so the check ids a structure reading answers are unknown; reinstall the plugin' "$ck"; return 1; }
    ids="$(awk '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s); print s }' "$ck" 2>/dev/null)"
    [ -n "$ids" ] \
      || { printf 'the structure checks file %s names no check id (a - **<id>** item); reinstall the plugin' "$ck"; return 1; }
    miss="$(printf '%s\n' "$span" | PROOF_IDS="$ids" PROOF_ANS="$PROOF_CHECK_ANSWERS" awk '
      BEGIN { n = split(ENVIRON["PROOF_ANS"], a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1
              w = split(ENVIRON["PROOF_IDS"], want, "\n") }
      /^check:[ \t]/ { m = split($0, f, /[ \t]+/); if (m >= 4 && (f[3] in ok)) done[f[2]] = 1 }
      END { for (i = 1; i <= w; i++) if (want[i] != "" && !(want[i] in done)) printf "%s%s", (c++ ? " " : ""), want[i] }')"
    [ -z "$miss" ] \
      || { printf 'the structure reading %s leaves %s unanswered; write one line check: <id> <answer> <reason> for each, the answer PASS, FLAG, FAIL or n/a' "$rec" "$miss"; return 1; }
    # The first check answering FAIL, else the first answering FLAG: the worst the pass found.
    worst="$(printf '%s\n' "$span" | awk '
      /^check:[ \t]/ { m = split($0, f, /[ \t]+/); if (m < 3) next
                       if (f[3] == "FAIL" && fail == "") fail = f[2] " FAIL"
                       if (f[3] == "FLAG" && flag == "") flag = f[2] " FLAG" }
      END { if (fail != "") print fail; else if (flag != "") print flag }')"
    case "$rr:$worst" in
      pass:?*|flag:*' FAIL')
        printf 'the structure reading %s says result: %s beside check: %s; a pass stands beside no FLAG or FAIL check and a flag beside no FAIL, so write the result its checks give' "$rec" "$rr" "$worst"; return 1 ;;
    esac
  fi
  # THE RESULT IS DERIVED FROM THE FINDINGS (wave-28 T15; D19, AC-8.4), when the reader was pushed the scale.
  if [ "$sev" = 1 ]; then
    got="$(_proof_findings_span "$rec" "$span")" || { printf '%s' "$got"; return 1; }
    # A STRUCTURE READING'S TWO DERIVATIONS AGREE (wave-28 T15; A-orch-34). F6 above holds the result
    # to the worst check, the table to the findings; a check answers FAIL only for a finding the table
    # sends to fix, so a FAIL check beside no finding to fix, or a finding to fix beside no FAIL check,
    # is refused in one line naming both. `worst` still holds the worst check here.
    if [ "$q" = structure ]; then
      ids="$(printf '%s\n' "$got" | awk -F'\t' '$5 == "fix" { print "finding " $1 " (" $2 " " $3 ")"; exit }')"
      case "$worst" in
        *' FAIL') [ -n "$ids" ] \
          || { printf 'the structure reading %s gives check: %s beside no finding to fix; a FAIL check stands beside a finding the table sends to fix and a finding to fix beside a FAIL check, so rate the finding or answer the check to agree' "$rec" "$worst"; return 1; } ;;
        *) [ -z "$ids" ] \
          || { printf 'the structure reading %s gives %s to fix beside no FAIL check; a FAIL check stands beside a finding the table sends to fix and a finding to fix beside a FAIL check, so rate the finding or answer the check to agree' "$rec" "$ids"; return 1; } ;;
      esac
    fi
    worst="$(proof_findings_result "$got")"
    [ "$rr" = "$worst" ] \
      || { printf 'the reading %s says result: %s, but its findings give %s (a finding to fix gives fail, any other finding flag, none pass); write result: %s' "$rec" "$rr" "$worst" "$worst"; return 1; }
  fi
  printf '%s %s %s' "$rr" "$rs" "$rv"
}

# proof_word_in <value> <set> -> 0 when <value> is one of the space-separated words of <set>,
# whole: a value holding a space matches no word (wave-27 T41; review pass 10 F2).
proof_word_in() {
  local w
  for w in $2; do [ "$1" = "$w" ] && return 0; done
  return 1
}

# ---------- A FINDING'S SEVERITY AND REACH (wave-28 T15; REQ-8, D19) ----------
#
# A reader pushed the severity scale writes each finding it rates, flush-left in its one pass:
#
#     findings: <n>
#     finding: <n> <S1|S2|S3|S4> <on|off> <path>:<line>|- <title>
#     shown: <n> <command>             for a finding the table sends to fix
#     debt: <kind> <concept> <path>:<line>[, <path>:<line>...]   a debt finding (wave-30 T22)
#
# A READER'S RATING IS FINAL (wave-31 T32; D6, REQ-6 AC-6.3). Wave-28 T41 let a finding carry
# `unsure: <n> <what is not known>` and owe a check, written as a `check:` line of `## SDLC State` that
# held `current 8` until `finding-check` settled it. All of it is gone: an `unsure:` line is an ordinary
# line of the record, read by nothing, so a finding to fix it stood in for is shown nowhere and refused;
# no `check:` line is written, and one an older plan carries binds, re-rates and holds nothing.
#
# A DEBT LINE IS A FINDING OF ITS OWN CLASS (wave-30 T22; D2, AC-11.1; A-orch-8). It names a kind of
# the debt table (PROOF_DEBT_KINDS), one concept and its sites, never a severity or a reach, and it is
# not counted in `findings:`. It reads as flag-class: it gives `flag` when no finding gives `fail`. A
# debt line carrying a severity or a reach word, a kind outside the table, or a site that is not a
# `<path>:<line>`, is refused, naming the line. The orchestrator writes the run's ledger from these
# lines (`session-poker.sh debt add`); the table defers nothing to the plan for them.
#
# The record writes no priority: the table gives it (`proof_priority`), and a `priority: <n> <word>`
# line that differs from the table is refused. The result follows from the priorities
# (`proof_findings_result`). At registration `proof-add` writes the plan's `deferred:` lines
# (`proof_finding_lines`); the tick and `release-check` print them with their priority
# (`proof_findings_owed`).

# proof_pushed_severity <pushed> -> 0 when the roster row's `pushed=` value (the context files the
# recorder pushed at start, comma-joined, read off the line by key as `questions=` is) names
# `severity` as a whole entry. A row with no key (one 1.12.0 wrote, or a reader with no question)
# was not pushed the scale, and its record is read as 1.12.0 read it.
proof_pushed_severity() {
  case ",${1:-}," in *,severity,*) return 0 ;; *) return 1 ;; esac
}

# proof_priority <S> <reach> -> `fix`, `defer` or `note`, the table's one cell; exit 1 when either is
# outside its set.
proof_priority() {
  _proof_priority_var "${1:-}" "${2:-}" || return 1
  printf '%s' "$_PROOF_P"
}

# _proof_priority_var <S> <reach> -> proof_priority's cell in `_PROOF_P` and no fork, for the batch reader
# (wave-28 T72), which asks it once per finding of every bound reading.
_proof_priority_var() {
  local c
  _PROOF_P=""
  for c in $PROOF_PRIORITY; do
    [ "${c%%=*}" = "${1:-}:${2:-}" ] && { _PROOF_P="${c#*=}"; return 0; }
  done
  return 1
}

# proof_findings <record> -> the findings of the record's one pass (from its `reviewed:` line), one
# tab-separated line each, in the order written:
#
#     <n> <S> <reach> <path:line|-> <fix|defer|note> <shown 1|0> <title>
#
# then one line per `debt:` line, in the order written, five fields, its first `debt` (never a finding's
# number) and its fifth `burn` (the debt table's disposition, burn-when-touched), so a reader of the
# fifth field reads it as a finding that is not to fix, and a reader of seven fields skips it:
#
#     debt <kind> <concept> <sites, joined by ", "> burn
#
# exit 0 (nothing printed for `findings: 0`); or exit 1 with one sentence saying what the findings
# lack and what to write (the verb's refusal). The rules: a `findings: <n>` line, given once; that
# many `finding:` lines, each number once, each severity and reach from its set, a `<path>:<line>`
# or `-`, and a title; a `shown:` or `priority:` line names a finding the record holds; a written
# priority is the table's; and a finding the table sends to fix carries a `<path>:<line>` with a
# `shown:` line. Any other line (an `unsure:` line among them, wave-31 T32) is the record's prose.
proof_findings() {
  local span
  span="$(awk '/^reviewed:[ \t]/ { if (n++) exit } n' "$1" 2>/dev/null)"
  [ -n "$span" ] || { printf 'the reading %s carries no reviewed: <a>..<b> line; write the range it read' "$1"; return 1; }
  _proof_findings_span "$1" "$span"
}

# proof_record_debts <record> -> the `debt` rows proof_findings gives, read from every flush-left `debt:`
# line of ANY record, a `reviewed:` line or not (wave-36 T13; D13, REQ-7 AC-7.2, census C24): a writer's or
# the orchestrator's `assumptions.md` hole line is read as a reading's is, by the one debt arm below, and
# refused in its words. The kinds are PROOF_DEBT_KINDS', so a caller widens them by setting it for the
# call (the debt verb hands lib/debt.sh's DEBT_KINDS, `hole` among them). Exit 0, nothing printed for a
# record with no debt line; or 1 with the arm's sentence.
proof_record_debts() {
  local span
  [ -f "${1:-}" ] && [ -r "$1" ] || { printf 'no readable record at %s' "${1:-}"; return 1; }
  span="$(printf 'findings: 0\n'; awk '/^debt:/' "$1" 2>/dev/null)"
  _proof_findings_span "$1" "$span"
}

# _proof_findings_span <record> <its pass> -> proof_findings' answer for a pass already cut.
_proof_findings_span() {
  local out
  out="$(PROOF_REC="$1" PROOF_PRI="$PROOF_PRIORITY" PROOF_SEV="$PROOF_SEVERITIES" PROOF_REACH="$PROOF_REACHES" PROOF_DK="$PROOF_DEBT_KINDS" awk '
    BEGIN {
      rec = ENVIRON["PROOF_REC"]
      n = split(ENVIRON["PROOF_PRI"], c, " ")
      for (i = 1; i <= n; i++) { k = c[i]; sub(/=.*$/, "", k); v = c[i]; sub(/^[^=]*=/, "", v); pri[k] = v }
      n = split(ENVIRON["PROOF_SEV"], c, " "); for (i = 1; i <= n; i++) sev[c[i]] = 1
      n = split(ENVIRON["PROOF_REACH"], c, " "); for (i = 1; i <= n; i++) rch[c[i]] = 1
      n = split(ENVIRON["PROOF_DK"], c, " "); for (i = 1; i <= n; i++) { dk[c[i]] = 1; dkl = (i == 1 ? "" : dkl (i == n ? " or " : ", ")) c[i] }
    }
    function bad(m) { if (err == "") err = "the reading " rec " " m }
    function rest(s, k,   i) { for (i = 0; i < k; i++) sub(/^[^ \t]+[ \t]*/, "", s); sub(/[ \t]+$/, "", s); return s }
    /^findings:/ {
      if (hf++) { bad("gives findings: twice in its pass; a key is given once"); next }
      want = rest($0, 1)
      if (want !~ /^[0-9]+$/) bad("says findings: '"'"'" want "'"'"', which is no count; write findings: <n>, the number of finding: lines")
      next
    }
    /^finding:/ {
      m = split($0, f, /[ \t]+/); id = f[2]
      if (id !~ /^[1-9][0-9]*$/) { bad("has a finding: line with no number (" $0 "); write finding: <n> <S1|S2|S3|S4> <on|off> <path>:<line>|- <title>"); next }
      if (id in S) { bad("gives finding " id " twice; number each finding once"); next }
      if (!(f[3] in sev)) { bad("rates finding " id " '"'"'" f[3] "'"'"', which is not one of S1, S2, S3 or S4; rate it by the severity scale"); next }
      if (!(f[4] in rch)) { bad("gives finding " id " the reach '"'"'" f[4] "'"'"', which is not on or off; say whether a user who follows what the run ships meets it"); next }
      if (f[5] != "-" && f[5] !~ /^[^ \t]+:[0-9]+$/) { bad("names '"'"'" f[5] "'"'"' where finding " id " takes a <path>:<line> or -; write the file and line at the reviewed head, or -"); next }
      t = rest($0, 5)
      if (t == "") { bad("gives finding " id " no title; write what is wrong after its <path>:<line> or -"); next }
      S[id] = f[3]; R[id] = f[4]; W[id] = f[5]; T[id] = t; ord[++cnt] = id
      next
    }
    /^shown:/ {
      m = split($0, f, /[ \t]+/)
      if (rest($0, 2) == "") { bad("has a shown: line with nothing after its number (" $0 "); write shown: <n> <command>"); next }
      sh[f[2]] = 1; named[f[2]] = "shown"; next
    }
    /^priority:/ { m = split($0, f, /[ \t]+/); wp[f[2]] = f[3]; named[f[2]] = "priority"; next }
    /^debt:/ {
      line = $0; sub(/[ \t]+$/, "", line); m = split(line, f, /[ \t,]+/)
      for (i = 2; i <= m; i++) if ((f[i] in sev) || (f[i] in rch)) {
        bad("rates its debt line (" line ") with '"'"'" f[i] "'"'"', and debt is rated by kind and concept, never by severity or reach; write debt: <kind> <concept> <path>:<line>[, <path>:<line>]"); next }
      if (!(f[2] in dk)) { bad("has a debt line (" line ") whose kind '"'"'" f[2] "'"'"' is not one of " dkl "; name the kind on the debt table in severity.md"); next }
      if (m < 4) { bad("has a debt line (" line ") with no site; write the concept, then each <path>:<line> it lives at"); next }
      k = split(rest(line, 3), st, /[ \t]*,[ \t]*/); ss = ""; ok = 1
      for (i = 1; i <= k && ok; i++) if (st[i] !~ /^[^ \t]+:[0-9]+$/) {
        bad("has a debt line (" line ") naming '"'"'" st[i] "'"'"' where a site takes <path>:<line>; write each site as the file and line at the reviewed head"); ok = 0 }
      else ss = ss (i > 1 ? ", " : "") st[i]
      if (ok) { dn++; DK[dn] = f[2]; DC[dn] = f[3]; DS[dn] = ss }
      next
    }
    END {
      if (err == "" && !hf) err = "the reading " rec " carries no findings: <n> line, and its reader was pushed the severity scale; write findings: <n> and one finding: line per finding (findings: 0 when it found none)"
      if (err == "" && cnt != want + 0) bad("says findings: " want " but holds " cnt " finding: lines; write one finding: line per finding, and the count they make")
      for (k in named) if (err == "" && !(k in S)) bad("has a " named[k] ": line for finding " k ", which it does not hold; name a finding it numbers")
      for (i = 1; i <= cnt && err == ""; i++) {
        id = ord[i]; p = pri[S[id] ":" R[id]]
        if ((id in wp) && wp[id] != p) bad("writes priority " wp[id] " for finding " id ", but the table gives " S[id] " " R[id] " " p "; a record writes no priority, so remove the line")
        else if (p == "fix" && !(W[id] != "-" && (id in sh))) bad("sends finding " id " (" S[id] " " R[id] ") to fix, but shows it nowhere; write its <path>:<line> and shown: " id " <command>")
      }
      if (err != "") { print "!" err; exit }
      for (i = 1; i <= cnt; i++) { id = ord[i]; printf "%s\t%s\t%s\t%s\t%s\t%d\t%s\n", id, S[id], R[id], W[id], pri[S[id] ":" R[id]], (id in sh), T[id] }
      for (i = 1; i <= dn; i++) printf "debt\t%s\t%s\t%s\tburn\n", DK[i], DC[i], DS[i]
    }' <<< "$2")"
  case "$out" in '!'*) printf '%s' "${out#!}"; return 1 ;; esac
  [ -z "$out" ] || printf '%s\n' "$out"
}

# proof_findings_result <proof_findings lines> -> `fail` when one is to fix, else `flag` when there
# are any, else `pass` (the interfaces' derived result).
proof_findings_result() {
  _proof_result_var "${1:-}"
  printf '%s\n' "$_PROOF_RESULT"
}

# _proof_result_var <proof_findings lines> -> proof_findings_result's word in `_PROOF_RESULT`, with no fork
# (wave-28 T72): the batch reader asks it once per bound reading, and a fork per ask is most of its cost.
# A finding line is one with a fifth field, the priority.
_proof_result_var() {
  local a b c d p _r any=0 fix=0
  while IFS='	' read -r a b c d p _r; do
    [ -n "$p" ] || continue
    any=1; [ "$p" != fix ] || fix=1
  done <<PROOF_RESULT_LINES
${1:-}
PROOF_RESULT_LINES
  if [ "$fix" = 1 ]; then _PROOF_RESULT=fail; elif [ "$any" = 1 ]; then _PROOF_RESULT=flag; else _PROOF_RESULT=pass; fi
}

# proof_finding_lines <record path> <proof_findings lines> -> the plan lines registration writes inside
# `## SDLC State`, newline-terminated: `deferred: <record>#<n> <S> <reach> "<title>"` for each finding
# the table defers; nothing for a note, nor for a finding to fix, which the verdict carries. A `"` in a
# title is written `'`, so the quoted title ends where its line does.
proof_finding_lines() {
  printf '%s\n' "${2:-}" | REC="$1" awk -F'\t' '
    NF >= 7 && $5 == "defer" { t = $7; gsub(/"/, "'"'"'", t); printf "deferred: %s#%s %s %s \"%s\"\n", ENVIRON["REC"], $1, $2, $3, t }'
}

# proof_finding_rating <plan> <record>#<n> <S> <reach> -> `<S> <reach> <priority>`, the rating a
# REGISTERED finding is read at and the priority it takes.
#
# THE SEAM FOR THE EFFECTIVE RATING (wave-28 T15 left it unbuilt; T42 fills the move). Every read of a
# registered record's findings passes each finding through here, and this is the one place the
# effective rating is applied. The rating is the one the record wrote: a reader's rating is final
# (wave-31 T32; D6), so no line of the plan re-rates it. The priority is the table's for that rating
# (`proof_priority`); a `moved: <record>#<n> to=<defer|fix>` line (T42, `_proof_moved_to`) replaces
# the priority alone, so the third word is the one a move changes — except that an S1 is never
# deferred, whoever wrote the line (AC-8.9). A move to fixed (`moved: … to=fixed row=<T>`, wave-36 T8) puts the
# finding on the fix side, as a move to fix does: it reads fix until its row lands green, and then drops out as
# fixed (`proof_fixed`). A caller reads `set -- $(…)`: three words, rated.
proof_finding_rating() {
  _proof_rating_apply "$(_proof_moved_to "$1" "$2")" "$3" "$4"
  printf '%s' "$_PROOF_RATING"
}

# _proof_rating_apply <moved to> <S> <reach> -> proof_finding_rating's answer once the plan read is in
# hand, in `_PROOF_RATING` and no fork (wave-28 T72): the batch reader (`proof_readings_derived`)
# gathers every finding's move in one pass over the plan and asks here, so the rule is spelled once.
_proof_rating_apply() {
  local mv="$1" s="$2" r="$3" p
  _proof_priority_var "$s" "$r"; p="$_PROOF_P"
  case "$mv" in
    fix|fixed) p=fix ;;
    defer) [ "$s" = S1 ] || p=defer ;;
  esac
  _PROOF_RATING="$s $r $p"
}

# _proof_moved_to <plan> <record>#<n> -> `defer`, `fix` or `fixed`, where the LAST `moved:` line of
# `## SDLC State` naming it (fences skipped) moved the finding, or nothing when there is none
# (wave-28 T42; D34, AC-8.9). A later move is the later word, so the last line decides. A line is a
# move only when it is whole, as `finding-move` writes it (`proof_move_of`):
# `moved: <record>#<n> to=<defer|fix> by=<name> at=<ISO-UTC> words="<words>" why="<why>"`, or
# `moved: <record>#<n> to=fixed row=<T> by=<name> at=<ISO-UTC>` (wave-36 T8; D9).
_proof_moved_to() {
  [ -f "$1" ] || return 0
  awk -v id="$2" "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^moved:[ \t]/ && proof_bound($0) == id { m = proof_move_of($0); if (m != "") to = m }
    END { if (to != "") print to }' "$1"
}

# proof_move_line <plan> <record>#<n> -> the finding's newest whole `moved:` line, verbatim, the one
# `_proof_moved_to` reads its direction from; nothing when the plan carries none (wave-36 T8; D10). What a
# refusal quotes when it names the move it read: `task-add --born` refuses a finding whose newest move is
# to defer, and `disposition` names the row a move to fixed names.
proof_move_line() {
  [ -f "$1" ] || return 0
  awk -v id="$2" "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^moved:[ \t]/ && proof_bound($0) == id && proof_move_of($0) != "" { l = $0 }
    END { if (l != "") print l }' "$1"
}

# _proof_moved_fixed <plan> -> `<row><TAB><record>#<n>`, one line per finding whose newest whole move is to
# fixed (`moved: <record>#<n> to=fixed row=<T> …`, wave-36 T8; D9), in the order the findings were first
# moved; a later move to defer or fix takes the finding back. `proof_fixed`'s second source.
_proof_moved_fixed() {
  [ -f "$1" ] || return 0
  awk "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^moved:[ \t]/ {
      id = proof_bound($0); m = proof_move_of($0)
      if (id == "" || m == "") next
      if (!(id in last)) ord[++n] = id
      last[id] = m; row[id] = proof_move_row($0)
    }
    END { for (i = 1; i <= n; i++) if (last[ord[i]] == "fixed") printf "%s\t%s\n", row[ord[i]], ord[i] }' "$1"
}

# proof_findings_owed <plan> -> one line per finding the plan's `## SDLC State` carries a `deferred:`
# line for, in the order first written, rated through `proof_finding_rating`:
# `<record>#<n> <S> <reach> <fix|defer|note> "<title>"`, the priority the effective rating takes. A
# `check:` line an older plan carries is not read (wave-31 T32; D6). What the tick and `release-check`
# print, so the priority a record never states is seen where the run is judged.
proof_findings_owed() {
  local plan="$1" id s r t
  [ -f "$plan" ] || return 0
  while IFS='	' read -r id s r t; do
    [ -n "$id" ] || continue
    set -- $(proof_finding_rating "$plan" "$id" "$s" "$r")
    [ $# -ge 3 ] && [ -n "$3" ] || continue
    printf '%s %s %s %s %s\n' "$id" "$1" "$2" "$3" "$t"
  done <<PROOF_OWED_FINDINGS
$(awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
  insdlc && /^deferred:[ \t]/ {
    m = split($0, f, /[ \t]+/); if (m < 4 || (f[2] in seen)) next
    seen[f[2]] = 1; t = $0; if (match(t, /"[^"]*"/)) t = substr(t, RSTART, RLENGTH); else t = "\"\""
    printf "%s\t%s\t%s\t%s\n", f[2], f[3], f[4], t
  }' "$plan")
PROOF_OWED_FINDINGS
}

# _proof_reading_result <plan> <docs root> <evidence> <written result> -> the reading's result as its
# findings give it at their effective ratings (wave-28 T41; D33): a reading whose record a binding line
# names (`proof_bind_awk`: a `deferred:` or `moved:` line keyed to a finding of it) is derived
# again from its record at the ratings the plan gives its findings; any other reading, or one whose
# record cannot be read, keeps its written result.
#
# A FIXED FINDING IS SETTLED (wave-33 T13; REQ-5 AC-5.2, D6). With the reading's <head>, its <tree> and the
# plan's fixed findings (`proof_fixed`'s lines) after the four operands, a finding of the reading that a born
# row fixed at or after <head> (`_proof_fixed_var`) drops out of the derivation, so a `fail` reading whose
# every finding to fix is fixed derives to `flag` or `pass`; a fixed finding binds the reading as a deferral
# does. Without them the answer is the one it always was.
_proof_reading_result() {
  _proof_reading_result_var "$@"
  printf '%s' "$PROOF_DERIVED"
}

# _proof_reading_result_var <as _proof_reading_result> -> its answer in `PROOF_DERIVED`, with no fork, leaving
# `_PROOF_FIXED_IDS` set for the reading. The fixes' landings are held on the walk by `_facts_born_landings`
# (wave-36 T7), which reads `proof_fixed` itself.
_proof_reading_result_var() {
  local plan="$1" droot="$2" ev="$3" res="$4" tab
  PROOF_DERIVED="$res"; _PROOF_FIXED_IDS=""
  [ -n "$droot" ] && [ -n "$ev" ] && [ -f "$droot/$ev" ] || return 0
  tab="$(_proof_binding_table "$plan" "$ev")" || tab=""
  _proof_fixed_var "${7:-}" "$ev" "${5:-}" "${6:-}"
  [ -n "$tab" ] || [ -n "$_PROOF_FIXED_IDS" ] || return 0
  _proof_reading_derive "$droot" "$ev" "$res" "$tab" "$_PROOF_FIXED_IDS"
}

# proof_fixed <plan> [<tree>] -> `<record>#<n><TAB><row><TAB><commit><TAB><born|moved>`, one line per finding a
# fix row answers and has landed green (wave-33 T13; REQ-5 AC-5.2, D6). The row answers the finding in one of
# two ways: it names the finding on its born marker (lib/units.sh `units_born_findings`, which `task-add --born
# <record>#<n>` writes), `born`; or the finding's newest move names it (`moved: <record>#<n> to=fixed row=<T>`,
# which `finding-move <record>#<n> fixed <row>` writes; wave-36 T8, D9), `moved`, born marker or none. A
# finding both answer is printed once, as `moved`. Either way the row's `## Tasks` status is `landed`, and the
# run's landing record (`proof_debt_record`, lib/line.sh's events) holds a verdict for it whose commit is the
# row's newest verdict commit and whose every suite there reads `result=green`, the last word per suite.
# <commit> is that commit, the landing the green verdicts name. Nothing when no born marker names a finding and
# no move names a row, so a plan without either pays one grep. Whether <commit> must be at or after a reading's
# head is the reader's to ask (`_proof_fixed_var`): a born row's must, a moved row's need not, since the move
# says the row fixed the finding whatever its ancestry (ADR-056: "a finding fixed before or beside the reading
# is fixed"). RED has no machine record (research-verbs-landing.md G1): the green landing is the proof read.
proof_fixed() {
  local plan="${1:-}" tree="${2:-}" born moved rec
  [ -f "$plan" ] || return 0
  /usr/bin/grep -qE ' born: review S[0-9]+ o[nf]f* of=|^moved:[[:space:]]+[^[:space:]]+[[:space:]]+to=fixed[[:space:]]' "$plan" 2>/dev/null || return 0
  _proof_units_load || return 0
  declare -F units_born_findings >/dev/null 2>&1 && declare -F units_rows >/dev/null 2>&1 || return 0
  born="$(units_born_findings "$plan" 2>/dev/null | awk -F'\t' '$2 == "landed" { print $1 "\t" $3 "\tborn" }')"
  moved="$({ printf '\034rows\n'; units_rows "$plan" 2>/dev/null; printf '\034moved\n'; _proof_moved_fixed "$plan"; } | awk -F'\t' '
    $0 == SUBSEP "rows" { part = 1; next }
    $0 == SUBSEP "moved" { part = 2; next }
    part == 1 { if ($10 == "landed") landed[$1] = 1; next }
    part == 2 && ($1 in landed) { print $1 "\t" $2 "\tmoved" }')"
  [ -n "$born" ] || [ -n "$moved" ] || return 0
  rec="$(proof_debt_record "$plan" "$tree")" || return 0
  [ -f "$rec" ] || return 0
  { printf '\034born\n'; [ -z "$moved" ] || printf '%s\n' "$moved"; [ -z "$born" ] || printf '%s\n' "$born"
    printf '\034rec\n'; cat "$rec" 2>/dev/null; } | awk -F'|' '
    function fv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    $0 == SUBSEP "born" { part = 1; next }
    $0 == SUBSEP "rec" { part = 2; next }
    part == 1 { split($0, b, "\t"); if (b[2] in seen1) next; seen1[b[2]] = 1; nb++; brow[nb] = b[1]; bid[nb] = b[2]; bhow[nb] = b[3]; want[b[1]] = 1; next }
    part == 2 && substr($0, 1, 8) == "line/v1|" && fv("ev") == "verdict" {
      r = fv("row"); if (!(r in want)) next
      c = fv("commit"); s = fv("suite"); v = fv("result")
      if (c == "" || s == "") next
      if (lc[r] != c) { lc[r] = c; ns[r] = 0 }
      if (!((r SUBSEP c SUBSEP s) in seen)) { seen[r, c, s] = 1; ns[r]++; sl[r, ns[r]] = s }
      res[r, s] = v
    }
    END {
      for (r in lc) { ok[r] = (ns[r] > 0); for (i = 1; i <= ns[r]; i++) if (res[r, sl[r, i]] != "green") ok[r] = 0 }
      for (i = 1; i <= nb; i++) if ((brow[i] in ok) && ok[brow[i]]) printf "%s\t%s\t%s\t%s\n", bid[i], brow[i], lc[brow[i]], bhow[i]
    }'
}

# _proof_fixed_var <proof_fixed lines> <record> <reading head> <tree> -> in `_PROOF_FIXED_IDS` the findings of
# <record> fixed for a reading at <reading head>, newline-wrapped (`\n<record>#<n>\n…`); empty when none. A born
# row's fix counts at or after the head (the landing's commit has the head on its history); a moved row's counts
# whatever its ancestry (wave-36 T8; D9). No fork but one `git merge-base` per born-fixed finding of the record.
_proof_fixed_var() {
  local id row c how nl=$'\n'
  _PROOF_FIXED_IDS=""
  [ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ -n "${4:-}" ] || return 0
  while IFS='	' read -r id row c how; do
    case "$id" in "$2#"*) : ;; *) continue ;; esac
    [ -n "$c" ] || continue
    [ "$how" = moved ] || git -C "$4" merge-base --is-ancestor "$3" "$c" 2>/dev/null || continue
    _PROOF_FIXED_IDS="$_PROOF_FIXED_IDS$nl$id"
  done <<PROOF_FIXED_LINES
$1
PROOF_FIXED_LINES
  [ -z "$_PROOF_FIXED_IDS" ] || _PROOF_FIXED_IDS="$_PROOF_FIXED_IDS$nl"
}

# _proof_binding_table <plan> <record> -> one line per finding of <record> a binding line of the plan's
# unfenced `## SDLC State` is keyed to: `<record>#<n><TAB><moved to>`, `-` when the plan says none
# (`_proof_moved_to`'s answer, read in one pass); exit 1, nothing printed, when no binding line names
# the record.
_proof_binding_table() {
  [ -f "$1" ] || return 1
  awk -v rec="$2" "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_binds($0, rec) {
      hit = 1; id = proof_bound($0); ids[id] = 1
      if ($0 ~ /^moved:/) { m = proof_move_of($0); if (m != "") mv[id] = m }
    }
    END {
      if (!hit) exit 1
      for (id in ids) print id "\t" (id in mv ? mv[id] : "-")
    }' "$1"
}

# _proof_reading_derive <docs root> <evidence> <written result> <binding table> -> in `PROOF_DERIVED`, the
# result <evidence>'s findings give at the ratings the table (`_proof_binding_table`'s lines) says: the one
# derivation, asked once per reading by `_proof_reading_result` and once per bound reading by
# `proof_readings_derived`, which prints it without a fork. A record that cannot be read keeps the
# written result. A fifth operand, `_proof_fixed_var`'s newline-wrapped ids, names the findings a landed
# born row fixed: each drops out, whatever its rating (wave-33 T13; D6).
_proof_reading_derive() {
  local droot="$1" ev="$2" res="$3" fixed="${5:-}" nl tb tab got n s r w mv out=""
  nl=$'\n'; tb=$'\t'; tab="$nl$4"; PROOF_DERIVED="$res"
  got="$(proof_findings "$droot/$ev" 2>/dev/null)" || return 0
  while IFS='	' read -r n s r w _; do
    [ -n "$n" ] || continue
    # A debt row is flag-class whatever the plan binds (no binding line names it): kept as it is.
    [ "$n" != debt ] || { out="$out$n	$s	$r	$w	burn
"; continue; }
    case "$fixed" in *"$nl$ev#$n$nl"*) continue ;; esac
    mv=""
    case "$tab" in
      *"$nl$ev#$n$tb"*)
        mv="${tab#*"$nl$ev#$n$tb"}"; mv="${mv%%"$nl"*}"
        [ "$mv" != - ] || mv="" ;;
    esac
    _proof_rating_apply "$mv" "$s" "$r"
    set -- $_PROOF_RATING
    [ $# -ge 3 ] || continue
    out="$out$n	$1	$2	$w	$3
"
  done <<PROOF_READING_FINDINGS
$got
PROOF_READING_FINDINGS
  _proof_result_var "$out"; PROOF_DERIVED="$_PROOF_RESULT"
}

# proof_checkout <repo> <branch> -> the path of the checkout of <repo> that has <branch> checked
# out; exit 1 with nothing printed when none does.
proof_checkout() {
  local repo="$1" branch="$2" wt
  [ -n "$branch" ] || return 1
  wt="$(git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk -v b="branch refs/heads/$branch" '/^worktree / { p = substr($0, 10) } $0 == b { print p; exit }')"
  [ -n "$wt" ] && [ -d "$wt" ] || return 1
  printf '%s' "$wt"
}

# proof_attested <kind> <evidence file> <checkout> [<plan>] [<question>] [<root>] [<head>] -> the 40-hex head the
# evidence attests, exit 0; or exit 1 with one sentence on stdout saying why not and what to do (the verb's refusal).
# <head> is the working head the evidence is held against: `proof-add` hands it the working branch's ref
# (`proof_branch_head`, the judge's one reading of the head) and its repository as <checkout>, so a branch no
# checkout holds is read as the judge reads it (wave-36 T12; D13, AC-7.4; C30). With none, <checkout>'s HEAD.
# "The checkout's HEAD" below means that head.
#   floor  THE LOG OF A RUN, IN THE FLOOR'S ONE GRAMMAR (wave-36 T35; D13, AC-7.10): its first
#          `head=<40-hex> dirty=0` line and its last line `rc=0`, nothing between read, whatever
#          ran it (`_proof_floor_log`, which says the rule whole). No roster is counted, no `Gating:`
#          verdict asked for and no config key needed; a <root> whose `.bionic/config.yaml` still
#          carries `floor-attestation:`, a removed key, is refused by name (`proof_floor_retired`).
#          THE FLOOR IS A RECORD OF RUNS (wave-31 T25; REQ-4 AC-4.1, REQ-13 AC-13.4; D3): <sha> is
#          the checkout's HEAD, or an ancestor of it from which `_proof_walk` proves every later
#          commit by the runs recorded at it (`_proof_floor_walk`). The run itself is judged first.
#   review a review: its first `reviewed: <a>..<b>` line. <b> must resolve to a commit that is
#          the checkout's HEAD or an ancestor of it; the proof names that commit — a review of an
#          older head is a true proof of that older head, and what landed since is unread.
#          <a> must be a commit on <b>'s history, and at or before what the plan already has
#          read (a review proof only): its last review proof's head, or with none its base, so no
#          commit between two review proofs goes unread (wave-26 T62; critic 2 K2-F2). A plain
#          review proof (no <question>) with no <plan>, or on a plan with no base that is a commit
#          here, is held to the other checks alone. With a <question>, the last review proof is
#          that question's own (wave-27 T2; D1): each question is its own chain, so a reader of
#          one question is never held to where another question's reading ended. A question's
#          first reading on a plan with no base, a base that is not a commit id (`HEAD`, a branch)
#          or one that names no commit here is refused, naming the frontmatter line to add
#          (wave-27 T45; review pass 13 F1; T14, review pass 20 F1).
#   task   whichever of the two the evidence carries, the run header first (A-T14.9).
#   check  the release-check verb's log (wave-27 T16; D12): its FIRST line after any `check-changed:
#          <path>` lines (T31; review pass 22 B1) is `head=<40-hex> rc=0`, which says the declared
#          command passed, and <sha> must be the checkout's HEAD: the command ran in that checkout
#          at that head.
proof_attested() {
  local kind="$1" ev="$2" co="$3" plan="${4:-}" q="${5:-}" root="${6:-}" head stamp sha dirty rng a ah b bh since sh what verdict
  head="$(git -C "$co" rev-parse --verify -q "${7:-HEAD}^{commit}" 2>/dev/null)" \
    || { printf 'the checkout %s has no head to hold the evidence against' "$co"; return 1; }
  if [ "$kind" = floor ]; then
    proof_floor_retired "$root" && return 1
    _proof_floor_log "$ev" "$head" "$co" "$plan" "$root"; return $?
  fi
  if [ "$kind" = check ]; then
    sha="$(awk '/^check-changed: / { next } { if ($0 ~ /^head=[0-9a-f]+ rc=0$/) { sub(/^head=/, ""); sub(/ rc=0$/, ""); print } exit }' "$ev" 2>/dev/null)"
    if [ "${#sha}" -ne 40 ]; then
      printf 'the evidence %s does not open with head=<40-hex> rc=0, the line release-check writes on a pass; run release-check' "$ev"; return 1
    fi
    if [ "$sha" != "$head" ]; then
      printf 'the check in %s ran at %s, but the working branch is at %s; run release-check again' \
        "$ev" "$(printf '%s' "$sha" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)"; return 1
    fi
    printf '%s' "$head"; return 0
  fi
  stamp="$(awk '/^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { s = $0 } END { if (s != "") print s }' "$ev" 2>/dev/null)"
  rng="$(awk '/^reviewed:[ \t]/ { sub(/^reviewed:[ \t]+/, ""); sub(/[ \t].*$/, ""); print; exit }' "$ev" 2>/dev/null)"
  case "$kind" in
    review) stamp="" ;;
    task) [ -n "$stamp" ] && rng="" ;;
  esac
  if [ -n "$stamp" ]; then
    sha="${stamp#head=}"; sha="${sha%% *}"; dirty="${stamp##*dirty=}"
    if [ "$sha" = none ]; then
      printf 'the run in %s read no repository (head=none); run it in the working branch checkout and cite that log' "$ev"; return 1
    fi
    if [ "$sha" != "$head" ]; then _proof_read_elsewhere "$ev" "$sha" "$head"; return 1; fi
    [ "$dirty" = 0 ] || { _proof_read_dirty "$ev" "$dirty"; return 1; }
    # THE RUN MUST ALSO HAVE PASSED (wave-26 T5; review 10 F1). A header says which head a run
    # read, not how it ended: a red run, or a note that quotes the header, attests the head all
    # the same, and the full-run wall reads a proved head as needing no run. So the runner's own
    # verdict, `Gating: <n> passed, <m> failed` (tests/run.sh), must follow the header with n > 0
    # and m = 0.
    # THE LAST RUN IN THE LOG, AND ITS OWN VERDICT (T52; review 14 S3). The stamp above is the
    # last header and the verdict is the last `Gating:` line after it, so a red run with another
    # head's green run appended is judged by the appended run, which read another head. A verdict
    # that a capture-close line (`───── end <suite> ─────`, the runner's `_verdict`) follows sat
    # inside a failing suite's captured output, a nested run's: the runner prints its own verdict
    # after every capture, so a log whose last verdict is followed by one was cut off.
    # NO VOID TERM (wave-35 T2; D11, AC-2.1): the runner reports no VOID, so a suite is passed or
    # failed and nothing else. A `Void:` line a log still carries counts for nothing.
    verdict="$(awk '
      /^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { seen = 1; v = ""; inside = 0; next }
      !seen { next }
      /^Gating: [0-9]+ passed, [0-9]+ failed$/ { v = $2 " " $4; inside = 0; next }
      v != "" && index($0, "───── end ") == 1 { inside = 1 }
      END { if (v == "") print "none"; else print v " " inside }' "$ev" 2>/dev/null)"
    case "$verdict" in
      none|'')
        printf 'the run in %s has no Gating: <n> passed, <m> failed verdict after its head= line; cite the whole log of a full run that finished' "$ev"; return 1 ;;
    esac
    set -- $verdict
    if [ "$3" != 0 ]; then
      printf 'the last verdict in %s sits inside a suite'"'"'s captured output (a ───── end line follows it), so the run itself has none; cite the whole log of a full run that finished' "$ev"; return 1
    fi
    # A TASK PROOF CITES A GREEN RUN, and a run with nothing passed proves nothing.
    if [ "$1" = 0 ] || [ "$2" != 0 ]; then
      printf 'the run in %s did not pass (Gating: %s passed, %s failed); fix it, run it again and cite that log' "$ev" "$1" "$2"; return 1
    fi
    printf '%s' "$sha"; return 0
  fi
  if [ -n "$rng" ]; then
    case "$rng" in
      *..*) b="${rng##*..}" ;;
      *) b="" ;;
    esac
    case "$b" in
      ''|*[!0-9a-fA-F]*)
        printf 'the review in %s names no range a..b (reviewed: %s); write the commits it read as reviewed: <a>..<b>' "$ev" "$rng"; return 1 ;;
    esac
    bh="$(git -C "$co" rev-parse --verify -q "$b^{commit}" 2>/dev/null)" \
      || { printf 'the review in %s read up to %s, which is no commit here; name the commit it read' "$ev" "$b"; return 1; }
    if ! git -C "$co" merge-base --is-ancestor "$bh" "$head" 2>/dev/null; then
      printf 'the review in %s read up to %s, which is not on the working branch (at %s); review that branch and name its commit' \
        "$ev" "$(printf '%s' "$bh" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)"; return 1
    fi
    # WHERE THE RANGE STARTS IS ATTESTED TOO (wave-26 T62; critic 2 K2-F2). Only its end was read,
    # so `<head~1>..<head>`, or a start that is no commit at all, proved every commit before it.
    a="${rng%%..*}"
    case "$a" in
      ''|*[!0-9a-fA-F]*) ah="" ;;
      *) ah="$(git -C "$co" rev-parse --verify -q "$a^{commit}" 2>/dev/null)" ;;
    esac
    [ -n "$ah" ] \
      || { printf 'the review in %s starts at %s, which is no commit here; name the commit it read from as reviewed: <a>..<b>' "$ev" "$a"; return 1; }
    if ! git -C "$co" merge-base --is-ancestor "$ah" "$bh" 2>/dev/null; then
      printf 'the review in %s starts at %s, which is not on the history of its end %s; name the range it read as reviewed: <a>..<b>' \
        "$ev" "$(printf '%s' "$ah" | cut -c1-12)" "$(printf '%s' "$bh" | cut -c1-12)"; return 1
    fi
    if [ -n "$plan" ] && [ "$kind" = review ]; then
      since="$(proof_last "$plan" review "$q")"; what="the last ${q:-review} proof"
      [ -n "$since" ] || { since="$(proof_plan_base "$plan" "$co")"; what="the plan's base"; }
      sh=""
      if [ -n "$since" ] && { [ "$what" != "the plan's base" ] || proof_base_id "$since"; }; then
        sh="$(git -C "$co" rev-parse --verify -q "$since^{commit}" 2>/dev/null)"
      fi
      # A QUESTION'S FIRST READING NEEDS THE BASE (wave-27 T45; review pass 13 F1). With no base to
      # hold its start, a reading of the last commit alone would stand for every commit before it,
      # and the judge would call the question covered. Nothing is derived in the base's place.
      if [ -n "$q" ] && [ "$what" = "the plan's base" ] && [ -z "$sh" ]; then
        printf 'add base-sha: <the commit the work started from> to the frontmatter of %s: %s, so where the %s chain starts cannot be held, and its first reading is refused' \
          "$plan" "$(if [ -z "$since" ]; then printf 'it names no base-sha:'; elif proof_base_id "$since"; then printf 'its base-sha: %s is no commit here' "$since"; else printf 'its base-sha: %s is not a commit id' "$since"; fi)" "$q"
        return 1
      fi
      if [ -n "$sh" ] && ! git -C "$co" merge-base --is-ancestor "$ah" "$sh" 2>/dev/null; then
        printf 'the review in %s starts at %s, past %s %s, so what landed between them is unread; review %s..%s' \
          "$ev" "$(printf '%s' "$ah" | cut -c1-12)" "$what" "$(printf '%s' "$sh" | cut -c1-12)" \
          "$(printf '%s' "$sh" | cut -c1-12)" "$(printf '%s' "$bh" | cut -c1-12)"; return 1
      fi
    fi
    printf '%s' "$bh"; return 0
  fi
  case "$kind" in
    review) printf 'the evidence %s carries no reviewed: <a>..<b> line; a review proof cites a review whose header names the range it read' "$ev" ;;
    *) printf 'the evidence %s carries neither a head=<sha> dirty=<n> run header nor a reviewed: <a>..<b> line; cite a run log or a review' "$ev" ;;
  esac
  return 1
}

# The two sentences a run header that read the wrong tree is refused with: another head, a dirty tree.
# One spelling each, for the runner's log and for a declared regression's evidence alike. A REGRESSION at
# another head is judged by `_proof_floor_walk` (wave-31 T25); a task proof keeps the first sentence bare.
_proof_read_elsewhere() {  # <evidence> <sha it read> <the working head>
  printf 'the run in %s read head %s, but the working branch is at %s; run it again on %s and cite that log' \
    "$1" "$(printf '%s' "$2" | cut -c1-12)" "$(printf '%s' "$3" | cut -c1-12)" "$(printf '%s' "$3" | cut -c1-12)"
}
_proof_read_dirty() {  # <evidence> <dirty count>
  printf 'the run in %s read a dirty tree (dirty=%s); commit, run it again and cite that log' "$1" "$2"
}

# _proof_floor_walk <evidence> <sha it read> <the working head> <checkout> [<plan>] [<root>] -> exit 0 when
# a whole green run at <sha> stands for the working head; or exit 1 with the refusal's sentence (wave-31
# T25; REQ-4 AC-4.1, REQ-13 AC-13.4; D3). The run itself is judged by the caller first. <sha> must be a
# commit here and an ancestor of the working head H; an empty change since it is the tree the run read;
# otherwise `_proof_walk` must prove every commit after it, reading the plan's landing record beside
# the stamps. The refusal names the first commit it cannot prove and what that commit lacks.
_proof_floor_walk() {
  local ev="$1" sha="$2" head="$3" co="$4" plan="${5:-}" root="${6:-}" owed="${7:-}" files rec="" why rc waive=0
  if ! git -C "$co" rev-parse --verify -q "$sha^{commit}" >/dev/null 2>&1; then
    printf 'the run in %s read head %.12s, which is no commit here; run the whole suite on the working branch (at %.12s) and cite that log' "$ev" "$sha" "$head"
    return 1
  fi
  if ! git -C "$co" merge-base --is-ancestor "$sha" "$head" 2>/dev/null; then
    printf 'the run in %s read head %.12s, which is not in the history of the working branch (at %.12s); run the whole suite on that branch and cite that log' "$ev" "$sha" "$head"
    return 1
  fi
  files="$(git -C "$co" diff --name-only --no-renames "$sha" "$head" 2>/dev/null)" \
    || { printf 'the run in %s read head %.12s, and git cannot list the change since it to the working head %.12s' "$ev" "$sha" "$head"; return 1; }
  [ -n "$files" ] || return 0
  [ -z "$plan" ] || rec="$(proof_debt_record "$plan" "$root" 2>/dev/null)" || rec=""
  [ -z "$plan" ] || ! proof_approved "$plan" regression-2 || waive=1
  # THE CANDIDATE'S OWN REDS ARE NO REFUSAL (wave-35 T9; D8): they are owed, and the judge says so after the
  # proof is written; only a commit the walk cannot prove refuses the log (exit 1).
  why="$(_proof_walk "$co" "$sha" "$head" "$rec" "$owed" "$waive")"; rc=$?
  [ "$rc" -ne 1 ] && return 0
  printf 'the run in %s read head %.12s, and the working branch is at %.12s: %s. Run the suites it lacks on %.12s, or the whole suite, then proof-add floor again' \
    "$ev" "$sha" "$head" "${why:-the commits since it cannot be walked}" "$head"
  return 1
}

# _proof_records <checkout> [<landing record>] -> THE RECORDS the floor judge weighs (`_proof_walk`, below),
# one tab-separated line each, in the order read (the landing record, then every git dir's stamp file):
#   O <commit> <row> <suites | ->               a published commit (or a `landed:` merge) and its row's suites
#   R <at> <commit> <suite | *> <green | red> <verdict | stamp>   one suite's run at one commit (`*`, a whole run)
# AN ENVIRONMENT RED IS NO RECORD (wave-33 T2; REQ-7 AC-7.2): a landing's `standing` event of
# `cause=environment` (lib/line.sh `_line_red_owner`) says a run of that suite on the same code disagrees
# with the red, so the red verdicts it stands for, of its suite at its head and on every candidate built
# on that head, are not the suite's state and are left out. A standing event of class `code`, or with no
# `cause=` (one written before 1.16.0), leaves them in. lib/line.sh `_line_cause` reads the same records.
# A SUITE IS KEYED BY ITS FILE NAME (wave-35 T6; REQ-5 AC-5.2, D14), as the gate, cost and debt key it: a stamp
# names `x.test.sh` (the wall's --suites) where a landing files its verdict, and ready its `suites=`, under the
# declared path (`tests/x.test.sh`, wave-34 T27), so every suite this prints, in an O line or an R line, is the
# part after the last `/`, and a reader compares file names.
_proof_records() {
  local co="$1" rec="${2:-}" gd f
  gd="$(cd "$co" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
  { if [ -n "$rec" ] && [ -f "$rec" ]; then cat "$rec"; fi
    if [ -n "$gd" ]; then for f in "$gd/bionic-stamps" "$gd"/worktrees/*/bionic-stamps; do
      [ -f "$f" ] && cat "$f"; done; fi; } 2>/dev/null | awk -F'|' '
    function fv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    function out(l) { lines[++nl] = l }
    function key(p) { sub(/.*\//, "", p); return p }
    function keys(l,   a, n, i, o) { n = split(l, a, ","); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") key(a[i]); return o }
    substr($0, 1, 8) == "line/v1|" {
      ev = substr($2, 4); r = fv("row")
      if (ev == "ready") { if (r != "") su[r] = keys(fv("suites")) }
      else if (ev == "published") { c = fv("commit"); if (c != "") out("O\t" c "\t" r "\t" ((r in su) ? su[r] : "-")) }
      else if (ev == "verdict") {
        c = fv("commit"); s = key(fv("suite")); v = fv("result")
        if (c != "" && s != "" && (v == "green" || v == "red")) { out("R\t" fv("at") "\t" c "\t" s "\t" v "\tverdict"); if (v == "red") { vc[nl] = c; vs[nl] = s } }
      }
      else if (ev == "candidate") { c = fv("commit"); if (c != "") base[c] = fv("base") }
      else if (ev == "standing") { if (fv("cause") == "environment") env[fv("head"), key(fv("suite"))] = 1 }
      next
    }
    substr($0, 1, 8) == "landed: " {
      r = ""; c = ""; m = split($0, w, " ")
      for (i = 2; i <= m; i++) { if (index(w[i], "row=") == 1) r = substr(w[i], 5); else if (index(w[i], "merge=") == 1) c = substr(w[i], 7) }
      if (c != "") out("O\t" c "\t" r "\t-")
      next
    }
    substr($0, 1, 9) == "stamp/v1|" {
      h = d = rc = s = at = ""; nh = nd = nr = ns = 0
      for (i = 2; i <= NF; i++) {
        if (substr($i, 1, 4) == "cmd=") break
        if (substr($i, 1, 5) == "head=")        { h = substr($i, 6); nh++ }
        else if (substr($i, 1, 6) == "dirty=")  { d = substr($i, 7); nd++ }
        else if (substr($i, 1, 3) == "rc=")     { rc = substr($i, 4); nr++ }
        else if (substr($i, 1, 7) == "suites=") { s = substr($i, 8); ns++ }
        else if (substr($i, 1, 3) == "at=")     at = substr($i, 4)
      }
      if (nh != 1 || nd != 1 || nr != 1 || ns > 1 || h == "" || h ~ /[^0-9a-f]/ || d != "0") next
      if (rc == "" || rc ~ /[^0-9]/ || rc == "75" || rc == "69") next
      v = (rc == "0") ? "green" : "red"
      m = split(s, a, ",")
      for (i = 1; i <= m; i++) {
        if (a[i] == "" || a[i] == "?") continue
        if (a[i] == "run.sh") { out("R\t" at "\t" h "\t*\t" v "\tstamp"); continue }
        out("R\t" at "\t" h "\t" key(a[i]) "\t" v "\tstamp")
      }
    }
    END {
      for (i = 1; i <= nl; i++) {
        if (i in vc && (((vc[i], vs[i]) in env) || ((vc[i] in base) && ((base[vc[i]], vs[i]) in env)))) continue
        print lines[i]
      }
    }'
}

# _proof_walk <checkout> <F> <H> [<landing record>] [<owed>] [<waive cover>] -> exit 0, printing nothing, when
# every commit on the working branch's first-parent line after F, up to and including H, is proved by the runs
# recorded at it and every suite F's whole run left red (<owed>, comma-joined file names) is closed; exit 1
# printing one sentence that names the first commit that is not proved, and what it lacks; exit 2 printing the
# owed suites still open, comma-joined, when every commit is proved and only those remain (wave-31 T25; REQ-13
# AC-13.3, AC-13.4; D3; A-T25-1, A-T25-2, A-T25-4; wave-35 T9: D8, D9, AC-1.3 to AC-1.5). F is an ancestor of
# H (the caller's).
#
# THE RECORDS, every one a run of one suite at one commit with a time (`at=`):
#   - the landing record's `line/v1|ev=verdict|…|commit=<C>|suite=<S>|result=green|red|…` events
#     (lib/line.sh), and the `stamp/v1|` lines `land` copied under its `landed:` headers;
#   - the `booked.sh` stamps in every git dir of the repository (`<common dir>/bionic-stamps` and
#     `<common dir>/worktrees/*/bionic-stamps`): each suite a clean stamp names, green at rc 0 and red
#     at any other rc but 75 and 69, which ran nothing; a `run.sh` stamp is every suite at its result.
# A RECORD IS KEYED BY THE TREE ITS COMMIT HAS, so a run at any commit with C's files is a run on C:
# a landing's verdicts are at its candidate, which is the published commit, and a stamp at a row head
# counts for the merge exactly when the merge left the row's tree as it was.
#
# WHAT A COMMIT OWES: nothing when its tree is its first parent's, or when every path it changed is a
# non-code path (`_proof_docs_path`'s one list, or under the docs root): A DOCS-ONLY COMMIT INHERITS ITS
# PARENT'S STANDING (wave-35 T9; AC-1.5). Otherwise its row's Lands-on set (the `suites=` of the row's last
# `ready` before the `published` event naming the commit) and every suite a record at its tree names. A
# commit owing nothing that changed its tree is not proved. NOTHING PREDICTS A SUITE SET: every member of an
# owed set is a record.
#
# WHEN A SUITE OWED AT C IS PROVED: the last commit from C to H whose tree holds a record of it decides,
# by its newest record: green proves it, red does not. A later green run covers an earlier commit's
# change, since the later tree holds it; a later red supersedes an earlier green. A whole run is a
# record of every suite at once (`*`), weighed against each suite's own by time: a red one leaves
# every suite owed at or before its commit red there, and a newer run, the whole or the suite's own,
# decides again (wave-31 T41).
#
# A SUITE COVERS WHAT IT READS (wave-35 T9; D9, AC-1.4; design-ledger Δ2; wave-36 T27, D12, ADR-056): a commit
# whose owed suites are all green is still not proved when it changed a code file that none of them reads, by
# the reads index at H (lib/anchors.sh `reads_index`, the one file-to-suite fact `brief` and the dispatch wall's
# Lands-on arm read, keyed by file name); a code file is a path outside tests/ and the non-code paths above. That commit owes a second whole run, unless <waive cover> is 1, the plan's
# `approved: regression-2` (the caller's to read).
#
# AN OWED RED IS CLOSED BY A LANDING (wave-35 T9; D8, AC-1.3): a suite of <owed> is closed when the last walked
# commit whose tree holds a landing's verdict of it (never a stamp, never a whole run) has its newest such
# verdict green, keyed by file name (wave-35 T6).
_proof_walk() {
  local co="$1" from="$2" to="$3" rec="${4:-}" owed="${5:-}" waive="${6:-0}" walk recs need trees pairs changed="" idx="" pfx="" droot top f c cls
  walk="$(git -C "$co" log --first-parent --reverse --format='W%x09%H%x09%T%x09%P' "$from..$to" 2>/dev/null)" \
    || { printf 'git cannot list the commits from %.12s to %.12s' "$from" "$to"; return 1; }
  if [ -z "$walk" ]; then
    [ -n "$owed" ] || return 0
    printf '%s' "$owed"; return 2
  fi
  recs="$(_proof_records "$co" "$rec")"
  # THE TREES, in one git call: every commit a record names and every walked commit's first parent.
  need="$(printf '%s\n%s\n' "$recs" "$walk" | awk -F'\t' '
    $1 == "R" { print $3 } $1 == "W" { split($4, p, " "); if (p[1] != "") print p[1] }' | sort -u)"
  trees=""
  [ -z "$need" ] || trees="$(printf '%s\n' "$need" | sed 's/$/^{tree}/' | git -C "$co" cat-file --batch-check='%(objectname)' 2>/dev/null)"
  pairs="$( { printf '%s\n' "$need"; printf -- '--\n'; printf '%s\n' "$trees"; } | awk '
    $0 == "--" && !s { s = 1; next }
    !s { n[++k] = $0; next }
    { i++; if ($0 ~ /^[0-9a-f]+$/ && n[i] != "") print "T\t" n[i] "\t" $0 }')"
  # WHAT EACH COMMIT CHANGED, in one git call, each path classed `doc` (non-code: inherits), `test` (under
  # tests/: owes its runs, declares nothing) or `code` (owes a declaring suite).
  _proof_roots_load
  top="$(git -C "$co" rev-parse --show-toplevel 2>/dev/null)"
  ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$co" 2>/dev/null)"
  case "${droot:-}" in "$top"/?*) pfx="${droot#"$top"/}"; pfx="${pfx%/}/" ;; esac
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      $'\001'*) c="${f#?}"; continue ;;
    esac
    if { [ -n "$pfx" ] && [ "${f#"$pfx"}" != "$f" ]; } || _proof_docs_path "$f"; then cls=doc
    else case "$f" in tests/*) cls=test ;; *) cls=code ;; esac; fi
    changed="$changed${changed:+$'\n'}C	$c	$cls	$f"
  done <<PROOF_WALK_FILES
$(git -C "$co" log --no-renames --first-parent -m --name-only --format='%x01%H' "${from}..${to}" 2>/dev/null)
PROOF_WALK_FILES
  case "$changed" in
    *"	code	"*) [ "$waive" = 1 ] || { _proof_anchors_load && idx="$(reads_index "$co" "$to" 2>/dev/null | sed 's/^/I	/')"; } ;;
  esac
  printf '%s\n%s\n%s\n%s\n%s\n' "$pairs" "$walk" "$recs" "$changed" "$idx" | PROOF_OWED_SET="$owed" awk -F'\t' -v waive="$waive" '
    $1 == "T" { tr[$2] = $3; next }
    $1 == "W" { n++; wc[n] = $2; wt[n] = $3; split($4, p, " "); wp[n] = p[1]; next }
    $1 == "O" { if ($3 != "" && index($3, "—") != 1) orow[$2] = $3; if ($4 != "" && $4 != "-") osu[$2] = $4; next }
    $1 == "R" {
      t = tr[$3]; if (t == "") next
      k = t SUBSEP $4
      if (!(k in rat) || $2 >= rat[k]) { rat[k] = $2; rres[k] = $5 }
      if ($6 == "verdict" && (!(k in vat) || $2 >= vat[k])) { vat[k] = $2; vres[k] = $5 }
      if ($4 != "*") nm[t] = nm[t] " " $4
      next
    }
    $1 == "C" { touched[$2] = 1; if ($3 != "doc") nondoc[$2] = 1; if ($3 == "code") codes[$2] = codes[$2] "\t" $4; next }
    $1 == "I" { k = split($3, a, ","); for (x = 1; x <= k; x++) { s = a[x]; sub(/.*\//, "", s); decl[$2] = decl[$2] "," s }; decl[$2] = decl[$2] ","; next }
    END {
      for (i = 1; i <= n; i++) {
        pt = (i > 1 && wp[i] == wc[i - 1]) ? wt[i - 1] : tr[wp[i]]
        if (pt != "" && pt == wt[i]) continue
        if ((wc[i] in touched) && !(wc[i] in nondoc)) continue
        split("", seen); m = 0
        if (wc[i] in osu) {
          k = split(osu[wc[i]], a, ",")
          for (x = 1; x <= k; x++) if (a[x] != "" && a[x] != "?" && !(a[x] in seen)) { seen[a[x]] = 1; ow[++m] = a[x] }
        }
        k = split(nm[wt[i]], a, " ")
        for (x = 1; x <= k; x++) if (a[x] != "" && !(a[x] in seen)) { seen[a[x]] = 1; ow[++m] = a[x] }
        who = (wc[i] in orow) ? "row " orow[wc[i]] : "no landing row"
        lead = "commit " substr(wc[i], 1, 12) " (" who ") is not proved: "
        if (m == 0) { print lead "no suite run is recorded at it"; exit 1 }
        lack = ""
        for (x = 1; x <= m; x++) {
          s = ow[x]; res = ""; when = ""; whole = 0
          for (j = n; j >= i; j--) {
            t = wt[j]
            if ((t SUBSEP s) in rat) { when = rat[t, s]; res = rres[t, s] }
            if ((t SUBSEP "*") in rat && (res == "" || rat[t, "*"] >= when)) { when = rat[t, "*"]; res = rres[t, "*"]; whole = 1 }
            if (res != "") break
          }
          if (res == "") why = s " has no run recorded at it or after it"
          else if (res == "green") continue
          else if (whole) why = "the whole run at " substr(wc[j], 1, 12) " is red"
          else why = s " is red at " substr(wc[j], 1, 12)
          if (index("; " lack "; ", "; " why "; ") == 0) lack = lack (lack == "" ? "" : "; ") why
        }
        if (lack != "") { print lead lack; exit 1 }
        if (waive == 1 || !(wc[i] in codes)) continue
        k = split(substr(codes[wc[i]], 2), a, "\t"); un = ""; nu = 0; ran = ""
        for (x = 1; x <= m; x++) ran = ran (x > 1 ? ", " : "") ow[x]
        for (x = 1; x <= k; x++) {
          d = 0
          for (y = 1; y <= m && !d; y++) if (index(decl[a[x]], "," ow[y] ",")) d = 1
          if (!d) { un = un (nu++ ? ", " : "") a[x] }
        }
        if (nu) { print lead un (nu > 1 ? " are" : " is") " read by no suite it ran (" ran "); a second whole run owed, or approve regression-2"; exit 1 }
      }
      no = split(ENVIRON["PROOF_OWED_SET"], o, ","); open = ""
      for (x = 1; x <= no; x++) {
        s = o[x]; if (s == "") continue
        res = ""
        for (j = n; j >= 1 && res == ""; j--) if ((wt[j] SUBSEP s) in vat) res = vres[wt[j], s]
        if (res != "green") open = open (open == "" ? "" : ",") s
      }
      if (open != "") { printf "%s", open; exit 2 }
    }'
}

# _proof_anchors_load -> 0 once lib/anchors.sh's reads index is defined, sourced from beside this file: the
# cover's one reader (wave-35 T9; D9; wave-36 T27, D12), loaded only when a walked commit changed a code file.
_proof_anchors_load() {
  local d
  declare -F reads_index >/dev/null 2>&1 && return 0
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  # shellcheck source=/dev/null
  [ -n "$d" ] && [ -r "$d/anchors.sh" ] && . "$d/anchors.sh" 2>/dev/null
  declare -F reads_index >/dev/null 2>&1
}

# _proof_floor_log <evidence> <working head> <checkout> [<plan>] [<root>] -> the 40-hex head the log read, exit 0;
# or exit 1 with the refusal's sentence (wave-36 T35; D13, AC-7.10; the synth-vision filing). THE FLOOR'S ONE
# GRAMMAR. What a project's regression is belongs to the project; the judge asks only that a run of it read a
# clean working head and said how it ended, so it reads two lines of the log the run left and nothing between:
#   the header  the first line that opens `head=`, read as `head=<40-hex> dirty=<n>`: <n> must be 0, and the head
#               the working head or an ancestor of it `_proof_floor_walk` proves every later commit from. Lines
#               before it (a runner's preamble: tests/run.sh prints `rung=` and `env:` first) are not read.
#   the close   the last line that is not blank, `rc=<n>`: rc=0 is a pass.
# A RED RUN is refused naming its rc, unless the runner's own `Failed:` block names its reds (`proof_floor_owed`),
# as many as its last `Gating:` counts failed: then it is the floor's red candidate, those suites owed (wave-35 T9;
# ADR-054). No tests/*.test.sh roster is counted, no `Gating:` verdict is asked for and no config key is needed,
# so tests/run.sh's log, floor-run's log and the log of a project's own runner are each one such log.
_proof_floor_log() {
  local ev="$1" head="$2" co="$3" plan="${4:-}" root="${5:-}" hdr sha dirty rc owed nred m
  hdr="$(awk '/^head=/ { if ($0 ~ /^head=[0-9a-f]+ dirty=[0-9]+$/) { split($0, w, /[ =]/); print w[2] " " w[4] } else print "bad " $0; exit }' "$ev" 2>/dev/null)"
  case "$hdr" in
    '') printf 'the evidence %s carries no head=<sha> dirty=<n> line; a regression proof cites the log of a run, which opens with it' "$ev"; return 1 ;;
    'bad head=none dirty=none') printf 'the run in %s read no repository (head=none); run it in the working branch checkout and cite that log' "$ev"; return 1 ;;
    bad\ *) printf 'the run header in %s reads %s, not head=<40-hex> dirty=<n>; cite the log of a run that opens with that line' "$ev" "${hdr#bad }"; return 1 ;;
  esac
  sha="${hdr%% *}"; dirty="${hdr#* }"
  [ "${#sha}" -eq 40 ] || { printf 'the run header in %s names head %s, which is not 40 hex; cite the log of a run that opens with head=<40-hex> dirty=<n>' "$ev" "$sha"; return 1; }
  [ "$dirty" = 0 ] || { _proof_read_dirty "$ev" "$dirty"; return 1; }
  rc="$(awk 'NF { l = $0 } END { sub(/[ \t\r]+$/, "", l); print l }' "$ev" 2>/dev/null)"
  case "$rc" in rc=[0-9]*) rc="${rc#rc=}" ;; *) rc=x ;; esac
  case "$rc" in *[!0-9]*) printf 'the log %s does not end with an rc=<n> line, so it does not say how its run ended; end it with the run'"'"'s exit code (rc=$?) and cite it' "$ev"; return 1 ;; esac
  owed=""
  if [ "$rc" != 0 ]; then
    owed="$(proof_floor_owed "$ev")"
    [ -n "$owed" ] || { printf 'the run in %s ended rc=%s, so the regression did not pass; fix what it names, run it again and cite that log' "$ev" "$rc"; return 1; }
    nred="$(printf '%s\n' "$owed" | awk -F, '{ print NF }')"
    m="$(awk '/^Gating: [0-9]+ passed, [0-9]+ failed$/ { m = $4 } END { print m + 0 }' "$ev" 2>/dev/null)"
    [ "$nred" = "$m" ] || { printf 'the run in %s counts %s failed but its Failed: block names %s; cite the whole log of a full run, as tests/run.sh wrote it' "$ev" "$m" "$nred"; return 1; }
  fi
  # THE RUN IS GOOD; NOW THE COMMITS SINCE IT (wave-31 T25; D3): a run at an ancestor stands for the working head
  # when every commit after it is proved by its recorded runs; a red candidate's reds stay owed.
  [ "$sha" = "$head" ] || _proof_floor_walk "$ev" "$sha" "$head" "$co" "$plan" "$root" "$owed" || return 1
  printf '%s' "$sha"
}

# proof_floor_retired <root> -> exit 0 with the refusal's sentence when <root>'s `.bionic/config.yaml` carries
# `floor-attestation:` (wave-36 T35; D13, AC-7.10). Wave-28 T75's key named a person's record that a run passed as
# the floor; a log is the fact, so nothing reads the key, and a config that still carries it is refused by its name
# rather than passed over. Exit 1, nothing printed, otherwise (no <root> included). `proof_attested floor`, so
# `proof-add floor`, and `floor-run` ask it first.
proof_floor_retired() {
  local v
  [ -n "${1:-}" ] || return 1
  _proof_roots_load
  v="$(config_value "$1" floor-attestation "" 2>/dev/null)"
  [ -n "$v" ] || return 1
  printf '.bionic/config.yaml carries floor-attestation: %s, a key bionic removed (wave-36): the floor is the log of a run, never a person'"'"'s word. Delete the line, then cite the regression'"'"'s log with proof-add floor <log> [<log>...]' "$v"
}

# proof_plan_base <plan> [<repo>] -> the commit the plan's run started from, or nothing. The places
# are read in this order: the first `base-sha:` inside its unfenced `## SDLC State` (the Step-4 block
# `current 4` fills), then the frontmatter key of the same name. The base is the first value that is
# a commit id, 7 to 40 hex (`proof_base_id`), so an empty or placeholder value in one place never
# hides a real one in the other (wave-27 T14; review pass 20 F4). With a <repo>, it is the first such
# value that ALSO names a commit there: a hex word that names none (`deadbeef`, forty zeros, a base
# rebased away) is passed over as a non-hex word is (T31; review pass 25 F2). Every caller holds a
# repository and passes it (proof_attested, facts_state, proof-add, release-check); the form with no
# <repo> reads text alone, for a caller that may not read git. With no place answering, the first
# non-empty value is printed as written, so a refusal can name it. The first review proof starts at
# or before the base (K2-F2).
proof_plan_base() {
  local c first="" got=""
  [ -f "$1" ] || return 0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    [ -n "$first" ] || first="$c"
    proof_base_id "$c" || continue
    if [ -n "${2:-}" ]; then
      git -C "$2" rev-parse --verify -q "$c^{commit}" >/dev/null 2>&1 || continue
    fi
    got="$c"; break
  done <<PROOF_BASES
$(awk '
    function val(s) { sub(/^[ \t]*base-sha[ \t]*:[ \t]*/, "", s); sub(/[ \t].*$/, "", s); gsub(/["\047]/, "", s); return s }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm && /^base-sha[ \t]*:/ { if (!hf) { hf = 1; f = val($0) } next }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^[ \t]*base-sha[ \t]*:/ { if (!hs) { hs = 1; v = val($0) } }
    END { if (hs) print v; if (hf) print f }' "$1")
PROOF_BASES
  printf '%s' "${got:-$first}"
}

# proof_base_id <value> -> 0 when <value> has the shape of a commit id, 7 to 40 hex. A word that git
# would resolve (`HEAD`, a branch, a tag) moves with the checkout, so it is no base, as a value that
# names no commit is none (wave-27 T14; review pass 20 F1).
proof_base_id() {
  case "${1:-}" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
  [ "${#1}" -ge 7 ] && [ "${#1}" -le 40 ]
}

# proof_awk -> the awk function `proof_fields(s)`, THE ONE READING OF A PROOF LINE (wave-26 T14;
# review 7 F6): 1 when <s> is a proof line, its kind in PROOF_KIND and its head in PROOF_HEAD; a
# reading's four fields in PROOF_QUESTION, PROOF_READER, PROOF_RESULT and PROOF_SCOPE, each empty
# on a line that carries none (wave-27 T2), and its record in PROOF_EVIDENCE (wave-28 T72: the one
# `evidence=` reader, where five programs each spelled their own).
# A proof line starts `proved:` at the first column (a bulleted `- proved:` is prose, not the
# line the writer writes), and carries `kind=<lower-case word>` and `head=<7 to 40 lower-case
# hex>` among its space-separated fields (`head=none` is no head). `proof_last` and the
# readiness program (units.sh) both read through it, so a line one counts the other counts.
proof_awk() {
  printf '%s' '
    function proof_fields(s,   f, m, i) {
      PROOF_KIND = ""; PROOF_HEAD = ""; PROOF_QUESTION = ""; PROOF_READER = ""; PROOF_RESULT = ""; PROOF_SCOPE = ""; PROOF_EVIDENCE = ""; PROOF_OWED = ""
      if (s !~ /^proved:[ \t]/) return 0
      m = split(s, f, /[ \t]+/)
      for (i = 2; i <= m; i++) {
        if (f[i] ~ /^kind=/) PROOF_KIND = substr(f[i], 6)
        else if (f[i] ~ /^head=/) PROOF_HEAD = substr(f[i], 6)
        else if (f[i] ~ /^question=/) PROOF_QUESTION = substr(f[i], 10)
        else if (f[i] ~ /^reader=/) PROOF_READER = substr(f[i], 8)
        else if (f[i] ~ /^result=/) PROOF_RESULT = substr(f[i], 8)
        else if (f[i] ~ /^scope=/) PROOF_SCOPE = substr(f[i], 7)
        else if (f[i] ~ /^evidence=/) PROOF_EVIDENCE = substr(f[i], 10)
        else if (f[i] ~ /^owed=/) PROOF_OWED = substr(f[i], 6)
      }
      return (PROOF_KIND ~ /^[a-z]+$/ && PROOF_HEAD ~ /^[0-9a-f]+$/ && length(PROOF_HEAD) >= 7 && length(PROOF_HEAD) <= 40)
    }
  '
}

# proof_bind_awk -> awk source: THE ONE PREDICATE for the lines that bind a record's pass, and the reads of
# what such a line says (wave-28 T72; D33, D34, AC-8.6, AC-8.9; A-T60.5, A-orch-213). A `deferred:` or
# `moved:` line of `## SDLC State` is keyed `<record>#<n>`: it defers or moves ONE finding of ONE pass,
# and every read of the record's findings applies it (`proof_finding_rating`), so a second pass registered
# on the same path would inherit it. `moved:` binds for the reason a deferral does: a move is the user's
# word about one finding, it changes the priority a later reader of that path judges (T42's seam), and a
# path that carries one is a settled pass whatever else it carries. A `check:` line binds nothing: a
# reader's rating is final (wave-31 T32; D6) and no reader reads one. Both callers (`proof_pass_conflict`,
# the registering verb's guard, and `_proof_reading_result`, the judge's re-derivation) and the batch
# reader (`proof_readings_derived`) ask these, so none can spell it again:
#
#     proof_bound(line)       the `<record>#<n>` a binding line is keyed to, else ""
#     proof_binds(line, rec)  1 when the line is keyed to a finding of the record <rec>
#     proof_move_of(line)     `defer` or `fix` when a `moved:` line is a whole move (who, when, the words
#                             and why, as `finding-move` writes it), `fixed` for a whole move to fixed
#                             (the row, who and when: `to=fixed row=<T> by=… at=…`, wave-36 T8), else ""
#     proof_move_row(line)    the <T> of a move to fixed, else ""
proof_bind_awk() {
  printf '%s' '
    function proof_bound(s,   f) {
      if (s !~ /^(deferred|moved):[ \t]/) return ""
      split(s, f, /[ \t]+/); return f[2]
    }
    function proof_binds(s, rec) { return index(proof_bound(s), rec "#") == 1 }
    function proof_move_of(s,   f) {
      split(s, f, /[ \t]+/)
      if (f[3] == "to=fixed") {
        if (f[4] !~ /^row=T[0-9]+$/ || s !~ / by=[^ \t]/ || s !~ / at=[0-9][0-9][0-9][0-9]-/) return ""
        return "fixed"
      }
      if (f[3] != "to=defer" && f[3] != "to=fix") return ""
      if (s !~ / by=[^ \t]/ || s !~ / at=[0-9][0-9][0-9][0-9]-/ || s !~ / words="/ || s !~ / why="/) return ""
      return substr(f[3], 4)
    }
    function proof_move_row(s,   f) {
      split(s, f, /[ \t]+/)
      return (f[3] == "to=fixed" && f[4] ~ /^row=T[0-9]+$/) ? substr(f[4], 5) : ""
    }
  '
}

# proof_last <plan> <kind> [<question>] -> the head of the LAST `proved:` line of <kind> inside
# the plan's unfenced `## SDLC State`, or nothing. Later lines are newer: the writer only appends.
# With a <question>, the last line of that kind carrying `question=<question>` (wave-27 T2); with
# none, the last line of the kind whatever its question, 1.11.0's reading.
proof_last() {
  _proof_last_read "$1" "$2" head "${3:-}"
}

# proof_last_line <plan> <kind> [<question>] -> that same last line, whole, or nothing: what a
# refusal quotes when it names the proof it read (head and evidence), so no caller parses the plan.
proof_last_line() {
  _proof_last_read "$1" "$2" line "${3:-}"
}

# proof_floor_absent <plan> -> the judge's words for a plan with no floor proof, `no regression proof on this
# plan yet`, exit 0, when the plan's unfenced `## SDLC State` holds no `proved: kind=floor` line (proof_last's
# reading); nothing, exit 1, when it holds one, whatever its head or owed= (wave-35 T38; critic-structure-3,
# debt `unpinned-pair floor-absent`). THE ONE READER OF "IS THERE A FLOOR LINE": the commit wall's Step-7 arm
# (lib/walls.sh `_eg_refuse_floor_absent`, text only, A-orch-50), proof_state and facts_state ask it, so the
# wall and the judge cannot answer one plan's text two ways; both ask it before the floor judge, which therefore
# never asks it again (wave-36 T12; C35). It reads text, through lib/run.sh `plan_lines`, and runs no git.
# Pinned by tests/canonical-sdlc-evidence-gate.test.sh §FLOOR-LINE FL-5, which drives both on one plan.
proof_floor_absent() {
  [ -n "$(proof_last "${1:-}" floor)" ] && return 1
  printf '%s' 'no regression proof on this plan yet'
}

# _proof_last_read <plan> <kind> <head|line|owed> [<question>] -> the one reader behind the two above, and the
# `owed=` field of that last line (wave-35 T9), nothing when it carries none. The plan's lines come from lib/run.sh
# `plan_lines`, the one plan line reader, CR translated (wave-36 T12; D13, AC-7.5): a raw read saw a CR-only plan as
# one line, so its floor line was absent to the wall and the judge alike (C34).
_proof_last_read() {
  local plan="$1" kind="$2" what="$3" q="${4:-}"
  [ -f "$plan" ] || return 0
  _proof_run_load
  plan_lines "$plan" | awk -v k="$kind" -v what="$what" -v q="$q" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == k && (q == "" || PROOF_QUESTION == q) { last = PROOF_HEAD; lastline = $0; lastowed = PROOF_OWED }
    END { if (last != "") { if (what == "line") print lastline; else if (what == "owed") { if (lastowed != "") print lastowed } else print last } }'
}

# proof_add_line <plan> <line> -> the plan with <line> placed inside `## SDLC State`: after the
# section's last `proved:` or `waived:` line, or, before the first, after the section's last
# non-blank line. Exit 1 (nothing printed) when the plan has no unfenced `## SDLC State`.
# Facts and waivers share the one block, so a line's place is its age (wave-27 T9): `facts_state`
# reads "newer" as "later in the section". A reading's `deferred:` lines (wave-28 T15), and a
# finding's `moved:` lines (T42), follow its proof line and belong to the block, so the next line goes
# after them, not between. A `check:` line (wave-28 T41, read by nothing since wave-31 T32) is not one.
proof_add_line() {
  local plan="$1" line="$2"
  [ -f "$plan" ] || return 1
  # THE LINE GOES IN THROUGH THE ENVIRONMENT, not `-v`, which reads a backslash as an escape: a
  # waiver carries the user's reply verbatim (wave-27 T9).
  PROOF_L="$line" awk '
    BEGIN { L = ENVIRON["PROOF_L"] }
    { row[NR] = $0 }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); if (insdlc) { seen = 1; lastn = NR }; next }
    insdlc && /^(proved|waived|deferred|moved|inherited):[[:space:]]/ { lastp = NR }
    insdlc && /[^[:space:]]/ { lastn = NR }
    END {
      if (!seen) exit 1
      at = lastp ? lastp : lastn
      for (i = 1; i <= NR; i++) { print row[i]; if (i == at) print L }
    }' "$plan"
}

# proof_pass_conflict <plan> <record path> <head> -> why <record path> cannot be registered for another
# pass at <head>, or nothing (wave-28 T60; D33, AC-8.6). ONE RECORD PATH IS ONE PASS: a line that binds a
# pass (`proof_bind_awk`: `deferred:` or `moved:`) is keyed `<record>#<n>`, so a second pass on the same
# path would inherit the first pass's deferral or move. The key stays unique by
# construction when the path is registered for one pass only, so the verb asks here before it writes. A
# reading's proof line (one with a `question=`) whose `evidence=` is <record path> and whose head is not
# <head> prints `head <that head>`; otherwise, when a binding line of `## SDLC State` names
# `<record path>#`, `settled <head>`. A reader relaunched on an unsettled record (the same head, no such
# line) gets nothing: it is admitted.
proof_pass_conflict() {
  [ -f "$1" ] || return 0
  awk -v rec="$2" -v head="$3" "$(proof_awk)$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_bound($0) != "" { if (proof_binds($0, rec)) child = 1; next }
    proof_fields($0) && PROOF_QUESTION != "" { if (PROOF_EVIDENCE == rec && PROOF_HEAD != head && other == "") other = PROOF_HEAD }
    END { if (other != "") print "head " other; else if (child) print "settled " head }' "$1"
}

# proof_readings_derived <plan> <tree> -> `<evidence><TAB><written result><TAB><derived result>` for each
# reading proof line (`kind=review` with a `question=`) of the plan's unfenced `## SDLC State`, the
# derived result what `_proof_reading_result` gives it (wave-28 T60; D33, AC-8.6; A-orch-161), and
# NOTHING when no binding line (`proof_bind_awk`) is in the plan: every derived result is then the
# written one. The commit wall judges text and reads no record, so its collector (hooks/bash-walls.sh)
# asks this once, from the step the wall reads (lib/walls.sh `eg_plan_reads_readings`), and hands the
# lines over; the wall and the judge answer a reading's result one way. ONE PASS OVER THE PLAN (T72): the
# readings and every binding line's state are gathered together (each reading's own lines come to the
# shell just before it), and only a reading a binding line names is derived from its record, so the cost
# is one plan read and one record read per bound reading, not a plan read per reading and per finding. <tree> is the project root whose docs root holds the records;
# with no docs root, the derived result is the written one.
#
# A FIXED FINDING BINDS TOO (wave-33 T13; REQ-5 AC-5.2, D6): with a <tree>, the plan's fixed findings
# (`proof_fixed`) are read once, and a reading one of whose findings a born row fixed at or after its head is
# derived as the judge derives it, so the wall and the judge read a fixed question one way.
proof_readings_derived() {
  local plan="${1:-}" tree="${2:-}" droot="" k a b c d tab="" nl fixed=""
  [ -f "$plan" ] || return 0
  nl=$'\n'
  if [ -n "$tree" ]; then
    _proof_roots_load
    ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$tree" 2>/dev/null)"
    fixed="$(proof_fixed "$plan" "$tree")"
  fi
  while IFS='	' read -r k a b c d; do
    case "$k" in
      S) tab="$tab$a	$b$nl" ;;
      R) PROOF_DERIVED="$c"
         _proof_fixed_var "$fixed" "$a" "$d" "$tree"
         if { [ "$b" = 1 ] || [ -n "$_PROOF_FIXED_IDS" ]; } && [ -n "$droot" ] && [ -f "$droot/$a" ]; then
           _proof_reading_derive "$droot" "$a" "$c" "$tab" "$_PROOF_FIXED_IDS"
         fi
         printf '%s\t%s\t%s\n' "$a" "$c" "$PROOF_DERIVED"; tab="" ;;
    esac
  done <<PROOF_READINGS
$(PROOF_HAS_FIXED="${fixed:+1}" awk "$(proof_awk)$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_bound($0) != "" {
      nbind++; id = proof_bound($0); ids[id] = 1
      if ($0 ~ /^moved:/) { m = proof_move_of($0); if (m != "") mv[id] = m }
      next
    }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" && !((PROOF_EVIDENCE SUBSEP PROOF_RESULT) in seen) {
      seen[PROOF_EVIDENCE SUBSEP PROOF_RESULT] = 1; nr++; rev[nr] = PROOF_EVIDENCE; rres[nr] = PROOF_RESULT; rhead[nr] = PROOF_HEAD
    }
    END {
      if (!nbind && ENVIRON["PROOF_HAS_FIXED"] == "") exit
      for (i = 1; i <= nr; i++) {
        hit = 0; p = rev[i] "#"
        for (id in ids) if (index(id, p) == 1) { hit = 1; print "S\t" id "\t" (id in mv ? mv[id] : "-") }
        print "R\t" rev[i] "\t" hit "\t" rres[i] "\t" rhead[i]
      }
    }' "$plan")
PROOF_READINGS
}

# _proof_roots_load -> lib/roots.sh sourced beside this file unless its readers are loaded: the one lazy
# source of it in this library (wave-28 T72; four copies of it stood here), for a caller that sourced
# proof.sh alone.
_proof_roots_load() {
  local d
  declare -F docs_root >/dev/null 2>&1 && declare -F config_value >/dev/null 2>&1 && return 0
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  # shellcheck source=/dev/null
  . "$d/roots.sh" >/dev/null 2>&1
  return 0
}

# proof_state <plan> <tree> -> whether the plan's last regression proof stands at the working head, one
# line (wave-31 T25; REQ-4 AC-4.1, REQ-13 AC-13.4; D3; A-orch-23; wave-35 T9: D8, AC-1.3):
#
#     covered<TAB><head>       the proof names the working head, or nothing changed since it, or every
#                              commit since it is proved by the runs recorded at it (`_proof_walk`), and
#                              every suite its whole run left red is closed; <head> is the working head
#                              judged, which the full-run wall names (T52 N6)
#     owed<TAB><suites>        every commit is proved, and these suites the whole run left red are still
#                              open, comma-joined file names: each is closed by a later green landing of it
#     uncovered<TAB><reason>   anything else, the reason in words: the commit the walk cannot prove and
#                              what it lacks, or the question that could not be answered
#
# (wave-26 T5; REQ-3, D6.) THE ONE PLACE THAT RUNS GIT FOR THE FLOOR'S STATE. The dispatch wall asks
# this and judges nothing itself. <tree> is the project root: its repository holds the working branch,
# and its docs tree holds the plan's landing record.
#
# THE HEAD IS THE WORKING BRANCH'S REF (wave-35 T9; A-orch-45): `proof_branch_head`, never the head of a
# checkout, so the floor reads the same whether the branch is checked out, its checkout is detached or
# the main checkout has moved to another branch; a branch that names no commit is uncovered.
#
# THE FLOOR IS ONE WHOLE RUN PLUS THE GREENS OF WHAT CHANGED (D3; wave-35 T9, D8, ADR-054): one whole run at
# a commit F on the branch, the proof line's head, green or red; each suite red in it closed by a later
# green landing of it; and every commit after F proved by the runs recorded at it, its code covered by
# the suites that declare it. `_proof_floor_judge` is the judge; this reads the head and asks it. Nothing
# predicts a suite set (A-T25-4). UNCOVERED IS THE SAFE DIRECTION: every question this cannot answer —
# no proof yet, no branch, a head git cannot read — answers it.
proof_state() {
  local plan="$1" tree="$2" c wb st
  st="$(proof_floor_absent "$plan")" && { printf 'uncovered\t%s\n' "$st"; return 0; }
  _proof_run_load
  wb="$(plan_working_branch "$plan")"
  [ -n "$wb" ] || { printf 'uncovered\tthe plan names no working-branch\n'; return 0; }
  c="$(proof_branch_head "$plan" "$tree")" \
    || { printf 'uncovered\tthe working branch %s names no commit here\n' "$wb"; return 0; }
  st="$(_proof_floor_judge "$plan" "$tree" "$c")"
  case "$st" in
    covered) printf 'covered\t%s\n' "$c" ;;
    *) printf '%s\n' "$st" ;;
  esac
}

# proof_branch_head <plan> <tree> -> the 40-hex commit the plan's working branch names, read from the
# branch's REF in <tree>'s repository (`refs/heads/<branch>`), exit 0; nothing and exit 1 when the plan names
# no branch (lib/run.sh `plan_working_branch`, the one reader) or the ref names no commit (wave-35 T9;
# A-orch-45). THE JUDGE'S ONE READING OF THE HEAD: proof_state asks it, and `current 7`, `current 8` and
# close-out hand its answer to `facts_state` (row T10), so no caller reads the head of a checkout.
proof_branch_head() {
  local wb
  _proof_run_load
  wb="$(plan_working_branch "${1:-}")"
  [ -n "$wb" ] || return 1
  git -C "${2:-.}" rev-parse --verify -q "refs/heads/${wb}^{commit}" 2>/dev/null
}

# _proof_floor_judge <plan> <tree> <head> -> the floor's state at <head>, one line: `covered`, `owed<TAB><suites>`
# or `uncovered<TAB><reason>` (wave-35 T9; D8, D9, AC-1.3 to AC-1.6). THE JUDGE, which proof_state and facts_state
# both ask. The plan's last `kind=floor` proof names F and the suites its whole run left red (`owed=`); a suite
# the plan carries as inherited debt (`proof_inherited`) is not owed. At F itself the reds decide; past it,
# `_proof_walk` walks F..<head> with the reds and the cover's waiver (`approved: regression-2`). BOTH CALLERS ASK
# `proof_floor_absent` FIRST and answer an absent floor themselves, so the judge never sees a plan with no floor
# line; the call it made here never decided (wave-36 T12; C35). Should one reach it, the empty head is no commit
# and the answer is uncovered, the safe direction.
_proof_floor_judge() {
  local plan="$1" tree="$2" c="$3" h owed inh files rec why rc waive=0
  h="$(proof_last "$plan" floor)"
  h="$(git -C "$tree" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" \
    || { printf 'uncovered\tthe proved head is not a commit here\n'; return 0; }
  c="$(git -C "$tree" rev-parse --verify -q "${c}^{commit}" 2>/dev/null)" \
    || { printf 'uncovered\tthe head %s is not a commit here\n' "$3"; return 0; }
  owed="$(_proof_last_read "$plan" floor owed)"
  inh="$(proof_inherited "$plan")"
  [ -z "$owed" ] || [ -z "$inh" ] || owed="$(PROOF_I=",$inh," awk -F, '{ for (i = 1; i <= NF; i++) if ($i != "" && !index(ENVIRON["PROOF_I"], "," $i ",")) o = o (o == "" ? "" : ",") $i; print o }' <<PROOF_OWED_IN
$owed
PROOF_OWED_IN
)"
  if [ "$h" = "$c" ]; then
    if [ -n "$owed" ]; then printf 'owed\t%s\n' "$owed"; else printf 'covered\n'; fi
    return 0
  fi
  git -C "$tree" merge-base --is-ancestor "$h" "$c" 2>/dev/null \
    || { printf 'uncovered\tthe proved head %.7s is not in the history of %.12s\n' "$h" "$c"; return 0; }
  files="$(git -C "$tree" diff --name-only --no-renames "$h" "$c" 2>/dev/null)" \
    || { printf 'uncovered\tgit cannot list the change since %.7s\n' "$h"; return 0; }
  # NO FILE CHANGED AND NOTHING OWED: the tree is the one the proof read, so it is covered whatever the commits.
  [ -n "$files" ] || [ -n "$owed" ] || { printf 'covered\n'; return 0; }
  _proof_roots_load
  rec="$(proof_debt_record "$plan" "$tree" 2>/dev/null)" || rec=""
  ! proof_approved "$plan" regression-2 || waive=1
  why="$(_proof_walk "$tree" "$h" "$c" "$rec" "$owed" "$waive")"; rc=$?
  case "$rc" in
    0) printf 'covered\n' ;;
    2) printf 'owed\t%s\n' "$why" ;;
    *) printf 'uncovered\t%s\n' "${why:-the commits since the proved head cannot be walked}" ;;
  esac
}

# _proof_run_load -> lib/run.sh sourced beside this file unless its working-branch reader is loaded.
_proof_run_load() {
  declare -F plan_working_branch >/dev/null 2>&1 && return 0
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/run.sh" >/dev/null 2>&1
  return 0
}

# proof_regression <plan> -> `no` when the plan's leading frontmatter says `regression: no`, else `yes`;
# exit 0 (wave-31 T27; REQ-12 AC-12.2; D4). THE REGRESSION IS A STEP-0 SETTING: `session-poker.sh
# regression` writes the key, and at `no` the run owes no floor. AN ABSENT KEY, OR ANY VALUE BUT `no`,
# READS `yes`, fail-closed as an absent `walk:` reads `required`: only the explicit word relaxes
# anything. The key's sibling `regression-override:` records who chose against the scale default; it is
# never read here. One reading for facts_owed below and lib/units.sh's integrate default; the Step-5
# arm (lib/walls.sh validate_tests_block), dispatch preflight and the card read the same key through
# the same function, lib/run.sh `plan_regression` (wave-33 T15), which this only maps to a word.
proof_regression() {
  if ! declare -F plan_regression >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/run.sh" >/dev/null 2>&1
  fi
  if [ "$(plan_regression "${1:-}")" = no ]; then printf 'no\n'; else printf 'yes\n'; fi
}

# facts_owed <rigor> <scale> [<tree>] [<plan>] -> one line per fact a run owes, exit 0; nothing and
# exit 1 when <rigor> is not one PROOF_DEALING knows or <scale> is not task, wave or epic (wave-27
# T9; D2):
#
#     floor                                          the full run, proof_state's question; not
#                                                    dealt when <plan> reads `regression: no`
#                                                    (proof_regression, wave-31 T27; REQ-12 AC-12.2)
#     review<TAB><question><TAB><role><TAB>piece     each question, for the role the rigor deals it
#     review<TAB><question><TAB><role><TAB>whole     at scale: wave, one more per code question (D10)
#     check                                          when <tree>'s .bionic/config.yaml names a
#                                                    release-check: command (wave-27 T16; D12)
#     debt<TAB><suite><TAB><token>                   one per suite and token the run's landing
#                                                    record owes: a `debt:` line `land` wrote
#                                                    that no `void:` line names (T31, T67; D23)
#
# THE ONE DEALING. The judge below reads it, and the dispatch wall (row T15) reads it for the
# questions a reader's brief may name; neither restates the table. The check is the project's, not
# the rigor's: it is owed only when the caller names the project root whose configuration declares
# it, as facts_state does, so the dealing of a rigor alone is the same in every project.
facts_owed() {
  local owed r="" floor=1
  # THE WORD IS READ AS ITS LEVEL (wave-28 T44; wave-30 T11, D1). The dealing is keyed by the level
  # words themselves, so the plan's word is read through lib/run.sh `rigor_level` and a word that is
  # no level deals nothing. A copy of this file read where run.sh is not beside it (a suite's
  # doctored copy) reads the word as written.
  declare -F rigor_level >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/run.sh" >/dev/null 2>&1
  if ! declare -F rigor_level >/dev/null 2>&1; then
    r="${1:-}"
  else
    r="$(rigor_level "${1:-}" 2>/dev/null)" || r=""
  fi
  [ -z "${4:-}" ] || [ "$(proof_regression "$4")" != no ] || floor=0
  owed="$(PROOF_D="$PROOF_DEALING" PROOF_Q="$PROOF_QUESTIONS" PROOF_C="$PROOF_CODE_QUESTIONS" awk -v r="$r" -v s="${2:-}" -v floor="$floor" '
    BEGIN {
      if (s != "task" && s != "wave" && s != "epic") exit 1
      n = split(ENVIRON["PROOF_D"], d, " ")
      for (i = 1; i <= n; i++) if (r != "" && index(d[i], r "=") == 1) roles = substr(d[i], length(r) + 2)
      if (roles == "") exit 1
      m = split(ENVIRON["PROOF_Q"], q, " "); split(roles, role, ",")
      if (floor == 1) print "floor"
      for (i = 1; i <= m; i++) print "review\t" q[i] "\t" role[i] "\tpiece"
      if (s == "wave")
        for (i = 1; i <= m; i++) if (index(" " ENVIRON["PROOF_C"] " ", " " q[i] " ")) print "review\t" q[i] "\t" role[i] "\twhole"
    }')" || return 1
  printf '%s\n' "$owed"
  [ -n "${3:-}" ] || return 0
  _proof_roots_load
  [ -z "$(config_value "$3" release-check "" 2>/dev/null)" ] || printf 'check\n'
  [ -z "${4:-}" ] || proof_debts "$4" "$3"
  return 0
}

# proof_debts <plan> [<tree>] -> `debt<TAB><suite><TAB><token>` once per suite and token the run's
# landing record owes, in the order the record first names them (wave-27 T31, T67; D23 as amended,
# A-orch-120). A DEBT IS OWED BECAUSE `land` WROTE IT: the record's `debt:` lines (lib/worktree.sh
# `_wt_debt_write`, before the merge) that no `void:` line names. A `landed red:` line in the plan is
# not read: missing, misshapen or hand-edited, it changes nothing. <tree> is the plan's checkout
# root, read from the plan's directory when not given.
proof_debts() {
  local rec
  rec="$(proof_debt_record "${1:-}" "${2:-}")" || return 0
  proof_debts_read "$rec" | awk -F'\t' '{ print "debt\t" $1 "\t" $2 }'
}

# proof_debt_record <plan> [<tree>] -> `<docs-root>/record/<the plan's name less .plan.md>/
# landing-proofs.log`, the record `land` writes for that plan (lib/worktree.sh `_wt_proofs_path`, the
# same rule: this file does not load worktree.sh). rc 1 when no path can be named.
proof_debt_record() {
  local plan="${1:-}" tree="${2:-}" slug
  [ -f "$plan" ] || return 1
  slug="${plan##*/}"; slug="${slug%.plan.md}"
  [ -n "$slug" ] || return 1
  [ -n "$tree" ] || tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$tree" ] || return 1
  _proof_roots_load
  declare -F docs_root >/dev/null 2>&1 || return 1
  printf '%s/record/%s/landing-proofs.log' "$(docs_root "$tree")" "$slug"
}

# proof_debt_origin <sid> <marker> <bound plan> -> the plan whose landing record holds the debts a
# commit bound to <bound plan> owes (wave-27 T76; review pass 60 P0-1; A-orch-170, A-orch-171). A
# plan verb proves its change by a dry commit of a COPY, `<plan>.<verb>-dry.<pid>`, under a session
# `planverb-<pid>` whose marker it writes with `dry_of=<plan>` beside `plan=<copy>` (hooks/
# session-poker.sh `plan_verb_dry`); the copy's own name names no record, so the dry commit reads the
# record of the plan it was made from. The field is honoured only when all three hold: the session
# is a plan verb's (`planverb-<pid>`), the marker says `dry_of=`, and the bound file is named
# `<dry_of>.<verb>-dry.<pid>`, the same pid.
# A real session bound to a real plan names no such file, so it reads exactly its own plan's record,
# whatever a marker line says. No fork: the marker is two or three lines, read here.
proof_debt_origin() {
  local sid="${1:-}" marker="${2:-}" plan="${3:-}" line from="" verb pid=""
  case "$sid" in planverb-*) pid="${sid#planverb-}" ;; esac
  case "$pid" in ''|*[!0-9]*) printf '%s' "$plan"; return 0 ;; esac
  if [ -f "$marker" ] && [ ! -L "$marker" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in dry_of=?*) from="${line#dry_of=}"; break ;; esac
    done < "$marker"
  fi
  verb=""
  case "$from" in ?*) case "$plan" in "$from".?*-dry."$pid") verb="${plan#"$from".}"; verb="${verb%-dry."$pid"}" ;; esac ;; esac
  case "$verb" in
    ''|*[!a-z-]*) printf '%s' "$plan" ;;
    *) printf '%s' "$from" ;;
  esac
}

# proof_debts_read <record> -> `<suite><TAB><token><TAB><time>` once per suite and token with a
# `debt:` line no `void:` line names, the time the NEWEST of those lines' `at=` (wave-27 T67; review
# pass 46 B2): each red landing is a debt of its own, and two on one suite and token are both covered
# only by a green run after the later one. A line whose `at=` is no <ISO-UTC> leaves the time empty,
# and an empty time is never covered.
proof_debts_read() {
  [ -f "${1:-}" ] || return 0
  awk '
    function fld(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    $1 == "void:" { v = fld("id"); if (v != "") voided[v] = 1; next }
    $1 == "debt:" { n++; id[n] = fld("id"); su[n] = fld("suite"); tk[n] = fld("token"); at[n] = fld("at") }
    END {
      iso = "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$"
      for (i = 1; i <= n; i++) {
        if (id[i] == "" || (id[i] in voided) || su[i] == "" || tk[i] == "") continue
        k = su[i] "\t" tk[i]
        if (!(k in when)) { when[k] = ""; ord[++no] = k }
        if (at[i] !~ iso) bad[k] = 1
        else if (at[i] > when[k]) when[k] = at[i]
      }
      for (j = 1; j <= no; j++) print ord[j] "\t" ((ord[j] in bad) ? "" : when[ord[j]])
    }' "$1" 2>/dev/null
}

# proof_debts_open <debts> < <section text> -> `debt<TAB><suite><TAB><token>` for each of <debts>
# (`proof_debts_read`'s lines, `<suite><TAB><token><TAB><time>`, what `land` wrote) that the `## SDLC
# State` text on stdin leaves open (wave-27 T31, T67; D23; A-orch-85, A-orch-121). This is the commit
# gate's predicate (lib/walls.sh `_eg_reading_gaps`), over two facts it is handed: the debts its
# collector read from the landing record (hooks/bash-walls.sh) and the plan text; a `landed red:`
# line in that text is not read. A debt stays open until a `proved: kind=floor` or `kind=task` line
# carries an `at=` STRICTLY later than its threshold: the red landing's own time, and for an
# `approval:<name>` debt the later of that and the first `approved: <name> by <who> <ISO-UTC> …`
# line, with none of which it stays open. A debt with no time is never cleared. Whether an `ext:`
# slug is still in a `## Tasks` cell, and whether a task log shows the suite green, is the judge's
# to read (`_facts_debt`), not this text's.
proof_debts_open() {
  PROOF_DEBTS="${1:-}" awk '
    BEGIN {
      iso = "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$"
      nd = split(ENVIRON["PROOF_DEBTS"], D, "\n")
    }
    /^approved:[ \t]/ {
      m = split($0, w, /[ \t]+/)
      if (m >= 3 && w[3] == "by" && !(w[2] in ap)) for (i = 4; i <= m; i++) if (w[i] ~ iso) { ap[w[2]] = w[i]; break }
      next
    }
    /^proved:[ \t]/ {
      m = split($0, w, /[ \t]+/); k = ""; at = ""
      for (i = 2; i <= m; i++) { if (w[i] ~ /^kind=/) k = substr(w[i], 6); else if (w[i] ~ /^at=/) at = substr(w[i], 4) }
      if ((k == "floor" || k == "task") && at ~ iso && at > latest) latest = at
    }
    END {
      for (i = 1; i <= nd; i++) {
        if (split(D[i], f, "\t") < 2 || f[1] == "" || f[2] == "") continue
        t = f[2]; c = (f[3] ~ iso ? f[3] : "")
        if (c != "" && t ~ /^approval:./) { n = substr(t, 10); c = (n in ap) ? (ap[n] > c ? ap[n] : c) : "" }
        else if (c != "" && t !~ /^ext:./) c = ""
        if (c != "" && latest > c) continue
        print "debt\t" f[1] "\t" t
      }
    }'
}

# facts_state <plan> <head> -> one line per fact `facts_owed` deals the plan's frontmatter rigor and
# scale, in its order: the owed line, a tab, its state. Exit 0 only when every line is covered, 1
# otherwise, 2 (nothing printed, one sentence on stderr) when the plan cannot be dealt, or its <head>
# or its base is no commit (wave-27 T9; D2; T45):
#
#     covered                  the fact holds at <head>
#     uncovered<TAB><a>..<b>   code landed past <a>, the last head the fact reached, to <b> = <head>; the
#                              regression adds a tab and the reason: the first commit past its proof that the
#                              walk cannot prove, and what it lacks (wave-35 T9)
#     owed<TAB><suites>        the regression only: a suite its whole run left red has no later green landing
#                              yet, comma-joined file names (wave-35 T9; D8, AC-1.3)
#     failing<TAB><evidence>   the question's newest fact is result=fail, and no waiver is newer
#     absent                   no fact of that kind, and no waiver
#
# THE DECLARED CHECK (wave-27 T16; D12) is owed when the plan's repository declares `release-check:`
# (facts_owed's <tree> is the plan's checkout root). The LAST `kind=check` line at <head> decides it:
# covered, or failing with that line's evidence when it carries `result=fail`, the line a failed run
# writes (T31; review pass 22 S3), so a later failure at one head is never hidden by an earlier pass.
# With no line at <head>, uncovered from the newest one's head, and absent with none. It is a command
# run at a head, so a docs-only tail does not carry it.
# A DECLARED DEBT (wave-27 T31, T67; D23 as amended), one per suite and token the run's landing record
# owes (`proof_debts`: what `land` wrote, never a plan line), is covered by a green run of that suite,
# or a regression proof, dated after the red landing and after the token cleared, and absent otherwise
# (`_facts_debt`); so `current 8`, close-out and the tick's integrate row, which all ask this judge,
# refuse while a debt is open.
#
# A QUESTION IS ONE CHAIN (D4). Its links are its readings (`proved: kind=review … question=<q>`,
# either scope) and its waivers (`waived: question=<q> head=<sha> …`), in section order, which is the
# order they were written (`proof_add_line`). `proof_attested` held each reading, when the verb wrote
# it, to start at or before its question's last head, and a question's first reading at or before
# the plan's base, refusing it on a plan with no base (wave-27 T45; review pass 13 F1, F9). So the
# judge, too, judges only a plan whose base-sha: is a commit: with none, the start of no chain can be
# held, and it exits 2, for every dealing owes a reading. <head> must resolve to a commit, or it exits
# 2, and each line's head is compared with the commit it resolves to, never as a string (F10). The
# chain holds at <head> when its newest link is no failing reading and that link's head is
# <head>, or every commit past it holds by the one cover rule (wave-36 T7; D9, D2; the COVER block below
# `_proof_docs_path`): its paths are all prose (the docs root, or the files `_proof_docs_path` lists; wave-30
# T6, D12), or it is the landing of a row born of this question's reading (wave-36 T31; D16) or of the floor's
# red. Any other commit owes, whatever its row was declared to be; `facts_cover` prints each commit's basis. A waiver covers its
# question up to its own head.
# Every line of the question counts, failing ones included: a later reading may start at a failing
# reading's head, so the chain is not rebuilt by skipping them, and only the newest decides failing.
# THE WHOLE READ (D10), owed once per code question at wave scale, needs a `scope=whole` reading, or a
# waiver newer than the newest such reading: absent with neither, failing when that newest whole reading
# fails. Past that, it reaches as far as its question's chain does (wave-36 T7; D9, D3): covered when the
# chain holds at <head>, failing or uncovered as the chain is. No whole reading covers whatever its head,
# so a whole read registered while code is still landing covers that code only once a later reading of
# the question, or the cover rule, carries the chain to <head>. A proof line carries no range start, so
# what a whole reading read is the verb's to hold: it refuses one whose range starts after the plan's
# base-sha (row T41), and the judge takes the line as written.
# THE REGRESSION is the floor judge's answer at <head> (`_proof_floor_judge`, proof_state's judge; wave-31 T25,
# D3; wave-35 T9, D8): covered; owed with the reds of its whole run still open; or uncovered from its proof's
# head to <head>, with the reason that names the first commit past it no recorded run proves. With no
# regression proof it is absent. <head> is the caller's, read from the working branch's ref
# (`proof_branch_head`), never a checkout's (A-orch-45).
# An owed line this judge has no rule for answers absent (the safe direction).
# A FINDING RE-RATED BY A MOVE (wave-28 T42; D34): a reading's result is the one its findings give at
# their effective ratings (`_proof_reading_result`). No check holds the step: a reader's rating is
# final (wave-31 T32; D6), and a `check:` line an older plan carries is not read.
# IT READS GIT, so a verb, the tick and close-out call it, never a wall: a wall is handed its answer
# (the freeze, .claude/rules/hook-authoring.md).
facts_state() {
  local plan="${1:-}" head="${2:-}" d rigor scale owed tree droot="" pfx chains fact kind q role scope st rc=0
  local x pt pr ph pe wt wr we wh fixed="" born="" walked="|"
  [ -f "$plan" ] || { printf 'facts_state: %s is not a plan file\n' "$plan" >&2; return 2; }
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  if ! declare -F plan_frontmatter_get >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$d/run.sh" >/dev/null 2>&1
  fi
  # THE DOCS ROOT IS PROSE TO THE WALK (wave-36 T31; A-T28-9): the judge loads lib/roots.sh itself, as facts_cover
  # does, so no caller needs a load of its own for `docs_root`.
  _proof_roots_load
  rigor="$(plan_frontmatter_get "$plan" rigor 2>/dev/null)"
  scale="$(plan_frontmatter_get "$plan" scale 2>/dev/null)"
  tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  owed="$(facts_owed "$rigor" "$scale" "$tree" "$plan")" || {
    printf 'facts_state: %s declares no rigor and scale the dealing knows (rigor: %s, scale: %s)\n' \
      "$plan" "${rigor:-none}" "${scale:-none}" >&2
    return 2
  }
  # THE HEAD AND THE BASE ARE COMMITS (wave-27 T45; review pass 13 F1, F10), or nothing is judged.
  x=""; [ -n "$tree" ] && [ -n "$head" ] && x="$(git -C "$tree" rev-parse --verify -q "$head^{commit}" 2>/dev/null)"
  [ -n "$x" ] || { printf 'facts_state: the head %s is no commit here\n' "${head:-(none)}" >&2; return 2; }
  head="$x"
  case "$owed" in
    review"	"*|*"
review	"*)
      x="$(proof_plan_base "$plan" "$tree")"
      if ! proof_base_id "$x" || ! git -C "$tree" rev-parse --verify -q "$x^{commit}" >/dev/null 2>&1; then
        printf 'facts_state: %s names no base-sha: that is a commit here%s, so where its chains start cannot be held\n' "$plan" \
          "$(if [ -n "$x" ] && ! proof_base_id "$x"; then printf ' (its base-sha: %s is not a commit id)' "$x"
             elif [ -n "$x" ]; then printf ' (its base-sha: %s is no commit here)' "$x"; fi)" >&2
        return 2
      fi ;;
  esac
  pfx="$(_facts_docs_prefix "$tree")"
  [ -z "$tree" ] || ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$tree" 2>/dev/null)"
  chains="$(awk -v qs="$PROOF_QUESTIONS" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      q = PROOF_QUESTION; pt[q] = "fact"; pr[q] = PROOF_RESULT; ph[q] = PROOF_HEAD; pe[q] = PROOF_EVIDENCE
      if (PROOF_SCOPE == "whole") { wt[q] = "fact"; wr[q] = PROOF_RESULT; we[q] = pe[q]; wh[q] = PROOF_HEAD }
      next
    }
    /^waived:[ \t]/ {
      m = split($0, w, /[ \t]+/); q = ""; h = ""
      for (i = 2; i <= m && w[i] != "by"; i++) {
        if (w[i] ~ /^question=/) q = substr(w[i], 10)
        else if (w[i] ~ /^head=/) h = substr(w[i], 6)
      }
      if (q == "" || h !~ /^[0-9a-f]+$/ || length(h) < 7 || length(h) > 40) next
      pt[q] = "waiver"; pr[q] = ""; ph[q] = h; pe[q] = ""; wt[q] = "waiver"; wr[q] = ""; we[q] = ""; wh[q] = h
    }
    END {
      n = split(qs, Q, " ")
      for (i = 1; i <= n; i++) { q = Q[i]; printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n", q, pt[q], pr[q], ph[q], pe[q], wt[q], wr[q], we[q], wh[q] }
    }' "$plan")"
  # THE FIXED FINDINGS, read once (wave-33 T13; REQ-5 AC-5.2, D6): the readings below derive without them.
  # THE BORN LANDINGS, read once (wave-36 T7; D9): the commits the walk holds as a born row's landing, the fixed
  # findings' green landings among them.
  case "$owed" in review"	"*|*"
review	"*) fixed="$(proof_fixed "$plan" "$tree")"; born="$(_facts_born_landings "$plan" "$tree" "$fixed")" ;; esac
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    case "$fact" in
      floor)
        # THE FLOOR AT <head> (wave-35 T9; D8, AC-1.3; A-orch-45): the judge itself, at the head handed in, never
        # a checkout's: owed while a red of the whole run is open, uncovered F..<head> with the reason only for
        # a commit it cannot prove.
        if proof_floor_absent "$plan" >/dev/null; then st=absent
        else
          x="$(proof_last "$plan" floor)"
          st="$(_proof_floor_judge "$plan" "$tree" "$head" 2>/dev/null | awk 'NR == 1')"
          case "$st" in
            covered|owed"	"?*) : ;;
            uncovered"	"?*) st="uncovered	$x..$head	${st#uncovered	}" ;;
            *) st="uncovered	$x..$head" ;;
          esac
        fi ;;
      review"	"*)
        IFS='	' read -r kind q role scope <<PROOF_OWED
$fact
PROOF_OWED
        x="$(printf '%s\n' "$chains" | awk -F'|' -v q="$q" '$1 == q')"
        IFS='|' read -r x pt pr ph pe wt wr we wh <<PROOF_CHAIN
$x
PROOF_CHAIN
        # THE RESULT IS THE ONE ITS FINDINGS GIVE AT THEIR EFFECTIVE RATINGS (wave-28 T41; D33): a
        # reading a check re-rated is derived again from its record, not read off its proof line.
        # A FINDING A BORN ROW FIXED IS SETTLED (wave-33 T13; D6): it drops out of the derivation, so a question
        # whose every finding to fix is fixed is no longer failing, with no waiver; one open finding to fix keeps
        # the reading failing. The commit that landed the fix is a born landing on the walk (wave-36 T7).
        if [ "$wt" = fact ]; then _proof_reading_result_var "$plan" "$droot" "$we" "$wr" "$wh" "$tree" "$fixed"; wr="$PROOF_DERIVED"; fi
        if [ "$pt" = fact ]; then _proof_reading_result_var "$plan" "$droot" "$pe" "$pr" "$ph" "$tree" "$fixed"; pr="$PROOF_DERIVED"; fi
        # THE QUESTION'S CHAIN: its newest link, whole or piece, covered to its head and extended by the walk
        # (wave-36 T7; D9), on which a review-born landing holds only when this question's reading bore it (wave-36
        # T31; D16). One walk per question and head, however many lines of the question ask it.
        if [ -z "$pt" ]; then st=absent
        elif [ "$pt" = fact ] && [ "$pr" = fail ]; then st="failing	$pe"
        else
          case "$walked" in
            *"|$q@$ph=0|"*) st=covered ;;
            *"|$q@$ph=1|"*) st="uncovered	$ph..$head" ;;
            *) if _facts_holds "$tree" "$pfx" "$ph" "$head" "$born" "$q"; then st=covered; walked="$walked$q@$ph=0|"
               else st="uncovered	$ph..$head"; walked="$walked$q@$ph=1|"; fi ;;
          esac
        fi
        # THE WHOLE LINE NEEDS A WHOLE READING, AND REACHES AS FAR AS ITS QUESTION'S CHAIN (wave-36 T7; D9, D3): the
        # whole read was taken, its newest is no failing one, and the chain it heads, or a later piece reading
        # heads, holds at <head>. No whole reading covers whatever its head.
        if [ "$scope" = whole ]; then
          if [ -z "$wt" ]; then st=absent
          elif [ "$wt" = fact ] && [ "$wr" = fail ]; then st="failing	$we"
          fi
        fi ;;
      check)
        x=""; [ -z "$tree" ] || x="$(git -C "$tree" rev-parse --verify -q "$head^{commit}" 2>/dev/null)"
        x="$(awk -v h="$head" -v hh="${x:-$head}" "$(proof_awk)"'
                /^[[:space:]]*```/ { fence = !fence; next }
          fence { next }
          /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
          insdlc && proof_fields($0) && PROOF_KIND == "check" {
            last = PROOF_HEAD
            if (last == h || last == hh) { at = 1; fail = (PROOF_RESULT == "fail"); ev = PROOF_EVIDENCE }
          }
          END { if (at && fail) print "failing\t" ev; else if (at) print "covered"; else print last }' "$plan")"
        case "$x" in
          covered) st=covered ;;
          failing"	"*) st="$x" ;;
          '') st=absent ;;
          *) st="uncovered	$x..$head" ;;
        esac ;;
      debt"	"*)
        IFS='	' read -r kind q x <<PROOF_DEBT
$fact
PROOF_DEBT
        st="$(_facts_debt "$plan" "$tree" "$q" "$x")" ;;
      *) st=absent ;;
    esac
    printf '%s\t%s\n' "$fact" "$st"
    [ "$st" = covered ] || rc=1
  done <<PROOF_FACTS
$owed
PROOF_FACTS
  return "$rc"
}

# _facts_debt <plan> <tree> <suite> <token> -> `covered`, or `absent` with any reason after a tab, for
# one declared debt (wave-27 T31, T67; D23; A-orch-85, A-orch-120). Covered only when a regression proof, or
# a task proof whose log shows <suite> green, carries an `at=` STRICTLY later than the debt's
# threshold, which is never earlier than the red landing (the newest debt line's `at=` in the
# landing record, `proof_debts_read`):
#   - no debt line of <suite> and <token> carries an <ISO-UTC> `at=`: never covered, and it says so;
#   - `approval:<name>`: the later of the red landing and the time on the first `approved: <name> by
#     <who> <ISO-UTC> …` line of the plan's `## SDLC State`; until that line is written, absent;
#   - `ext:<slug>`: absent while any `## Tasks` cell still names `ext:<slug>` (the owner removing it
#     is the statement that the blocker cleared); then the red landing's own time. Nothing dates a
#     clearing, so the green run is held to be later than the red landing, not later than the
#     clearing;
#   - any other token: absent.
# A log shows <suite> green by the runner's `<suite> … PASS` line or the suite's own
# `<suite>: <n>/<n> passed, 0 failed` tally.
_facts_debt() {
  local plan="$1" tree="$2" suite="$3" tok="$4" clear landed droot ev x
  x="$(proof_debt_record "$plan" "$tree")" || x=""
  landed="$(proof_debts_read "$x" | awk -F'\t' -v s="$suite" -v t="$tok" '$1 == s && $2 == t { print $3; exit }')"
  if [ -z "$landed" ]; then
    printf 'absent\tits debt line in the landing record carries no at=<ISO-UTC>, so no green run can be dated after the red landing'
    return 0
  fi
  case "$tok" in
    approval:?*)
      clear="$(awk -v n="${tok#approval:}" '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
        insdlc && /^approved:[ \t]/ {
          m = split($0, w, /[ \t]+/)
          if (m < 3 || w[2] != n || w[3] != "by") next
          for (i = 4; i <= m; i++) if (w[i] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) { print w[i]; exit }
        }' "$plan")"
      # The later of the approval and the red landing (wave-27 T67; review pass 46 B1).
      if [ -n "$clear" ] && [[ "$landed" > "$clear" ]]; then clear="$landed"; fi ;;
    ext:?*)
      x="$(awk -v want="$tok" '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^##[[:space:]]/ { intasks = ($0 ~ /^##[[:space:]]+Tasks[[:space:]]*$/); next }
        # THE SLUG AS A WHOLE TOKEN, whatever stands around it (wave-27 T67; review pass 46 N5): no
        # slug character before it, and none after it but a `.` that ends the slug (a full stop).
        intasks && /^[[:space:]]*\|/ {
          l = $0
          while ((p = index(l, want)) > 0) {
            pre = (p > 1 ? substr(l, p - 1, 1) : ""); r = substr(l, p + length(want))
            nx = substr(r, 1, 1)
            if (pre !~ /[A-Za-z0-9._:-]/ && nx !~ /[A-Za-z0-9_-]/ && !(nx == "." && substr(r, 2, 1) ~ /[A-Za-z0-9._-]/)) { print "held"; exit }
            l = substr(l, p + 1)
          }
        }' "$plan")"
      if [ -n "$x" ]; then clear=""; else clear="$landed"; fi ;;
    *) clear="" ;;
  esac
  [ -n "$clear" ] || { printf 'absent'; return 0; }
  droot=""; [ -z "$tree" ] || ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$tree" 2>/dev/null)"
  while IFS='	' read -r x ev; do
    case "$x" in
      floor) printf 'covered'; return 0 ;;
      task)
        case "$ev" in /*) : ;; *) [ -n "$droot" ] || continue; ev="$droot/$ev" ;; esac
        [ -f "$ev" ] || continue
        if awk -v s="$suite" '
          $1 == s && $NF == "PASS" { ok = 1; exit }
          $1 == s ":" && $4 == "0" && $5 == "failed" { split($2, c, "/"); if (c[1] == c[2] && c[1] + 0 > 0) { ok = 1; exit } }
          END { exit !ok }' "$ev" 2>/dev/null; then
          printf 'covered'; return 0
        fi ;;
    esac
  done <<PROOF_LATER
$(awk -v t="$clear" "$(proof_awk)"'
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
  insdlc && proof_fields($0) && (PROOF_KIND == "floor" || PROOF_KIND == "task") {
    m = split($0, f, /[ \t]+/); at = ""
    for (i = 2; i <= m; i++) if (f[i] ~ /^at=/) at = substr(f[i], 4)
    if (at > t) print PROOF_KIND "\t" PROOF_EVIDENCE
  }' "$plan")
PROOF_LATER
  printf 'absent'
}

# _proof_docs_path <path> -> 0 when <path> (relative to the repository root) is a documentation file
# whose landing owes no reading (wave-30 T6; design-ledger Δ12, D12; A-orch-309): CHANGELOG.md,
# README.md, CLAUDE.md, anything under .bionic/, anything under .claude/rules/ and the runner's timing table
# tests/timing.tsv (wave-35 T9; AC-1.5: the floor's walk reads the same list, so a commit of these alone
# inherits its parent's standing there too). THIS CASE IS THE ONE LIST. It is never skills/ or agents/ prose, which agents execute, and never a payload/ file; a
# README or CHANGELOG deeper than the root is not in it either. Nothing else under tests/ is in it: tests/run.sh
# and tests/lib/ are code the suites execute (wave-36 T7; AC-3.5), so a commit of them owes a reading.
_proof_docs_path() {
  case "$1" in
    CHANGELOG.md|README.md|CLAUDE.md|.bionic/*|.claude/rules/*|tests/timing.tsv) return 0 ;;
  esac
  return 1
}

# ---------- COVER: HOW FAR A READING REACHES PAST ITS HEAD (wave-36 T7; REQ-3 AC-3.2, AC-3.3, AC-3.5; D9, D2, D3) ----------
#
# A reading is covered to its head. A later commit on the head's first-parent line extends it when it holds, and
# each commit's basis is one of four words:
#   prose        every path it touched (a merge as what it brought in, a rename as both its paths) is under the docs
#                root or on `_proof_docs_path`'s list; a commit that touches nothing is prose too
#   born-review  the landing record names it as the landing of a row whose `- T<n>:` line carries ` born: review …
#                of=<record>#<n>`, or `proof_fixed` names it as a fix row's green landing, AND the asked question's
#                reading bore the row: one of those records is the evidence of a registered reading of that question
#                (wave-36 T31; D16). On every other question's chain the same commit reads `owes`.
#   born-floor   the landing record names it as the landing of a row whose `- T<n>:` line carries ` born: floor …`
#   owes         anything else, whatever kind its row declared (a doc row that touched payload/ owes)
# Content is asked first, so a born row's docs-only landing reads prose. `facts_cover` prints the basis, the walk
# below decides it, and `facts_state` asks the same walk, so the line and the verdict never disagree.

# _facts_docs_prefix <tree> -> the docs root as a path relative to <tree> with a trailing `/`, or nothing when it is
# not under <tree> (or roots.sh is not loaded): the prefix the walk reads as prose.
_facts_docs_prefix() {
  local tree="${1:-}" droot p
  [ -n "$tree" ] && declare -F docs_root >/dev/null 2>&1 || return 0
  droot="$(docs_root "$tree" 2>/dev/null)"
  case "$droot" in "$tree"/?*) p="${droot#"$tree"/}"; printf '%s/' "${p%/}" ;; esac
}

# _facts_born_landings <plan> <tree> [<proof_fixed lines>] -> `<commit>\t<review|floor>\t<questions>`, one line per
# commit the walk holds as a born row's landing: each `ev=published|row=<T>|commit=<c>` event (lib/line.sh) and each
# `landed: row=<T> … merge=<c>` line (lib/worktree.sh) of the run's landing record (`proof_debt_record`) whose row's
# `- <T>:` line carries a born marker (lib/units.sh `units_born_marks`), and each commit `proof_fixed` names,
# review-born. A plan with no marker and no fixed finding pays one grep.
# THE ASKERS (wave-36 T31; D16, ADR-056 "a row born of that reading"): <questions> names, space-separated, the
# questions whose chains a review-born landing holds on, and is empty for a floor-born one, which holds on every
# chain. A marker's `of=<record>#<n>` (lib/units.sh `units_born_findings`) and a fixed finding's `<record>#<n>` name
# a record; the registered review readings of `## SDLC State` whose evidence is that record name its question. A
# marker naming findings of several readings holds on each of their questions; a rating-form marker, or a record no
# registered reading names, gives no question, so that landing owes on every chain.
_facts_born_landings() {
  local plan="$1" tree="$2" fixed="${3:-}" marks="" finds="" asks="" rec="" want
  if /usr/bin/grep -qE ' born: (review|floor) ' "$plan" 2>/dev/null && _proof_units_load \
    && declare -F units_born_marks >/dev/null 2>&1; then
    marks="$(units_born_marks "$plan" 2>/dev/null)"
    if [ -n "$marks" ]; then
      rec="$(proof_debt_record "$plan" "$tree")" && [ -f "$rec" ] || rec=""
    fi
  fi
  [ -n "$fixed" ] || [ -n "$rec" ] || return 0
  # A fixed finding or a review mark needs the askers; a `case` on the string, never a pipe into a quitting grep (§BP).
  want="$fixed"; case "$marks" in *"	review	"*) want=1 ;; esac
  if [ -n "$want" ]; then
    ! declare -F units_born_findings >/dev/null 2>&1 || finds="$(units_born_findings "$plan" 2>/dev/null)"
    asks="$(awk "$(proof_awk)"'
      /^[[:space:]]*```/ { fence = !fence; next }
      fence { next }
      /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
      insdlc && proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" {
        print PROOF_EVIDENCE "\t" PROOF_QUESTION
      }' "$plan" 2>/dev/null)"
  fi
  { printf '\034asks\n%s\n\034fixed\n%s\n\034marks\n%s\n\034finds\n%s\n\034rec\n' "$asks" "$fixed" "$marks" "$finds"
    [ -z "$rec" ] || cat "$rec" 2>/dev/null; } | awk -F'|' '
    function fv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    function rec_of(id) { return match(id, /#[0-9]+$/) ? substr(id, 1, RSTART - 1) : "" }
    function addq(cur, qs,   n, a, i) {
      n = split(qs, a, " ")
      for (i = 1; i <= n; i++) if (index(" " cur " ", " " a[i] " ") == 0) cur = cur (cur == "" ? "" : " ") a[i]
      return cur
    }
    function says(r) { return kind[r] == "review" ? rowq[r] : "" }
    $0 == SUBSEP "asks" { part = 1; next }
    $0 == SUBSEP "fixed" { part = 2; next }
    $0 == SUBSEP "marks" { part = 3; next }
    $0 == SUBSEP "finds" { part = 4; next }
    $0 == SUBSEP "rec" { part = 5; next }
    $0 == "" && part < 5 { next }
    part == 1 { split($0, a, "\t"); recq[a[1]] = addq(recq[a[1]], a[2]); next }
    part == 2 { split($0, x, "\t"); if (x[3] != "") print x[3] "\treview\t" recq[rec_of(x[1])]; next }
    part == 3 { split($0, m, "\t"); if (m[1] != "") kind[m[1]] = m[2]; next }
    part == 4 { split($0, f, "\t"); if (f[1] != "") rowq[f[1]] = addq(rowq[f[1]], recq[rec_of(f[3])]); next }
    part == 5 && substr($0, 1, 8) == "line/v1|" && fv("ev") == "published" {
      r = fv("row"); c = fv("commit"); if ((r in kind) && c != "") print c "\t" kind[r] "\t" says(r); next
    }
    part == 5 && substr($0, 1, 8) == "landed: " {
      r = ""; c = ""; n = split($0, w, " ")
      for (i = 2; i <= n; i++) { if (index(w[i], "row=") == 1) r = substr(w[i], 5); else if (index(w[i], "merge=") == 1) c = substr(w[i], 7) }
      if ((r in kind) && c != "") print c "\t" kind[r] "\t" says(r)
    }'
}

# _facts_basis <commit> <prose: 0 or not> <born landings> [<question>] -> prints `cover <commit> <basis>`; 1 when it
# owes. A born landing names its commit in full or by a prefix of at least seven hex digits. A floor-born landing holds
# on every chain; a review-born one only on the chain of a question it names (wave-36 T31; D16), so with no question
# asked it owes.
_facts_basis() {
  local c="$1" b=owes k w qs
  if [ "$2" != 0 ]; then b=prose
  elif [ -n "${3:-}" ]; then
    while IFS='	' read -r k w qs; do
      [ "${#k}" -ge 7 ] && [ "${c#"$k"}" != "$c" ] || continue
      case "$w" in
        floor) b=born-floor; break ;;
        review) [ -n "${4:-}" ] || continue
                case " $qs " in *" $4 "*) b=born-review; break ;; esac ;;
      esac
    done <<PROOF_BORN
$3
PROOF_BORN
  fi
  printf 'cover %s %s\n' "$c" "$b"
  [ "$b" != owes ]
}

# _facts_walk <tree> <docs prefix> <last head> <head> [<born landings>] [<question>] -> one `_facts_basis` line per
# commit past <last head> on <head>'s first-parent line, oldest first, on <question>'s chain; 0 when none owes. Nothing printed and 0 when <head> is
# <last head>; nothing printed and 1 when <last head> is not on <head>'s history, or git cannot answer: uncovered is
# the safe direction. Both heads are compared as the commits they resolve to, never as strings (T45; review pass 13 F10).
_facts_walk() {
  local tree="$1" pfx="$2" born="${5:-}" q="${6:-}" lh hh files f c="" prose=1 rc=0
  [ -n "$tree" ] || return 1
  lh="$(git -C "$tree" rev-parse --verify -q "$3^{commit}" 2>/dev/null)" || return 1
  hh="$(git -C "$tree" rev-parse --verify -q "$4^{commit}" 2>/dev/null)" || return 1
  [ "$lh" != "$hh" ] || return 0
  git -C "$tree" merge-base --is-ancestor "$lh" "$hh" 2>/dev/null || return 1
  files="$(git -C "$tree" log --reverse --first-parent -m --no-renames --name-only --format='%x01%H' "$lh..$hh" 2>/dev/null)" || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      $'\001'*) [ -z "$c" ] || _facts_basis "$c" "$prose" "$born" "$q" || rc=1; c="${f#?}"; prose=1; continue ;;
    esac
    [ "$prose" = 1 ] || continue
    [ "${f#"$pfx"}" != "$f" ] || _proof_docs_path "$f" || prose=0
  done <<PROOF_DOCS_FILES
$files
PROOF_DOCS_FILES
  [ -z "$c" ] || _facts_basis "$c" "$prose" "$born" "$q" || rc=1
  return "$rc"
}

# _facts_holds <tree> <docs prefix> <last head> <head> [<born landings>] [<question>] -> `_facts_walk`'s answer, its
# lines unprinted.
_facts_holds() {
  _facts_walk "$@" >/dev/null
}

# facts_cover <plan> <from> <to> [<question>] -> THE JUDGE'S BASIS (AC-3.3): one `cover <sha> prose|born-review|
# born-floor|owes` line per commit on <to>'s first-parent line past <from>, oldest first, the walk `facts_state` holds
# <question>'s reading by. A landing born of a reading of another question owes on this chain (wave-36 T31; D16), and
# with no question named it owes on every chain. rc 0 when no commit owes; 1 when one does, or when <from> is not on
# <to>'s history (nothing printed); 2, one sentence on stderr, when the plan or either head cannot be read. A reader
# that prints `review <question> … uncovered <a>..<b>` from facts_state asks `facts_cover <plan> <a> <b> <question>`
# for the commit that owes.
facts_cover() {
  local plan="${1:-}" tree x fixed
  [ -f "$plan" ] || { printf 'facts_cover: %s is not a plan file\n' "$plan" >&2; return 2; }
  tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  for x in "${2:-}" "${3:-}"; do
    [ -n "$tree" ] && [ -n "$x" ] && git -C "$tree" rev-parse --verify -q "$x^{commit}" >/dev/null 2>&1 \
      || { printf 'facts_cover: %s is no commit here\n' "${x:-(none)}" >&2; return 2; }
  done
  _proof_roots_load
  fixed="$(proof_fixed "$plan" "$tree")"
  _facts_walk "$tree" "$(_facts_docs_prefix "$tree")" "$2" "$3" "$(_facts_born_landings "$plan" "$tree" "$fixed")" "${4:-}"
}


# ---------- THE DEBT LEDGER (wave-30 T22; D2, P2, AC-11.2, AC-11.3, AC-11.4) ----------
#
# `<docs-root>/record/<the plan's name less .plan.md>/debt.md`, derived as the landing record's path is
# (`_wt_proofs_path`, lib/worktree.sh): PROOF_DEBT_HEADER, then one line per item, six cells joined by
# ` | `:
#
#     <concept> | <kind> | <sites> | raised-by <record> | touches <N> | —            (not yet burned)
#     <concept> | <kind> | <sites> | raised-by <record> | touches <N> | burned <row>
#
# ONE WRITER, `session-poker.sh debt` (add, touched, burn), under a lock beside the file. These are its
# readers: the dispatch wall's advisory (`proof_debt_hits`), `ready`'s landing report
# (`proof_debt_row_counts`) and close-out's card and carry (`proof_debt_counts`, `proof_debt_items`). The
# last cell is read with index(), never by comparing the `—` glyph (macOS awk and multibyte `==`).
PROOF_DEBT_HEADER='# debt ledger: concept | kind | sites | raised-by <record> | touches N | burned <row> | —'

# proof_debt_ledger_path <root> <plan> -> the run's ledger path.
proof_debt_ledger_path() {
  local slug="${2##*/}"
  slug="${slug%.plan.md}"
  [ -n "${1:-}" ] && [ -n "$slug" ] || return 1
  printf '%s/record/%s/debt.md\n' "$(docs_root "$1")" "$slug"
}

# proof_debt_items <ledger> -> one tab-separated line per item, in ledger order:
# `<concept> <kind> <sites> <record> <touches> <burned row, or ->`. A line of another shape is not an item.
proof_debt_items() {
  [ -f "${1:-}" ] || return 0
  awk '
    /^#/ || NF == 0 { next }
    {
      if (split($0, c, / \| /) != 6) next
      if (index(c[4], "raised-by ") != 1 || c[5] !~ /^touches [0-9]+$/) next
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", c[1], c[2], c[3], substr(c[4], 11), substr(c[5], 9), (index(c[6], "burned ") == 1 ? substr(c[6], 8) : "-")
    }' "$1"
}

# proof_debt_hits <ledger> <Files cell> -> the items (as proof_debt_items prints them, burned ones too)
# one of whose sites the cell covers: the path itself, a directory above it, or a glob over it, by
# lib/units.sh `cell_covers`, the dispatch grammar's one matcher.
proof_debt_hits() {
  local items
  items="$(proof_debt_items "${1:-}")"
  [ -n "$items" ] && [ -n "${2:-}" ] || return 0
  _proof_units_load || return 0
  printf '%s\n' "$items" | PROOF_CELL="$2" awk -F'\t' "$(_units_files_awk)"'
    {
      n = split($3, s, /[ \t]*,[ \t]*/)
      for (i = 1; i <= n; i++) { p = s[i]; sub(/:[0-9]+$/, "", p); if (p != "" && cell_covers(ENVIRON["PROOF_CELL"], p)) { print; next } }
    }'
}

# proof_debt_counts <ledger> -> `<touched> <burned>` for the run: the touches summed over every item,
# and the items burned. Never the ledger's length (AC-11.4).
proof_debt_counts() {
  proof_debt_items "${1:-}" | awk -F'\t' '{ t += $5; if ($6 != "-") b++ } END { printf "%d %d\n", t, b }'
}

# proof_debt_row_counts <ledger> <row> <Files cell> -> `<burned> <touched>` for one row: the items whose
# last cell says `burned <row>`, and the items one of whose sites the row's Files cover.
proof_debt_row_counts() {
  local b t
  b="$(proof_debt_items "${1:-}" | awk -F'\t' -v r="${2:-}" 'r != "" && $6 == r { n++ } END { print n + 0 }')"
  t="$(proof_debt_hits "${1:-}" "${3:-}" | awk 'NF { n++ } END { print n + 0 }')"
  printf '%s %s\n' "$b" "$t"
}

# _proof_units_load -> 0 once lib/units.sh's Files matcher is defined, sourced from beside this file.
_proof_units_load() {
  local d
  declare -F _units_files_awk >/dev/null 2>&1 && return 0
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  # shellcheck source=/dev/null
  [ -n "$d" ] && [ -r "$d/units.sh" ] && . "$d/units.sh" 2>/dev/null
  declare -F _units_files_awk >/dev/null 2>&1
}
