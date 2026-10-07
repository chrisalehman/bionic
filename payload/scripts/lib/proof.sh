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
PROOF_READER_ROLES="bionic:auditor bionic:critic bionic:reviewer"
# THE DEALING (wave-27 T9; D2, D6): the reader role that answers each question at each rigor, one
# role per question, in PROOF_QUESTIONS' order, `<rigor>=<evidence>,<adversarial>,<structure>`.
# `facts_owed` is its one reader.
PROOF_DEALING="tested=bionic:critic,bionic:critic,bionic:critic peer-reviewed=bionic:auditor,bionic:critic,bionic:critic audited=bionic:auditor,bionic:critic,bionic:reviewer"
# The questions that read the code; at wave scale each also owes one read of the whole (D10).
PROOF_CODE_QUESTIONS="adversarial structure"
# THE SEVERITY SCALE'S TWO CLOSED SETS AND ITS TABLE (wave-28 T15; D19, AC-8.1, AC-8.3): a finding's
# severity and reach, and the one priority each pair gives, `<S>:<reach>=<fix|defer|note>`. This
# is the table's one definition: `proof_priority` reads it, and every awk that rates a finding is
# handed it whole through its environment.
PROOF_SEVERITIES="S1 S2 S3 S4"
PROOF_REACHES="on off"
PROOF_PRIORITY="S1:on=fix S1:off=fix S2:on=fix S2:off=defer S3:on=defer S3:off=note S4:on=note S4:off=note"

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
#     unsure: <n> <what is not known>  for a finding that owes a check
#
# The record writes no priority: the table gives it (`proof_priority`), and a `priority: <n> <word>`
# line that differs from the table is refused. The result follows from the priorities
# (`proof_findings_result`). At registration `proof-add` writes the plan's `deferred:` and `check:`
# lines (`proof_finding_lines`); the tick and `release-check` print them with their priority
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
#     <n> <S> <reach> <path:line|-> <fix|defer|note> <shown 1|0> <unsure 1|0> <title>
#
# exit 0 (nothing printed for `findings: 0`); or exit 1 with one sentence saying what the findings
# lack and what to write (the verb's refusal). The rules: a `findings: <n>` line, given once; that
# many `finding:` lines, each number once, each severity and reach from its set, a `<path>:<line>`
# or `-`, and a title; a `shown:`, `unsure:` or `priority:` line names a finding the record holds;
# a written priority is the table's; and a finding the table sends to fix carries a `<path>:<line>`
# with a `shown:` line, or an `unsure:` line.
proof_findings() {
  local span
  span="$(awk '/^reviewed:[ \t]/ { if (n++) exit } n' "$1" 2>/dev/null)"
  [ -n "$span" ] || { printf 'the reading %s carries no reviewed: <a>..<b> line; write the range it read' "$1"; return 1; }
  _proof_findings_span "$1" "$span"
}

