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
# table in payload/context/severity.md lists them (tests/docs-pins.test.sh holds the two to one list).
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
      n = split(ENVIRON["PROOF_DK"], c, " "); for (i = 1; i <= n; i++) dk[c[i]] = 1
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
      if (!(f[2] in dk)) { bad("has a debt line (" line ") whose kind '"'"'" f[2] "'"'"' is not one of duplicate, unpinned-pair or one-case-abstraction; name the kind on the debt table in severity.md"); next }
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
# deferred, whoever wrote the line (AC-8.9). A caller reads `set -- $(…)`: three words, rated.
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
    fix) p=fix ;;
    defer) [ "$s" = S1 ] || p=defer ;;
  esac
  _PROOF_RATING="$s $r $p"
}

# _proof_moved_to <plan> <record>#<n> -> `defer` or `fix`, the priority the LAST `moved:` line of
# `## SDLC State` naming it (fences skipped) moved the finding to, or nothing when there is none
# (wave-28 T42; D34, AC-8.9). A later move is the user's later word, so the last line decides. A line
# is a move only when it carries who, when, the words and why, as `finding-move` writes it:
# `moved: <record>#<n> to=<defer|fix> by=<name> at=<ISO-UTC> words="<words>" why="<why>"`.
_proof_moved_to() {
  [ -f "$1" ] || return 0
  awk -v id="$2" "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^moved:[ \t]/ && proof_bound($0) == id { m = proof_move_of($0); if (m != "") to = m }
    END { if (to != "") print to }' "$1"
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
_proof_reading_result() {
  local plan="$1" droot="$2" ev="$3" res="$4" tab
  [ -n "$droot" ] && [ -n "$ev" ] && [ -f "$droot/$ev" ] || { printf '%s' "$res"; return 0; }
  tab="$(_proof_binding_table "$plan" "$ev")" || { printf '%s' "$res"; return 0; }
  _proof_reading_derive "$droot" "$ev" "$res" "$tab"
  printf '%s' "$PROOF_DERIVED"
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
# written result.
_proof_reading_derive() {
  local droot="$1" ev="$2" res="$3" nl tb tab got n s r w mv out=""
  nl=$'\n'; tb=$'\t'; tab="$nl$4"; PROOF_DERIVED="$res"
  got="$(proof_findings "$droot/$ev" 2>/dev/null)" || return 0
  while IFS='	' read -r n s r w _; do
    [ -n "$n" ] || continue
    # A debt row is flag-class whatever the plan binds (no binding line names it): kept as it is.
    [ "$n" != debt ] || { out="$out$n	$s	$r	$w	burn
"; continue; }
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

# proof_working_branch <plan> -> the plan's `working-branch:`, or nothing. The `## SDLC State`
# key first — the one the `current` verb reads to fill the Step-4 block — then the frontmatter
# key of the same name, which a plan written by Step 0 also carries. Fenced lines are not read.
proof_working_branch() {
  local plan="$1" wb
  [ -f "$plan" ] || return 0
  wb="$(awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^[[:space:]]*working-branch[[:space:]]*:/ {
      v = $0; sub(/^[[:space:]]*working-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
      print v; exit }' "$plan")"
  if [ -z "$wb" ]; then
    wb="$(awk '
      NR == 1 && $0 == "---" { f = 1; next }
      f && $0 == "---" { exit }
      f && /^[[:space:]]*working-branch[[:space:]]*:/ {
        v = $0; sub(/^[[:space:]]*working-branch[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
        gsub(/^["\047]|["\047]$/, "", v); print v; exit }' "$plan")"
  fi
  printf '%s' "$wb"
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

# proof_head <repo> <branch> -> the 40-hex HEAD of the checkout of <repo> that has <branch>
# checked out; exit 1 with nothing printed when no checkout holds it.
proof_head() {
  local wt
  wt="$(proof_checkout "$1" "$2")" || return 1
  git -C "$wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null
}

# proof_attested <kind> <evidence file> <checkout> [<plan>] [<question>] [<root>] -> the 40-hex head the evidence
# attests, exit 0; or exit 1 with one sentence on stdout saying why not and what to do (the verb's refusal).
#   floor  a full run's log: its LAST `head=<sha> dirty=<n>` line, the header the suite runner
#          prints before any suite, so the last run in the log is the one judged (T52). <n>
#          must be 0; the runner's verdict after it must read
#          `Gating: <n> passed, 0 failed`, outside any suite's captured output; and the run must
#          be WHOLE: <n> passed plus the suites its `Void:` line lists equal the suites at <sha>.
#          THE FLOOR IS A RECORD OF RUNS (wave-31 T25; REQ-4 AC-4.1, REQ-13 AC-13.4; D3): <sha> is
#          the checkout's HEAD, or an ancestor of it from which `_proof_walk` proves every later
#          commit by the runs recorded at it (`_proof_floor_walk`). The run itself is judged first.
#          UNLESS THE PROJECT DECLARES ITS REGRESSION (wave-28 T75; REQ-17, D36): with a <root> whose
#          `.bionic/config.yaml` names `floor:` or `floor-attestation:`, the evidence is judged by
#          `_proof_floor_declared` instead, and neither the verdict nor the roster is read. With
#          neither key, or no <root>, this rule stands as it was.
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
  local kind="$1" ev="$2" co="$3" plan="${4:-}" q="${5:-}" root="${6:-}" head stamp sha dirty rng a ah b bh since sh what verdict roster fl fa
  head="$(git -C "$co" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'the checkout %s has no head to hold the evidence against' "$co"; return 1; }
  if [ "$kind" = floor ] && [ -n "$root" ]; then
    _proof_roots_load
    fl="$(config_value "$root" floor "" 2>/dev/null)"; fa="$(config_value "$root" floor-attestation "" 2>/dev/null)"
    [ -z "$fl$fa" ] || { _proof_floor_declared "$ev" "$head" "$fl" "$fa" "$co" "$plan" "$root"; return $?; }
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
    floor) rng="" ;;
    review) stamp="" ;;
    task) [ -n "$stamp" ] && rng="" ;;
  esac
  if [ -n "$stamp" ]; then
    sha="${stamp#head=}"; sha="${sha%% *}"; dirty="${stamp##*dirty=}"
    if [ "$sha" = none ]; then
      printf 'the run in %s read no repository (head=none); run it in the working branch checkout and cite that log' "$ev"; return 1
    fi
    if [ "$sha" != "$head" ]; then
      if [ "$kind" != floor ]; then _proof_read_elsewhere "$ev" "$sha" "$head"; return 1; fi
      git -C "$co" rev-parse --verify -q "$sha^{commit}" >/dev/null 2>&1 \
        || { _proof_floor_walk "$ev" "$sha" "$head" "$co" "$plan" "$root"; return 1; }
    fi
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
    # A VOID SUITE PASSED (T43), so a `Void:` line no longer refuses (review 14 N2, retiring
    # A-T5.15); its count joins the tally below.
    verdict="$(awk '
      /^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { seen = 1; v = ""; void = 0; inside = 0; next }
      !seen { next }
      /^Gating: [0-9]+ passed, [0-9]+ failed$/ { v = $2 " " $4; void = 0; inside = 0; next }
      v != "" && index($0, "───── end ") == 1 { inside = 1 }
      v != "" && /^Void: [0-9]+ / { void = $2 + 0 }
      END { if (v == "") print "none"; else print v " " void " " inside }' "$ev" 2>/dev/null)"
    case "$verdict" in
      none|'')
        printf 'the run in %s has no Gating: <n> passed, <m> failed verdict after its head= line; cite the whole log of a full run that finished' "$ev"; return 1 ;;
    esac
    set -- $verdict
    if [ "$4" != 0 ]; then
      printf 'the last verdict in %s sits inside a suite'"'"'s captured output (a ───── end line follows it), so the run itself has none; cite the whole log of a full run that finished' "$ev"; return 1
    fi
    if [ "$2" != 0 ] || [ "$1" = 0 ]; then
      printf 'the run in %s did not pass (Gating: %s passed, %s failed); fix it, run it again and cite that log' "$ev" "$1" "$2"; return 1
    fi
    # A REGRESSION IS A WHOLE RUN (T52; review 14 N1). The runner's roster is every tests/*.test.sh
    # in the tree, with no skip list and no subset mode (a match that is not a suite stops the
    # run before any verdict), and every suite on it ends passed, failed or void. So a regression's
    # passed plus void equals the suites at the head the run read: one git call, here in the
    # verb, never in a wall. A clean tree (dirty=0, checked above) holds no untracked suite.
    if [ "$kind" = floor ]; then
      roster="$(git -C "$co" ls-tree --name-only "$sha" tests/ 2>/dev/null \
        | awk '/^tests\/[^\/]+\.test\.sh$/ { n++ } END { print n + 0 }')"
      if [ "$(($1 + $3))" -ne "${roster:-0}" ]; then
        printf 'the run in %s is not a whole run (%s passed and %s void of %s suites at its head); cite the log of a full run' \
          "$ev" "$1" "$3" "${roster:-0}"; return 1
      fi
      # THE RUN IS GOOD; NOW THE COMMITS SINCE IT (wave-31 T25; D3): a whole green run at an ancestor
      # stands for the working head when every commit after it is proved by its recorded runs.
      [ "$sha" = "$head" ] || _proof_floor_walk "$ev" "$sha" "$head" "$co" "$plan" "$root" || return 1
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
    floor) printf 'the evidence %s carries no head=<sha> dirty=<n> line; a regression proof cites the log of a full run, whose header prints it' "$ev" ;;
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
  local ev="$1" sha="$2" head="$3" co="$4" plan="${5:-}" root="${6:-}" files rec="" why
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
  why="$(_proof_walk "$co" "$sha" "$head" "$rec")" && return 0
  printf 'the run in %s read head %.12s, and the working branch is at %.12s: %s. Run the suites it lacks on %.12s, or the whole suite, then proof-add floor again' \
    "$ev" "$sha" "$head" "${why:-the commits since it cannot be walked}" "$head"
  return 1
}

# _proof_walk <checkout> <F> <H> [<landing record>] -> exit 0, printing nothing, when every commit on the
# working branch's first-parent line after F, up to and including H, is proved by the runs recorded at
# it; exit 1 printing one sentence that names the first commit that is not, and what it lacks (wave-31
# T25; REQ-13 AC-13.3, AC-13.4; D3; A-T25-1, A-T25-2, A-T25-4). F is an ancestor of H (the caller's).
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
# WHAT A COMMIT OWES: nothing when its tree is its first parent's; otherwise its row's Lands-on set
# (the `suites=` of the row's last `ready` before the `published` event naming the commit) and every
# suite a record at its tree names. A commit owing nothing that changed its tree is not proved. NOTHING
# PREDICTS A SUITE SET: every member of an owed set is a record.
#
# WHEN A SUITE OWED AT C IS PROVED: the last commit from C to H whose tree holds a record of it decides,
# by its newest record: green proves it, red does not. A later green run covers an earlier commit's
# change, since the later tree holds it; a later red supersedes an earlier green. A whole run is a
# record of every suite at once (`*`), weighed against each suite's own by time: a red one leaves
# every suite owed at or before its commit red there, and a newer run, the whole or the suite's own,
# decides again (wave-31 T41).
_proof_walk() {
  local co="$1" from="$2" to="$3" rec="${4:-}" walk gd recs need trees pairs f
  walk="$(git -C "$co" log --first-parent --reverse --format='W%x09%H%x09%T%x09%P' "$from..$to" 2>/dev/null)" \
    || { printf 'git cannot list the commits from %.12s to %.12s' "$from" "$to"; return 1; }
  [ -n "$walk" ] || return 0
  gd="$(cd "$co" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)"
  recs="$( { if [ -n "$rec" ] && [ -f "$rec" ]; then cat "$rec"; fi
             if [ -n "$gd" ]; then for f in "$gd/bionic-stamps" "$gd"/worktrees/*/bionic-stamps; do
               [ -f "$f" ] && cat "$f"; done; fi; } 2>/dev/null | awk -F'|' '
    function fv(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    substr($0, 1, 8) == "line/v1|" {
      ev = substr($2, 4); r = fv("row")
      if (ev == "ready") { if (r != "") su[r] = fv("suites") }
      else if (ev == "published") { c = fv("commit"); if (c != "") print "O\t" c "\t" r "\t" ((r in su) ? su[r] : "-") }
      else if (ev == "verdict") {
        c = fv("commit"); s = fv("suite"); v = fv("result")
        if (c != "" && s != "" && (v == "green" || v == "red")) print "R\t" fv("at") "\t" c "\t" s "\t" v
      }
      next
    }
    substr($0, 1, 8) == "landed: " {
      r = ""; c = ""; m = split($0, w, " ")
      for (i = 2; i <= m; i++) { if (index(w[i], "row=") == 1) r = substr(w[i], 5); else if (index(w[i], "merge=") == 1) c = substr(w[i], 7) }
      if (c != "") print "O\t" c "\t" r "\t-"
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
        if (a[i] == "run.sh") { print "R\t" at "\t" h "\t*\t" v; continue }
        print "R\t" at "\t" h "\t" a[i] "\t" v
      }
    }')"
  # THE TREES, in one git call: every commit a record names and every walked commit's first parent.
  need="$(printf '%s\n%s\n' "$recs" "$walk" | awk -F'\t' '
    $1 == "R" { print $3 } $1 == "W" { split($4, p, " "); if (p[1] != "") print p[1] }' | sort -u)"
  trees=""
  [ -z "$need" ] || trees="$(printf '%s\n' "$need" | sed 's/$/^{tree}/' | git -C "$co" cat-file --batch-check='%(objectname)' 2>/dev/null)"
  pairs="$( { printf '%s\n' "$need"; printf -- '--\n'; printf '%s\n' "$trees"; } | awk '
    $0 == "--" && !s { s = 1; next }
    !s { n[++k] = $0; next }
    { i++; if ($0 ~ /^[0-9a-f]+$/ && n[i] != "") print "T\t" n[i] "\t" $0 }')"
  printf '%s\n%s\n%s\n' "$pairs" "$walk" "$recs" | awk -F'\t' '
    $1 == "T" { tr[$2] = $3; next }
    $1 == "W" { n++; wc[n] = $2; wt[n] = $3; split($4, p, " "); wp[n] = p[1]; next }
    $1 == "O" { if ($3 != "" && index($3, "—") != 1) orow[$2] = $3; if ($4 != "" && $4 != "-") osu[$2] = $4; next }
    $1 == "R" {
      t = tr[$3]; if (t == "") next
      k = t SUBSEP $4
      if (!(k in rat) || $2 >= rat[k]) { rat[k] = $2; rres[k] = $5 }
      if ($4 != "*") nm[t] = nm[t] " " $4
      next
    }
    END {
      for (i = 1; i <= n; i++) {
        pt = (i > 1 && wp[i] == wc[i - 1]) ? wt[i - 1] : tr[wp[i]]
        if (pt != "" && pt == wt[i]) continue
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
      }
    }'
}

# _proof_floor_declared <evidence> <working head> <floor: command> <floor-attestation: value> -> the head,
# exit 0; or exit 1 with the refusal's sentence (wave-28 T75; REQ-17, D36). WHAT A PROJECT'S REGRESSION IS
# BELONGS TO THE PROJECT: the judge asks only that a regression was declared, ran at a clean working head and
# passed, never what its runner printed. Two shapes, either key alone enough:
#   floor: <command>         the log `floor-run` writes, whose FIRST line is `head=<40-hex> dirty=<n>
#                            rc=<n>`: the head the working head, dirty 0, rc 0. No Gating: verdict, no roster.
#   floor-attestation: user  the user's record: a `head=<40-hex> dirty=0` line (the last one) naming the
#                            working head, and a `floor-attested-by: <who> <when> <what ran>` line, three
#                            words or more after the key. A missing line is refused by its name.
# With both keys the declared shape is tried first: a first line in its shape is judged as one, so a red
# run is refused as red and never read again as an attestation. Any value of floor-attestation: but
# `user` is refused, whatever else the configuration says (fail closed).
_proof_floor_declared() {
  local ev="$1" head="$2" fl="$3" fa="$4" co="${5:-}" plan="${6:-}" root="${7:-}" hdr sha dirty rc who
  case "$fa" in
    ''|user) : ;;
    *) printf 'the floor-attestation: in .bionic/config.yaml is %s, and the one value it takes is user; write floor-attestation: user or remove the line' "$fa"; return 1 ;;
  esac
  if [ -n "$fl" ]; then
    hdr="$(awk 'NR == 1 { if ($0 ~ /^head=[0-9a-f]+ dirty=[0-9]+ rc=[0-9]+$/) { gsub(/(head|dirty|rc)=/, ""); print } exit }' "$ev" 2>/dev/null)"
    sha="${hdr%% *}"
    if [ "${#sha}" -eq 40 ]; then
      dirty="${hdr#* }"; rc="${dirty#* }"; dirty="${dirty%% *}"
      [ "$dirty" = 0 ] || { _proof_read_dirty "$ev" "$dirty"; return 1; }
      [ "$rc" = 0 ] || { printf 'the regression in %s did not pass (rc=%s); fix it, run floor-run again and cite that log' "$ev" "$rc"; return 1; }
      [ "$sha" = "$head" ] || _proof_floor_walk "$ev" "$sha" "$head" "$co" "$plan" "$root" || return 1
      printf '%s' "$sha"; return 0
    fi
    if [ -z "$fa" ]; then
      printf 'the evidence %s does not open with head=<40-hex> dirty=<n> rc=<n>, the line floor-run writes; run floor-run and cite its log' "$ev"; return 1
    fi
  fi
  sha="$(awk '/^head=[0-9a-f]+ dirty=0$/ { s = $1 } END { sub(/^head=/, "", s); print s }' "$ev" 2>/dev/null)"
  who="$(awk '/^floor-attested-by:[ \t]/ { sub(/^floor-attested-by:[ \t]+/, ""); sub(/[ \t]+$/, ""); if (split($0, w, /[ \t]+/) >= 3) { print; exit } }' "$ev" 2>/dev/null)"
  [ "${#sha}" -eq 40 ] || { printf 'the attestation %s carries no head=<40-hex> dirty=0 line naming the working head' "$ev"; return 1; }
  [ -n "$who" ] || { printf 'the attestation %s carries no floor-attested-by: <who> <when> <what ran> line' "$ev"; return 1; }
  [ "$sha" = "$head" ] || _proof_floor_walk "$ev" "$sha" "$head" "$co" "$plan" "$root" || return 1
  printf '%s' "$sha"
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
      PROOF_KIND = ""; PROOF_HEAD = ""; PROOF_QUESTION = ""; PROOF_READER = ""; PROOF_RESULT = ""; PROOF_SCOPE = ""; PROOF_EVIDENCE = ""
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
#                             and why, as `finding-move` writes it), else ""
proof_bind_awk() {
  printf '%s' '
    function proof_bound(s,   f) {
      if (s !~ /^(deferred|moved):[ \t]/) return ""
      split(s, f, /[ \t]+/); return f[2]
    }
    function proof_binds(s, rec) { return index(proof_bound(s), rec "#") == 1 }
    function proof_move_of(s,   f) {
      split(s, f, /[ \t]+/)
      if (f[3] != "to=defer" && f[3] != "to=fix") return ""
      if (s !~ / by=[^ \t]/ || s !~ / at=[0-9][0-9][0-9][0-9]-/ || s !~ / words="/ || s !~ / why="/) return ""
      return substr(f[3], 4)
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

# _proof_last_read <plan> <kind> <head|line> [<question>] -> the one reader behind the two above.
_proof_last_read() {
  local plan="$1" kind="$2" what="$3" q="${4:-}"
  [ -f "$plan" ] || return 0
  awk -v k="$kind" -v what="$what" -v q="$q" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_fields($0) && PROOF_KIND == k && (q == "" || PROOF_QUESTION == q) { last = PROOF_HEAD; lastline = $0 }
    END { if (last != "") print (what == "line" ? lastline : last) }' "$plan"
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
    insdlc && /^(proved|waived|deferred|moved):[[:space:]]/ { lastp = NR }
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
proof_readings_derived() {
  local plan="${1:-}" tree="${2:-}" droot="" k a b c tab="" nl
  [ -f "$plan" ] || return 0
  nl=$'\n'
  if [ -n "$tree" ]; then
    _proof_roots_load
    ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$tree" 2>/dev/null)"
  fi
  while IFS='	' read -r k a b c; do
    case "$k" in
      S) tab="$tab$a	$b$nl" ;;
      R) PROOF_DERIVED="$c"
         if [ "$b" = 1 ] && [ -n "$droot" ] && [ -f "$droot/$a" ]; then _proof_reading_derive "$droot" "$a" "$c" "$tab"; fi
         printf '%s\t%s\t%s\n' "$a" "$c" "$PROOF_DERIVED"; tab="" ;;
    esac
  done <<PROOF_READINGS
$(awk "$(proof_awk)$(proof_bind_awk)"'
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
      seen[PROOF_EVIDENCE SUBSEP PROOF_RESULT] = 1; nr++; rev[nr] = PROOF_EVIDENCE; rres[nr] = PROOF_RESULT
    }
    END {
      if (!nbind) exit
      for (i = 1; i <= nr; i++) {
        hit = 0; p = rev[i] "#"
        for (id in ids) if (index(id, p) == 1) { hit = 1; print "S\t" id "\t" (id in mv ? mv[id] : "-") }
        print "R\t" rev[i] "\t" hit "\t" rres[i]
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
# line, in exactly two words (wave-31 T25; REQ-4 AC-4.1, REQ-13 AC-13.4; D3; A-orch-23):
#
#     covered<TAB><head>       the proof names the working head, or nothing changed since it, or every
#                              commit since it is proved by the runs recorded at it (`_proof_walk`);
#                              <head> is the working head judged, which the full-run wall names (T52 N6)
#     uncovered<TAB><reason>   anything else, the reason in words: the commit the walk cannot prove and
#                              what it lacks, or the question that could not be answered
#
# (wave-26 T5; REQ-3, D6.) THE ONE PLACE THAT RUNS GIT FOR THE FLOOR'S STATE. The dispatch wall asks
# this and judges nothing itself. <tree> is the project root: its repository holds the working
# branch's checkout, where the head is read, and its docs tree holds the plan's landing record.
#
# THE FLOOR IS A RECORD OF RUNS (D3): one whole green run at a commit F on the branch, the proof line's
# head, and every commit after F proved by the runs recorded at it. Nothing predicts a suite set: the
# map, its bound and the rules that read a runner change, a deleted suite or an outside branch as owing
# a full run are gone (A-T25-4). A merge from outside the run is a first-parent commit no landing names,
# so it owes the suites recorded at it, and with none it is uncovered. UNCOVERED IS THE SAFE DIRECTION:
# every question this cannot answer — no proof yet, no checkout, a head git cannot read — answers it.
proof_state() {
  local plan="$1" tree="$2" h c wb wt files rec why
  h="$(proof_last "$plan" floor)"
  [ -n "$h" ] || { printf 'uncovered\tno regression proof on this plan yet\n'; return 0; }
  wb="$(proof_working_branch "$plan")"
  [ -n "$wb" ] || { printf 'uncovered\tthe plan names no working-branch\n'; return 0; }
  wt="$(proof_checkout "$tree" "$wb")" \
    || { printf 'uncovered\tno checkout holds the working branch %s\n' "$wb"; return 0; }
  c="$(git -C "$wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'uncovered\tthe head of %s cannot be read\n' "$wb"; return 0; }
  h="$(git -C "$wt" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" \
    || { printf 'uncovered\tthe proved head is not a commit here\n'; return 0; }
  [ "$h" != "$c" ] || { printf 'covered\t%s\n' "$c"; return 0; }
  git -C "$wt" merge-base --is-ancestor "$h" "$c" 2>/dev/null \
    || { printf 'uncovered\tthe proved head %.7s is not in the history of %s\n' "$h" "$wb"; return 0; }
  files="$(git -C "$wt" diff --name-only --no-renames "$h" "$c" 2>/dev/null)" \
    || { printf 'uncovered\tgit cannot list the change since %.7s\n' "$h"; return 0; }
  # NO FILE CHANGED: the tree is the one the proof read, so it is covered whatever the commits.
  [ -n "$files" ] || { printf 'covered\t%s\n' "$c"; return 0; }
  _proof_roots_load
  rec="$(proof_debt_record "$plan" "$tree" 2>/dev/null)" || rec=""
  why="$(_proof_walk "$wt" "$h" "$c" "$rec")" \
    || { printf 'uncovered\t%s\n' "${why:-the commits since the proved head cannot be walked}"; return 0; }
  printf 'covered\t%s\n' "$c"
}

# proof_regression <plan> -> `no` when the plan's leading frontmatter says `regression: no`, else `yes`;
# exit 0 (wave-31 T27; REQ-12 AC-12.2; D4). THE REGRESSION IS A STEP-0 SETTING: `session-poker.sh
# regression` writes the key, and at `no` the run owes no floor. AN ABSENT KEY, OR ANY VALUE BUT `no`,
# READS `yes`, fail-closed as an absent `walk:` reads `required`: only the explicit word relaxes
# anything. The key's sibling `regression-override:` records who chose against the scale default; it is
# never read here. One reading for facts_owed below and lib/units.sh's integrate default; the Step-5
# arm (lib/walls.sh validate_tests_block) reads the same key through the gate's own frontmatter_get.
proof_regression() {
  local v=""
  [ -f "${1:-}" ] && v="$(awk '
    { sub(/\r$/, "") }
    NR == 1 && $0 == "---" { f = 1; next }
    f && $0 == "---" { exit }
    f && /^[[:space:]]*regression[[:space:]]*:/ {
      v = $0; sub(/^[[:space:]]*regression[[:space:]]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      gsub(/^["\047]|["\047]$/, "", v); print v; exit }' "$1" 2>/dev/null)"
  if [ "$v" = no ]; then printf 'no\n'; else printf 'yes\n'; fi
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
#     uncovered<TAB><a>..<b>   code landed past <a>, the last head the fact reached, to <b> = <head>
#     uncovered<TAB><suite>…   the regression only: the map bounds the change, and these suites have no
#                              green run at <head> (wave-30 T13)
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
# <head>, or every commit past it touches only documentation: the docs root, or the files
# `_proof_docs_path` lists (wave-30 T6; D12), so a docs-only landing owes no reading. Covered code is
# every tracked path outside both. A waiver covers its question up to its own head.
# Every line of the question counts, failing ones included: a later reading may start at a failing
# reading's head, so the chain is not rebuilt by skipping them, and only the newest decides failing.
# THE WHOLE READ (D10), owed once per code question at wave scale, is covered by a non-failing
# `scope=whole` reading, or a waiver newer than the newest such reading. Code landed after it is the
# piece chain's to cover, so a whole line is covered, failing or absent, never uncovered. A proof
# line carries no range start, so what a whole reading read is the verb's to hold: it refuses one
# whose range starts after the plan's base-sha (row T41), and the judge takes the line as written.
# THE REGRESSION is proof_state's answer (wave-31 T25; D3): `covered` is covered, and `uncovered<TAB>
# <reason>` is uncovered with proof_state's reason, which names the first commit past the floor that no
# recorded run proves; with no regression proof it is absent. proof_state judges the working checkout's
# head, so for any other <head> the regression is uncovered from its proof's head, the range, never
# covered (T45; review pass 13 F3).
# An owed line this judge has no rule for answers absent (the safe direction).
# A FINDING RE-RATED BY A MOVE (wave-28 T42; D34): a reading's result is the one its findings give at
# their effective ratings (`_proof_reading_result`). No check holds the step: a reader's rating is
# final (wave-31 T32; D6), and a `check:` line an older plan carries is not read.
# IT READS GIT, so a verb, the tick and close-out call it, never a wall: a wall is handed its answer
# (the freeze, .claude/rules/hook-authoring.md).
facts_state() {
  local plan="${1:-}" head="${2:-}" d rigor scale owed tree droot pfx chains fact kind q role scope st rc=0
  local x pt pr ph pe wt wr we
  [ -f "$plan" ] || { printf 'facts_state: %s is not a plan file\n' "$plan" >&2; return 2; }
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  if ! declare -F plan_frontmatter_get >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$d/run.sh" >/dev/null 2>&1
  fi
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
  pfx=""
  if [ -n "$tree" ] && declare -F docs_root >/dev/null 2>&1; then
    droot="$(docs_root "$tree" 2>/dev/null)"
    case "$droot" in "$tree"/?*) pfx="${droot#"$tree"/}"; pfx="${pfx%/}/" ;; esac
  fi
  chains="$(awk -v qs="$PROOF_QUESTIONS" "$(proof_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      q = PROOF_QUESTION; pt[q] = "fact"; pr[q] = PROOF_RESULT; ph[q] = PROOF_HEAD; pe[q] = PROOF_EVIDENCE
      if (PROOF_SCOPE == "whole") { wt[q] = "fact"; wr[q] = PROOF_RESULT; we[q] = pe[q] }
      next
    }
    /^waived:[ \t]/ {
      m = split($0, w, /[ \t]+/); q = ""; h = ""
      for (i = 2; i <= m && w[i] != "by"; i++) {
        if (w[i] ~ /^question=/) q = substr(w[i], 10)
        else if (w[i] ~ /^head=/) h = substr(w[i], 6)
      }
      if (q == "" || h !~ /^[0-9a-f]+$/ || length(h) < 7 || length(h) > 40) next
      pt[q] = "waiver"; pr[q] = ""; ph[q] = h; pe[q] = ""; wt[q] = "waiver"; wr[q] = ""; we[q] = ""
    }
    END {
      n = split(qs, Q, " ")
      for (i = 1; i <= n; i++) { q = Q[i]; printf "%s|%s|%s|%s|%s|%s|%s|%s\n", q, pt[q], pr[q], ph[q], pe[q], wt[q], wr[q], we[q] }
    }' "$plan")"
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    case "$fact" in
      floor)
        x="$(proof_last "$plan" floor)"
        if [ -z "$x" ]; then st=absent
        elif [ "$(proof_head "$tree" "$(proof_working_branch "$plan")" 2>/dev/null)" != "$head" ]; then
          st="uncovered	$x..$head"
        else
          st="$(proof_state "$plan" "$tree" 2>/dev/null | awk 'NR == 1')"
          case "$st" in
            covered*) st=covered ;;
            uncovered"	"?*) : ;;
            *) st="uncovered	$x..$head" ;;
          esac
        fi ;;
      review"	"*)
        IFS='	' read -r kind q role scope <<PROOF_OWED
$fact
PROOF_OWED
        x="$(printf '%s\n' "$chains" | awk -F'|' -v q="$q" '$1 == q')"
        IFS='|' read -r x pt pr ph pe wt wr we <<PROOF_CHAIN
$x
PROOF_CHAIN
        # THE RESULT IS THE ONE ITS FINDINGS GIVE AT THEIR EFFECTIVE RATINGS (wave-28 T41; D33): a
        # reading a check re-rated is derived again from its record, not read off its proof line.
        [ "$pt" != fact ] || pr="$(_proof_reading_result "$plan" "$droot" "$pe" "$pr")"
        [ "$wt" != fact ] || wr="$(_proof_reading_result "$plan" "$droot" "$we" "$wr")"
        if [ "$scope" = whole ]; then
          if [ -z "$wt" ]; then st=absent
          elif [ "$wt" = fact ] && [ "$wr" = fail ]; then st="failing	$we"
          else st=covered; fi
        elif [ -z "$pt" ]; then st=absent
        elif [ "$pt" = fact ] && [ "$pr" = fail ]; then st="failing	$pe"
        elif _facts_holds "$tree" "$pfx" "$ph" "$head"; then st=covered
        else st="uncovered	$ph..$head"
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
# README.md, CLAUDE.md, anything under .bionic/ and anything under .claude/rules/. THIS CASE IS THE
# ONE LIST. It is never skills/ or agents/ prose, which agents execute, and never a payload/ file; a
# README or CHANGELOG deeper than the root is not in it either.
_proof_docs_path() {
  case "$1" in
    CHANGELOG.md|README.md|CLAUDE.md|.bionic/*|.claude/rules/*) return 0 ;;
  esac
  return 1
}

# _facts_holds <tree> <docs prefix> <last head> <head> -> 0 when <head> is <last head>, or <last
# head> is on its history and every commit past it on <head>'s first-parent line (a merge as what it
# brought in) touches only documentation: a path under <docs prefix>, or one `_proof_docs_path`
# names, a rename as both its paths. A commit that mixes a docs file with any other file is not
# docs-only, so one path outside both fails the range. 1 otherwise, and whenever git cannot answer:
# uncovered is the safe direction. Both heads are compared as the commits they resolve to, never as
# strings (T45; review pass 13 F10).
_facts_holds() {
  local tree="$1" pfx="$2" lh hh files f
  [ -n "$tree" ] || return 1
  lh="$(git -C "$tree" rev-parse --verify -q "$3^{commit}" 2>/dev/null)" || return 1
  hh="$(git -C "$tree" rev-parse --verify -q "$4^{commit}" 2>/dev/null)" || return 1
  [ "$lh" != "$hh" ] || return 0
  git -C "$tree" merge-base --is-ancestor "$lh" "$hh" 2>/dev/null || return 1
  files="$(git -C "$tree" log --first-parent -m --no-renames --name-only --format= "$lh..$hh" 2>/dev/null)" || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "${f#"$pfx"}" != "$f" ] || _proof_docs_path "$f" || return 1
  done <<PROOF_DOCS_FILES
$files
PROOF_DOCS_FILES
  return 0
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
