#!/bin/bash
# payload/scripts/lib/proof.sh — the proof record (epic-23 wave-26 T4; REQ-3, D5).
#
# WHAT IT OWNS. One fact per proof: which commit a test pass or a review read. A proof is a
# line inside the plan's `## SDLC State`:
#
#     proved: kind=<floor|review|task> head=<40-hex> at=<ISO-UTC> evidence=<path under record/>
#
# written only by `session-poker.sh proof-add <kind> <evidence>` through the plan verbs'
# transaction, and read by `proof_last`. A READING (wave-27 T2; D1) is a review proof that adds
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

PROOF_KINDS="floor review task"
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
proof_reading() {
  local rec="$1" q="$2" ck="${3:-}" span got rv rq rr rs ids miss worst
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
  [ -n "$rq" ] || { printf 'the reading %s carries no question: <q> line; write question: %s (only its first pass is read, from its first reviewed: line to the next)' "$rec" "$q"; return 1; }
  proof_word_in "$rq" "$PROOF_QUESTIONS" \
    || { printf 'the reading %s says question: '"'"'%s'"'"', which is not one of evidence, adversarial or structure; write the question it answers' "$rec" "$rq"; return 1; }
  [ "$rq" = "$q" ] \
    || { printf 'the reading %s says question: %s, but the proof is for %s; register it under the question it answers' "$rec" "$rq" "$q"; return 1; }
  [ -n "$rr" ] || { printf 'the reading %s carries no result: line; write result: pass, flag or fail (only its first pass is read, from its first reviewed: line to the next)' "$rec"; return 1; }
  proof_word_in "$rr" "$PROOF_RESULTS" \
    || { printf 'the reading %s says result: '"'"'%s'"'"', which is not one of pass, flag or fail; write the result the reader gave' "$rec" "$rr"; return 1; }
  [ -n "$rs" ] || { printf 'the reading %s carries no scope: line; write scope: piece or whole (only its first pass is read, from its first reviewed: line to the next)' "$rec"; return 1; }
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
  printf '%s %s %s' "$rr" "$rs" "$rv"
}