# _proof_findings_span <record> <its pass> -> proof_findings' answer for a pass already cut.
_proof_findings_span() {
  local out
  out="$(PROOF_REC="$1" PROOF_PRI="$PROOF_PRIORITY" PROOF_SEV="$PROOF_SEVERITIES" PROOF_REACH="$PROOF_REACHES" awk '
    BEGIN {
      rec = ENVIRON["PROOF_REC"]
      n = split(ENVIRON["PROOF_PRI"], c, " ")
      for (i = 1; i <= n; i++) { k = c[i]; sub(/=.*$/, "", k); v = c[i]; sub(/^[^=]*=/, "", v); pri[k] = v }
      n = split(ENVIRON["PROOF_SEV"], c, " "); for (i = 1; i <= n; i++) sev[c[i]] = 1
      n = split(ENVIRON["PROOF_REACH"], c, " "); for (i = 1; i <= n; i++) rch[c[i]] = 1
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
    /^(shown|unsure):/ {
      m = split($0, f, /[ \t]+/); k = f[1]; sub(/:$/, "", k)
      if (rest($0, 2) == "") { bad("has a " k ": line with nothing after its number (" $0 "); write " k ": <n> " (k == "shown" ? "<command>" : "<what is not known>")); next }
      if (k == "shown") sh[f[2]] = 1; else un[f[2]] = 1
      named[f[2]] = k; next
    }
    /^priority:/ { m = split($0, f, /[ \t]+/); wp[f[2]] = f[3]; named[f[2]] = "priority"; next }
    END {
      if (err == "" && !hf) err = "the reading " rec " carries no findings: <n> line, and its reader was pushed the severity scale; write findings: <n> and one finding: line per finding (findings: 0 when it found none)"
      if (err == "" && cnt != want + 0) bad("says findings: " want " but holds " cnt " finding: lines; write one finding: line per finding, and the count they make")
      for (k in named) if (err == "" && !(k in S)) bad("has a " named[k] ": line for finding " k ", which it does not hold; name a finding it numbers")
      for (i = 1; i <= cnt && err == ""; i++) {
        id = ord[i]; p = pri[S[id] ":" R[id]]
        if ((id in wp) && wp[id] != p) bad("writes priority " wp[id] " for finding " id ", but the table gives " S[id] " " R[id] " " p "; a record writes no priority, so remove the line")
        else if (p == "fix" && !((W[id] != "-" && (id in sh)) || (id in un))) bad("sends finding " id " (" S[id] " " R[id] ") to fix, but shows it nowhere; write its <path>:<line> and shown: " id " <command>, or unsure: " id " <what is not known>")
      }
      if (err != "") { print "!" err; exit }
      for (i = 1; i <= cnt; i++) { id = ord[i]; printf "%s\t%s\t%s\t%s\t%s\t%d\t%d\t%s\n", id, S[id], R[id], W[id], pri[S[id] ":" R[id]], (id in sh), (id in un), T[id] }
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
# the table defers, then `check: <record>#<n> <S> <reach> "<title>"` for each unsure one; nothing for
# a note, nor for a finding to fix, which the verdict carries. A `"` in a title is written `'`, so the
# quoted title ends where its line does.
proof_finding_lines() {
  printf '%s\n' "${2:-}" | REC="$1" awk -F'\t' '
    NF >= 8 { t = $8; gsub(/"/, "'"'"'", t); l = ENVIRON["REC"] "#" $1 " " $2 " " $3 " \"" t "\""
              if ($5 == "defer") d = d "deferred: " l "\n"
              if ($7 == 1) c = c "check: " l "\n" }
    END { printf "%s%s", d, c }'
}

# proof_finding_rating <plan> <record>#<n> <S> <reach> -> `<S> <reach> <priority>`, the rating a
# REGISTERED finding is read at and the priority it takes, with a fourth word `open` while its check is
# open; nothing when it is dropped.
#
# THE SEAM FOR THE EFFECTIVE RATING (wave-28 T15 left it unbuilt; T41 fills the check, T42 the move).
# Every read of a registered record's findings passes each finding through here, and this is the one
# place the effective rating is applied. The `check:` line for <record>#<n> (`_proof_check_state`)
# decides first: ` settled=<S>:<reach>` gives that rating; ` refuted` drops the finding (print
# nothing); neither, the check is open: the finding keeps the rating it was registered at, which the
# scale's rule made the higher one, and the fourth word `open` says the step is held (`current 8`, the
# judge). With no check: line it is the rating the record wrote. The priority is the table's for the
# rating given (`proof_priority`); a `moved: <record>#<n> to=<defer|fix>` line (T42, `_proof_moved_to`)
# replaces the priority alone, so the third word is the one a move changes — except that an S1 is never
# deferred, whoever wrote the line (AC-8.9). A caller reads `set -- $(…)`: no words, dropped; three or
# four, rated.
proof_finding_rating() {
  _proof_rating_apply "$(_proof_check_state "$1" "$2")" "$(_proof_moved_to "$1" "$2")" "$3" "$4"
  printf '%s' "$_PROOF_RATING"
}

# _proof_rating_apply <check state> <moved to> <S> <reach> -> proof_finding_rating's answer once the two
# plan reads are in hand, in `_PROOF_RATING` and no fork (wave-28 T72): the batch reader
# (`proof_readings_derived`) gathers every finding's state and move in one pass over the plan and asks
# here, so the rule is spelled once.
_proof_rating_apply() {
  local st="$1" mv="$2" s="$3" r="$4" p
  _PROOF_RATING=""
  case "$st" in
    refuted) return 0 ;;
    settled=*:*) s="${st#settled=}"; r="${s#*:}"; s="${s%%:*}" ;;
  esac
  _proof_priority_var "$s" "$r"; p="$_PROOF_P"
  case "$mv" in
    fix) p=fix ;;
    defer) [ "$s" = S1 ] || p=defer ;;
  esac
  _PROOF_RATING="$s $r $p"
  [ "$st" != open ] || _PROOF_RATING="$_PROOF_RATING open"
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

# _proof_check_state <plan> <record>#<n> -> the state of the first `check:` line of `## SDLC State`
# naming it (fences skipped): `settled=<S>:<reach>`, `refuted`, `open`, or nothing when there is no
# such line (wave-28 T41; D33). Only what follows the quoted title is read, so a title that holds the
# words is still the title (a title never holds a `"`: registration writes it `'`).
_proof_check_state() {
  [ -f "$1" ] || return 0
  awk -v id="$2" "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^check:[ \t]/ && proof_bound($0) == id { print proof_check_of($0); exit }' "$1"
}

# proof_findings_owed <plan> -> one line per finding the plan's `## SDLC State` carries a `deferred:` or
# `check:` line for, in the order first written, rated through `proof_finding_rating`:
# `<record>#<n> <S> <reach> <fix|defer|note|check> "<title>"`, the priority the effective rating takes,
# or `check` while the finding's check is open — it is neither a fix nor a deferral until a check
# settles it (wave-28 T41; D33). A refuted finding is not printed. What the tick and `release-check`
# print, so the priority a record never states is seen where the run is judged.
proof_findings_owed() {
  local plan="$1" id s r t p
  [ -f "$plan" ] || return 0
  while IFS='	' read -r id s r t; do
    [ -n "$id" ] || continue
    set -- $(proof_finding_rating "$plan" "$id" "$s" "$r")
    [ $# -ge 3 ] && [ -n "$3" ] || continue
    p="$3"; [ "${4:-}" != open ] || p=check
    printf '%s %s %s %s %s\n' "$id" "$1" "$2" "$p" "$t"
  done <<PROOF_OWED_FINDINGS
$(awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { next }
  /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
  insdlc && /^(deferred|check):[ \t]/ {
    m = split($0, f, /[ \t]+/); if (m < 4 || (f[2] in seen)) next
    seen[f[2]] = 1; t = $0; if (match(t, /"[^"]*"/)) t = substr(t, RSTART, RLENGTH); else t = "\"\""
    printf "%s\t%s\t%s\t%s\n", f[2], f[3], f[4], t
  }' "$plan")
PROOF_OWED_FINDINGS
}

# proof_checks_open <plan> -> the owed lines whose check is open, `<record>#<n> <S> <reach> check
# "<title>"`, in the order first written: THE ONE READER of which checks hold the step (wave-28 T41;
# D33, AC-8.6). The judge (`facts_state`) and `current 8` (session-poker.sh) both ask it.
proof_checks_open() {
  proof_findings_owed "$1" | awk '$4 == "check"'
}

# _proof_reading_result <plan> <docs root> <evidence> <written result> -> the reading's result as its
# findings give it at their effective ratings (wave-28 T41; D33): a reading whose record a binding line
# names (`proof_bind_awk`: a `check:`, `deferred:` or `moved:` line keyed to a finding of it) is derived
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
# unfenced `## SDLC State` is keyed to: `<record>#<n><TAB><check state><TAB><moved to>`, each `-` when the
# plan says none (`_proof_check_state`'s and `_proof_moved_to`'s answers, read together in one pass);
# exit 1, nothing printed, when no binding line names the record.
_proof_binding_table() {
  [ -f "$1" ] || return 1
  awk -v rec="$2" "$(proof_bind_awk)"'
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && proof_binds($0, rec) {
      hit = 1; id = proof_bound($0); ids[id] = 1
      if ($0 ~ /^check:/) { if (!(id in cs)) cs[id] = proof_check_of($0) }
      else if ($0 ~ /^moved:/) { m = proof_move_of($0); if (m != "") mv[id] = m }
    }
    END {
      if (!hit) exit 1
      for (id in ids) print id "\t" (id in cs ? cs[id] : "-") "\t" (id in mv ? mv[id] : "-")
    }' "$1"
}

# _proof_reading_derive <docs root> <evidence> <written result> <binding table> -> in `PROOF_DERIVED`, the
# result <evidence>'s findings give at the ratings the table (`_proof_binding_table`'s lines) says: the one
# derivation, asked once per reading by `_proof_reading_result` and once per bound reading by
# `proof_readings_derived`, which prints it without a fork. A record that cannot be read keeps the
# written result.
_proof_reading_derive() {
  local droot="$1" ev="$2" res="$3" nl tb tab got n s r w row st mv out=""
  nl=$'\n'; tb=$'\t'; tab="$nl$4"; PROOF_DERIVED="$res"
  got="$(proof_findings "$droot/$ev" 2>/dev/null)" || return 0
  while IFS='	' read -r n s r w _; do
    [ -n "$n" ] || continue
    st=""; mv=""
    case "$tab" in
      *"$nl$ev#$n$tb"*)
        row="${tab#*"$nl$ev#$n$tb"}"; row="${row%%"$nl"*}"
        st="${row%%"$tb"*}"; mv="${row#*"$tb"}"
        [ "$st" != - ] || st=""; [ "$mv" != - ] || mv="" ;;
    esac
    _proof_rating_apply "$st" "$mv" "$s" "$r"
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

# proof_attested <kind> <evidence file> <checkout> [<plan>] [<question>] -> the 40-hex head the evidence attests, exit
# 0; or exit 1 with one sentence on stdout saying why not and what to do (the verb's refusal).
#   floor  a full run's log: its LAST `head=<sha> dirty=<n>` line, the header the suite runner
#          prints before any suite, so the last run in the log is the one judged (T52). <sha>
#          must be the checkout's HEAD and <n> 0; the runner's verdict after it must read
#          `Gating: <n> passed, 0 failed`, outside any suite's captured output; and the run must
#          be WHOLE: <n> passed plus the suites its `Void:` line lists equal the suites at <sha>.
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
  local kind="$1" ev="$2" co="$3" plan="${4:-}" q="${5:-}" head stamp sha dirty rng a ah b bh since sh what verdict roster
  head="$(git -C "$co" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'the checkout %s has no head to hold the evidence against' "$co"; return 1; }
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
      printf 'the run in %s read head %s, but the working branch is at %s; run it again on %s and cite that log' \
        "$ev" "$(printf '%s' "$sha" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)" "$(printf '%s' "$head" | cut -c1-12)"; return 1
    fi
    if [ "$dirty" != 0 ]; then
      printf 'the run in %s read a dirty tree (dirty=%s); commit, run it again and cite that log' "$ev" "$dirty"; return 1
    fi
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
    # A FLOOR IS A WHOLE RUN (T52; review 14 N1). The runner's roster is every tests/*.test.sh
    # in the tree, with no skip list and no subset mode (a match that is not a suite stops the
    # run before any verdict), and every suite on it ends passed, failed or void. So a floor's
    # passed plus void equals the suites at the head the run read: one git call, here in the
    # verb, never in a wall. A clean tree (dirty=0, checked above) holds no untracked suite.
    if [ "$kind" = floor ]; then
      roster="$(git -C "$co" ls-tree --name-only "$head" tests/ 2>/dev/null \
        | awk '/^tests\/[^\/]+\.test\.sh$/ { n++ } END { print n + 0 }')"
      if [ "$(($1 + $3))" -ne "${roster:-0}" ]; then
        printf 'the run in %s is not a whole run (%s passed and %s void of %s suites at its head); cite the log of a full run' \
          "$ev" "$1" "$3" "${roster:-0}"; return 1
      fi
    fi
    printf '%s' "$head"; return 0
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
    floor) printf 'the evidence %s carries no head=<sha> dirty=<n> line; a floor proof cites the log of a full run, whose header prints it' "$ev" ;;
    review) printf 'the evidence %s carries no reviewed: <a>..<b> line; a review proof cites a review whose header names the range it read' "$ev" ;;
    *) printf 'the evidence %s carries neither a head=<sha> dirty=<n> run header nor a reviewed: <a>..<b> line; cite a run log or a review' "$ev" ;;
  esac
  return 1
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
# what such a line says (wave-28 T72; D33, D34, AC-8.6, AC-8.9; A-T60.5, A-orch-213). A `check:`,
# `deferred:` or `moved:` line of `## SDLC State` is keyed `<record>#<n>`: it settles, defers or moves ONE
# finding of ONE pass, and every read of the record's findings applies it (`proof_finding_rating`), so a
# second pass registered on the same path would inherit it. `moved:` binds for the reason a check does: a
# move is the user's word about one finding, it changes the priority a later reader of that path judges
# (T42's seam), and a path that carries one is a settled pass whatever else it carries. Both callers
# (`proof_pass_conflict`, the registering verb's guard, and `_proof_reading_result`, the judge's
# re-derivation) and the batch reader (`proof_readings_derived`) ask these, so none can spell it again:
#
#     proof_bound(line)       the `<record>#<n>` a binding line is keyed to, else ""
#     proof_binds(line, rec)  1 when the line is keyed to a finding of the record <rec>
#     proof_check_of(line)    what a `check:` line says: `settled=<S>:<reach>`, `refuted` or `open`
#                             (only what follows the quoted title is read: a title that holds the words
#                             is still the title; registration writes a `"` in one as `'`)
#     proof_move_of(line)     `defer` or `fix` when a `moved:` line is a whole move (who, when, the words
#                             and why, as `finding-move` writes it), else ""
proof_bind_awk() {
  printf '%s' '
    function proof_bound(s,   f) {
      if (s !~ /^(check|deferred|moved):[ \t]/) return ""
      split(s, f, /[ \t]+/); return f[2]
    }
    function proof_binds(s, rec) { return index(proof_bound(s), rec "#") == 1 }
    function proof_check_of(s,   t, i, st) {
      t = s; i = index(t, "\""); if (i) { t = substr(t, i + 1); i = index(t, "\""); t = (i ? substr(t, i + 1) : "") }
      st = "open"
      if (match(t, /(^|[ \t])settled=S[1-4]:(on|off)([ \t]|$)/)) { st = substr(t, RSTART, RLENGTH); gsub(/[ \t]/, "", st) }
      else if (t ~ /(^|[ \t])refuted([ \t]|$)/) st = "refuted"
      return st
    }
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
# reads "newer" as "later in the section". A reading's `deferred:` and `check:` lines (wave-28 T15),
# and a finding's `moved:` lines (T42), follow its proof line and belong to the block, so the next
# line goes after them, not between.
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
    insdlc && /^(proved|waived|deferred|check|moved):[[:space:]]/ { lastp = NR }
    insdlc && /[^[:space:]]/ { lastn = NR }
    END {
      if (!seen) exit 1
      at = lastp ? lastp : lastn
      for (i = 1; i <= NR; i++) { print row[i]; if (i == at) print L }
    }' "$plan"
}