# proof_word_in <value> <set> -> 0 when <value> is one of the space-separated words of <set>,
# whole: a value holding a space matches no word (wave-27 T41; review pass 10 F2).
proof_word_in() {
  local w
  for w in $2; do [ "$1" = "$w" ] && return 0; done
  return 1
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
#          commit between two review proofs goes unread (wave-26 T62; critic 2 K2-F2). With no
#          <plan>, or a plan whose base names no commit here, the first review is held to the
#          other checks alone. With a <question>, the last review proof is that question's own
#          (wave-27 T2; D1): each question is its own chain, so a reader of one question is never
#          held to where another question's reading ended. A question's first reading on a plan
#          with no base that is a commit here is refused, naming the frontmatter line to add
#          (wave-27 T45; review pass 13 F1).
#   task   whichever of the two the evidence carries, the run header first (A-T14.9).
proof_attested() {
  local kind="$1" ev="$2" co="$3" plan="${4:-}" q="${5:-}" head stamp sha dirty rng a ah b bh since sh what verdict roster
  head="$(git -C "$co" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null)" \
    || { printf 'the checkout %s has no head to hold the evidence against' "$co"; return 1; }
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
      [ -n "$since" ] || { since="$(proof_plan_base "$plan")"; what="the plan's base"; }
      sh=""; [ -n "$since" ] && sh="$(git -C "$co" rev-parse --verify -q "$since^{commit}" 2>/dev/null)"
      # A QUESTION'S FIRST READING NEEDS THE BASE (wave-27 T45; review pass 13 F1). With no base to
      # hold its start, a reading of the last commit alone would stand for every commit before it,
      # and the judge would call the question covered. Nothing is derived in the base's place.
      if [ -n "$q" ] && [ "$what" = "the plan's base" ] && [ -z "$sh" ]; then
        printf 'add base-sha: <the commit the work started from> to the frontmatter of %s: %s, so where the %s chain starts cannot be held, and its first reading is refused' \
          "$plan" "$(if [ -n "$since" ]; then printf 'its base-sha: %s is no commit here' "$since"; else printf 'it names no base-sha:'; fi)" "$q"
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

# proof_plan_base <plan> -> the commit the plan's run started from, as written, or nothing: the
# first `base-sha:` inside its unfenced `## SDLC State` (the Step-4 block `current 4` fills), then
# the frontmatter key of the same name. The first review proof starts at or before it (K2-F2).
proof_plan_base() {
  [ -f "$1" ] || return 0
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { fm = 0; next }
    fm && /^base-sha[ \t]*:/ { if (f == "") { f = $0; sub(/^base-sha[ \t]*:[ \t]*/, "", f); sub(/[ \t].*$/, "", f); gsub(/["\047]/, "", f) } next }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    insdlc && /^[ \t]*base-sha[ \t]*:/ { v = $0; sub(/^[ \t]*base-sha[ \t]*:[ \t]*/, "", v); sub(/[ \t].*$/, "", v); print v; done = 1; exit }
    END { if (!done && f != "") print f }' "$1"
}

# proof_awk -> the awk function `proof_fields(s)`, THE ONE READING OF A PROOF LINE (wave-26 T14;
# review 7 F6): 1 when <s> is a proof line, its kind in PROOF_KIND and its head in PROOF_HEAD; a
# reading's four fields in PROOF_QUESTION, PROOF_READER, PROOF_RESULT and PROOF_SCOPE, each empty
# on a line that carries none (wave-27 T2).
# A proof line starts `proved:` at the first column (a bulleted `- proved:` is prose, not the
# line the writer writes), and carries `kind=<lower-case word>` and `head=<7 to 40 lower-case
# hex>` among its space-separated fields (`head=none` is no head). `proof_last` and the
# readiness program (units.sh) both read through it, so a line one counts the other counts.
proof_awk() {
  printf '%s' '
    function proof_fields(s,   f, m, i) {
      PROOF_KIND = ""; PROOF_HEAD = ""; PROOF_QUESTION = ""; PROOF_READER = ""; PROOF_RESULT = ""; PROOF_SCOPE = ""
      if (s !~ /^proved:[ \t]/) return 0
      m = split(s, f, /[ \t]+/)
      for (i = 2; i <= m; i++) {
        if (f[i] ~ /^kind=/) PROOF_KIND = substr(f[i], 6)
        else if (f[i] ~ /^head=/) PROOF_HEAD = substr(f[i], 6)
        else if (f[i] ~ /^question=/) PROOF_QUESTION = substr(f[i], 10)
        else if (f[i] ~ /^reader=/) PROOF_READER = substr(f[i], 8)
        else if (f[i] ~ /^result=/) PROOF_RESULT = substr(f[i], 8)
        else if (f[i] ~ /^scope=/) PROOF_SCOPE = substr(f[i], 7)
      }
      return (PROOF_KIND ~ /^[a-z]+$/ && PROOF_HEAD ~ /^[0-9a-f]+$/ && length(PROOF_HEAD) >= 7 && length(PROOF_HEAD) <= 40)
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
# reads "newer" as "later in the section".
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
    insdlc && /^(proved|waived):[[:space:]]/ { lastp = NR }
    insdlc && /[^[:space:]]/ { lastn = NR }
    END {
      if (!seen) exit 1
      at = lastp ? lastp : lastn
      for (i = 1; i <= NR; i++) { print row[i]; if (i == at) print L }
    }' "$plan"
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
  if ! declare -F config_value >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$d/roots.sh" >/dev/null 2>&1
  fi
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

# facts_owed <rigor> <scale> -> one line per fact a run owes, exit 0; nothing and exit 1 when
# <rigor> is not one PROOF_DEALING knows or <scale> is not task, wave or epic (wave-27 T9; D2):
#
#     floor                                          the full run, proof_state's question
#     review<TAB><question><TAB><role><TAB>piece     each question, for the role the rigor deals it
#     review<TAB><question><TAB><role><TAB>whole     at scale: wave, one more per code question (D10)
#
# THE ONE DEALING. The judge below reads it, and the dispatch wall (row T15) reads it for the
# questions a reader's brief may name; neither restates the table.
facts_owed() {
  PROOF_D="$PROOF_DEALING" PROOF_Q="$PROOF_QUESTIONS" PROOF_C="$PROOF_CODE_QUESTIONS" awk -v r="${1:-}" -v s="${2:-}" '
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
  owed="$(facts_owed "$rigor" "$scale")" || {
    printf 'facts_state: %s declares no rigor and scale the dealing knows (rigor: %s, scale: %s)\n' \
      "$plan" "${rigor:-none}" "${scale:-none}" >&2
    return 2
  }
  tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  # THE HEAD AND THE BASE ARE COMMITS (wave-27 T45; review pass 13 F1, F10), or nothing is judged.
  x=""; [ -n "$tree" ] && [ -n "$head" ] && x="$(git -C "$tree" rev-parse --verify -q "$head^{commit}" 2>/dev/null)"
  [ -n "$x" ] || { printf 'facts_state: the head %s is no commit here\n' "${head:-(none)}" >&2; return 2; }
  head="$x"
  case "$owed" in
    review"	"*|*"
review	"*)
      x="$(proof_plan_base "$plan")"
      if [ -z "$x" ] || ! git -C "$tree" rev-parse --verify -q "$x^{commit}" >/dev/null 2>&1; then
        printf 'facts_state: %s names no base-sha: that is a commit here, so where its chains start cannot be held\n' "$plan" >&2
        return 2
      fi ;;
  esac
  pfx=""
  if [ -n "$tree" ] && declare -F docs_root >/dev/null 2>&1; then
    droot="$(docs_root "$tree" 2>/dev/null)"
    case "$droot" in "$tree"/?*) pfx="${droot#"$tree"/}"; pfx="${pfx%/}/" ;; esac
  fi
  chains="$(awk -v qs="$PROOF_QUESTIONS" "$(proof_awk)"'
    function evid(s,   f, m, i) { m = split(s, f, /[ \t]+/); for (i = 2; i <= m; i++) if (f[i] ~ /^evidence=/) return substr(f[i], 10); return "" }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]/ { insdlc = ($0 ~ /^##[[:space:]]+SDLC State/); next }
    !insdlc { next }
    proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      q = PROOF_QUESTION; pt[q] = "fact"; pr[q] = PROOF_RESULT; ph[q] = PROOF_HEAD; pe[q] = evid($0)
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
        if [ "$scope" = whole ]; then
          if [ -z "$wt" ]; then st=absent
          elif [ "$wt" = fact ] && [ "$wr" = fail ]; then st="failing	$we"
          else st=covered; fi
        elif [ -z "$pt" ]; then st=absent
        elif [ "$pt" = fact ] && [ "$pr" = fail ]; then st="failing	$pe"
        elif _facts_holds "$tree" "$pfx" "$ph" "$head"; then st=covered
        else st="uncovered	$ph..$head"
        fi ;;
      *) st=absent ;;
    esac
    printf '%s\t%s\n' "$fact" "$st"
    [ "$st" = covered ] || rc=1
  done <<PROOF_FACTS
$owed
PROOF_FACTS
  return "$rc"
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