# proof_pass_conflict <plan> <record path> <head> -> why <record path> cannot be registered for another
# pass at <head>, or nothing (wave-28 T60; D33, AC-8.6). ONE RECORD PATH IS ONE PASS: a line that binds a
# pass (`proof_bind_awk`: `check:`, `deferred:` or `moved:`) is keyed `<record>#<n>`, so a second pass on
# the same path would inherit the first pass's settlement, deferral or move. The key stays unique by
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
      S) tab="$tab$a	$b	$c$nl" ;;
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
      if ($0 ~ /^check:/) { if (!(id in cs)) cs[id] = proof_check_of($0) }
      else if ($0 ~ /^moved:/) { m = proof_move_of($0); if (m != "") mv[id] = m }
      next
    }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" && !((PROOF_EVIDENCE SUBSEP PROOF_RESULT) in seen) {
      seen[PROOF_EVIDENCE SUBSEP PROOF_RESULT] = 1; nr++; rev[nr] = PROOF_EVIDENCE; rres[nr] = PROOF_RESULT
    }
    END {
      if (!nbind) exit
      for (i = 1; i <= nr; i++) {
        hit = 0; p = rev[i] "#"
        for (id in ids) if (index(id, p) == 1) { hit = 1; print "S\t" id "\t" (id in cs ? cs[id] : "-") "\t" (id in mv ? mv[id] : "-") }
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

# proof_state <plan> <tree> -> what the change since the last floor proof needs, one line:
#
#     covered<TAB><head>               the working branch's head is the one the proof names, or
#                                      no file changed since it; <head> is the working head
#                                      judged, which the refusal names (T52; review 14 N6)
#     bounded<TAB><suite> <suite>…     every changed file has a non-empty answer from the map,
#                                      the union is not every suite, and no commit in the range
#                                      is on another branch
#     unbounded<TAB><reason>           anything else, the reason in words
#
# (wave-26 T5; REQ-3, D6.) THE ONE PLACE THAT RUNS GIT FOR THE FULL-RUN DECISION. The dispatch
# wall asks this and judges nothing itself. <tree> is the project root: its `.bionic/config.yaml`
# names the map (`impact-command:`), and its repository holds the working branch's checkout,
# where the head is read, the map runs and the suite roster is counted.
#
# UNBOUNDED IS THE SAFE DIRECTION. It admits a full run; a wrong `bounded` would refuse one the
# change needed. So every question this cannot answer — no proof yet, no checkout, a map that
# fails or overruns — answers `unbounded` and says which question it was.
#
# THE STEPS, CHEAPEST FIRST: the proof line; the head; one `git diff --name-only --no-renames`
# over the range (a rename is its two paths, and the old side is often the wider answer); two
# `rev-list --count` calls for the outside test; one map call over every changed file.
#
# AN OUTSIDE COMMIT is one some branch other than the working branch and the run's task
# branches contains (research R7 §5, which found commit subjects unreliable). The task branches
# are `wt/<NN>-*`, NN read from a `wave/<NN>-…` working branch, the convention spawn-worktree
# and close-out share; a working branch of any other shape excludes only itself, which reads
# the run's own task branches as outside — the safe direction again. "Some branch" is a local
# branch, a remote-tracking ref (`git merge origin/main`, `git pull`) or a tag, the run's own
# names excluded under any remote (T52; review 14 S1). ONE CASE CANNOT BE SEEN: an outside branch
# deleted after its merge leaves its commits on no ref but the working branch, exactly like a
# landed task branch that was deleted, and reads as the run's own.
#
# A CHANGE TO THE RUNNER OR TO tests/lib/ OWES A FULL RUN (T52; ruling R2): every suite runs
# through the one and sources the other, so the map's answer for them is not the reach of the
# change. A change that DELETES A SUITE owes one too (review 14 N8; A-T52.6): the roster the full
# run reads has changed, and no remaining suite is known to prove the deletion. Both are asked of
# the file list before the outside test and the map, at no git cost.
#
# THE MAP IS ASKED FOR THE CHANGE, THEN FOR EACH FILE IT LEFT UNNAMED (T52; review 14 S2). The
# map prints one line per suite, naming the strongest file that reaches it, so a file whose
# suites another changed file claims is named by no line. Such a file is asked again alone,
# inside the same bound, and only a file whose own answer is empty is "answered with no suite".
# A suite the working checkout does not hold is never named, and never counts as an answer.
proof_state() {
  local plan="$1" tree="$2" h c wb wt files nn total rest cmd tmp lst roster ans f s rc nog
  local d
  h="$(proof_last "$plan" floor)"
  [ -n "$h" ] || { printf 'unbounded\tno floor proof on this plan yet\n'; return 0; }
  wb="$(proof_working_branch "$plan")"
  [ -n "$wb" ] || { printf 'unbounded\tthe plan names no working-branch\n'; return 0; }
  wt="$(proof_checkout "$tree" "$wb")" \
    || { printf 'unbounded\tno checkout holds the working branch %s\n' "$wb"; return 0; }
  c="$(git -C "$wt" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'unbounded\tthe head of %s cannot be read\n' "$wb"; return 0; }
  h="$(git -C "$wt" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" \
    || { printf 'unbounded\tthe proved head is not a commit here\n'; return 0; }
  [ "$h" != "$c" ] || { printf 'covered\t%s\n' "$c"; return 0; }
  git -C "$wt" merge-base --is-ancestor "$h" "$c" 2>/dev/null \
    || { printf 'unbounded\tthe proved head %.7s is not in the history of %s\n' "$h" "$wb"; return 0; }
  files="$(git -C "$wt" diff --name-only --no-renames "$h" "$c" 2>/dev/null)" \
    || { printf 'unbounded\tgit cannot list the change since %.7s\n' "$h"; return 0; }
  # NO FILE CHANGED: the tree is the one the proof read, so it is covered whatever the commits.
  [ -n "$files" ] || { printf 'covered\t%s\n' "$c"; return 0; }

  # THE RUNNER, THE TEST LIBRARY, A DELETED SUITE: a full run, whatever the map says (R2, N8).
  while IFS= read -r f; do
    case "$f" in
      tests/run.sh)
        printf 'unbounded\tthe change touches the full-suite runner %s, which every suite runs through\n' "$f"; return 0 ;;
      tests/lib/*)
        printf 'unbounded\tthe change touches %s, in the test library the suites run on\n' "$f"; return 0 ;;
      tests/*/*) ;;
      tests/*.test.sh)
        [ -e "$wt/$f" ] || { printf 'unbounded\tthe change deletes the suite %s, so the roster a full run reads has changed\n' "$f"; return 0; } ;;
    esac
  done <<PROOF_FILES
$files
PROOF_FILES

  nn="$(printf '%s' "$wb" | sed -nE 's#^wave/([0-9]+)-.*#\1#p')"
  total="$(git -C "$wt" rev-list --count "$h..$c" 2>/dev/null)"
  if [ -n "$nn" ]; then
    rest="$(git -C "$wt" rev-list --count "$h..$c" --not \
      --exclude="$wb" --exclude="wt/${nn}-*" --branches \
      --exclude="*/$wb" --exclude="*/wt/${nn}-*" --remotes --tags 2>/dev/null)"
  else
    rest="$(git -C "$wt" rev-list --count "$h..$c" --not \
      --exclude="$wb" --branches --exclude="*/$wb" --remotes --tags 2>/dev/null)"
  fi
  case "$total$rest" in ''|*[!0-9]*)
    printf 'unbounded\tgit cannot count the commits since %.7s\n' "$h"; return 0 ;;
  esac
  if [ "$rest" -lt "$total" ]; then
    printf 'unbounded\t%s of %s commits since %.7s are on another branch than %s and its task branches (a merge from outside the run)\n' \
      "$((total - rest))" "$total" "$h" "$wb"
    return 0
  fi

  d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
  _proof_roots_load
  if [ -z "${IMPACT_BOUND_S:-}" ]; then
    # shellcheck source=/dev/null
    . "$d/bounds.sh" >/dev/null 2>&1
  fi
  cmd="$(config_value "$tree" impact-command "" 2>/dev/null)"
  [ -n "$cmd" ] || { printf 'unbounded\tno impact-command is configured to map the change to suites\n'; return 0; }
  tmp="${TMPDIR:-/tmp}/bionic-proof-$$-${RANDOM}"
  lst="$tmp.files"; printf '%s\n' "$files" > "$lst"
  for s in "$wt"/tests/*.test.sh; do [ -f "$s" ] && printf '%s\n' "${s##*/}"; done > "$tmp.roster"
  roster="$(awk 'END { print NR + 0 }' "$tmp.roster")"
  if [ "${roster:-0}" -eq 0 ]; then
    rm -f "$lst" "$tmp.roster"
    printf 'unbounded\tthe working checkout has no suite roster (tests/*.test.sh) to count against\n'; return 0
  fi

  # THE MAP, BOUNDED THE WAY brief.sh BOUNDS ITS DERIVATION, ONE BOUND FOR EVERY CALL BELOW.
  # It runs in the working checkout, so a file the change added is a file the map can see.
  SECONDS=0
  # The files split one per line, a path with a space whole; the COMMAND is configuration and
  # splits on blanks, as brief.sh runs it. Globbing is off for the split and restored after.
  case "$-" in *f*) nog=1 ;; *) nog=0 ;; esac
  set -f; IFS='
'
  # shellcheck disable=SC2086
  set -- $files
  unset IFS; [ "$nog" -eq 1 ] || set +f
  _proof_map "$wt" "$cmd" "$tmp.out" "$@"; rc=$?
  # THE JOINT ANSWER, THEN EACH FILE IT LEFT UNNAMED, ALONE, IN TABLE ORDER. A line is
  # `<suite><TAB><reason>:<file>`; a file is named when a line for a suite the checkout holds
  # names it after the reason. The first file whose own answer names no such suite is the reason.
  if [ "$rc" -eq 0 ]; then
    _proof_named "$tmp.roster" "$tmp.out" > "$tmp.named"
    ans="$(awk 'FILENAME == ARGV[1] { got[$0] = 1; next } $0 != "" && !($0 in got)' \
      "$tmp.named" "$lst" 2>/dev/null)"
    while [ -n "$ans" ]; do
      f="${ans%%$'\n'*}"
      case "$ans" in *$'\n'*) ans="${ans#*$'\n'}" ;; *) ans="" ;; esac
      _proof_map "$wt" "$cmd" "$tmp.one" "$f"; rc=$?
      [ "$rc" -eq 0 ] || break
      if [ -z "$(_proof_named "$tmp.roster" "$tmp.one")" ]; then
        rm -f "$tmp.out" "$tmp.one" "$tmp.named" "$tmp.roster" "$lst"
        printf 'unbounded\tthe map answers %s with no suite\n' "$f"; return 0
      fi
      cat "$tmp.one" >> "$tmp.out"
    done
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp.out" "$tmp.one" "$tmp.named" "$tmp.roster" "$lst"
    if [ "${_PROOF_MAP_OVER:-0}" -eq 1 ]; then
      printf 'unbounded\tthe map overran its %s s bound\n' "${IMPACT_BOUND_S:-10}"; return 0
    fi
    printf 'unbounded\tthe map failed (exit %s)\n' "$rc"; return 0
  fi
  # THE SUITES: those the checkout holds, once each, sorted; or every suite.
  ans="$(awk -F'\t' 'FILENAME == ARGV[1] { have[$0] = 1; next } ($1 in have) { print $1 }' \
    "$tmp.roster" "$tmp.out" 2>/dev/null | sort -u)"
  rm -f "$tmp.out" "$tmp.one" "$tmp.named" "$tmp.roster" "$lst"
  [ -n "$ans" ] || { printf 'unbounded\tthe map gave no answer\n'; return 0; }
  s="$(printf '%s\n' "$ans" | awk 'END { print NR + 0 }')"
  if [ "$s" -ge "$roster" ]; then
    printf 'unbounded\tthe map answers the change with every suite (%s of %s)\n' "$s" "$roster"; return 0
  fi
  printf 'bounded\t%s\n' "$(printf '%s\n' "$ans" | tr '\n' ' ' | sed 's/ $//')"
}

# facts_owed <rigor> <scale> [<tree>] [<plan>] -> one line per fact a run owes, exit 0; nothing and
# exit 1 when <rigor> is not one PROOF_DEALING knows or <scale> is not task, wave or epic (wave-27
# T9; D2):
#
#     floor                                          the full run, proof_state's question
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
  local owed d lvl k r=""
  # THE WORD IS READ AS ITS LEVEL (wave-28 T44; REQ-16, D35, A-orch-7). The dealing stays keyed by
  # the words it was written in; the plan's word and each key are both read through lib/run.sh
  # `rigor_level`, so `high` is dealt what `audited` is, and a word that is no level deals nothing.
  # A copy of this file read where run.sh is not beside it (a suite's doctored copy) reads the word
  # as written, which is what every caller got before the levels existed.
  declare -F rigor_level >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/run.sh" >/dev/null 2>&1
  if ! declare -F rigor_level >/dev/null 2>&1; then
    r="${1:-}"
  elif lvl="$(rigor_level "${1:-}" 2>/dev/null)"; then
    for k in $PROOF_DEALING; do [ "$(rigor_level "${k%%=*}" 2>/dev/null)" = "$lvl" ] && r="${k%%=*}"; done
  fi
  owed="$(PROOF_D="$PROOF_DEALING" PROOF_Q="$PROOF_QUESTIONS" PROOF_C="$PROOF_CODE_QUESTIONS" awk -v r="$r" -v s="${2:-}" '
    BEGIN {
      if (s != "task" && s != "wave" && s != "epic") exit 1
      n = split(ENVIRON["PROOF_D"], d, " ")
      for (i = 1; i <= n; i++) if (r != "" && index(d[i], r "=") == 1) roles = substr(d[i], length(r) + 2)
      if (roles == "") exit 1
      m = split(ENVIRON["PROOF_Q"], q, " "); split(roles, role, ",")
      print "floor"
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
# or a floor proof, dated after the red landing and after the token cleared, and absent otherwise
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
# <head>, or every commit past it touches only the docs root (covered code is every tracked path
# outside it). A waiver covers its question up to its own head.
# Every line of the question counts, failing ones included: a later reading may start at a failing
# reading's head, so the chain is not rebuilt by skipping them, and only the newest decides failing.
# THE WHOLE READ (D10), owed once per code question at wave scale, is covered by a non-failing
# `scope=whole` reading, or a waiver newer than the newest such reading. Code landed after it is the
# piece chain's to cover, so a whole line is covered, failing or absent, never uncovered. A proof
# line carries no range start, so what a whole reading read is the verb's to hold: it refuses one
# whose range starts after the plan's base-sha (row T41), and the judge takes the line as written.
# THE FLOOR is proof_state's answer, unchanged: `covered` or `bounded` is covered; with no floor
# proof it is absent; anything else is uncovered from the floor proof's head. proof_state judges
# the working checkout's head, so for any other <head> the floor is uncovered from the floor proof's
# head, never covered (T45; review pass 13 F3).
# An owed line this judge has no rule for answers absent (the safe direction).
# A FINDING RE-RATED BY ITS CHECK (wave-28 T41; D33): a reading's result is the one its findings give
# at their effective ratings (`_proof_reading_result`), and each open check is one more line that does
# not hold, `finding-check<TAB><record>#<n><TAB>open`.
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
          st="$(proof_state "$plan" "$tree" 2>/dev/null | awk 'NR == 1 { print $1 }')"
          case "$st" in
            covered|bounded) st=covered ;;
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
  # AN OPEN CHECK HOLDS THE STEP (wave-28 T41; D33, AC-8.6): one `finding-check<TAB><record>#<n><TAB>open`
  # line per check the one reader finds open (`proof_checks_open`), after the owed facts.
  while read -r x _; do
    [ -n "$x" ] || continue
    printf 'finding-check\t%s\topen\n' "$x"; rc=1
  done < <(proof_checks_open "$plan" 2>/dev/null)
  return "$rc"
}

# _facts_debt <plan> <tree> <suite> <token> -> `covered`, or `absent` with any reason after a tab, for
# one declared debt (wave-27 T31, T67; D23; A-orch-85, A-orch-120). Covered only when a floor proof, or
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

# _facts_holds <tree> <docs prefix> <last head> <head> -> 0 when <head> is <last head>, or <last
# head> is on its history and every commit past it on <head>'s first-parent line (a merge as what it
# brought in) touches only paths under <docs prefix>, a rename as both its paths. 1 otherwise, and
# whenever git cannot answer: uncovered is the safe direction. Both heads are compared as the
# commits they resolve to, never as strings (T45; review pass 13 F10).
_facts_holds() {
  local tree="$1" pfx="$2" lh hh files
  [ -n "$tree" ] || return 1
  lh="$(git -C "$tree" rev-parse --verify -q "$3^{commit}" 2>/dev/null)" || return 1
  hh="$(git -C "$tree" rev-parse --verify -q "$4^{commit}" 2>/dev/null)" || return 1
  [ "$lh" != "$hh" ] || return 0
  [ -n "$pfx" ] || return 1
  git -C "$tree" merge-base --is-ancestor "$lh" "$hh" 2>/dev/null || return 1
  files="$(git -C "$tree" log --first-parent -m --no-renames --name-only --format= "$lh..$hh" 2>/dev/null)" || return 1
  printf '%s\n' "$files" | awk -v p="$pfx" 'NF && index($0, p) != 1 { bad = 1; exit } END { exit bad }'
}

# _proof_named <roster file> <answer file> -> each file the answer names on a line for a suite
# the roster holds: `<suite><TAB><reason>:<file>`, the file after the reason's first colon.
_proof_named() {
  awk -F'\t' '
    FILENAME == ARGV[1] { have[$0] = 1; next }
    ($1 in have) { p = index($2, ":"); if (p) print substr($2, p + 1) }' "$1" "$2" 2>/dev/null
}

# _proof_map <checkout> <command> <out> <file>... -> the map's exit status, its answer in <out>;
# 124 with _PROOF_MAP_OVER=1 when the bound (IMPACT_BOUND_S, counted on the caller's SECONDS)
# ran out. THE BOUND KILLS THE MAP ITSELF (T52; review 14 N5): the subshell execs the command,
# so the pid the clock watches is the map's own, not a shell that would leave it running. TERM
# first, then KILL after a second for a map that ignores TERM, so the wall never waits on it.
#
# THE FIRST TENTH OF A SECOND IS POLLED FINELY (wave-26 T64). The ready set now asks this on the
# tick and at the turn end, and a map that answers in a few milliseconds waited out a whole 0.1 s
# sleep per call; ten 0.01 s polls come first, then the 0.1 s cadence.
_proof_map() {
  local wt="$1" cmd="$2" out="$3" pid i n=0
  shift 3
  _PROOF_MAP_OVER=0
  (
    cd "$wt" 2>/dev/null || exit 1
    set -f
    # shellcheck disable=SC2086
    exec $cmd "$@" > "$out" 2>/dev/null
  ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 10 ]; do sleep 0.01; n=$((n + 1)); done
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "${IMPACT_BOUND_S:-10}" ]; then
      _PROOF_MAP_OVER=1
      kill -TERM "$pid" 2>/dev/null
      i=0
      while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 0.1; i=$((i + 1)); done
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
  done
  wait "$pid" 2>/dev/null
}
