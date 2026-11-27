#!/bin/bash
# payload/scripts/lib/proof.sh — the proof record (epic-23 wave-26 T4; REQ-3, D5).
#
# WHAT IT OWNS. One fact per proof: which commit a test pass or a review read. A proof is one event in the run's log,
#
#     run/v1|ev=proof|kind=<regression|review|task|check|walk|inherited|point>|head=<40-hex>|evidence=<path under record/>|…|at=
#
# appended by `proof_event` alone, and read through the reader's facts (`proof_last`). A `check`
# is written only by `session-poker.sh release-check`, the verb that runs the project's declared command, and its
# evidence is that verb's log. A READING is a review proof that adds four fields,
# `question=<q> reader=<roster name> result=<pass|flag|fail> scope=<piece|whole>`, written by
# `proof-add review <record> --question <q> --reader <name>`; every reader keyed by kind alone reads it as the review
# proof it is. What is unproved is the difference since the head a
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

# THE REGRESSION IS KIND `regression` (wave-38 T8; REQ-9, D6). A line 1.20.0 wrote, `kind=floor`, is read as it:
# the one reading of a proof's fields (`proof_take`) normalises the kind through lib/alias.sh, the one map of the old spellings.
# A WHOLE-RUN POINT'S RUN IS KIND `point`, carrying `point=<row>`: a run among the build, never the head's proof, so no
# reader of the regression reads it.
PROOF_KINDS="regression review task check walk point"
# Every library below is loaded once through lib/loader.sh `bionic_need`; a caller that sourced this file alone gets
# the loader from beside it.
# shellcheck source=/dev/null
declare -F bionic_need >/dev/null 2>&1 || case "${BASH_SOURCE[0]}" in */*) . "${BASH_SOURCE[0]%/*}/loader.sh" ;; *) . ./loader.sh ;; esac
# THE MAP IS SOURCED SOFTLY: a copy of this file read where alias.sh cannot be found (a suite's doctored copy) reads
# only the new spellings, and _proof_alias_norm and _proof_alias_born say so by writing no arm.
bionic_need alias.sh alias_read
# _proof_alias_norm <kind> <awk variable> -> lib/alias.sh `alias_awk_norm`'s statements, or a blank when the map is
# not loaded. _proof_alias_born -> the born marker's spellings as an ERE alternation, the new one alone without it.
_proof_alias_norm() { if declare -F alias_awk_norm >/dev/null 2>&1; then alias_awk_norm "$@"; else printf ' '; fi; }
_proof_alias_born() { if declare -F alias_alt >/dev/null 2>&1; then alias_alt born; else printf 'regression'; fi; }
# THE KIND'S STATEMENTS ARE WRITTEN ONCE, AT LOAD: `proof_take` is pasted into every proof reader, so it costs no process.
_PROOF_KIND_NORM="$(_proof_alias_norm kind PROOF_KIND)"
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
# THE DEBT TABLE'S KINDS are lib/debt.sh's, read where they are used so the reader's kinds and the debt line's
# grammar are one list, in the order the table in payload/context/severity.md lists them.
bionic_need debt.sh debt_line_ok
PROOF_DEBT_KINDS="${DEBT_TABLE_KINDS-}"

# proof_kind_ok <kind> -> 0 when <kind> is one of PROOF_KINDS.
proof_kind_ok() {
  case " $PROOF_KINDS " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac
}

# proof_question_ok <question> [waive] -> 0 when <question> is one of PROOF_QUESTIONS. In the waive mode it also takes
# `all`, the word `session-poker.sh waive` records the user's word for all three by; proof-add asks without the mode.
proof_question_ok() {
  local qs="$PROOF_QUESTIONS"
  [ "${2:-}" != waive ] || qs="$qs all"
  case " $qs " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac
}

# proof_line <kind> <head> <at> <evidence> [<question> <reader> <result> <scope>] -> a proof as a `proved:` line,
# newline-terminated; a reading's four fields follow the evidence when a question is given.
# No verb writes it: a proof is an event (`proof_event`), and this shape is kept for the suites, which build a proof's
# event from what it prints.
proof_line() {
  if [ -n "${5:-}" ]; then
    printf 'proved: kind=%s head=%s at=%s evidence=%s question=%s reader=%s result=%s scope=%s\n' \
      "$1" "$2" "$3" "$4" "$5" "${6:-}" "${7:-}" "${8:-}"
  else
    printf 'proved: kind=%s head=%s at=%s evidence=%s\n' "$1" "$2" "$3" "$4"
  fi
}

# proof_floor_line <head> <at> <evidence> [<owed>] [<run>] -> the floor's proof line, newline-terminated: proof_line's,
# and ` owed=<suite>[,<suite>]` after the evidence when the whole run it cites left suites red (wave-35 T9; D8,
# AC-1.3). THE REDS RIDE ON THE LINE: `proof-add floor` writes what `proof_floor_owed` read from the log it
# judged, and the judge (`_proof_floor_judge`) reads the field, never the log again, so a floor line with no
# `owed=` is a green whole run's, as every line written before 1.18.0 is. THE LINE NAMES THE RUN IT READ (wave-37 T4;
# AC-6.2): <run>, `run=<at> head=<sha> rc=<n>` from `proof_floor_run`, ends it.
proof_floor_line() {
  local l
  if [ -n "${4:-}" ]; then
    l="$(printf 'proved: kind=regression head=%s at=%s evidence=%s owed=%s' "$1" "$2" "$3" "$4")"
  else
    l="$(proof_line regression "$1" "$2" "$3")"
  fi
  printf '%s%s\n' "$l" "${5:+ $5}"
}

# _proof_log_awk <awk args> -> awk, reading bytes. A run's log holds whatever its suites printed, and a failing suite can print a
# byte that is no character; in a UTF-8 locale awk stops at such a byte, and these readers hide its error, so a red run read as
# naming no failed suite. THE ONE PLACE THE LOG READERS ASK FOR BYTES (`proof_floor_owed`, `proof_run_counts`,
# `_proof_floor_ends`, the verdict and count reads of `_proof_floor_log` and `proof_attested`, `proof_regression_results`): every
# pattern they match is ASCII or a whole multibyte literal compared as bytes, so reading bytes changes no verdict.
_proof_log_awk() { LC_ALL=C awk "$@"; }

# proof_floor_owed <whole-run log> -> the suites the log's LAST run left red, comma-joined on one line, each
# by its file name (wave-35 T9; D8, AC-1.3); nothing for a green run. Read from the runner's own `Failed:`
# block (tests/run.sh), the lines `    - <suite>[ (<why>)]` after the last `Gating:` verdict that follows the
# last `head=<sha> dirty=<n>` header, so a log with an earlier run in it is judged by its last. A LOG THAT ENDS
# `rc=0` OWES NOTHING (wave-36 T35; AC-7.10): its run passed, whatever a block above its close says.
proof_floor_owed() {
  _proof_log_awk '
    NF { last = $0 }
    /^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { seen = 1; o = ""; inf = 0; next }
    !seen { next }
    /^Gating: [0-9]+ passed, [0-9]+ failed$/ { o = ""; inf = 0; v = 1; next }
    v && $0 == "Failed:" { inf = 1; next }
    inf && /^    - [^ ]/ { s = substr($0, 7); sub(/ .*$/, "", s); sub(/.*\//, "", s); o = o (o == "" ? "" : ",") s; next }
    inf { inf = 0 }
    END { if (o != "" && last !~ /^rc=0[ \t\r]*$/) print o }' "${1:-/dev/null}" 2>/dev/null
}

# proof_run_counts <log> -> `<passed> <total>` from the last `Gating: <n> passed, <m> failed` verdict after the log's last
# `head=` header, as the floor's own reader takes it (the task-proof attest); nothing when the log has none,
# for a project's own runner need not print one.
proof_run_counts() {
  _proof_log_awk '/^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { seen = 1; v = 0; next }
    !seen { next }
    /^Gating: [0-9]+ passed, [0-9]+ failed$/ { p = $2; f = $4; v = 1 }
    END { if (v) print p, p + f }' "$1" 2>/dev/null
}

# proof_inherited_lines <plan> -> each inherited suite of the plan's run, one `inherited: <suite> base=<sha> head=<sha>
# at=<ISO-UTC> evidence=<log>` line each: THE ONE READER of inherited debt, written by
# `session-poker.sh proof-add inherited <suite>` once the suite ran red at the base, as a `proof kind=inherited` event,
# kept whole beside the fold (`_proof_facts`): two suites at one regression head are two debts. The judge reads their suites
# (`proof_inherited`); close-out carries the lines into the continuation. Exit 2 when the run's facts cannot be read.
proof_inherited_lines() {
  [ -f "${1:-}" ] || return 0
  _proof_facts "$1" >/dev/null || return 2
  printf '%s' "$_PROOF_INHERITED" | awk -F'|' "$_LINE_FIELDS_AWK"'
    line_kv("suite") != "" { printf "inherited: %s base=%s head=%s at=%s evidence=%s\n", line_kv("suite"), line_kv("base"), line_kv("head"), line_kv("at"), line_kv("evidence") }'
}

# proof_inherited <plan> -> the suites the plan carries as inherited debt, comma-joined on one line, each once by
# its file name, read off `proof_inherited_lines`. The floor's judge owes nothing for a suite named here, and
# stands on the rest. Exit 2 when the run's facts cannot be read.
proof_inherited() {
  local l
  l="$(proof_inherited_lines "${1:-}")" || return 2
  [ -n "$l" ] || return 0
  printf '%s\n' "$l" | awk '
    { split($0, w, /[ \t]+/); s = w[2]; sub(/.*\//, "", s)
      if (!(s in seen)) { seen[s] = 1; o = o (o == "" ? "" : ",") s } }
    END { if (o != "") print o }'
}

# proof_approved <plan> <name> -> 0 when an approval of <name> stands for the plan's run, the user's act
# `session-poker.sh approve <name>` writes, as the reader holds it (`reader approved`); 1 otherwise.
proof_approved() {
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 1
  _proof_ask "$1" reader_q_approved "$1" "$2" >/dev/null
}

# proof_approved_head <plan> <name> -> the 40-hex head the standing approval of <name> records (`head=`), exit 0;
# nothing, exit 1, with no such approval or one that names no head; exit 2 when the run's facts could not be read. The
# approve verb writes it (the working branch's head at the user's reply); `current 8` reads it for the release. An
# approval of a name stands once: a later one replaces it, so its head is the newest. Every caller acts on the head it
# answers (publish, the release's render, the advance to 8, the close), so it reads the log, never the kept facts;
# `_proof_approved_head` is the same read in the caller's mode, for the judge, which the tick asks too.
proof_approved_head() { local _PROOF_FRESH=1; _proof_approved_head "$@"; }
_proof_approved_head() {
  local facts
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 1
  proof_facts_at "$1" || return 2
  _proof_facts_awk -F'|' -v n="$2" "$(proof_fact_awk)"'
    ev() == "approval" && line_kv("key") == n { h = line_kv("head") }
    END { if (h !~ /^[0-9a-f]+$/ || length(h) != 40) exit 1; print h }'
}

# proof_approval_lines <plan> -> each standing approval, one line each,
# `approved: <name> by <who> <at>`, in the order the facts were last set; exit 2 when the run's facts could not be read. A
# declared red's debt on approval:<name> clears after that instant, read here alone: a name approved twice is read at its
# later approval, the one that stands.
proof_approval_lines() {
  local facts
  proof_facts_at "${1:-}" || return 2
  _proof_facts_awk -F'|' "$(proof_fact_awk)"'
    ev() == "approval" && line_kv("key") != "" { print "approved: " line_kv("key") " by " line_kv("by") " " line_kv("at") }'
}

# proof_waiver_line <question> <head> <who> <at> <reason> -> a waiver as a `waived:` line,
# newline-terminated. No verb writes it: the waiver is an event (`proof_waiver_event`), and this shape is kept for the
# suites, which build a waiver's event from what it prints.
proof_waiver_line() {
  printf 'waived: question=%s head=%s by %s %s "%s"\n' "$1" "$2" "$3" "$4" "$5"
}

# THE RUN'S LOG HOLDS A WAIVER AND A FINDING. Each is one event appended through the one appender (lib/log.sh
# `log_append`) to the run log the reader joins to the plan (`reader_log`), by one writer each, so no second function
# can write either type:
#
#   waiver   question=<q> head=<sha> by=<who> said=<the reply>
#   finding  ref=<record>#<n> severity=<S> reach=<on|off> to=deferred title=<title>       the registration's deferral
#   finding  ref=<record>#<n> to=<defer|fix> by=<who> words=<words> session=<sid> why=<why> [severity= reach= title=]
#            [stated=<the changelog sentence>]                                            a person's move
#   finding  ref=<record>#<n> to=<fixed|carried> row=<T> by=<who> [landing=<commit>]       a move to a row
#   finding  ref=<record>#<n> [to=<deferred|defer>] stated=<the sentence> by=<who>          a sentence, moving nothing
#
# words, why and stated hold `\` and `"` escaped, as the plan's quoted fields held them. RUN_LOG is set for the one
# call and never exported, so the caller's shell keeps its own. Exit 0 appended; 2 when the plan has no
# record to hold its log, the appender cannot be loaded, or the appender refuses a value (a `|` or a line break); 1
# when the write failed.
_proof_event_load() {  # -> 0 once the reader and the appender are loaded in this shell; 2 when either cannot be
  _proof_reader_load && bionic_need log.sh log_append || return 2
}
proof_waiver_event() {  # <plan> <field>=<value>… -> one waiver event in the plan's run log
  local log
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  shift
  RUN_LOG="$log" log_append waiver "$@"
}
proof_finding_event() {  # <plan> <field>=<value>… -> one finding event in the plan's run log
  local log
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  shift
  RUN_LOG="$log" log_append finding "$@"
}

# THE RUN'S LOG HOLDS A STEP, and this is the type's one writer: the advance calls it, and so does close-out for the
# facts its close gives. A step's evidence is what happened, asked of the event that holds it; only what no other event
# and no header line holds rides on the step's own event, in the fields the reader names for that step
# (lib/reader.sh `reader_step_fields`), so a field no reader asks for is refused unwritten. A caller whose plan has moved
# since it read where its run's log is (the archive moves a plan and never its record) names that log in the plan's
# place: it must be a log that exists, so no directory is made for it. Exits as proof_waiver_event's, and 2 for a step
# this lifecycle has not, a field its step does not carry, or a log named that is not there.
proof_step_event() {  # <plan|its run's log> <step> [<field>=<value>…] -> one step event in that run's log
  local log n="${2:-}" f
  case "$n" in [0-9]|[0-9][ab]) ;; *) return 2 ;; esac
  case "$1" in
    */run.log) [ -f "$1" ] && [ ! -L "$1" ] && _proof_event_load || return 2; log="$1" ;;
    *) _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2 ;;
  esac
  shift 2
  for f in "$@"; do
    case " $(reader_step_fields "$n") " in *" ${f%%=*} "*) ;; *) return 2 ;; esac
  done
  RUN_LOG="$log" log_append step "n=$n" "$@"
}

# THE RUN'S LOG HOLDS AN APPROVAL, and this is the type's one writer: the approve verb calls it for the plan's approval
# (key step3), a criterion a person confirms, and any other name.
# Its fields are `by=<who> [head=<sha>] said=<the reply>`;
# nothing writes an approval into a plan. Exits as
# proof_waiver_event's, and 2 for a key that is not one name.
proof_approval_event() {  # <plan> <key> [<field>=<value>…] -> one approval event in the plan's run log
  local log k="${2:-}"
  case "$k" in ''|*[!A-Za-z0-9._-]*) return 2 ;; esac
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  shift 2
  RUN_LOG="$log" log_append approval "key=$k" "$@"
}

# THE RUN'S LOG HOLDS A SESSION'S FACTS, one writer for each type, and no plan line is written for any of them. Exits as
# proof_waiver_event's, and 2 for a value its type does not take.
proof_order_event() {  # <plan> <given|lifted> <the user's words> -> one order event in the plan's run log
  local log
  case "${2:-}" in given|lifted) ;; *) return 2 ;; esac
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  RUN_LOG="$log" log_append order "act=$2" "said=${3:-}"
}
proof_handoff_event() {  # <plan> <the handoff file, project-root-relative> -> one handoff event in the plan's run log
  local log
  [ -n "${2:-}" ] || return 2
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  RUN_LOG="$log" log_append handoff "path=$2"
}
proof_bind_event() {  # <plan> <session id> <engage|bind|write> -> one bind event in the plan's run log
  local log
  case "${2:-}" in ''|unknown|*[!A-Za-z0-9_-]*) return 2 ;; esac
  case "${3:-}" in engage|bind|write) ;; *) return 2 ;; esac
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  RUN_LOG="$log" log_append bind "session=$2" "by=$3"
}

# THE RUN'S LOG HOLDS A DECISION'S ROUND, and this is the type's one writer: the decisions verb's put and its ruling,
# however the ruling arrives, call it. Its fields are:
#
#   decision  entry=Δ<k> d=D<n> verb=put by=<who> title=<title> [wait=<the wait line>]
#   decision  entry=Δ<k> d=D<n> verb=ruled said=<the reply> by=<who> [title=<title>]
#
# entry= numbers the round one past the highest the reader holds for the run, so two
# rounds in the same words are two facts. Exits as proof_waiver_event's.
proof_decision_event() {  # <plan> <field>=<value>… -> one decision round in the plan's run log
  local log k
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" && k="$(_proof_ask "$1" reader_q_ledger "$1")" || return 2
  k="$(printf '%s\n' "$k" | awk -F'|' "$_READER_AWK"'{ e = line_kv("entry"); sub(/^Δ/, "", e); if (e ~ /^[0-9]+$/ && e + 1 > n) n = e + 1 } END { print n + 0 }')"
  shift
  RUN_LOG="$log" log_append decision "entry=Δ$k" "$@"
}

# A STEP A DRY JUDGMENT ASKS ABOUT stands last in the facts of that judgment and nowhere else. The advance runs the
# commit gate on the plan itself under its own session, `planverb-<pid>`, with the step it moves to in BIONIC_DRY_STEP;
# close-out judges the plan under `closeout-preflight-<pid>` before its acts, with the facts those acts will write on the
# same channel, one per line after the step: the step's own fields on its line (`8|cleanup=done|…`), then the landing of
# each row it lands (`published|row=<id>|…|kind=close|by=close-out`) and each tree it removes (`tree|row=<id>|path=`).
# Those three kinds are the whole list: an approval, a proof, a waiver or a finding is what a person or a reviewer gives,
# and a pending line of any other shape fails the fold, so a judgment never stands on one. Any other session's commit
# is judged on what its log holds, whatever its environment carries, since a variable anyone can set must never move a
# gate. What is pending is folded in after the facts, never held and never appended.
_PROOF_DRY=""; _PROOF_DRY_SID="-"; _PROOF_DRY_BAD=""
_proof_dry_step() {  # -> _PROOF_DRY set to the pending lines, empty when the session judged names none; _PROOF_DRY_BAD saying why they are refused
  local first rest l n f row path kind by dry IFS=$' \t\n'
  local -a w
  [ "$_PROOF_DRY_SID" != "${BIONIC_SID:-}" ] || return 0
  _PROOF_DRY_SID="${BIONIC_SID:-}"; _PROOF_DRY=""; _PROOF_DRY_BAD=""
  case "$_PROOF_DRY_SID" in planverb-*|closeout-preflight-*) ;; *) return 0 ;; esac
  case "${_PROOF_DRY_SID##*-}" in ''|*[!0-9]*) return 0 ;; esac
  [ -n "${BIONIC_DRY_STEP:-}" ] || return 0
  first="${BIONIC_DRY_STEP%%$'\n'*}"; rest=""; [ "$first" = "$BIONIC_DRY_STEP" ] || rest="${BIONIC_DRY_STEP#*$'\n'}"
  IFS='|' read -r -a w <<< "$first"; n="${w[0]}"
  case "$n" in [0-9]|[0-9][ab]) ;; *) _PROOF_DRY_BAD="the pending step '$n' is no step"; return 0 ;; esac
  for f in "${w[@]:1}"; do
    case "$f" in *=*) ;; *) _PROOF_DRY_BAD="the pending step's '$f' is no field"; return 0 ;; esac
    case " $(reader_step_fields "$n") " in *" ${f%%=*} "*) ;; *) _PROOF_DRY_BAD="step $n carries no field ${f%%=*}"; return 0 ;; esac
  done
  dry="run/v1|ev=step|n=$first|at="
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    IFS='|' read -r -a w <<< "$l"; row=""; path="-"; kind=""; by=""
    for f in "${w[@]:1}"; do case "$f" in row=*) row="${f#row=}" ;; path=*) path="${f#path=}" ;; kind=*) kind="${f#kind=}" ;; by=*) by="${f#by=}" ;; esac; done
    case "${w[0]}" in
      published) [ -n "$row" ] && [ "$kind" = close ] && [ "$by" = close-out ] || { _PROOF_DRY_BAD="a pending landing is not one the close makes"; return 0; } ;;
      tree) [ -n "$row" ] && [ -z "$path" ] || { _PROOF_DRY_BAD="a pending tree is not one the close removes"; return 0; } ;;
      *) _PROOF_DRY_BAD="a pending ${w[0]:-line} is no fact the close writes"; return 0 ;;
    esac
    dry="$dry"$'\n'"run/v1|ev=$l|at="
  done <<< "$rest"
  _PROOF_DRY="$dry"
}
_proof_dry_refused() {  # -> 0, one line on stderr, when the pending lines of this judgment are refused
  _proof_dry_step
  [ -n "$_PROOF_DRY_BAD" ] || return 1
  printf '_proof_facts: the facts pending in %s are refused (%s); nothing is judged on them\n' "$_PROOF_DRY_SID" "$_PROOF_DRY_BAD" >&2
}

# THE RUN'S LOG HOLDS A PROOF, whatever it proves, `at=` being the appender's:
#
#   proof  kind=<regression|task|walk> head=<sha> evidence=<path>[,<path>…] [owed=<suites>] [run=<at> rc=<rc>]
#   proof  kind=review head=<sha> evidence=<record> question=<q> reader=<name> result=<r> scope=<s>
#   proof  kind=check head=<sha> evidence=<log> [result=fail]
#   proof  kind=inherited head=<the regression's head> evidence=<log> suite=<suite> base=<sha>
#
# Exits as proof_waiver_event's.
proof_event() {  # <plan> <field>=<value>… -> one proof event in the plan's run log
  local log
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  shift
  RUN_LOG="$log" log_append proof "$@"
}

# A VERB THAT JUDGES ITS PLAN COPY BEFORE IT APPENDS reads its proof as standing: nothing may refuse once the event is
# in, so the copy's matrix and row edits are made, and judged, first. proof_pending <field>=<value>… sets
# _PROOF_PENDING to the event as proof_event will append it, and every read of the facts in this shell folds it in
# last (`_proof_facts`); `proof_pending` with no field clears it. The copy is read through its plan: a copy's own name
# names no record. Exit 2, nothing set, for a field the appender would refuse.
proof_pending() {
  local f l="run/v1|ev=proof"
  _PROOF_PENDING=""
  [ "$#" -gt 0 ] || return 0
  _proof_event_load || return 2
  for f in "$@"; do
    case "$f" in *'|'*|*$'\n'*|*$'\r'*|=*|[!a-z]*) return 2 ;; *=*) l="$l|$f" ;; *) return 2 ;; esac
  done
  _PROOF_PENDING="$l|at=$(_line_now)"
}

# ---------- THE RELEASE'S COVER ----------
#
# A release-set commit (`_proof_release_path`) is covered by a passing release check at its head and its readers
# (`_proof_release_readers`) green there (`_proof_release_proved`), for every question and the regression. The check
# runs no suite, and the set holds files suites read, so the check alone proves nothing a suite would.

# _proof_release_path <path> -> 0 when <path> (relative to the repository root) is in THE RELEASE SET: the release
# row's own files, exactly CHANGELOG.md, payload/.claude-plugin/plugin.json, payload/commands/*.md,
# payload/integrity/rendered.sha256, the check suite tests/release-check.test.sh, and the promoted records
# docs/adrs/*.md. A folder's files are one level deep: a deeper path is not in it. THIS CASE IS THE ONE LIST. A commit
# whose every path is in it is covered by a passing release check and its readers green at its head
# (`_proof_release_proved`): the review walk's `release` basis (`_facts_basis`) reads it. One path outside it and the
# commit owes.
_proof_release_path() {
  case "$1" in
    CHANGELOG.md|payload/.claude-plugin/plugin.json|payload/integrity/rendered.sha256|tests/release-check.test.sh) return 0 ;;
    payload/commands/*/*|docs/adrs/*/*) return 1 ;;
    payload/commands/?*.md|docs/adrs/?*.md) return 0 ;;
  esac
  return 1
}

# proof_check_passes <plan> <tree> -> the 40-hex commit of each head at which the run's last check proof passes (carries
# no `result=fail`), one per line, in the order first named; nothing when there is none. A head that is no commit in
# <tree> is not printed. The last check at a head decides it, as facts_state's check arm reads it. Exit 2, nothing
# printed, when the run's facts cannot be read.
proof_check_passes() {
  local plan="${1:-}" tree="${2:-}" h r c pl
  [ -f "$plan" ] && [ -n "$tree" ] || return 0
  pl="$(proof_lines "$plan")" || return 2
  [ -n "$pl" ] || return 0
  printf '%s\n' "$pl" | awk "$(proof_awk)"'
    proof_fields($0) && PROOF_KIND == "check" { print PROOF_HEAD "\t" (PROOF_RESULT == "fail" ? "fail" : "pass") }' \
    | while IFS='	' read -r h r; do
        c="$(git -C "$tree" rev-parse --verify -q "$h^{commit}" 2>/dev/null)" || continue
        printf '%s\t%s\n' "$c" "$r"
      done \
    | awk -F'\t' '{ if (!($1 in r)) k[++n] = $1; r[$1] = $2 } END { for (i = 1; i <= n; i++) if (r[k[i]] == "pass") print k[i] }'
}

# _proof_release_readers -> THE SET'S READERS, the suites that read the release set, one per line, beside the one list
# so a path that gains a reader names it here. release-check.test.sh is in the set itself; shell-lint.test.sh holds
# every suite, that one among them, to its header and the census; render.test.sh reads rendered.sha256 and the command
# pages; commands.test.sh reads the generated version page; words.test.sh reads the command pages.
_proof_release_readers() {
  printf '%s\n' release-check.test.sh shell-lint.test.sh render.test.sh commands.test.sh words.test.sh
}

# _proof_release_proved <plan> <tree> -> the commits of `proof_check_passes`, in its order, at which every reader
# (`_proof_release_readers`) is green in the plan's landing record: its newest `ev=verdict` at the commit, a landing's
# or the whole run's, reads `result=green`. A commit with one reader absent or red there is not printed, so its
# release-set change is not read as proved by a check that ran no suite.
_proof_release_proved() {
  _proof_tree_key "${1:-}" "${2:-}" && _proof_derive_ready "$1" || _PROOF_TREE_KEY=""
  _proof_derive _proof_release_proved "$_PROOF_TREE_KEY" _proof_release_made "$@"
}
_proof_release_made() {
  local chk rec
  chk="$(proof_check_passes "${1:-}" "${2:-}")" || return 2
  [ -n "$chk" ] && rec="$(proof_debt_record "$1" "$2" 2>/dev/null)" && _proof_fields && line_held "$rec" || return 0
  { printf '%s\n\034\n' "$chk"; _proof_release_readers; printf '\034\n'; line_lines "$rec"; } | awk -F'|' "$_LINE_FIELDS_AWK"'
    $0 == SUBSEP { part++; next }
    part == 0 { k[++n] = $0; next }
    part == 1 { rd[++m] = $0; next }
    line_ev() == "verdict" { v[line_kv("commit"), line_kv("suite")] = line_kv("result") }
    END { for (i = 1; i <= n; i++) { ok = 1; for (j = 1; j <= m; j++) if (v[k[i], rd[j]] != "green") ok = 0; if (ok) print k[i] } }'
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
  [ -n "$span" ] || { printf 'the review %s carries no reviewed: <a>..<b> line; write the range it read' "$rec"; return 1; }
  # A READING RECORD IS ONE PASS, AND A KEY IS GIVEN ONCE IN IT (wave-27 T45; review pass 16
  # findings 1, 3). A second flush-left `reviewed:` line is a second pass, whatever it holds, so a
  # record of two is refused rather than read from its top; and a pass that states question:,
  # result:, scope: or one check id twice is refused, rather than taken at its first value.
  got="$(awk '/^reviewed:[ \t]/ { n++ } END { print n + 0 }' "$rec" 2>/dev/null)"
  [ "$got" -le 1 ] \
    || { printf 'the review %s holds %s passes (%s flush-left reviewed: lines); a review record holds one pass, so write each pass as a record of its own' "$rec" "$got" "$got"; return 1; }
  got="$(printf '%s\n' "$span" | awk '
    /^(question|result|scope):/ { k = $0; sub(/:.*$/, ":", k); if (seen[k]++) { print k; exit } }
    /^check:[ \t]/ { m = split($0, f, /[ \t]+/); if (m >= 2) { k = "check: " f[2]; if (seen[k]++) { print k; exit } } }')"
  [ -z "$got" ] \
    || { printf 'the review %s gives %s twice in its pass; a key is given once, so keep the line the reviewer meant' "$rec" "$got"; return 1; }
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
  [ -n "$rq" ] || { printf 'the review %s carries no question: <q> line; write question: %s (a review record holds exactly one pass; a second is refused)' "$rec" "$q"; return 1; }
  proof_word_in "$rq" "$PROOF_QUESTIONS" \
    || { printf 'the review %s says question: '"'"'%s'"'"', which is not one of evidence, adversarial or structure; write the question it answers' "$rec" "$rq"; return 1; }
  [ "$rq" = "$q" ] \
    || { printf 'the review %s says question: %s, but the proof is for %s; register it under the question it answers' "$rec" "$rq" "$q"; return 1; }
  [ -n "$rr" ] || { printf 'the review %s carries no result: line; write result: pass, flag or fail (a review record holds exactly one pass; a second is refused)' "$rec"; return 1; }
  proof_word_in "$rr" "$PROOF_RESULTS" \
    || { printf 'the review %s says result: '"'"'%s'"'"', which is not one of pass, flag or fail; write the result the reviewer gave' "$rec" "$rr"; return 1; }
  [ -n "$rs" ] || { printf 'the review %s carries no scope: line; write scope: piece or whole (a review record holds exactly one pass; a second is refused)' "$rec"; return 1; }
  proof_word_in "$rs" "$PROOF_SCOPES" \
    || { printf 'the review %s says scope: '"'"'%s'"'"', which is not one of piece or whole; write the scope the reviewer read' "$rec" "$rs"; return 1; }
  if [ "$q" = structure ]; then
    [ -n "$ck" ] && [ -f "$ck" ] && [ -r "$ck" ] \
      || { printf 'the structure checks file %s cannot be read, so the check ids a structure review answers are unknown; reinstall the plugin' "$ck"; return 1; }
    ids="$(awk '/^- \*\*[a-z][a-z-]*\*\*/ { s = $0; sub(/^- \*\*/, "", s); sub(/\*\*.*$/, "", s); print s }' "$ck" 2>/dev/null)"
    [ -n "$ids" ] \
      || { printf 'the structure checks file %s names no check id (a - **<id>** item); reinstall the plugin' "$ck"; return 1; }
    miss="$(printf '%s\n' "$span" | PROOF_IDS="$ids" PROOF_ANS="$PROOF_CHECK_ANSWERS" awk '
      BEGIN { n = split(ENVIRON["PROOF_ANS"], a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1
              w = split(ENVIRON["PROOF_IDS"], want, "\n") }
      /^check:[ \t]/ { m = split($0, f, /[ \t]+/); if (m >= 4 && (f[3] in ok)) done[f[2]] = 1 }
      END { for (i = 1; i <= w; i++) if (want[i] != "" && !(want[i] in done)) printf "%s%s", (c++ ? " " : ""), want[i] }')"
    [ -z "$miss" ] \
      || { printf 'the structure review %s leaves %s unanswered; write one line check: <id> <answer> <reason> for each, the answer PASS, FLAG, FAIL or n/a' "$rec" "$miss"; return 1; }
    # The first check answering FAIL, else the first answering FLAG: the worst the pass found.
    worst="$(printf '%s\n' "$span" | awk '
      /^check:[ \t]/ { m = split($0, f, /[ \t]+/); if (m < 3) next
                       if (f[3] == "FAIL" && fail == "") fail = f[2] " FAIL"
                       if (f[3] == "FLAG" && flag == "") flag = f[2] " FLAG" }
      END { if (fail != "") print fail; else if (flag != "") print flag }')"
    case "$rr:$worst" in
      pass:?*|flag:*' FAIL')
        printf 'the structure review %s says result: %s beside check: %s; a pass stands beside no FLAG or FAIL check and a flag beside no FAIL, so write the result its checks give' "$rec" "$rr" "$worst"; return 1 ;;
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
          || { printf 'the structure review %s gives check: %s beside no finding to fix; a FAIL check stands beside a finding the table sends to fix and a finding to fix beside a FAIL check, so rate the finding or answer the check to agree' "$rec" "$worst"; return 1; } ;;
        *) [ -z "$ids" ] \
          || { printf 'the structure review %s gives %s to fix beside no FAIL check; a FAIL check stands beside a finding the table sends to fix and a finding to fix beside a FAIL check, so rate the finding or answer the check to agree' "$rec" "$ids"; return 1; } ;;
      esac
    fi
    worst="$(proof_findings_result "$got")"
    [ "$rr" = "$worst" ] \
      || { printf 'the review %s says result: %s, but its findings give %s (a finding to fix gives fail, any other finding flag, none pass); write result: %s' "$rec" "$rr" "$worst" "$worst"; return 1; }
  fi
  printf '%s %s %s' "$rr" "$rs" "$rv"
}

# proof_word_in <value> <set> -> 0 when <value> is one of the space-separated words of <set>,
# whole: a value holding a space matches no word (wave-27 T41; review pass 10 F2).
# Every list this library splits is split on its own separators, never its caller's: a card calls in under a tab.
proof_word_in() {
  local w IFS=$' \t\n'
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
# no `check:` line is written, and one in a plan binds, re-rates and holds nothing.
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
# (`proof_findings_result`). At registration `proof-add` writes a deferral event per finding the table defers
# (`proof_finding_deferrals`); the tick and `release-check` print them with their priority
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
  local c IFS=$' \t\n'
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
  [ -n "$span" ] || { printf 'the review %s carries no reviewed: <a>..<b> line; write the range it read' "$1"; return 1; }
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
    function bad(m) { if (err == "") err = "the review " rec " " m }
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
      if (err == "" && !hf) err = "the review " rec " carries no findings: <n> line, and its reviewer was pushed the severity scale; write findings: <n> and one finding: line per finding (findings: 0 when it found none)"
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

# proof_finding_lines <record path> <proof_findings lines> -> the deferrals as lines,
# newline-terminated: `deferred: <record>#<n> <S> <reach> "<title>"` for each finding the table defers. No verb writes
# them: registration writes each deferral as an event (`proof_finding_deferrals`), and this shape is what proof-add
# reports it registered. A `"` in a title is written `'`.
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
# (`proof_priority`); a move to defer or fix (`_proof_moved_to`) replaces
# the priority alone, so the third word is the one a move changes — except that an S1 is never
# deferred, whoever moved it. A move to fixed (`to=fixed row=<T>`) puts the
# finding on the fix side, as a move to fix does: it reads fix until its row lands green, and then drops out as
# fixed (`proof_fixed`). A caller reads `set -- $(…)`: three words, rated.
proof_finding_rating() {
  local mv
  mv="$(_proof_moved_to "$1" "$2")" || return 2
  _proof_rating_apply "$mv" "$3" "$4"
  printf '%s' "$_PROOF_RATING"
}

# proof_finding_stated <plan> <record>#<n> -> the finding's one changelog sentence, unescaped, nothing when none is given;
# exit 1 when the run never deferred it (the sentence a carry would take is printed all the same), 2 when the fold
# fails. Every event of the finding is read, not its standing fact alone: that is its newest word, and a move written
# after the deferral replaces it without the sentence. The newest sentence given is the one.
proof_finding_stated() {
  local ev l rc
  _proof_findings_load "$1" || return 2; ev="$_PROOF_FINDINGS"
  l="$(printf '%s\n' "$ev" | awk -v id="$2" "$(proof_bind_awk)"'
    proof_bound($0) == id { if (proof_defers($0)) d = 1; v = proof_fkv($0, "stated"); if (v != "") st = v }
    END { print st; exit !d }')"; rc=$?
  [ -z "$l" ] || printf '%s\n' "$l" | sed -e 's/\\\(.\)/\1/g'
  return "$rc"
}

# proof_finding_deferrals <plan> <record path> <proof_findings lines> -> one deferral event in the plan's run log for
# each finding the table defers (`proof_finding_lines`' findings): `finding ref=<record>#<n> severity=<S> reach=<reach>
# to=deferred title=<title>`, a `"` in the title written `'`. Exit as `proof_finding_event`, at the first that fails.
proof_finding_deferrals() {
  local plan="$1" rec="$2" n s r t
  while IFS='	' read -r n s r t; do
    [ -n "$n" ] || continue
    proof_finding_event "$plan" "ref=$rec#$n" "severity=$s" "reach=$r" to=deferred "title=$t" || return
  done <<PROOF_DEFERRALS
$(printf '%s\n' "${3:-}" | awk -F'\t' 'NF >= 7 && $5 == "defer" { t = $7; gsub(/"/, "'"'"'", t); print $1 "\t" $2 "\t" $3 "\t" t }')
PROOF_DEFERRALS
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

# _proof_moved_to <plan> <record>#<n> -> `defer`, `fix` or `fixed`, where the LAST whole move among the run's finding
# events naming it (`_proof_findings_load`, `proof_move_of`) moved the finding, or nothing when there is none
# A later move is the later word, so the last decides. Exit 2 when the fold fails.
_proof_moved_to() {
  local ev
  _proof_findings_load "$1" || return 2; ev="$_PROOF_FINDINGS"
  printf '%s\n' "$ev" | awk -v id="$2" "$(proof_bind_awk)"'
    proof_bound($0) == id { m = proof_move_of($0); if (m != "") to = m }
    END { if (to != "") print to }'
}

# proof_move_line <plan> <record>#<n> -> the finding's newest whole move event, verbatim, the one `_proof_moved_to`
# reads its direction from; nothing when the run holds none. What a refusal quotes when it names the
# move it read: `task-add --born` refuses a finding whose newest move is to defer. Exit 2 when the fold fails.
proof_move_line() {
  local ev
  _proof_findings_load "$1" || return 2; ev="$_PROOF_FINDINGS"
  printf '%s\n' "$ev" | awk -v id="$2" "$(proof_bind_awk)"'
    proof_bound($0) == id && proof_move_of($0) != "" { l = $0 }
    END { if (l != "") print l }'
}

# _proof_moved_fixed <plan> -> `<row><TAB><record>#<n>`, one line per finding whose newest whole move is to fixed
# in the order the findings were first moved; a later move to defer or fix takes the finding back.
# `proof_fixed`'s second source. Exit 2 when the fold fails.
_proof_moved_fixed() {
  local ev
  _proof_findings_load "$1" || return 2; ev="$_PROOF_FINDINGS"
  printf '%s\n' "$ev" | awk "$(proof_bind_awk)"'
    {
      id = proof_bound($0); m = proof_move_of($0)
      if (id == "" || m == "") next
      if (!(id in last)) ord[++n] = id
      last[id] = m; row[id] = proof_move_row($0)
    }
    END { for (i = 1; i <= n; i++) if (last[ord[i]] == "fixed") printf "%s\t%s\n", row[ord[i]], ord[i] }'
}

# proof_findings_owed <plan> -> one line per finding the run has deferred (`proof_defers`: the registration's deferral,
# or a move to defer carrying the rating), in the order first deferred, rated as `proof_finding_rating` rates it, from
# the same events: `<record>#<n> <S> <reach> <fix|defer|note> "<title>"`, the priority the effective rating takes. What
# the tick and `release-check` print, so the priority a record never states is seen where the run is judged. Exit 2
# when the fold fails.
proof_findings_owed() {
  local plan="$1" ev id s r t mv IFS=$' \t\n'
  [ -f "$plan" ] || return 0
  _proof_findings_load "$plan" || return 2; ev="$_PROOF_FINDINGS"
  while IFS=$'\037' read -r id s r t mv; do
    [ -n "$id" ] || continue
    _proof_rating_apply "$mv" "$s" "$r"
    set -- $_PROOF_RATING
    [ $# -ge 3 ] && [ -n "$3" ] || continue
    printf '%s %s %s %s "%s"\n' "$id" "$1" "$2" "$3" "$t"
  done <<PROOF_OWED_FINDINGS
$(printf '%s\n' "$ev" | awk "$(proof_bind_awk)"'
  { id = proof_bound($0) }
  id == "" { next }
  proof_defers($0) && !(id in seen) { seen[id] = 1; ord[++n] = id; sv[id] = proof_fkv($0, "severity"); rc[id] = proof_fkv($0, "reach"); tt[id] = proof_fkv($0, "title") }
  { m = proof_move_of($0); if (m != "") mv[id] = m }
  END { for (i = 1; i <= n; i++) { id = ord[i]; printf "%s\037%s\037%s\037%s\037%s\n", id, sv[id], rc[id], tt[id], mv[id] } }')
PROOF_OWED_FINDINGS
}

# _proof_reading_result <plan> <docs root> <evidence> <written result> -> the reading's result as its
# findings give it at their effective ratings (wave-28 T41; D33): a reading whose record a binding line
# names (`proof_bind_awk`: a finding event keyed to a finding of it) is derived
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
  tab="$(_proof_binding_table "$plan" "$ev")" || { [ "$?" -eq 1 ] || return 2; tab=""; }
  _proof_fixed_var "${7:-}" "$ev" "${5:-}" "${6:-}"
  [ -n "$tab" ] || [ -n "$_PROOF_FIXED_IDS" ] || return 0
  _proof_reading_derive "$droot" "$ev" "$res" "$tab" "$_PROOF_FIXED_IDS"
}

# proof_fixed <plan> [<tree>] -> `<record>#<n><TAB><row><TAB><commit><TAB><born|moved>`, one line per finding a
# fix row answers and has landed green (wave-33 T13; REQ-5 AC-5.2, D6). The row answers the finding in one of
# two ways: it names the finding on its born marker (lib/units.sh `units_born_findings`, which `task-add --born
# <record>#<n>` writes), `born`; or the finding's newest move names it (`to=fixed row=<T>`,
# which `finding-move <record>#<n> fixed <row>` writes; wave-36 T8, D9), `moved`, born marker or none. A
# finding both answer is printed once, as `moved`. Either way the row's `## Tasks` status is `landed`, and the
# run's landing record (`proof_debt_record`, lib/line.sh's events) holds a verdict for it whose commit is the
# row's newest verdict commit and whose every suite there reads `result=green`, the last word per suite.
# <commit> is that commit, the landing the green verdicts name. AN ABSENT SUITE IS NOT OWED (wave-39 T19; A-orch-9):
# a `result=absent` verdict (lib/line.sh, a Lands-on suite the row removed) is neither green nor red, so a landing
# green on the rest is fixed. A LANDING PROOF MAY BE THE REGRESSION (wave-39 T19; REQ-14 AC-14.1, D9): a row whose
# landing owes no verdict (none recorded, a hand landing; or every one absent) is fixed at its landing commit, the
# commit of its last `published` event (`_proof_regression_landing`), once a green regression stands at a head that
# commit is an ancestor of (`_proof_regression_heads`); <commit> is then that landing. A red landing verdict is never
# overridden by a regression. Nothing when no born marker names a finding and
# no move names a row, so a plan without either asks the units library once. Whether <commit> must be at or after a reading's
# head is the reader's to ask (`_proof_fixed_var`): a born row's must, a moved row's need not, since the move
# says the row fixed the finding whatever its ancestry (ADR-056: "a finding fixed before or beside the reading
# is fixed"). RED has no machine record (research-verbs-landing.md G1): the green landing is the proof read.
proof_fixed() {
  [ -f "${1:-}" ] || return 0
  _proof_tree_key "$1" "${2:-}" && _proof_derive_ready "$1" || _PROOF_TREE_KEY=""
  _proof_derive proof_fixed "$_PROOF_TREE_KEY" _proof_fixed_made "$@"
}
_proof_fixed_made() {
  local plan="${1:-}" tree="${2:-}" born moved mf rec out gt="" heads="" lands="" byrow="" k id row c how l
  [ -f "$plan" ] || return 0
  mf="$(_proof_moved_fixed "$plan")" || return 2
  [ -n "$mf" ] || { _proof_units_load && units_born_logged "$plan"; } || return 0
  _proof_units_load || return 0
  declare -F units_born_findings >/dev/null 2>&1 && declare -F units_rows >/dev/null 2>&1 || return 0
  born="$(units_born_findings "$plan" 2>/dev/null | awk -F'\t' '$2 == "landed" { print $1 "\t" $3 "\tborn" }')"
  moved="$({ printf '\034rows\n'; units_rows "$plan" 2>/dev/null; printf '\034moved\n'; printf '%s\n' "$mf"; } | awk -F'\t' '
    $0 == SUBSEP "rows" { part = 1; next }
    $0 == SUBSEP "moved" { part = 2; next }
    part == 1 { if ($10 == "landed") landed[$1] = 1; next }
    part == 2 && ($1 in landed) { print $1 "\t" $2 "\tmoved" }')"
  [ -n "$born" ] || [ -n "$moved" ] || return 0
  rec="$(proof_debt_record "$plan" "$tree")" || return 0
  _proof_fields && line_held "$rec" || return 0
  # Each finding comes out `F` (its row's newest verdict commit owes a suite and every owed suite reads green there:
  # fixed at that commit) or `R` (the row's landing owes no verdict: none recorded, or every one `result=absent`, so
  # the regression arm asks below); a row with a red, or any word but green or absent, is neither.
  out="$({ printf '\034born\n'; [ -z "$moved" ] || printf '%s\n' "$moved"; [ -z "$born" ] || printf '%s\n' "$born"
    printf '\034rec\n'; line_lines "$rec" 2>/dev/null; } | awk -F'|' "$_LINE_FIELDS_AWK"'
    $0 == SUBSEP "born" { part = 1; next }
    $0 == SUBSEP "rec" { part = 2; next }
    part == 1 { split($0, b, "\t"); if (b[2] in seen1) next; seen1[b[2]] = 1; nb++; brow[nb] = b[1]; bid[nb] = b[2]; bhow[nb] = b[3]; want[b[1]] = 1; next }
    part == 2 && line_ev() == "verdict" {
      r = line_kv("row"); if (!(r in want)) next
      c = line_kv("commit"); s = line_kv("suite"); v = line_kv("result")
      if (c == "" || s == "") next
      if (lc[r] != c) { lc[r] = c; ns[r] = 0 }
      if (!((r SUBSEP c SUBSEP s) in seen)) { seen[r, c, s] = 1; ns[r]++; sl[r, ns[r]] = s }
      res[r, s] = v
    }
    END {
      for (r in lc) {
        g = 0; bad = 0
        for (i = 1; i <= ns[r]; i++) { v = res[r, sl[r, i]]; if (v == "green") g++; else if (v != "absent") bad = 1 }
        ok[r] = (g > 0 && !bad); owes[r] = (g > 0 || bad)
      }
      for (i = 1; i <= nb; i++) {
        r = brow[i]
        if ((r in ok) && ok[r]) printf "F\t%s\t%s\t%s\t%s\n", bid[i], r, lc[r], bhow[i]
        else if (!((r in owes) && owes[r])) printf "R\t%s\t%s\t%s\n", bid[i], r, bhow[i]
      }
    }')"
  case $'\n'"$out" in
    *$'\n'R$'\t'*)
      gt="$tree"; [ -n "$gt" ] || gt="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
      heads="$(_proof_regression_heads "$plan" "$rec")" || return 2
      [ -z "$heads" ] || ! declare -F units_landings >/dev/null 2>&1 || lands="$(units_landings "$plan" "$rec" 2>/dev/null)" ;;
  esac
  while IFS='	' read -r k id row c how; do
    case "$k" in
      F) printf '%s\t%s\t%s\t%s\n' "$id" "$row" "$c" "$how" ;;
      R) [ -n "$lands" ] || continue
         case "$byrow" in *" $row="*) l="${byrow#*" $row="}"; l="${l%% *}" ;; *) l="$(_proof_regression_landing "$gt" "$row" "$lands" "$heads")"; byrow="$byrow $row=${l:--}" ;; esac
         [ -n "$l" ] && [ "$l" != - ] || continue
         printf '%s\t%s\t%s\t%s\n' "$id" "$row" "$l" "$c" ;;
    esac
  done <<PROOF_FIXED_OUT
$out
PROOF_FIXED_OUT
}

# _proof_regression_landing <git tree> <row> <units_landings lines> <green regression heads> -> the row's landing commit,
# 40-hex, when one of the heads has it as an ancestor: the `commit=` of the last `published` event that
# names the row (lib/units.sh `units_landings`). Nothing, rc 1, when the row has no landing or no head descends from it.
_proof_regression_landing() {
  local gt="$1" l h
  l="$(printf '%s\n' "$3" | awk -F'\t' -v r="$2" '$1 == r && $2 != "-" { print $2; exit }')"
  [ -n "$l" ] && [ -n "$4" ] && [ -n "$gt" ] || return 1
  l="$(git -C "$gt" rev-parse --verify -q "${l}^{commit}" 2>/dev/null)" || return 1
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    git -C "$gt" merge-base --is-ancestor "$l" "$h" 2>/dev/null || continue
    printf '%s' "$l"; return 0
  done <<PROOF_REG_HEADS
$4
PROOF_REG_HEADS
  return 1
}

# _proof_regression_heads <plan> <landing record> -> the head of each GREEN regression, once each, one per line (wave-39 T19;
# D9): a head whose `kind=regression` facts in the record (`proof_regression_fold`) read, by each suite's last word, one
# green at least and nothing but green or absent; or a regression proof of the run's facts (`proof_lines`) whose run
# left no suite red (`owed=`). A red suite the plan carries as inherited debt (`proof_inherited`) is not counted, as the
# regression's judge does not count it (`_proof_floor_base`). A waiver is the person's word, not a green run: not read.
# Exit 2, nothing printed, when the run's facts cannot be read.
_proof_regression_heads() {
  local inh pl
  _proof_fields || return 0
  inh="$(proof_inherited "$1")" && pl="$(proof_lines "$1")" || return 2
  { printf '\034plan\n'; [ -z "$pl" ] || printf '%s\n' "$pl"
    printf '\034rec\n'; [ -z "${2:-}" ] || line_lines "$2" 2>/dev/null; } \
    | PROOF_I=",$inh," awk -F'|' "$(proof_awk)$_LINE_FIELDS_AWK"'
    function inh(s) { return index(ENVIRON["PROOF_I"], "," s ",") > 0 }
    function clean(o,   n, a, i) { n = split(o, a, ","); for (i = 1; i <= n; i++) if (a[i] != "" && !inh(a[i])) return 0; return 1 }
    function put(h) { if (!(h in out)) { out[h] = 1; print h } }
    $0 == SUBSEP "plan" { part = 1; next }
    $0 == SUBSEP "rec" { part = 2; next }
    part == 1 && proof_fields($0) && PROOF_KIND == "regression" && clean(PROOF_OWED) { put(PROOF_HEAD); next }
    part == 2 && line_ev() == "verdict" && line_kv("kind") == "regression" {
      c = line_kv("commit"); s = line_kv("suite"); v = line_kv("result")
      if (c == "" || s == "") next
      if (!(c in nc)) { nc[c] = 0; co[++nh] = c }
      if (!((c SUBSEP s) in w)) { nc[c]++; su[c, nc[c]] = s }
      w[c, s] = v
    }
    END {
      for (k = 1; k <= nh; k++) {
        c = co[k]; g = 0; bad = 0
        for (i = 1; i <= nc[c]; i++) { s = su[c, i]; v = w[c, s]; if (v == "green") g++; else if (v != "absent" && !inh(s)) bad = 1 }
        if (g > 0 && !bad) put(c)
      }
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

# _proof_binding_table <plan> <record> -> one line per finding of <record> a finding event of the run is keyed to:
# `<record>#<n><TAB><moved to>`, `-` when the run says none (`_proof_moved_to`'s answer, read in one pass); exit 1,
# nothing printed, when no finding event names the record; exit 2 when the fold fails.
_proof_binding_table() {
  local ev
  [ -f "$1" ] || return 1
  _proof_findings_load "$1" || return 2; ev="$_PROOF_FINDINGS"
  printf '%s\n' "$ev" | awk -v rec="$2" "$(proof_bind_awk)"'
    proof_binds($0, rec) {
      hit = 1; id = proof_bound($0); ids[id] = 1
      m = proof_move_of($0); if (m != "") mv[id] = m
    }
    END {
      if (!hit) exit 1
      for (id in ids) print id "\t" (id in mv ? mv[id] : "-")
    }'
}

# _proof_reading_derive <docs root> <evidence> <written result> <binding table> -> in `PROOF_DERIVED`, the
# result <evidence>'s findings give at the ratings the table (`_proof_binding_table`'s lines) says: the one
# derivation, asked once per reading by `_proof_reading_result` and once per bound reading by
# `proof_readings_derived`, which prints it without a fork. A record that cannot be read keeps the
# written result. A fifth operand, `_proof_fixed_var`'s newline-wrapped ids, names the findings a landed
# born row fixed: each drops out, whatever its rating (wave-33 T13; D6).
_proof_reading_derive() {
  local droot="$1" ev="$2" res="$3" fixed="${5:-}" nl tb tab got n s r w mv out="" IFS=$' \t\n'
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
#          <sha> is the checkout's HEAD: a run at any other head proves nothing here.
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
  local kind="$1" ev="$2" co="$3" plan="${4:-}" q="${5:-}" root="${6:-}" head stamp sha dirty rng a ah b bh since sh what verdict IFS=$' \t\n'
  # THE KIND OPERAND IS READ THROUGH THE MAP (wave-38 T8), silently: a caller passing the old kind is the new one.
  declare -F alias_read >/dev/null 2>&1 && { alias_read kind "$kind" 2>/dev/null; kind="$ALIAS_TOKEN"; }
  head="$(git -C "$co" rev-parse --verify -q "${7:-HEAD}^{commit}" 2>/dev/null)" \
    || { printf 'the checkout %s has no head to hold the evidence against' "$co"; return 1; }
  if [ "$kind" = regression ]; then
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
  stamp="$(_proof_log_awk '/^head=([0-9a-f]+|none) dirty=([0-9]+|none)$/ { s = $0 } END { if (s != "") print s }' "$ev" 2>/dev/null)"
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
    verdict="$(_proof_log_awk '
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
      # THE USER'S WAIVER IS A LINK OF THE CHAIN: a waiver of the question later than its last reading holds it up to
      # the head it names, so the next reading starts there (`proof_chain_head`), as the judge's chain does.
      if [ -n "$q" ]; then
        sh="$(proof_chain_head "$plan" "$q")"
        case "$sh" in *" waiver") since="${sh% *}"; what="the user's $q waiver at" ;; esac
      fi
      [ -n "$since" ] || { since="$(proof_plan_base "$plan" "$co")"; what="the plan's base"; }
      sh=""
      if [ -n "$since" ] && { [ "$what" != "the plan's base" ] || proof_base_id "$since"; }; then
        sh="$(git -C "$co" rev-parse --verify -q "$since^{commit}" 2>/dev/null)"
      fi
      # A QUESTION'S FIRST READING NEEDS THE BASE (wave-27 T45; review pass 13 F1). With no base to
      # hold its start, a reading of the last commit alone would stand for every commit before it,
      # and the judge would call the question covered. Nothing is derived in the base's place.
      if [ -n "$q" ] && [ "$what" = "the plan's base" ] && [ -z "$sh" ]; then
        printf 'add base-sha: <the commit the work started from> to the frontmatter of %s: %s, so where the %s chain starts cannot be held, and its first review is refused' \
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
# One spelling each, for the runner's log and for a declared regression's evidence alike.
_proof_read_elsewhere() {  # <evidence> <sha it read> <the working head>
  printf 'the run in %s read head %s, but the working branch is at %s; run it again on %s and cite that log' \
    "$1" "$(printf '%s' "$2" | cut -c1-12)" "$(printf '%s' "$3" | cut -c1-12)" "$(printf '%s' "$3" | cut -c1-12)"
}
_proof_read_dirty() {  # <evidence> <dirty count>
  printf 'the run in %s read a dirty tree (dirty=%s); commit, run it again and cite that log' "$1" "$2"
}

# _proof_records <checkout> [<landing record>] -> THE RECORDS lib/line.sh weighs,
# one tab-separated line each, in the order read (the landing record, then every git dir's stamp file):
#   O <commit> <row> <suites | ->               a published commit and its row's suites
#                                               (`-` for a hand landing whose ready named none: its verdicts are its suites)
#   R <at> <commit> <suite | *> <green | red> <verdict | stamp | regression>   one suite's run at one commit (`*`, a
#                                               whole run); `regression` is a fact the whole run's fold wrote (wave-39 T24;
#                                               D9), a run at its tree but never a landing's, so it closes no owed red
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
  _proof_fields || return 0
  gd=""
  if [ -d "$co" ]; then
    bionic_need root.sh git_common_dir
    gd="$(git_common_dir "$co" 2>/dev/null)"
  fi
  { if [ -n "$rec" ]; then line_lines "$rec"; fi
    if [ -n "$gd" ]; then for f in "$gd/bionic-stamps" "$gd"/worktrees/*/bionic-stamps; do
      [ -f "$f" ] && cat "$f"; done; fi; } 2>/dev/null | awk -F'|' "$_LINE_FIELDS_AWK"'
    function out(l) { lines[++nl] = l }
    function key(p) { sub(/.*\//, "", p); return p }
    function keys(l,   a, n, i, o) { n = split(l, a, ","); o = ""; for (i = 1; i <= n; i++) o = o (i > 1 ? "," : "") key(a[i]); return o }
    (ev = line_ev()) != "" {
      r = line_kv("row")
      if (ev == "ready") { if (r != "") su[r] = keys(line_kv("suites")) }
      else if (ev == "published") { c = line_kv("commit"); x = (r in su) ? su[r] : "-"; if (x == "none") x = "-"; if (c != "") out("O\t" c "\t" r "\t" x) }
      else if (ev == "verdict") {
        c = line_kv("commit"); s = key(line_kv("suite")); v = line_kv("result")
        if (c != "" && s != "" && (v == "green" || v == "red")) { out("R\t" line_kv("at") "\t" c "\t" s "\t" v "\t" (line_kv("kind") == "regression" ? "regression" : "verdict")); if (v == "red") { vc[nl] = c; vs[nl] = s } }
      }
      else if (ev == "candidate") { c = line_kv("commit"); if (c != "") base[c] = line_kv("base") }
      else if (ev == "standing") { if (line_kv("cause") == "environment") env[line_kv("head"), key(line_kv("suite"))] = 1 }
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

# _proof_line_load -> 0 once lib/line.sh is loaded, for `line_event`, the fold's writer.
_proof_line_load() { bionic_need line.sh line_event; }
# _proof_fields -> 0 once lib/line.sh's reader of a record line (`_LINE_FIELDS_AWK`) is loaded: every read of the
# landing record below goes through it, so a field is read by its name and there is no second parser.
_proof_fields() { [ -n "${_LINE_FIELDS_AWK:-}" ] || _proof_line_load; [ -n "${_LINE_FIELDS_AWK:-}" ]; }

# proof_regression_results <whole-run log> -> `<suite><TAB>green|red` for each suite the log's last run judged, in its
# order (wave-39 T24; D9): tests/run.sh's verdict lines (`  <suite>  ✓ PASS`, `✗ FAIL…`, `✗ KILLED…`) after its last
# `Gating suites:` header, outside every captured block (`───── <suite>: … ─────` to `───── end <suite> ─────`). A
# suite the runner refused (`✗ REFUSED`) never ran and has no result.
proof_regression_results() {
  _proof_log_awk '
    index($0, "Gating suites:") == 1 { on = 1; n = 0; split("", r); split("", at); blk = ""; next }
    !on { next }
    index($0, "Gating: ") == 1 { on = 0; next }
    blk != "" { if (index($0, "───── ") == 1 && $2 == "end" && $3 == blk) blk = ""; next }
    index($0, "───── ") == 1 { if ($2 ~ /:$/) blk = substr($2, 1, length($2) - 1); next }
    substr($0, 1, 2) != "  " || NF < 3 || $1 !~ /^[A-Za-z0-9._-]+$/ { next }
    { v = "" }
    index($0, "✓ PASS") { v = "green" }
    index($0, "✗ FAIL") || index($0, "✗ KILLED") { v = "red" }
    v != "" { if (!($1 in r)) at[++n] = $1; r[$1] = v }
    END { for (i = 1; i <= n; i++) print at[i] "\t" r[at[i]] }' "${1:-/dev/null}" 2>/dev/null
}

# proof_regression_fold <plan> <checkout> <head> <whole-run log> <the log as the record names it> -> one `ev=verdict` fact
# per suite the whole run judged, written to the plan's landing record through lib/line.sh `line_verdict_event`:
# `row=regression|commit=<head>|suite=|result=|log=|admitted=-|width=-|kind=regression`, keyed by the commit
# it ran at. A suite with a fact from this log at <head> already is not written again. `_proof_records` reads these as a
# whole run's, never a landing's. Exit 1 when line.sh's writer cannot be loaded. <checkout> is kept for its callers.
proof_regression_fold() {
  local plan="$1" head="$3" log="$4" rel="$5" res rec s r
  _proof_line_load || return 1
  res="$(proof_regression_results "$log")"
  [ -n "$res" ] || return 0
  rec="$(line_record "$plan" 2>/dev/null)" || rec=""
  while IFS='	' read -r s r; do
    [ -n "$s" ] || continue
    [ -z "$rec" ] || ! line_lines "$rec" 2>/dev/null | awk -F'|' -v c="$head" -v su="$s" -v l="$rel" "$_LINE_FIELDS_AWK"'
      line_ev() == "verdict" && line_kv("commit") == c && line_kv("suite") == su && line_kv("log") == l && line_kv("kind") == "regression" { f = 1 }
      END { exit !f }' 2>/dev/null \
      || continue
    line_verdict_event "$plan" "row=regression" "commit=$head" "suite=$s" "result=$r" "log=$rel" "admitted=-" "width=-" \
      "kind=regression" || return 1
  done <<PROOF_FOLD
$res
PROOF_FOLD
}

# _proof_floor_log <evidence> <working head> <checkout> [<plan>] [<root>] -> the 40-hex head the log read, exit 0;
# or exit 1 with the refusal's sentence (wave-36 T35; D13, AC-7.10; the synth-vision filing). THE FLOOR'S ONE
# GRAMMAR. What a project's regression is belongs to the project; the judge asks only that a run of it read a
# clean working head and said how it ended, so it reads two lines of the log the run left and nothing between:
#   the header  the first line that opens `head=`, read as `head=<40-hex> dirty=<n>`: <n> must be 0, and the head
#               the working head. Lines
#               before it (a runner's preamble: tests/run.sh prints `rung=` and `env:` first) are not read.
#   the close   the last line that is not blank, `rc=<n>`: rc=0 is a pass.
# A RED RUN is refused naming its rc, unless the runner's own `Failed:` block names its reds (`proof_floor_owed`),
# as many as its last `Gating:` counts failed: then it is the floor's red candidate, those suites owed (wave-35 T9;
# ADR-054). No tests/*.test.sh roster is counted, no `Gating:` verdict is asked for and no config key is needed,
# so tests/run.sh's log, floor-run's log and the log of a project's own runner are each one such log.
_proof_floor_log() {
  local ev="$1" head="$2" co="$3" plan="${4:-}" root="${5:-}" ends hdr sha dirty rc owed nred m run inh why
  ends="$(_proof_floor_ends "$ev")"; hdr="${ends%%$'\n'*}"; rc="${ends#*$'\n'}"; [ "$ends" != "$hdr" ] || rc=""
  case "$hdr" in
    '') printf 'the evidence %s carries no head=<sha> dirty=<n> line; a regression proof cites the log of a run, which opens with it' "$ev"; return 1 ;;
    'bad head=none dirty=none') printf 'the run in %s read no repository (head=none); run it in the working branch checkout and cite that log' "$ev"; return 1 ;;
    bad\ *) printf 'the run header in %s reads %s, not head=<40-hex> dirty=<n>; cite the log of a run that opens with that line' "$ev" "${hdr#bad }"; return 1 ;;
  esac
  sha="${hdr%% *}"; dirty="${hdr#* }"
  [ "${#sha}" -eq 40 ] || { printf 'the run header in %s names head %s, which is not 40 hex; cite the log of a run that opens with head=<40-hex> dirty=<n>' "$ev" "$sha"; return 1; }
  [ "$dirty" = 0 ] || { _proof_read_dirty "$ev" "$dirty"; return 1; }
  case "$rc" in rc=[0-9]*) rc="${rc#rc=}" ;; *) rc=x ;; esac
  case "$rc" in *[!0-9]*) printf 'the log %s does not end with an rc=<n> line, so it does not say how its run ended; end it with the run'"'"'s exit code (rc=$?) and cite it' "$ev"; return 1 ;; esac
  owed=""
  if [ "$rc" != 0 ]; then
    owed="$(proof_floor_owed "$ev")"
    [ -n "$owed" ] || { printf 'the run in %s ended rc=%s, so the regression did not pass; fix what it names, run it again and cite that log' "$ev" "$rc"; return 1; }
    nred="$(printf '%s\n' "$owed" | awk -F, '{ print NF }')"
    m="$(_proof_log_awk '/^Gating: [0-9]+ passed, [0-9]+ failed$/ { m = $4 } END { print m + 0 }' "$ev" 2>/dev/null)"
    [ "$nred" = "$m" ] || { printf 'the run in %s counts %s failed but its Failed: block names %s; cite the whole log of a full run, as tests/run.sh wrote it' "$ev" "$m" "$nred"; return 1; }
  fi
  # THE LOG IS A RUN THE MACHINE RECORDED (wave-37 T4; D7, AC-6.1; ADR-057): the grammar above is read first, then
  # one `ev=run` line of the plan's landing record must match the log on head, exit and hash (`_proof_floor_match`).
  run="$(_proof_floor_match "$ev" "$plan" "$root" "$sha" "$rc")" || { printf '%s' "$run"; return 1; }
  # A RUN AT AN ANCESTOR STANDS WHERE THE JUDGE SAYS IT DOES: the head is covered when every commit after the run is
  # excused or proved (`_proof_past_f`, the question `_proof_floor_judge` asks), a red the run left still open being
  # the owed set the proof line carries. Else the first commit it cannot prove is named. A run at a head outside the
  # working head's history, or cited with no plan, stands for nothing: a whole run is owed at the working head.
  if [ "$sha" != "$head" ]; then
    if [ -n "$plan" ] && git -C "$co" merge-base --is-ancestor "$sha" "$head" 2>/dev/null; then
      inh="$(proof_inherited "$plan")" || { printf 'the run'"'"'s facts cannot be read, so the suites it carries as inherited debt are not known; run it again'; return 1; }
      [ -z "$owed" ] || [ -z "$inh" ] || owed="$(PROOF_I=",$inh," awk -F, '{ for (i = 1; i <= NF; i++) if ($i != "" && !index(ENVIRON["PROOF_I"], "," $i ",")) o = o (o == "" ? "" : ",") $i; print o }' <<PROOF_LOG_OWED
$owed
PROOF_LOG_OWED
)"
      why="$(_proof_past_f "$plan" "$co" "$sha" "$head" "$owed")"
      case $? in
        0|2) printf '%s' "$sha"; return 0 ;;
      esac
      printf 'the run in %s read head %.12s, and the working branch is at %.12s: %s; land the suites it lacks there' \
        "$ev" "$sha" "$head" "$why"
      return 1
    fi
    printf 'the run in %s read head %.12s, and the working branch is at %.12s: a whole run is owed at %.12s; run it there and cite that log' \
      "$ev" "$sha" "$head" "$head"
    return 1
  fi
  printf '%s' "$sha"
}

# _proof_floor_ends <log> -> two lines, the two the floor's one grammar reads (`_proof_floor_log`): the header, the
# first line that opens `head=`, as `<sha> <dirty>` when it reads `head=<hex> dirty=<n>`, else `bad <the line>`, else
# empty; then the log's last non-blank line, its trailing blanks cut. Nothing for a log that cannot be read.
_proof_floor_ends() {
  _proof_log_awk 'h == "" && /^head=/ { if ($0 ~ /^head=[0-9a-f]+ dirty=[0-9]+$/) { split($0, w, /[ =]/); h = w[2] " " w[4] } else h = "bad " $0 }
    NF { l = $0 }
    END { sub(/[ \t\r]+$/, "", l); print h; print l }' "$1" 2>/dev/null
}

# _proof_sha256 <file> -> its sha256, hex, through lib/detect.sh `_detect_sha256`, the one hash helper (loaded when
# the caller has not); rc 1 when no tool can answer.
_proof_sha256() {
  bionic_need detect.sh _detect_sha256 || return 1
  _detect_sha256 "$1"
}

# _proof_run_key <log> <root> -> the log as a run line's `log=` names it (wave-37 T4; A-T4-1): its real path under the
# docs root of <root> (`record/…`, as floor-run writes it and proof-add cites it), else under <root> itself (a
# detached booked.sh run's `.bionic/tmp/runs/<id>.log`), else the real path whole.
_proof_run_key() {
  local real docs top
  real="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)/${1##*/}"
  [ -n "${2:-}" ] || { printf '%s' "$real"; return 0; }
  _proof_roots_load
  docs="$(docs_root "$2" 2>/dev/null)"; docs="$(cd "${docs:-/nonexistent}" 2>/dev/null && pwd -P)"
  top="$(cd "$2" 2>/dev/null && pwd -P)"
  if [ -n "$docs" ] && [ "${real#"$docs"/}" != "$real" ]; then printf '%s' "${real#"$docs"/}"
  elif [ -n "$top" ] && [ "${real#"$top"/}" != "$real" ]; then printf '%s' "${real#"$top"/}"
  else printf '%s' "$real"; fi
}

# THE RUN LINE (wave-37 T4; D7, REQ-6 AC-6.1, AC-6.2; ADR-057). `floor-run` (hooks/session-poker.sh), right after it
# writes its log, and booked.sh's run close each append one line per run to the plan's landing record (lib/line.sh
# `line_event <plan> run`, through `_wt_proofs_put`):
#
#     line/v1|ev=run|log=<rel path>|head=<40-hex>|dirty=<n>|rc=<n>|sha256=<log hash>|at=<ISO>
#
# _proof_floor_match <log> <plan> <root> <head the log read> <rc it ended> -> `<at> <head> <rc>` of the run the log is,
# exit 0; or exit 1 with the refusal's sentence. The runs are the reader's `run` facts of the plan's run (`_proof_facts`),
# and a refusal names the plan's record (`proof_debt_record`) where they are written. A run is the log's
# when its `log=` names it (`_proof_run_key`) or its `sha256=` is the log's hash (a byte copy under record/, the only
# place proof-add cites from; A-T4-2). One whose sha256=, head= and rc= all equal the log's as it is now is its run.
# Else a line naming the log by path that differs is refused "the log changed since its run", naming the first fact
# that differs (sha256, then head, then rc); else "no run recorded for this log". THE HASH BINDS THE LOG, not the line:
# the record can be written by hand, but a log edited after its run no longer matches the run that wrote it. Runs that
# could not be read are not "no run": that refusal exits 2.
_proof_floor_match() {
  local log="$1" plan="${2:-}" root="${3:-}" sha="${4:-}" rc="${5:-}" rec="" key hash got facts="" f a b
  hash="$(_proof_sha256 "$log")" || hash=""
  if [ -z "$hash" ]; then
    printf 'the log %s cannot be hashed (no shasum or sha256sum answers), so the run that wrote it cannot be matched; install one and run proof-add regression again' "$log"
    return 1
  fi
  [ -z "$plan" ] || rec="$(proof_debt_record "$plan" "$root" 2>/dev/null)" || rec=""
  key="$(_proof_run_key "$log" "$root")"
  if [ -f "$plan" ] && ! proof_facts_at "$plan"; then
    printf 'the facts of %s could not be read, so the run that wrote the log %s cannot be matched; run proof-add regression again' "$plan" "$log"
    return 2
  fi
  [ -f "$plan" ] && got="$(_proof_facts_awk -F'|' -v key="$key" -v h="$hash" -v hd="$sha" -v rc="$rc" "$(proof_fact_awk)"'
    ev() != "run" { next }
    { l = line_kv("log"); s = line_kv("sha256") }
    l != key && s != h { next }
    s == h && line_kv("head") == hd && line_kv("rc") == rc { ok = line_kv("at") " " hd " " rc; next }
    l == key {
      if (s != h) bad = line_kv("at") "\tsha256\t" h "\t" s
      else if (line_kv("head") != hd) bad = line_kv("at") "\thead\t" hd "\t" line_kv("head")
      else bad = line_kv("at") "\trc\t" rc "\t" line_kv("rc")
    }
    END { if (ok != "") print "ok\t" ok; else if (bad != "") print "changed\t" bad }' 2>/dev/null)"
  case "${got:-}" in
    ok"	"*) printf '%s' "${got#ok	}"; return 0 ;;
    changed"	"*)
      got="${got#changed	}"
      IFS='	' read -r a f b got <<PROOF_RUN_BAD
$got
PROOF_RUN_BAD
      [ "$f" = rc ] || { b="$(printf '%s' "$b" | cut -c1-12)"; got="$(printf '%s' "$got" | cut -c1-12)"; }
      printf 'the log changed since its run: %s reads %s %s, but its run at %s recorded %s %s (%s); cite the log as its run left it, or run regression-run again and cite that log' \
        "$log" "$f" "$b" "$a" "$f" "$got" "$rec"
      return 1 ;;
  esac
  printf 'no run recorded for this log: %s (head %.12s, rc=%s, sha256 %.12s) is named by no ev=run line in %s; a regression proof cites a run the machine recorded, so run the regression with regression-run, or detached through booked.sh, and cite the log it writes' \
    "$log" "$sha" "$rc" "$hash" "${rec:-the landing record of a plan (none was named)}"
  return 1
}

# proof_floor_run <log> <plan> <root> -> `<at> <head> <rc>` of the recorded run the log is, exit 0; or exit 1 with the
# refusal's sentence (`_proof_floor_match`, the log's header and close read as the floor's grammar reads them). proof-add
# floor asks it for each log it accepted, so the proof line names the run it read (AC-6.2).
proof_floor_run() {
  local ends hdr rc
  ends="$(_proof_floor_ends "${1:-}")"; hdr="${ends%%$'\n'*}"; rc="${ends#*$'\n'}"
  [ "$ends" != "$hdr" ] || rc=""
  _proof_floor_match "${1:-}" "${2:-}" "${3:-}" "${hdr%% *}" "${rc#rc=}"
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
  printf '.bionic/config.yaml carries floor-attestation: %s, a key bionic removed (wave-36): the regression is the log of a run, never a person'"'"'s word. Delete the line, then cite the regression'"'"'s log with proof-add regression <log> [<log>...]' "$v"
}

# proof_plan_base <plan> [<repo>] -> the commit the plan's run started from, or nothing: the first word of the header's
# `base-sha:` (lib/reader.sh `reader_q_header`), printed as written, so a refusal can name it. Whether that word is a
# commit id (`proof_base_id`) and names a commit in <repo> is asked by every caller, each of which holds a repository
# (proof_attested, facts_state, proof-add, release-check). The first review proof starts at or before the base.
proof_plan_base() {
  local c
  [ -f "$1" ] && _proof_reader_load 2>/dev/null || return 0
  c="$(reader_q_header "$1" base-sha 2>/dev/null)" || return 0
  c="${c#base-sha=}"; printf '%s' "${c%%[[:space:]]*}"
}

# proof_base_id <value> -> 0 when <value> has the shape of a commit id, 7 to 40 hex. A word that git
# would resolve (`HEAD`, a branch, a tag) moves with the checkout, so it is no base, as a value that
# names no commit is none (wave-27 T14; review pass 20 F1).
proof_base_id() {
  case "${1:-}" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
  [ "${#1}" -ge 7 ] && [ "${#1}" -le 40 ]
}

# _PROOF_TAKE_AWK -> the awk function `proof_take(f, m)`, THE ONE READING OF A PROOF'S FIELDS: <f>[2..<m>] are its
# `<key>=<value>` fields, the first of a key its value as lib/fields.sh `line_kv` reads it. It sets PROOF_KIND (through
# lib/alias.sh's map) and PROOF_HEAD; a reading's PROOF_QUESTION, PROOF_READER, PROOF_RESULT and PROOF_SCOPE; the record
# in PROOF_EVIDENCE, PROOF_OWED and a point's row in PROOF_POINT, each empty when absent; 1 when the kind is a
# lower-case word and the head 7 to 40 lower-case hex (`head=none` is no head). A log fact (`proof_fact`) and a printed
# line (`proof_fields`) both ask it, so a field one reads the other reads.
_PROOF_TAKE_AWK='
    function proof_take(f, m,   i, j, p) {
      split("", p)
      for (i = m; i >= 2; i--) if (j = index(f[i], "=")) p[substr(f[i], 1, j - 1)] = substr(f[i], j + 1)
      PROOF_KIND = p["kind"]; PROOF_HEAD = p["head"]; PROOF_QUESTION = p["question"]; PROOF_READER = p["reader"]; PROOF_RESULT = p["result"]
      PROOF_SCOPE = p["scope"]; PROOF_EVIDENCE = p["evidence"]; PROOF_OWED = p["owed"]; PROOF_POINT = p["point"]
      '"$_PROOF_KIND_NORM"'
      return (PROOF_KIND ~ /^[a-z]+$/ && PROOF_HEAD ~ /^[0-9a-f]+$/ && length(PROOF_HEAD) >= 7 && length(PROOF_HEAD) <= 40)
    }'
# proof_awk -> the awk function `proof_fields(s)`, the view of a printed proof line (`proof_lines`) over the one reading
# (`proof_take`): 1 when <s> is a proof line, its fields set as a log fact's are. A proof line starts `proved:` at the
# first column (a bulleted `- proved:` is prose, not the line the writer writes) and carries its fields space-separated,
# so it reads alike whatever field separator its caller's program splits on.
proof_awk() {
  printf '%s' "$_PROOF_TAKE_AWK"'
    function proof_fields(s,   f) { split("", f); return proof_take(f, s ~ /^proved:[ \t]/ ? split(s, f, /[ \t]+/) : 0) }
  '
}

# proof_bind_awk -> awk source: THE ONE PREDICATE for the events that bind a record's pass, and the reads of what such
# an event says. A finding event (`_proof_findings_load`) is keyed
# `ref=<record>#<n>`: it defers or moves ONE finding of ONE pass, and every read of the record's findings applies it
# (`proof_finding_rating`), so a second pass registered on the same path would inherit it. A move binds for the reason
# a deferral does: it is the person's word about one finding, it changes the priority a later reader of that path
# judges, and a path that carries one is a settled pass whatever else it carries. Every caller asks these, so none
# can spell them again; each reads the event whole, whatever the field separator of its own input:
#
#     proof_fkv(line, key)    the value of a field of a finding event, else ""
#     proof_bound(line)       the `<record>#<n>` a finding event is keyed to, else ""
#     proof_binding(line)     1 when the event is keyed to a finding and says where it goes (`to=`): a Known-limits
#                             sentence alone rates nothing, so it binds no pass
#     proof_binds(line, rec)  1 when the event is binding and keyed to a finding of the record <rec>
#     proof_defers(line)      1 when the event is a deferral: the registration's, or a move to defer that carries the
#                             finding's rating
#     proof_move_of(line)     `defer` or `fix` when the event is a whole move (who, when, the words and why, as
#                             `finding-move` writes it), `fixed` for a whole move to fixed (the row, who and when),
#                             else ""
#     proof_move_row(line)    the <T> of a move to fixed, else ""
proof_bind_awk() {
  printf '%s' '
    function proof_fkv(s, k,   n, w, i) {
      n = split(s, w, "|")
      for (i = 2; i <= n; i++) if (index(w[i], k "=") == 1) return substr(w[i], length(k) + 2)
      return ""
    }
    function proof_bound(s) { return (index(s, "run/v1|ev=finding|") == 1) ? proof_fkv(s, "ref") : "" }
    function proof_binding(s) { return proof_bound(s) != "" && proof_fkv(s, "to") != "" }
    function proof_binds(s, rec) { return proof_binding(s) && index(proof_bound(s), rec "#") == 1 }
    function proof_defers(s,   t) {
      t = proof_fkv(s, "to")
      return proof_bound(s) != "" && (t == "deferred" || (t == "defer" && proof_fkv(s, "severity") != ""))
    }
    function proof_move_of(s,   t) {
      if (proof_bound(s) == "") return ""
      t = proof_fkv(s, "to")
      if (proof_fkv(s, "by") == "" || proof_fkv(s, "at") !~ /^[0-9][0-9][0-9][0-9]-/) return ""
      if (t == "fixed") return (proof_fkv(s, "row") ~ /^T[0-9]+$/) ? "fixed" : ""
      if (t != "defer" && t != "fix") return ""
      return (proof_fkv(s, "words") != "" && proof_fkv(s, "why") != "") ? t : ""
    }
    function proof_move_row(s) { return (proof_fkv(s, "to") == "fixed" && proof_fkv(s, "row") ~ /^T[0-9]+$/) ? proof_fkv(s, "row") : "" }
  '
}

# ---------- THE RUN'S FACTS, ASKED OF THE READER ----------
#
# A proof, a waiver, an approval and a recorded run are facts of the run, and lib/reader.sh is their one reader: it
# reads the run's log. The readers below ask it and never read the log themselves, so a fact is never read two ways.
# A fold costs a read of the whole log, so it is kept between calls, in this shell and in one file per plan for the
# subshells and processes after it, and served only while the plan, its log and every library that reads them are
# byte for byte the same (`cksum` of each). Outside a held command every ask sums them, so a write between two reads
# is seen; inside one the sum is taken where the log may have moved (`_proof_facts_held`).

# THE COUNTS (tests/speed-counts.test.sh): when BIONIC_COUNT names a file, a counted place appends `<kind> <function>`.
# `send` is the whole facts leaving as a string inside a held command, to a reader that is not /dev/null; `sum` is a
# checksum of the run's log taken for a key; `judge` is a judgment's entry, the first ask a decider makes under its own
# `_PROOF_FRESH=1`, which the ask leaves at 2 so the judgment's later asks in that shell are not entries again.
_proof_count() { [ -z "${BIONIC_COUNT:-}" ] || printf '%s %s\n' "$1" "$2" 2>/dev/null >>"$BIONIC_COUNT" || :; }
_proof_count_send() {
  [ -n "${BIONIC_COUNT:-}" ] && [ ! /dev/stdout -ef /dev/null ] && _proof_held_dir || return 0
  _proof_count send "$1"
}
_proof_count_fresh() { [ "${_PROOF_FRESH:-}" = 1 ] || return 0; _proof_count judge _proof_facts; _PROOF_FRESH=2; }

_proof_reader_load() { bionic_need reader.sh reader_facts; }  # -> 0 once lib/reader.sh is loaded

# The files a fold depends on: the reader's libraries, then the run's log, and no other file of its record.
_PROOF_FACTS_LIBS="reader.sh plan-read.sh log.sh line.sh"
_PROOF_FACTS_LAYOUT="facts+findings+inherited"   # the kept fold's layout, named last in every key
_PROOF_FACTS_KEY=""; _PROOF_FACTS_LOG=""; _PROOF_FACTS=""; _PROOF_FINDINGS=""; _PROOF_INHERITED=""; _PROOF_HELD_PLAN=""; _PROOF_HELD_FINDINGS=""; _PROOF_HELD_FACTS=""
# The kept file is a cache and never evidence, yet what it holds is served as the run's proofs and approvals, under a
# key anyone who reads the repository can compute. So it is read and written only in a directory this user owns
# (`[ -O ]`), that is a directory and no link and that neither group nor other can write (one `find`, which follows no
# link it is handed); anywhere else, or where find cannot answer, the fold is made again and nothing is kept. Each
# write leaves the newest _PROOF_FACTS_KEEP files, so the fold of a plan that is gone, a suite's, is not kept for ever.
# A CALLER THAT DECIDES (_PROOF_FRESH, below) is never served the kept file and never writes it: its facts are folded
# from the log the seal vouches for, and this shell's memory serves them again only when they were folded so
# (_PROOF_FACTS_LOG), never when they were read from the kept file.
_PROOF_FACTS_KEEP=16

_proof_facts() {  # <plan> -> the reader's standing facts of the plan's run, one `run/v1` line each, in fact order; exit 2 with one line on stderr when the fold fails
  # INSIDE A HELD COMMAND the facts are the command's files (`_proof_facts_held`): they are printed here only for a
  # caller that takes them as a string, and a reader reads them by path instead (`proof_facts_at`).
  if _proof_held_dir; then
    _proof_facts_held "${1:-}" || return 2
    _proof_facts_send; return
  fi
  local plan="${1:-}" log="" dir="" stamp key cdir cache="" tmp got evs rc=0 IFS=$' \t\n'
  local -a deps
  [ -f "$plan" ] || return 0
  _proof_reader_load || { printf '_proof_facts: lib/reader.sh cannot be loaded, so the facts of %s are not read\n' "$plan" >&2; return 2; }
  # The lookup's exit tells a plan with no record (2), which has no event, from a lookup that died: that would send a
  # run with a log down the path for one without, so it is a failed fold.
  log="$(reader_log "$plan" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) dir="${log%/*}" ;;
    2) rc=0 ;;
    *) printf '_proof_facts: the lookup of the run log of %s exited %s, so its facts are not read\n' "$plan" "$rc" >&2; return 2 ;;
  esac
  # The key covers every file the fold depends on, or no fold is served or kept under it: a file cksum cannot read
  # would leave the key blind to its changes. A fresh fold is still the run's facts, so that is not worth a word.
  deps=("$plan"); [ -z "$log" ] || [ ! -f "$log" ] || deps+=("$log")
  _proof_facts_libsum || :
  _proof_count_fresh; _proof_count sum _proof_facts
  stamp=""
  [ -z "$_PROOF_FACTS_LIBSUM" ] || { stamp="$(cksum "${deps[@]}" 2>/dev/null)" \
    && stamp="$(printf '%s\n' "$stamp" "$_PROOF_FACTS_LIBSUM" | cksum)" || stamp=""; }
  # The key names the kept file's layout too, so a file another layout wrote is never read as this one.
  key="$plan $stamp $_PROOF_FACTS_LAYOUT"
  if [ "$_PROOF_FACTS_KEY" = "$key" ] && { [ -z "${_PROOF_FRESH:-}" ] || [ -n "$_PROOF_FACTS_LOG" ]; }; then _proof_facts_out; return; fi
  cdir="${TMPDIR:-/tmp}/bionic-facts-$(id -u 2>/dev/null)"
  [ -d "$cdir" ] || mkdir -p -m 700 "$cdir" 2>/dev/null
  if [ -n "$stamp" ] && [ -z "${_PROOF_FRESH:-}" ] && [ -O "$cdir" ] && [ -n "$(find "$cdir" -prune -type d ! -perm -020 ! -perm -002 2>/dev/null)" ]; then
    cache="$cdir/$(printf '%s' "$plan" | cksum | tr -c '0-9\n' '-')"
  fi
  # The kept file is read once, key and body together: another process prunes the directory, and a file gone between
  # two reads would be an empty body under a good key.
  if [ -n "$cache" ] && [ -f "$cache" ] && got="$(cat "$cache" 2>/dev/null)" && [ "${got%%$'\n'*}" = "$key" ] \
     && _proof_kept_split "$got"; then
    _PROOF_FACTS_LOG=""
  else
    # A plan the reader cannot join to a record has no log, and so no event.
    evs=""; _PROOF_FACTS_LOG=1
    # pipefail: the reader reads a pipe, and a stage killed in it would leave a short read that exits 0.
    [ -z "$dir" ] || evs="$(set -o pipefail; reader_events "$plan")" || rc=$?
    # The events are read once: the facts are folded from them, and a finding's events are kept whole beside the facts,
    # since a finding is read from all of them (`_proof_findings_load`), not from its standing fact alone.
    [ "$rc" -ne 0 ] || _PROOF_FACTS="$( set -o pipefail; reader_events() { printf '%s\n' "$evs"; }; reader_facts "$plan" )" || rc=$?
    _PROOF_FINDINGS="$(awk -v t=finding 'index($0, "run/v1|ev=" t "|") == 1' <<PROOF_EVENTS
$evs
PROOF_EVENTS
)"
    [ -z "$_PROOF_FINDINGS" ] || _PROOF_FINDINGS="$_PROOF_FINDINGS"$'\n'
    # An inherited suite is a proof of its own, yet two of them at one regression head are one fact to the fold, so
    # they too are kept whole (`proof_inherited_lines`).
    _PROOF_INHERITED="$(awk 'index($0, "run/v1|ev=proof|kind=inherited|") == 1' <<PROOF_EVENTS
$evs
PROOF_EVENTS
)"
    [ -z "$_PROOF_INHERITED" ] || _PROOF_INHERITED="$_PROOF_INHERITED"$'\n'
  fi
  # A fold that failed (a process refused under memory pressure) is short or empty: kept, it would answer every later
  # ask that the run has no proof. It is an error to whoever asked, and nothing is kept, in this shell or on disk.
  if [ "$rc" -ne 0 ]; then
    _PROOF_FACTS_KEY=""; _PROOF_FACTS_LOG=""; _PROOF_FACTS=""; _PROOF_FINDINGS=""; _PROOF_INHERITED=""
    printf '_proof_facts: lib/reader.sh exited %s folding the facts of %s; nothing is kept\n' "$rc" "$plan" >&2
    return 2
  fi
  [ -z "$_PROOF_FACTS" ] || _PROOF_FACTS="$_PROOF_FACTS"$'\n'
  _PROOF_FACTS_KEY="${stamp:+$key}"
  if [ -n "$cache" ] && tmp="$(mktemp "$cdir/.facts.XXXXXX" 2>/dev/null)"; then
    _proof_kept_write "$key" > "$tmp" && mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp"
    _proof_keep_sweep "$cdir" "$_PROOF_FACTS_KEEP"
  fi
  _proof_facts_out
}

# THE COMMAND'S FACTS ARE FILES (`_proof_held_dir`). Inside a held command a plan's fold is written once into the
# command's directory, as files every reader in every process of the command reads by path: `fold-<id>` the standing
# facts, `findings-<id>` and `inherited-<id>` the finding events and the inherited proofs whole, `made-<id>` the key
# they were folded under, and last `key-<id>`, one line, the key the run stood at when it was last summed. An ask
# compares that line with the key this shell holds and reads nothing more: no process, no sum. The log is summed for
# a key only where it may have moved: at the command's first ask, at the first ask after the command appends to a
# run's log (lib/log.sh `_log_moved` removes every `key-`), and at each judgment's entry (`_PROOF_FRESH=1`), so a
# judgment folds the log as it stands when it starts. A write to the log from outside the command is read at the
# command's next append or its next judgment, not at every ask. The key is the plan's, the log's and the reader's
# libraries' cksum, never a file's times, and the libraries are summed once a process. The directory is the
# command's alone and goes with it, so nothing kept here is read by a later command.
_PROOF_HELD_ID=""; _PROOF_HELD_FOLD=""; _PROOF_FACTS_FILE=""; _PROOF_FACTS_TEXT=""; _PROOF_FACTS_LIBSUM=""
_proof_facts_held() {  # <plan> -> 0 with _PROOF_HELD_FOLD its fold's file (empty for no plan), _PROOF_FACTS_KEY, _PROOF_FINDINGS and _PROOF_INHERITED set; 2, one line on stderr, when the fold fails
  local plan="${1:-}" d="$_PROOF_HELD_DIR" id k="" m="" log="" stamp="" key="" f ev rc=0 IFS=$' \t\n'
  local -a deps
  _PROOF_HELD_FOLD=""
  [ -f "$plan" ] || return 0
  id="${plan//[^A-Za-z0-9._-]/%}"
  if [ "${#id}" -gt 200 ]; then id="$(cksum <<< "$plan")"; id="${id%% *}"; fi
  if [ "${_PROOF_FRESH:-}" != 1 ] && [ -f "$d/key-$id" ] && IFS= read -r k < "$d/key-$id" && [ -n "$k" ]; then
    if [ "$k" = "$_PROOF_FACTS_KEY" ] && [ "$_PROOF_HELD_ID" = "$d/$id" ]; then _PROOF_HELD_FOLD="$d/fold-$id"; return 0; fi
    # Another process's fold is taken only when its key ends in this process's own libraries: a copy of the reader that
    # differs by a line, asking inside the hold, folds for itself and is never served what another reader folded.
    if _proof_facts_libsum && [ "${k%" $_PROOF_FACTS_LIBSUM $_PROOF_FACTS_LAYOUT"}" != "$k" ] \
       && [ -f "$d/made-$id" ] && IFS= read -r m < "$d/made-$id" && [ "$m" = "$k" ]; then _proof_held_take "$d" "$id" "$k"; return 0; fi
  fi
  _proof_reader_load || { printf '_proof_facts: lib/reader.sh cannot be loaded, so the facts of %s are not read\n' "$plan" >&2; return 2; }
  log="$(reader_log "$plan" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) ;;
    2) rc=0; log="" ;;
    *) printf '_proof_facts: the lookup of the run log of %s exited %s, so its facts are not read\n' "$plan" "$rc" >&2; return 2 ;;
  esac
  _proof_facts_libsum || :
  _proof_count_fresh; _proof_count sum _proof_facts
  deps=("$plan"); [ -z "$log" ] || [ ! -f "$log" ] || deps+=("$log")
  stamp="$(cksum "${deps[@]}" 2>/dev/null)" || stamp=""
  # A file cksum cannot read would leave the key blind to its changes: then nothing is keyed, and every ask folds.
  [ -z "$stamp" ] || [ -z "$_PROOF_FACTS_LIBSUM" ] || key="$plan ${stamp//$'\n'/ } $_PROOF_FACTS_LIBSUM $_PROOF_FACTS_LAYOUT"
  if [ -n "$key" ]; then
    if [ "$key" = "$_PROOF_FACTS_KEY" ] && [ "$_PROOF_HELD_ID" = "$d/$id" ] && [ -f "$d/fold-$id" ]; then
      printf '%s\n' "$key" > "$d/key-$id" 2>/dev/null; _PROOF_HELD_FOLD="$d/fold-$id"; return 0
    fi
    if [ -f "$d/made-$id" ] && IFS= read -r m < "$d/made-$id" && [ "$m" = "$key" ]; then
      printf '%s\n' "$key" > "$d/key-$id" 2>/dev/null; _proof_held_take "$d" "$id" "$key"; return 0
    fi
  fi
  # THE ONE FOLD: the log is read once into the directory, the facts folded from that read, and the finding events and
  # the inherited proofs taken from it whole in one pass, since a finding is read from all of its events. A fold that
  # failed is short or empty: it is an error to whoever asked, and nothing of it is kept.
  # Its scratch files are named off one made by the exclusive create, so a sibling folding the same plan writes its own.
  ev=""
  if bionic_need root.sh bionic_new && bionic_new "$d/.events-$id"; then ev="$BIONIC_NEW"; else rc=2; fi
  if [ "$rc" -ne 0 ]; then :; elif [ -n "$log" ]; then reader_events "$plan" >| "$ev" 2>/dev/null || rc=$?; else : >| "$ev"; fi
  [ "$rc" -ne 0 ] || ( set -o pipefail; reader_events() { cat "$ev"; }; reader_facts "$plan" ) > "$ev.f" || rc=$?
  [ "$rc" -ne 0 ] || { : > "$ev.n"; : > "$ev.i"; }
  [ "$rc" -ne 0 ] || awk -v fo="$ev.n" -v io="$ev.i" 'index($0, "run/v1|ev=finding|") == 1 { print > fo }
    index($0, "run/v1|ev=proof|kind=inherited|") == 1 { print > io }' "$ev" || rc=$?
  if [ "$rc" -eq 0 ]; then
    mv -f "$ev.f" "$d/fold-$id" && mv -f "$ev.n" "$d/findings-$id" && mv -f "$ev.i" "$d/inherited-$id" || rc=2
  fi
  [ -z "$ev" ] || rm -f "$ev" "$ev.f" "$ev.n" "$ev.i"
  if [ "$rc" -ne 0 ]; then
    _PROOF_FACTS_KEY=""; _PROOF_FACTS_LOG=""; _PROOF_HELD_ID=""; _PROOF_FINDINGS=""; _PROOF_INHERITED=""
    rm -f "$d/key-$id" "$d/made-$id"
    if [ -z "$ev" ]; then printf '_proof_facts: no scratch file could be made in %s to fold the facts of %s; nothing is kept\n' "$d" "$plan" >&2
    else printf '_proof_facts: lib/reader.sh exited %s folding the facts of %s; nothing is kept\n' "$rc" "$plan" >&2; fi
    return 2
  fi
  if [ -n "$key" ]; then printf '%s\n' "$key" > "$d/made-$id" && printf '%s\n' "$key" > "$d/key-$id"; else rm -f "$d/key-$id" "$d/made-$id"; fi
  _proof_held_take "$d" "$id" "$key" fold
}
# _proof_facts_libsum -> 0 with the code each kept key covers, decided here alone and summed once a process (counted
# `libs`): _PROOF_FACTS_LIBSUM the reader's libraries, _PROOF_PLACE_LIBS proof.sh and those, _PROOF_DERIVE_LIBSUM
# proof.sh and units.sh, which derive an answer; 1 when a reader library cannot be read. A sum whose file cannot be read
# is empty, so what it keys is made at every ask. The reader's libraries are the loaded reader's, else the ones beside
# this file; units.sh the loaded one, else the one beside. A sum leaves out the path, so a key is the same wherever a
# process names the same bytes from, and costs the one cksum.
_PROOF_DERIVE_LIBSUM=""
_proof_facts_libsum() {
  [ -z "$_PROOF_FACTS_LIBSUM" ] || return 0
  local lib="${BASH_SOURCE[0]%/*}" own f out c n p i=0 nr sum="" IFS=$' \t\n'
  local -a deps=() sums=()
  [ "$lib" != "${BASH_SOURCE[0]}" ] || lib=.
  own="$lib"
  ! declare -F reader_facts >/dev/null 2>&1 || lib="$_READER_LIB_DIR"
  for f in $_PROOF_FACTS_LIBS; do deps+=("$lib/$f"); done
  nr="${#deps[@]}"; deps+=("$own/proof.sh" "${_UNITS_DIR:-$own}/units.sh")
  _proof_count libs _proof_facts
  # cksum names each file it read, in the order handed, and none it could not: a file absent from its lines is unread.
  out="$(cksum "${deps[@]}" 2>/dev/null)" || :
  while read -r c n p; do
    while [ "$i" -lt "${#deps[@]}" ] && [ "$p" != "${deps[$i]}" ]; do i=$((i + 1)); done
    [ "$i" -ge "${#deps[@]}" ] || sums[$i]="$c $n"; i=$((i + 1))
  done <<PROOF_LIBSUM
$out
PROOF_LIBSUM
  i=0; while [ "$i" -lt "$nr" ]; do [ -n "${sums[$i]:-}" ] || return 1; sum="$sum${sum:+ }${sums[$i]}"; i=$((i + 1)); done
  _PROOF_FACTS_LIBSUM="$sum"
  _PROOF_PLACE_LIBS="${sums[$nr]:+${sums[$nr]} $sum}"
  _PROOF_DERIVE_LIBSUM=""; [ -z "${sums[$nr]:-}" ] || [ -z "${sums[$((nr + 1))]:-}" ] || _PROOF_DERIVE_LIBSUM="${sums[$nr]} ${sums[$((nr + 1))]}"
}
# _proof_held_take <dir> <id> <key> [fold] -> the fold under <key> held by this shell: its files named, its findings and
# inherited proofs read in, with no process. A fold this shell did not make itself is counted (`held`).
_proof_held_take() {
  [ -n "${4:-}" ] || _proof_count held _proof_facts
  _PROOF_FACTS_KEY="$3"; _PROOF_FACTS_LOG=1; _PROOF_HELD_ID="$1/$2"; _PROOF_HELD_FOLD="$1/fold-$2"; _PROOF_FACTS=""
  _PROOF_FINDINGS=""; [ ! -f "$1/findings-$2" ] || IFS= read -r -d '' _PROOF_FINDINGS < "$1/findings-$2" || :
  _PROOF_INHERITED=""; [ ! -f "$1/inherited-$2" ] || IFS= read -r -d '' _PROOF_INHERITED < "$1/inherited-$2" || :
}

# proof_facts_at <plan> -> 0 with the plan's facts ready for a read, the pending lines laid over them
# (`_proof_out_at`): inside a held command _PROOF_FACTS_FILE names the file that holds them, and outside one
# _PROOF_FACTS_TEXT holds them, taken as `_proof_facts` prints them; 2, one line on stderr, when they cannot be read.
# It runs in the caller's shell, so the fold it takes is held there for every later ask.
proof_facts_at() {
  _PROOF_FACTS_FILE=""; _PROOF_FACTS_TEXT=""
  if _proof_held_dir; then _proof_facts_held "${1:-}" && _proof_out_at || return 2; return 0; fi
  _PROOF_FACTS_TEXT="$(_proof_facts "${1:-}")" || { _PROOF_FACTS_TEXT=""; return 2; }
}
# _proof_facts_awk <awk args…> -> awk run over the facts proof_facts_at made ready: their file by path, or the string
# handed in on stdin where there is none; its exit is awk's.
_proof_facts_awk() {
  if [ -n "$_PROOF_FACTS_FILE" ]; then awk "$@" "$_PROOF_FACTS_FILE"; else printf '%s' "$_PROOF_FACTS_TEXT" | awk "$@"; fi
}
# _proof_facts_read <plan> <awk args…> -> both: the plan's facts made ready and the awk run over them; 2 when they cannot be read
_proof_facts_read() {
  local plan="$1"; shift
  proof_facts_at "$plan" || return 2
  _proof_facts_awk "$@"
}

# The kept file's layout, read and written by `_proof_facts` alone (a held fold keeps each part in a file of its own):
# the key, the facts, then the finding events and the inherited proofs, each part after a line of one \036.
_proof_kept_write() {  # <key> -> the layout of the fold this shell holds
  printf '%s\n' "$1"; printf '%s' "$_PROOF_FACTS"; printf '\036\n%s' "$_PROOF_FINDINGS"; printf '\036\n%s' "$_PROOF_INHERITED"
}
_proof_kept_split() {  # <the layout, key line first> -> 0 with _PROOF_FACTS, _PROOF_FINDINGS and _PROOF_INHERITED set; 1, none set, when it is not whole
  local rest
  [ -n "$(printf '%s\n' "$1" | awk '$0 == "\036" { print 1; exit }')" ] || return 1
  # Split by awk, not by a pattern in the shell: bash 3.2 matches `${v#*x}` over a long value in quadratic time.
  _PROOF_FACTS="$(printf '%s\n' "$1" | awk 'NR == 1 { next } $0 == "\036" { exit } { print }')"
  # The findings and the inherited proofs are short, so one pass takes both and the shell splits them.
  rest="$(printf '%s\n' "$1" | awk 'f { print } $0 == "\036" { f = 1 }')"
  _PROOF_FINDINGS="${rest%%$'\036'*}"; _PROOF_FINDINGS="${_PROOF_FINDINGS%$'\n'}"
  case "$rest" in *$'\036'*) _PROOF_INHERITED="${rest#*$'\036'}"; _PROOF_INHERITED="${_PROOF_INHERITED#$'\n'}" ;; *) _PROOF_INHERITED="" ;; esac
  [ -z "$_PROOF_FACTS" ] || _PROOF_FACTS="$_PROOF_FACTS"$'\n'
  [ -z "$_PROOF_FINDINGS" ] || _PROOF_FINDINGS="$_PROOF_FINDINGS"$'\n'
  [ -z "$_PROOF_INHERITED" ] || _PROOF_INHERITED="$_PROOF_INHERITED"$'\n'
}

# ---------- ONE COMMAND'S HOLD ----------
#
# One command a person waits on is one process tree, and in it the run's log is folded once. The command's first process
# makes a directory and names it in BIONIC_HELD for every process it starts (hooks/session-poker.sh), and removes it
# when the command ends. What is held there is keyed by the plan, the `cksum` of the plan, the log and the reader's
# libraries, and the overlay it carries, never by a file's times (`_proof_facts_held`); a fold is written there only
# when it was folded from the log, so a decider served from it reads the log's facts. A directory is trusted only while
# the process that made it lives (its pid is in its name), and only when this user owns it and no one else can write
# it, so a directory an earlier command left holds nothing for a later one.
_PROOF_HELD_DIR=""; _PROOF_HELD_SEEN="-"
_proof_held_dir() {  # -> 0 with _PROOF_HELD_DIR set when this command holds its reads; 1 when it does not
  if [ "$_PROOF_HELD_SEEN" = "${BIONIC_HELD:-}" ]; then [ -n "$_PROOF_HELD_DIR" ] && [ -d "$_PROOF_HELD_DIR" ]; return; fi
  _PROOF_HELD_SEEN="${BIONIC_HELD:-}"; _PROOF_HELD_DIR=""
  local d="${BIONIC_HELD:-}" pid
  [ -n "$d" ] && [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] || return 1
  pid="${d##*/bionic-held-}"; pid="${pid%%.*}"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  [ -n "$(find "$d" -prune -type d ! -perm -020 ! -perm -002 2>/dev/null)" ] || return 1
  _PROOF_HELD_DIR="$d"
}
# proof_hold_begin -> 0, BIONIC_HELD exported, when this process opens a held command: a directory of its own under
# $TMPDIR, named by its pid; 1, nothing exported, when one already holds for this command or none can be made. The
# caller that opened it removes it (`proof_hold_end`) when its command ends.
proof_hold_begin() {
  local d
  ! _proof_held_dir || return 1
  d="$(mktemp -d "${TMPDIR:-/tmp}/bionic-held-$$.XXXXXX" 2>/dev/null)" || return 1
  chmod 700 "$d" 2>/dev/null || { rm -rf "$d"; return 1; }
  BIONIC_HELD="$d"; export BIONIC_HELD
}
proof_hold_end() {  # -> the directory proof_hold_begin opened removed, and nothing held any more
  case "${BIONIC_HELD:-}" in */bionic-held-"$$".*) rm -rf "$BIONIC_HELD" ;; esac
  unset BIONIC_HELD; _PROOF_HELD_DIR=""; _PROOF_HELD_SEEN="-"; _PROOF_HELD_ID=""; _PROOF_HELD_FOLD=""; _PROOF_FACTS_KEY=""
}

# ---------- AN ANSWER DERIVED FROM THE FACTS, MADE ONCE A COMMAND ----------
#
# The row states, the proofs, the born rows, the fixed findings, the proved release heads, the floor judge at a head and
# the whole pass's line at a head are computed from the run's facts, the plan, and commits that never change. Inside a
# held command each is computed once for its key and kept in the command's directory, and every later ask, in any
# process of the command, reads it back with no process. The key is the answer's name, its arguments, the sum of the
# code that derives it (`_proof_facts_libsum`) and the key of the facts it was computed from, as the facts' own files
# hold it (`made-` beside the fold, `.key` beside an overlay), so an answer computed before the command appended to
# the log, or over other pending lines, or by another copy of that code, is never served after, and a judgment that
# folds afresh is served only what the same facts give. A caller that holds the units library's
# facts (`_units_fold`) adds their key the same way; facts held as a string have no key, so their answer is computed.
# Only an answer that exited 0 is kept, so a failure is heard again at every ask. Outside a held command every ask
# computes, as before. Each compute counts `derive <name> <key>` (tests/speed-counts.test.sh), `-` for an unkept one.
# _proof_derive <name> <key> <function> <args…> -> what <function> <args…> prints, and its exit. The caller has made the
# facts the answer reads ready (`proof_facts_at`), and hands an empty <key> for an argument the key cannot cover, so
# that answer is computed.
_PROOF_DERIVE_KEY=""; _PROOF_IDENT=""
_proof_derive() {
  local name="$1" key="$2" fn="$3" idx="" k p got="" out rc
  shift 3
  if [ -n "$key" ] && _proof_held_dir && _proof_derive_key "$key"; then
    key="$name"$'\035'"$_PROOF_DERIVE_KEY"; idx="$_PROOF_HELD_DIR/derive-$name"
    if [ -f "$idx" ]; then
      while IFS=$'\t' read -r k p; do [ "$k" != "$key" ] || got="$p"; done < "$idx"
      if [ -n "$got" ] && [ -f "$got" ]; then
        out=""; IFS= read -r -d '' out < "$got" || :
        printf '%s' "$out"; return 0
      fi
    fi
  fi
  _proof_count derive "$name ${idx:+${key//[[:space:]]/_}}${idx:--}"
  [ -n "$idx" ] || { "$fn" "$@"; return; }
  out="$("$fn" "$@"; printf 'x%s' "$?")"; rc="${out##*x}"; out="${out%x*}"
  if [ "$rc" = 0 ] && _proof_derive_file "$idx" "$out"; then
    # The answer is whole on disk before the index names it, so a reader in another process never reads half of one.
    printf '%s\t%s\n' "$key" "$_PROOF_DERIVE_FILE" >> "$idx" 2>/dev/null || rm -f "$_PROOF_DERIVE_FILE"
  fi
  printf '%s' "$out"; return "$rc"
}
# _proof_derive_file <index> <answer> -> 0 with _PROOF_DERIVE_FILE a file beside <index> made new for <answer> and
# holding it; 1, nothing made, when none can be. NO KEPT ANSWER IS WRITTEN OVER: a subshell shares its parent's $$,
# and under bash 3.2 the children of a subshell that drew $RANDOM each draw the same next value, so two answers made
# in sibling subshells would draw one name. Each file is made by lib/root.sh `bionic_new`, an exclusive create that
# draws again while a name is held, so an index line names only the answer written for its own key.
_PROOF_DERIVE_FILE=""
_proof_derive_file() {
  _PROOF_DERIVE_FILE=""
  bionic_need root.sh bionic_new && bionic_new "$1" || return 1
  if { printf '%s' "$2" >| "$BIONIC_NEW"; } 2>/dev/null; then _PROOF_DERIVE_FILE="$BIONIC_NEW"; return 0; fi
  rm -f "$BIONIC_NEW"; return 1
}
# _proof_derive_key <key> -> 0 with _PROOF_DERIVE_KEY <key>, the sum of the code that derives the answer and the key
# of each view of the facts the caller holds, one line; 1 when that code or a view has none
_proof_derive_key() {
  local k="$1" f
  _proof_facts_libsum && [ -n "$_PROOF_DERIVE_LIBSUM" ] || return 1
  _proof_facts_ident "${_PROOF_FACTS_FILE:-}" || return 1
  k="$k"$'\035'"code=$_PROOF_DERIVE_LIBSUM"$'\035'"facts=$_PROOF_IDENT"; f="$_PROOF_IDENT"
  # The units view adds to the key only where it holds other facts than the reader's: the same facts give one answer.
  if [ -n "${_UNITS_FACTS_PLAN:-}" ]; then
    _proof_facts_ident "${_UNITS_FACTS_FILE:-}" || return 1
    [ "$_PROOF_IDENT" = "$f" ] || k="$k"$'\035'"units=$_UNITS_FACTS_PLAN=$_PROOF_IDENT"
  fi
  k="${k//$'\n'/$'\035'}"; _PROOF_DERIVE_KEY="${k//$'\t'/$'\036'}"
}
# _proof_facts_ident <facts file> -> 0 with _PROOF_IDENT the key the held file was made under; 1 when it is no file of
# this command's hold, or its key is gone
_proof_facts_ident() {
  local f="$1" k=""
  _PROOF_IDENT=""
  case "$f" in
    "$_PROOF_HELD_DIR"/fold-*) [ ! -f "$_PROOF_HELD_DIR/made-${f##*/fold-}" ] || IFS= read -r k < "$_PROOF_HELD_DIR/made-${f##*/fold-}" || k="" ;;
    "$_PROOF_HELD_DIR"/out-*) [ ! -f "$f.key" ] || IFS= read -r -d '' k < "$f.key" || : ;;
  esac
  [ -n "$k" ] || return 1
  _PROOF_IDENT="$k"
}
# _proof_tree_key <plan> <tree> [<head>] -> 0 with _PROOF_TREE_KEY the key of an answer that reads the plan's text, <tree>
# and the commit <head>: the arguments and the plan's cksum now, since a verb may write the plan between two sums of the
# log. Only when the plan is its own and not a verb's copy, and lies in <tree>, so the landing record the tree names is
# the plan's own run log, which the facts' key covers; and when a <head> handed in is a full commit name, which never
# moves. 1, the key empty, otherwise: that answer is computed at every ask.
_PROOF_TREE_KEY=""
_proof_tree_key() {
  local c
  _PROOF_TREE_KEY=""
  case "${1:-}" in ''|*.plan.md.*) return 1 ;; esac
  [ -n "${2:-}" ] || return 1
  case "$1" in "${2%/}"/*) ;; *) return 1 ;; esac
  if [ "$#" -ge 3 ]; then case "$3" in *[!0-9a-f]*|'') return 1 ;; esac; [ "${#3}" = 40 ] || return 1; fi
  c="$(cksum < "$1" 2>/dev/null)" && [ -n "$c" ] || return 1
  _PROOF_TREE_KEY="$1"$'\035'"$2"$'\035'"${3:-}"$'\035'"plan=$c"
}
# _proof_derive_ready <plan> -> 0 inside a held command with the plan's facts ready for the key (`_proof_derive_key`),
# as the answer's own first ask makes them ready; 1 outside one, where nothing is kept, or when they cannot be read,
# which the answer, computed, then says in its own words.
_proof_derive_ready() {
  _proof_held_dir && { _proof_held_facts_at "$1" || proof_facts_at "$1"; } 2>/dev/null
}

# _proof_facts_out -> the kept facts, a pending proof (`proof_pending`) folded in after them: the facts re-folded with it
# answer as the fold of every event and it would, the standing facts being each identity's last. Outside a held
# command nothing of it is kept.
_proof_facts_out() {
  local f p
  ! _proof_dry_refused || return 2
  p="${_PROOF_PENDING:-}"; [ -z "$_PROOF_DRY" ] || p="${p:+$p$'\n'}$_PROOF_DRY"
  [ -n "$p" ] || { printf '%s' "$_PROOF_FACTS"; return 0; }
  f="$( set -o pipefail; reader_events() { printf '%s%s\n' "$_PROOF_FACTS" "$p"; }; reader_facts - )" || return 2
  [ -z "$f" ] || f="$f"$'\n'
  printf '%s' "$f"
}
# _proof_out_at -> 0 with _PROOF_FACTS_FILE the file a reader of the held fold (`_proof_facts_held`) reads: the fold
# itself, or the fold with the pending lines laid over it as `_proof_facts_out` lays them. Inside a held command the
# overlay is folded once per fold and pending lines, kept in this shell for its subshells and in the command's
# directory for its other processes, its key whole in a file beside it; 2 when the pending lines are refused or the
# overlay fails.
_PROOF_OUT_KEY=""; _PROOF_OUT_FILE=""
_proof_out_at() {
  local p k o got="" tmp
  _PROOF_FACTS_FILE=""
  ! _proof_dry_refused || return 2
  [ -n "$_PROOF_HELD_FOLD" ] || return 0
  p="${_PROOF_PENDING:-}"; [ -z "$_PROOF_DRY" ] || p="${p:+$p$'\n'}$_PROOF_DRY"
  [ -n "$p" ] || { _PROOF_FACTS_FILE="$_PROOF_HELD_FOLD"; return 0; }
  k="$_PROOF_FACTS_KEY log=1"$'\n'"$p"$'\n'$'\035'
  if [ "$_PROOF_OUT_KEY" = "$k" ] && [ -f "$_PROOF_OUT_FILE" ]; then _PROOF_FACTS_FILE="$_PROOF_OUT_FILE"; return 0; fi
  o="$_PROOF_HELD_DIR/out-$(printf '%s' "$k" | cksum | tr -c '0-9\n' '-')"
  [ ! -f "$o.key" ] || IFS= read -r -d '' got < "$o.key" || :
  if [ "$got" != "$k" ] || [ ! -f "$o" ]; then
    # A shell that took the fold from another process's files has not loaded the reader yet.
    _proof_reader_load || return 2
    tmp="$(mktemp "$o.XXXXXX" 2>/dev/null)" || return 2
    ( set -o pipefail; _PROOF_READ_FILE="$_PROOF_HELD_FOLD" _PROOF_READ_PENDING="$p"
      reader_events() { cat "$_PROOF_READ_FILE"; printf '%s\n' "$_PROOF_READ_PENDING"; }; reader_facts - ) > "$tmp" \
      || { rm -f "$tmp"; return 2; }
    mv -f "$tmp" "$o" 2>/dev/null && printf '%s' "$k" > "$o.key" 2>/dev/null || { rm -f "$tmp"; return 2; }
  fi
  _PROOF_OUT_KEY="$k"; _PROOF_OUT_FILE="$o"; _PROOF_FACTS_FILE="$o"
}
# _proof_facts_send -> the held facts, the pending lines laid over them, printed for a caller that takes them as a
# string; to a caller that sends them to /dev/null, nothing: the ask has made them ready, and that is all it wanted.
_proof_facts_send() {
  _proof_out_at || return 2
  [ -n "$_PROOF_FACTS_FILE" ] && [ ! /dev/stdout -ef /dev/null ] || return 0
  _proof_count_send _proof_facts
  cat "$_PROOF_FACTS_FILE"
}

# _proof_findings_load <plan> -> 0 with _PROOF_FINDINGS set in the calling shell to every finding event of the plan's
# run, in the order the reader reads them, kept with the facts; 2 when the fold fails. A finding's facts come from all
# its events: a finding's deferral and a later move of it are two events, and the move, standing, would leave the
# deferral unread. A reader in this shell reads the one fold, and every later ask in this shell or a subshell is
# served from it. A plan whose findings a caller holds (`_proof_findings_hold`) is answered from what it holds, with
# no fold and no key: the held copy is restored each time, since a fold of another plan in between overwrites
# _PROOF_FINDINGS.
_proof_findings_load() {
  [ -f "${1:-}" ] || { _PROOF_FINDINGS=""; return 0; }
  if [ -n "${_PROOF_HELD_PLAN:-}" ] && [ "$_PROOF_HELD_PLAN" = "$1" ]; then _PROOF_FINDINGS="$_PROOF_HELD_FINDINGS"; return 0; fi
  _proof_facts "$1" >/dev/null
}

# _proof_findings_hold <plan> -> 0 with the plan's fold taken in the calling shell (_PROOF_FACTS) and its findings held,
# so every later reader of them in this shell or a subshell takes no fold; 2, nothing held, when the fold fails. No
# plan releases the hold. A hold is as fresh as the fold it took, so a caller holds only across reads that write no
# event, and declares the two _PROOF_HELD_* variables local to bound it.
_proof_findings_hold() {
  _PROOF_HELD_PLAN=""; _PROOF_HELD_FINDINGS=""; _PROOF_HELD_FACTS=""
  [ -n "${1:-}" ] || return 0
  _proof_findings_load "$1" || return 2
  _PROOF_HELD_FINDINGS="$_PROOF_FINDINGS"; _PROOF_HELD_FACTS="$_PROOF_FACTS"; _PROOF_HELD_PLAN="$1"
  # Inside a held command what is held is the fold's file, read by path (`_proof_held_facts_at`).
  _PROOF_HELD_FACTS_FILE=""; ! _proof_held_dir || _PROOF_HELD_FACTS_FILE="$_PROOF_HELD_FOLD"
}
# proof_held_facts <plan> -> the facts a caller holds for <plan> (`_proof_findings_hold`), exit 0; exit 1, nothing printed,
# when none are held for it or a proof is pending, which a hold does not hold: the caller then asks the fold.
proof_held_facts() {
  _proof_dry_step
  [ -n "${_PROOF_HELD_PLAN:-}" ] && [ "$_PROOF_HELD_PLAN" = "${1:-}" ] && [ -z "${_PROOF_PENDING:-}$_PROOF_DRY$_PROOF_DRY_BAD" ] || return 1
  _proof_count_send proof_held_facts
  if [ -n "${_PROOF_HELD_FACTS_FILE:-}" ]; then cat "$_PROOF_HELD_FACTS_FILE"; else printf '%s' "${_PROOF_HELD_FACTS:-}"; fi
}
# _proof_held_facts_at <plan> -> 0 with the facts a caller holds for <plan> ready as proof_facts_at leaves them; 1, when
# none are held for it or a proof is pending: the caller then asks proof_facts_at.
_PROOF_HELD_FACTS_FILE=""
_proof_held_facts_at() {
  _proof_dry_step
  [ -n "${_PROOF_HELD_PLAN:-}" ] && [ "$_PROOF_HELD_PLAN" = "${1:-}" ] && [ -z "${_PROOF_PENDING:-}$_PROOF_DRY$_PROOF_DRY_BAD" ] || return 1
  _PROOF_FACTS_FILE="${_PROOF_HELD_FACTS_FILE:-}"; _PROOF_FACTS_TEXT=""
  [ -n "$_PROOF_FACTS_FILE" ] || _PROOF_FACTS_TEXT="${_PROOF_HELD_FACTS:-}"
}

_proof_keep_sweep() {  # <dir> <n> -> the newest <n> files of <dir> are left, the rest removed; a directory is no file
  ls -tp "$1" 2>/dev/null | sed -e '/\/$/d' -e "1,${2}d" | while IFS= read -r f; do rm -f "$1/$f"; done
}

# ---------- THE RUN'S PLACE, HELD ----------
#
# Where a run stands is asked of every plan at session start and by every hook that scopes itself to a run, under a
# deadline, so it is not taken from the whole fold. proof_step_held answers it from the run's log, and keeps the three
# answers beside the kept fold, under a key of every file that answer is read from: the plan, its log, the reader's
# libraries and this one. An appended event, an edited line or a changed library is a new key, and the next ask folds
# again. A fold that failed is returned and never kept. This is the
# one reader and writer of the held file; it holds the answers and nothing else, in a directory of its own beside the
# kept fold's, and the kept fold's sweep (`_proof_keep_sweep`) sweeps it. The run's standing order and its sessions are
# held after the three, each line led by `order.` or `sessions.`: the same log holds them, so one fold answers all,
# and the runner asks the order at every suite's start and every engagement the sessions (`proof_order_held`,
# `proof_sessions_held`).
#
# A CALLER THAT DECIDES A COMMIT sets _PROOF_FRESH, and for it the held file is never read: it is a cache under
# $TMPDIR, and a cache rewritten by hand must not move the gate. Its place is folded from the log, then served again in
# that shell and its subshells from this shell's memory alone, under the same key, so one hook folds the run once. It
# neither reads nor writes the held file, which stays the other hooks' own.
_PROOF_STEP_KEEP=128
_PROOF_PLACE_LIBS=""; _PROOF_PLACE_DIR=""; _PROOF_PLACE_MEMO_KEY=""; _PROOF_PLACE_MEMO=""
proof_step_held() {  # <plan> -> n=<step> when one stands, state=open|delivered|abandoned, approved=1|0; exit 2, one line on stderr, when the fold fails
  # The answer is also left in _PROOF_PLACE, so a caller in this shell reads it with no subshell.
  local plan="${1:-}" log="" dir="" f stamp key held="" got ev tmp k rc=0 IFS=$' \t\n'
  local -a deps
  _PROOF_PLACE=""; _PROOF_PLACE_ORDER=""; _PROOF_PLACE_SESSIONS=""
  [ -f "$plan" ] || return 0
  _proof_reader_load || { printf 'proof_step_held: lib/reader.sh cannot be loaded, so the place of %s is not read\n' "$plan" >&2; return 2; }
  log="$(reader_log "$plan" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) dir="${log%/*}" ;;
    2) rc=0 ;;
    *) printf 'proof_step_held: the lookup of the run log of %s exited %s, so its place is not read\n' "$plan" "$rc" >&2; return 2 ;;
  esac
  # The libraries are summed once a shell and the place's directory is judged once a shell, since neither changes
  # under a process; the plan and its log are summed at every ask.
  if [ -z "$_PROOF_PLACE_LIBS" ]; then
    _proof_facts_libsum || :
    # A directory of its own beside the kept fold's, never inside it: a sweep of the kept folds meets no entry it
    # did not write. Trusted as the kept fold is, owned by this user and writable by no one else.
    _PROOF_PLACE_DIR="${TMPDIR:-/tmp}/bionic-place-${UID:-0}"
    [ -d "$_PROOF_PLACE_DIR" ] || mkdir -p -m 700 "$_PROOF_PLACE_DIR" 2>/dev/null
    [ -O "$_PROOF_PLACE_DIR" ] && [ -n "$(find "$_PROOF_PLACE_DIR" -prune -type d ! -perm -020 ! -perm -002 2>/dev/null)" ] \
      || _PROOF_PLACE_DIR=""
  fi
  # INSIDE A HELD COMMAND the place is read from the command's files (`_proof_facts_held`), the pending step laid over
  # them as the facts' overlay lays it (`_proof_out_at`) and a pending proof left out, so it serves a decider and a
  # reader alike, and it is kept in this shell's memory under the fold's key: the log is summed for no key of its own.
  # The held file under $TMPDIR is neither read nor written here: it stays the place of the hooks outside a hold.
  if _proof_held_dir; then
    ! _proof_dry_refused || return 2
    _PROOF_PENDING="" proof_facts_at "$plan" || rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$_PROOF_FACTS_KEY" ] && [ "$_PROOF_PLACE_MEMO_KEY" = "$_PROOF_FACTS_KEY|$_PROOF_DRY|held" ]; then
      _proof_place_split "$_PROOF_PLACE_MEMO"; printf '%s\n' "$_PROOF_PLACE"; return 0
    fi
    [ "$rc" -ne 0 ] || got="$( set -o pipefail; _PROOF_READ_FILE="$_PROOF_FACTS_FILE"
      reader_facts() { [ -z "$_PROOF_READ_FILE" ] || cat "$_PROOF_READ_FILE"; }
      reader_q_step "$plan" || exit; if reader_q_approved "$plan" step3; then echo approved=1; else [ "$?" -eq 1 ] || exit; echo approved=0; fi
      reader_q_order "$plan" | sed 's/^/order./' || exit; reader_q_sessions "$plan" | sed 's/^/sessions./' )" || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'proof_step_held: lib/reader.sh exited %s reading the place of %s; nothing is kept\n' "$rc" "$plan" >&2; return 2
    fi
    [ -z "$_PROOF_FACTS_KEY" ] || { _PROOF_PLACE_MEMO_KEY="$_PROOF_FACTS_KEY|$_PROOF_DRY|held"; _PROOF_PLACE_MEMO="$got"; }
    _proof_place_split "$got"; printf '%s\n' "$_PROOF_PLACE"; return 0
  fi
  # The log is summed less its turns' ends (`reader_log_stamp`): the place reads steps, abandons, approvals, orders and
  # binds alone, and a stop event comes at every turn.
  deps=("$plan")
  stamp="$(cksum "${deps[@]}" 2>/dev/null)" || stamp=""
  if [ -n "$stamp" ] && [ -n "$log" ] && [ -f "$log" ]; then
    _proof_count sum proof_step_held
    f="$(reader_log_stamp "$log")" && stamp="$stamp run.log less its stop events $f" || stamp=""
  fi
  key="$plan ${stamp//$'\n'/ } $_PROOF_PLACE_LIBS"
  # A step pending in an advance's own judgment is no place to keep: it is neither read from the held file nor kept in it.
  ! _proof_dry_refused || return 2
  if [ -n "$stamp" ] && [ -n "$_PROOF_PLACE_LIBS" ] && [ -n "$_PROOF_PLACE_DIR" ] && [ -z "$_PROOF_DRY" ] && [ -z "${_PROOF_FRESH:-}" ]; then
    held="${plan//[^A-Za-z0-9._-]/%}"; [ "${#held}" -le 200 ] || { held="$(cksum <<< "$plan")"; held="${held%% *}"; }
    held="$_PROOF_PLACE_DIR/$held"
  fi
  if [ -n "${_PROOF_FRESH:-}" ] && [ -n "$stamp" ] && [ "$_PROOF_PLACE_MEMO_KEY" = "$key|$_PROOF_DRY" ]; then
    _proof_place_split "$_PROOF_PLACE_MEMO"; printf '%s\n' "$_PROOF_PLACE"; return 0
  fi
  if [ -n "$held" ] && [ -f "$held" ] && { IFS= read -r k; got=""; while IFS= read -r f; do got="$got$f"$'\n'; done; } < "$held" \
     && [ "$k" = "$key" ] && [ -n "$got" ]; then
    _proof_place_split "$got"; printf '%s\n' "$_PROOF_PLACE"; return 0
  fi
  ev=""; [ -z "$dir" ] || ev="$(reader_events "$plan")" || rc=$?
  [ -z "$_PROOF_DRY" ] || ev="${ev:+$ev$'\n'}$_PROOF_DRY"
  [ "$rc" -ne 0 ] || got="$( set -o pipefail; reader_events() { printf '%s\n' "$ev"; }
    reader_q_step "$plan" || exit; if reader_q_approved "$plan" step3; then echo approved=1; else [ "$?" -eq 1 ] || exit; echo approved=0; fi
    reader_q_order "$plan" | sed 's/^/order./' || exit; reader_q_sessions "$plan" | sed 's/^/sessions./' )" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'proof_step_held: lib/reader.sh exited %s reading the place of %s; nothing is kept\n' "$rc" "$plan" >&2; return 2
  fi
  if [ -n "$held" ] && tmp="$(mktemp "$_PROOF_PLACE_DIR/.held.XXXXXX" 2>/dev/null)"; then
    printf '%s\n%s\n' "$key" "$got" > "$tmp" && mv -f "$tmp" "$held" 2>/dev/null || rm -f "$tmp"
    _proof_keep_sweep "$_PROOF_PLACE_DIR" "$_PROOF_STEP_KEEP"
  fi
  [ -z "${_PROOF_FRESH:-}" ] || [ -z "$stamp" ] || { _PROOF_PLACE_MEMO_KEY="$key|$_PROOF_DRY"; _PROOF_PLACE_MEMO="$got"; }
  _proof_place_split "$got"; printf '%s\n' "$_PROOF_PLACE"
}
_proof_place_split() {  # <held lines> -> _PROOF_PLACE, the place's lines, _PROOF_PLACE_ORDER and _PROOF_PLACE_SESSIONS, unled
  local l p="" o="" s=""
  while IFS= read -r l; do
    case "$l" in
      order.*) o="$o${l#order.}"$'\n' ;;
      sessions.*) s="$s${l#sessions.}"$'\n' ;;
      ?*) p="$p$l"$'\n' ;;
    esac
  done <<PROOF_HELD
$1
PROOF_HELD
  _PROOF_PLACE="${p%$'\n'}"; _PROOF_PLACE_ORDER="${o%$'\n'}"; _PROOF_PLACE_SESSIONS="${s%$'\n'}"
}
proof_order_held() {  # <plan> -> the reader's order answer for the run, from its held place; exits as proof_step_held's
  proof_step_held "${1:-}" >/dev/null || return
  [ -z "$_PROOF_PLACE_ORDER" ] || printf '%s\n' "$_PROOF_PLACE_ORDER"
}
proof_sessions_held() {  # <plan> -> the reader's sessions answer for the run, from its held place; exits as proof_step_held's
  proof_step_held "${1:-}" >/dev/null || return
  [ -z "$_PROOF_PLACE_SESSIONS" ] || printf '%s\n' "$_PROOF_PLACE_SESSIONS"
}

_proof_ask() {  # <plan> <reader question's function> [args] -> its answer and exit, over the facts _proof_facts keeps
  local plan="$1" facts; shift
  proof_facts_at "$plan" || return
  _proof_reader_load || return 1
  # Inside a held command the question reads the command's file by path, outside it the string as before. The path
  # rides in a name of this library's own, which no question's locals can shadow.
  if [ -n "$_PROOF_FACTS_FILE" ]; then ( _PROOF_READ_FILE="$_PROOF_FACTS_FILE"; reader_facts() { cat "$_PROOF_READ_FILE"; }; "$@" ); return; fi
  facts="$_PROOF_FACTS_TEXT"
  ( reader_facts() { printf '%s' "$facts"; }; "$@" )
}

# proof_fact_awk -> awk source over `run/v1` facts, beside lib/line.sh's `line_kv` and the reader's `ev()`: the
# function `proof_fact()`, the one reading (`proof_take`) of the record when it is a proof event, 0 for any other.
# `proof_fact_line()` prints the fact as the `proved:` line its writer writes, for a caller that quotes the line.
proof_fact_awk() {
  _proof_reader_load
  printf '%s' "$_READER_AWK$_PROOF_TAKE_AWK"'
    function proof_fact(   f, i, m) {
      split("", f); if (ev() == "proof") for (m = i = NF; i >= 2; i--) f[i] = $i
      return proof_take(f, m)
    }
    function proof_fact_line(   l) {
      l = "proved: kind=" line_kv("kind") " head=" PROOF_HEAD " at=" line_kv("at") " evidence=" PROOF_EVIDENCE
      if (PROOF_QUESTION != "") l = l " question=" PROOF_QUESTION " reader=" PROOF_READER " result=" PROOF_RESULT " scope=" PROOF_SCOPE
      else if (PROOF_RESULT != "") l = l " result=" PROOF_RESULT
      if (PROOF_OWED != "") l = l " owed=" PROOF_OWED
      if (line_kv("run") != "") l = l " run=" line_kv("run") " head=" PROOF_HEAD " rc=" line_kv("rc")
      if (PROOF_POINT != "") l = l " point=" PROOF_POINT
      return l
    }
  '
}

# proof_run_plan <plan> -> the plan whose run holds <plan>'s proofs: a plan writer's copy `<plan>.<verb>.<pid>` beside
# it names no record, and no copy adds a proof, so its proofs are its plan's run's, as lib/units.sh reads a row's state;
# any other plan is its own.
proof_run_plan() {
  local plan="${1:-}" o
  case "${plan##*/}" in
    *.plan.md.*) o="${plan%%.plan.md.*}.plan.md"; [ ! -f "$o" ] || plan="$o" ;;
  esac
  printf '%s' "$plan"
}

# proof_lines <plan> -> each standing proof of the plan's run as a `proved:` line
# (`proof_fact_line`), in the order the proofs were last set: one read of the kept fold for a caller whose awk reads
# proof lines (`proof_awk`), a copy read as its plan (`proof_run_plan`). A pending proof (`proof_pending`) stands last.
# Exit 2 when the facts cannot be read.
proof_lines() {
  local plan
  plan="$(proof_run_plan "${1:-}")"
  _proof_held_facts_at "$plan" || proof_facts_at "$plan" || return 2
  _proof_derive proof_lines "$plan" _proof_facts_proofs
}
# proof_fact_lines [<facts file>] < facts -> each proof among the `run/v1` facts of the file, else on stdin, as
# `proof_lines` prints it: for a caller that already holds the fold's answer, so the proofs cost no second entry into it.
proof_fact_lines() {
  # The proofs are taken out first by a plain match: the fact reader's field functions are paid on proofs alone.
  awk 'index($0, "run/v1|ev=proof|") == 1' "$@" | awk -F'|' "$(proof_fact_awk)"'proof_fact() { print proof_fact_line() }'
}
# _proof_facts_proofs -> `proof_fact_lines` over the facts proof_facts_at made ready, their file read by path
_proof_facts_proofs() {
  if [ -n "$_PROOF_FACTS_FILE" ]; then proof_fact_lines "$_PROOF_FACTS_FILE"
  elif [ -n "$_PROOF_FACTS_TEXT" ]; then printf '%s' "$_PROOF_FACTS_TEXT" | proof_fact_lines; fi
}

# proof_points <plan> -> `<row><TAB><head><TAB><evidence><TAB><owed>` for each point proof of the plan's run, in the order
# the proofs were last set, so a row's newest is its last line: THE ONE READER of a point's proof, which its row lands on
# and a fix row born of its red names. Exit 2 when the facts cannot be read.
proof_points() {
  local pl
  pl="$(proof_lines "${1:-}")" || return 2
  printf '%s\n' "$pl" | awk "$(proof_awk)"'
    proof_fields($0) && PROOF_KIND == "point" && PROOF_POINT != "" { printf "%s\t%s\t%s\t%s\n", PROOF_POINT, PROOF_HEAD, PROOF_EVIDENCE, PROOF_OWED }'
}

# proof_last <plan> <kind> [<question>] -> the head of the NEWEST standing proof of <kind> the reader holds for the
# plan's run, or nothing (`_proof_last_read`). With a <question>, the newest of that kind carrying
# `question=<question>`; with none, the newest of the kind whatever its question, 1.11.0's reading.
proof_last() {
  _proof_last_read "$1" "$2" head "${3:-}"
}

# proof_last_line <plan> <kind> [<question>] -> that same last line, whole, or nothing: what a
# refusal quotes when it names the proof it read (head and evidence), so no caller parses the plan.
proof_last_line() {
  _proof_last_read "$1" "$2" line "${3:-}"
}

# proof_chain_head <plan> <question> -> `<head> proof` or `<head> waiver`: the question's newest link among the reviews
# the reader holds (`reader reviews`, its review proofs and the user's waivers of a question, in fact order), its last
# review proof or its last waiver, whichever is later; nothing when it has neither. A waiver's head is read as the
# judge's chain reads it (`facts_state`): 7 to 40 hex. Exit 2, nothing printed, when the run's facts could not be read.
proof_chain_head() {
  local facts
  [ -f "${1:-}" ] && [ -n "${2:-}" ] || return 0
  facts="$(_proof_ask "$1" reader_q_reviews "$1")" || return 2
  printf '%s' "$facts" | awk -F'|' -v q="$2" "$(proof_fact_awk)"'
    proof_fact() && PROOF_KIND == "review" && PROOF_QUESTION == q { h = PROOF_HEAD; w = "proof"; next }
    ev() == "waiver" && line_kv("question") == q {
      wh = line_kv("head"); if (wh ~ /^[0-9a-f]+$/ && length(wh) >= 7 && length(wh) <= 40) { h = wh; w = "waiver" }
    }
    END { if (h != "") print h " " w }'
}

# proof_floor_absent <plan> -> the judge's words for a plan with no floor proof, `no regression proof on this
# plan yet`, exit 0, when the run's log holds no regression proof (proof_last's
# reading); nothing, exit 1, when it holds one, whatever its head or owed= (wave-35 T38; critic-structure-3,
# debt `unpinned-pair floor-absent`). THE ONE READER OF "IS THERE A FLOOR LINE": the commit wall's Step-7 arm
# (lib/walls.sh `_eg_refuse_floor_absent`, text only, A-orch-50), proof_state and facts_state ask it, so the
# wall and the judge cannot answer one plan's text two ways; both ask it before the floor judge, which therefore
# never asks it again. It reads the run's facts through `proof_last` and runs no git.
# Pinned by tests/canonical-sdlc-evidence-gate.test.sh §FLOOR-LINE FL-5, which drives both on one plan.
proof_floor_absent() {
  [ -n "$(proof_last "${1:-}" regression)" ] && return 1
  printf '%s' 'no regression proof on this plan yet'
}

# _proof_last_read <plan> <kind> <head|line|owed|evidence> [<question>] -> the one reader behind the two above, and the
# `owed=` or `evidence=` field of that newest proof, nothing when it carries none. The facts are the reader's
# (`_proof_facts`), in the order they were last set, so the newest is the last one standing. Exit 2, nothing printed,
# when they could not be read: no proof read is not the same answer as no proof held.
_proof_last_read() {
  local plan="$1" kind="$2" what="$3" q="${4:-}" facts
  # THE KIND ASKED FOR IS READ THROUGH THE MAP TOO (wave-38 T8): a caller asking for the old kind is answered as one
  # asking for the new, silently: the operand is code's, never a person's.
  declare -F alias_read >/dev/null 2>&1 && { alias_read kind "$kind" 2>/dev/null; kind="$ALIAS_TOKEN"; }
  [ -f "$plan" ] || return 0
  proof_facts_at "$plan" || return 2
  _proof_facts_awk -F'|' -v k="$kind" -v what="$what" -v q="$q" "$(proof_fact_awk)"'
    proof_fact() && PROOF_KIND == k && (q == "" || PROOF_QUESTION == q) { last = PROOF_HEAD; lastline = proof_fact_line(); lastowed = PROOF_OWED; lastev = PROOF_EVIDENCE }
    END { if (last != "") { if (what == "line") print lastline; else if (what == "owed") { if (lastowed != "") print lastowed }
      else if (what == "evidence") { if (lastev != "") print lastev } else print last } }'
}

# proof_pass_conflict <plan> <record path> <head> -> why <record path> cannot be registered for another
# pass at <head>, or nothing. ONE RECORD PATH IS ONE PASS: a finding event binds a
# pass (`proof_bind_awk`) and is keyed `<record>#<n>`, so a second pass on the same
# path would inherit the first pass's deferral or move. The key stays unique by
# construction when the path is registered for one pass only, so the verb asks here before it writes. A
# reading's proof line (one with a `question=`) whose `evidence=` is <record path> and whose head is not
# <head> prints `head <that head>`; otherwise, when a finding event names
# `<record path>#`, `settled <head>`. A reader relaunched on an unsettled record (the same head, no such
# line) gets nothing: it is admitted.
proof_pass_conflict() {
  local ev pl
  [ -f "$1" ] || return 0
  _proof_findings_load "$1" || return 2; ev="$_PROOF_FINDINGS"
  pl="$(proof_lines "$1")" || return 2
  { printf '%s\n\034\n' "$ev"; [ -z "$pl" ] || printf '%s\n' "$pl"; } | awk -v rec="$2" -v head="$3" "$(proof_awk)$(proof_bind_awk)"'
    $0 == "\034" { proofs = 1; next }
    !proofs { if (proof_binds($0, rec)) child = 1; next }
    proof_fields($0) && PROOF_QUESTION != "" { if (PROOF_EVIDENCE == rec && PROOF_HEAD != head && other == "") other = PROOF_HEAD }
    END { if (other != "") print "head " other; else if (child) print "settled " head }'
}

# proof_readings_derived <plan> <tree> -> `<evidence><TAB><written result><TAB><derived result>` for each
# reading (`kind=review` with a `question=`) of the plan's facts (`proof_lines`), the
# derived result what `_proof_reading_result` gives it (wave-28 T60; D33, AC-8.6; A-orch-161), and
# NOTHING when no finding event of the run binds a pass (`proof_bind_awk`): every derived result is then the
# written one. The finding events are the plan's, read once (`_proof_findings_load`); exit 2 when that fails. The commit wall judges text and reads no record, so its collector (hooks/bash-walls.sh)
# asks this once, from the step the wall reads (lib/walls.sh `eg_plan_reads_readings`), and hands the
# lines over; the wall and the judge answer a reading's result one way. ONE PASS OVER THE PLAN (T72): the
# readings and every binding event's state are gathered together (each reading's own lines come to the
# shell just before it), and only a reading a binding event names is derived from its record, so the cost
# is one plan read and one record read per bound reading, not a plan read per reading and per finding. <tree> is the project root whose docs root holds the records;
# with no docs root, the derived result is the written one.
#
# A FIXED FINDING BINDS TOO (wave-33 T13; REQ-5 AC-5.2, D6): with a <tree>, the plan's fixed findings
# (`proof_fixed`) are read once, and a reading one of whose findings a born row fixed at or after its head is
# derived as the judge derives it, so the wall and the judge read a fixed question one way.
proof_readings_derived() {
  # What the gate is handed is part of its verdict, so it is read from the log (`_PROOF_FRESH`).
  local _PROOF_FRESH=1 plan="${1:-}" tree="${2:-}" droot="" k a b c d tab="" nl fixed="" ev pl
  [ -f "$plan" ] || return 0
  nl=$'\n'
  _proof_findings_load "$plan" || return 2; ev="$_PROOF_FINDINGS"
  pl="$(proof_lines "$plan")" || return 2
  if [ -n "$tree" ]; then
    _proof_roots_load
    ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$tree" 2>/dev/null)"
    fixed="$(proof_fixed "$plan" "$tree")" || return 2
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
$(printf '%s\n\034\n%s\n' "$ev" "$pl" | PROOF_HAS_FIXED="${fixed:+1}" awk "$(proof_awk)$(proof_bind_awk)"'
    $0 == "\034" { proofs = 1; next }
    !proofs {
      if (!proof_binding($0)) next
      nbind++; id = proof_bound($0); ids[id] = 1
      m = proof_move_of($0); if (m != "") mv[id] = m
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
    }')
PROOF_READINGS
}

# _proof_roots_load -> lib/roots.sh loaded unless its readers are, for a caller that sourced proof.sh alone; exit 0
# whether or not it could be.
_proof_roots_load() { bionic_need roots.sh docs_root; bionic_need roots.sh config_value; return 0; }

# _proof_prose_load -> lib/prose.sh loaded unless its predicate is: the prose list has one home, which the floor's walk
# and the cover walk read here and the dispatch wall reads too. Exit 0 whether or not it could be.
_proof_prose_load() { bionic_need prose.sh prose_path; bionic_need prose.sh prose_list; return 0; }

# proof_state <plan> <tree> -> whether the plan's last regression proof stands at the working head, one
# line (wave-31 T25; REQ-4 AC-4.1, REQ-13 AC-13.4; D3; A-orch-23; wave-35 T9: D8, AC-1.3):
#
#     covered<TAB><head>       the proof names the working head and its whole run left nothing red; <head>
#                              is the working head judged, which the full-run wall names
#     owed<TAB><suites>        the proof names the working head, and these suites its whole run left red,
#                              comma-joined file names
#     uncovered<TAB><reason>   anything else, the reason in words: the first commit past the last whole run that
#                              no landing proves, the head that run read when it is not on this history, or the
#                              question that could not be answered; it never offers a second whole run
#
# THE READBACK A WALK READS IS THIS ANSWER CUT TO A LOG, so it is read as a fact and not recalled. The log holds the
# command that reaches the judge (`bash -c '. lib/proof.sh && proof_state <plan> <tree>'`; a verb that refuses before
# it asks the judge, as `current N --check` does on an unfinished matrix, is not a readback), the command's output,
# and `rc=<n>` as its last line. The first field of the output is `covered` at the working head, or `uncovered`
# naming a commit; no line of it offers a whole run. A log missing any of the three, or one whose first field is
# anything else, is refused as no readback.
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

# proof_whole_text <plan> <tree> [<head>] -> the full pass's state at <head>, the working head (`proof_branch_head`)
# when none is handed in, one line: `green at <F8>` when <head> is F, the last regression proof's head, and the judge
# (`_proof_floor_judge`, proof_state's) reads it covered there; `green at <F8>, <n> landings since moved no code` when
# the judge reads F covered and every commit on the first-parent line from F to <head> moved no code by the judge's own
# cover basis (`_facts_walk`: `prose` or `release`); `red at <F8>, <n> landings before this head` otherwise, n the
# first-parent commits from F to <head> (`1 landing` for one, on either line); `red at <F8>, not in this head's
# history` when F is not behind <head> or either cannot be read; `none` when the plan holds no regression proof.
# THE ONE PRINTER OF THE FULL PASS: the release card, the scorecard and close-out's continuation print this line and
# compute nothing of their own, so no two of them can disagree over one run. GREEN IS CONTENT, NOT POSITION: a full
# pass at F proves every head whose commits since F changed only docs, or only the release set with its check passing
# at each, because nothing a suite runs differs from F. A commit past F that moved code keeps the head red, even where
# the landings' own suites cover it to the judge, since no full pass ran over that code; a born row's landing is red
# here too unless its content alone is prose or release. The basis is the walk's, asked here and never re-derived, so
# this line and the judge's cover cannot disagree. Red is the safe direction: every question this cannot answer
# answers it.
proof_whole_text() {
  local h="${3:-}"
  # The working head is read here, before the key, so a branch that moves during the command is asked at its new head.
  [ -n "$h" ] || h="$(proof_branch_head "$1" "$2" 2>/dev/null)" || h=""
  _proof_tree_key "$1" "$2" "$h" && _proof_derive_ready "$1" || _PROOF_TREE_KEY=""
  _proof_derive proof_whole_text "$_PROOF_TREE_KEY" _proof_whole_made "$1" "$2" "$h"
}
_proof_whole_made() {
  local plan="$1" tree="$2" f fc c n
  f="$(proof_last "$plan" regression 2>/dev/null)"
  [ -n "$f" ] || { printf 'none\n'; return 0; }
  if [ -n "${3:-}" ]; then c="$(git -C "$tree" rev-parse --verify -q "${3}^{commit}" 2>/dev/null)" || c=""
  else c="$(proof_branch_head "$plan" "$tree" 2>/dev/null)" || c=""; fi
  fc="$(git -C "$tree" rev-parse --verify -q "${f}^{commit}" 2>/dev/null)" || fc=""
  n=""
  if [ -n "$c" ] && [ -n "$fc" ] && git -C "$tree" merge-base --is-ancestor "$fc" "$c" 2>/dev/null; then
    if [ "$fc" = "$c" ]; then
      case "$(_proof_floor_judge "$plan" "$tree" "$c" 2>/dev/null)" in covered*) printf 'green at %.8s\n' "$f"; return 0 ;; esac
    fi
    n="$(git -C "$tree" rev-list --first-parent --count "$fc..$c" 2>/dev/null)" || n=""
    case "$n" in
      ''|*[!0-9]*|0) : ;;
      *) if _proof_moved_no_code "$plan" "$tree" "$fc" "$c" "$n"; then
           if [ "$n" = 1 ]; then printf 'green at %.8s, 1 landing since moved no code\n' "$f"
           else printf 'green at %.8s, %s landings since moved no code\n' "$f" "$n"; fi
           return 0
         fi ;;
    esac
  fi
  case "$n" in
    1) printf 'red at %.8s, 1 landing before this head\n' "$f" ;;
    ''|*[!0-9]*) printf "red at %.8s, not in this head's history\n" "$f" ;;
    *) printf 'red at %.8s, %s landings before this head\n' "$f" "$n" ;;
  esac
}

# _proof_moved_no_code <plan> <tree> <F> <head> <n> -> 0 when the judge reads F covered and the judge's cover walk
# (`_facts_walk`, with the born landings and the proved release heads `facts_cover` hands it, no question) gives each of the
# <n> first-parent commits from <F> to <head> the basis `prose` or `release`; 1 otherwise. A walk that answers for
# fewer commits than <n>, or cannot answer, is no proof that nothing moved, so it reads 1.
_proof_moved_no_code() {
  local plan="$1" tree="$2" fc="$3" c="$4" n="$5" walk fixed rel born
  case "$(_proof_floor_judge "$plan" "$tree" "$fc" 2>/dev/null)" in covered*) : ;; *) return 1 ;; esac
  _proof_roots_load
  fixed="$(proof_fixed "$plan" "$tree")" && rel="$(_proof_release_proved "$plan" "$tree")" \
    && born="$(_facts_born_landings "$plan" "$tree" "$fixed")" || return 1
  walk="$(_facts_walk "$tree" "$(_facts_docs_prefix "$tree")" "$fc" "$c" "$born" "" "$rel")"
  [ -n "$walk" ] || return 1
  printf '%s\n' "$walk" | awk -v n="$n" '
    $1 != "cover" || ($3 != "prose" && $3 != "release") { bad = 1 }
    { k++ }
    END { exit (bad || k != n) }'
}

# proof_unproved_approved <plan> <head> -> 0 when the plan's newest `approved: merge-unproved` line names <head>, the
# 40-hex commit; 1 otherwise. THE PERSON'S WORD IS GIVEN AT A HEAD: a line at any other head is stale, so a head the
# branch moved to is asked again, as a release approval the head moved past is.
proof_unproved_approved() {
  local h
  h="$(_proof_approved_head "${1:-}" merge-unproved 2>/dev/null)" || return 1
  [ -n "${2:-}" ] && [ "$h" = "$2" ]
}

# proof_merge_ask <plan> <tree> <head> -> whether a merge at <head> is the person's to take on their word, read from the
# floor judge at <head> (`_proof_floor_judge`) and the whole suite's state (`proof_whole_text`). Exit 0, printing the
# whole suite's state at <head>, when the judge reads the floor covered or uncovered, no pass ran green at it and no word
# was given at it; over an uncovered floor the judge's reason follows it (`<state>; commit <c> (row <id>) is not proved:
# …`), so the person reads which landing no run proved before giving the word, as the refusal names it. Exit 1, nothing printed, when the pass ran green there or the word was given there. Exit 2, printing
# the suites still owed, when the judge reads the floor owed. A <head> that is the release entry's reviews part rendered
# fresh on its parent is judged at that parent (`proof_part_base`): the part is written after the pass and the word, from
# the lines they left, so it asks neither again. THE WORD ACCEPTS ABSENCE: covered (every landing proved by its own
# suites) and uncovered (a landing no run proved, or a head the run cannot reach) are proof missing, which the person may
# merge over; owed is a red the whole run reported, which no word waives. THE ONE RULE the release card's draw and the
# judge's regression exit both call, so the card asks the word on exactly the heads the gate honours it on.
proof_merge_ask() {
  local plan="$1" tree="$2" head="$3" at st
  st="$(_proof_floor_judge "$plan" "$tree" "$head" 2>/dev/null | awk 'NR == 1')"
  case "$st" in
    covered|uncovered"	"*) : ;;
    owed"	"?*) printf '%s\n' "${st#owed	}"; return 2 ;;
    *) return 1 ;;
  esac
  at="$(proof_part_base "$plan" "$tree" "$head")"
  proof_unproved_approved "$plan" "$head" && return 1
  [ "$at" = "$head" ] || ! proof_unproved_approved "$plan" "$at" || return 1
  case "$(proof_whole_text "$plan" "$tree" "$at")" in "green at "*) return 1 ;; esac
  case "$st" in
    uncovered"	"?*) printf '%s; %s\n' "$(proof_whole_text "$plan" "$tree" "$head")" "${st#uncovered	}" ;;
    *) proof_whole_text "$plan" "$tree" "$head" ;;
  esac
}

# proof_owed_needs <suites> -> the exit of a floor the whole run left red, one line: a fix row whose suites include
# <suites>, landed green, then the pass. No word of the person's is an exit here, so none is named.
proof_owed_needs() {
  printf 'needs: the pass — a fix row for %s, then the pass (session-poker.sh regression-run)\n' "${1:-the red suites}"
}

# proof_merge_decision <plan> <tree> <head> -> the decision number the newest release card rendered at <head> gives
# `approve:merge-unproved` (its replay table, `release-approval/v1|dec=<n>|key=…`), exit 0; nothing, exit 1, while no
# card whose header names <head> holds that key. THE ONE READING of the card's number for the merge word: the judge's
# exit names it, and a reply typed for the card replays it.
proof_merge_decision() {
  local plan="$1" tree="$2" head="$3" dir n
  _proof_roots_load
  declare -F docs_root >/dev/null 2>&1 && [ -n "$head" ] || return 1
  dir="$(docs_root "$tree" 2>/dev/null)/record/$(proof_plan_slug "$plan" 2>/dev/null)"
  [ -d "$dir" ] || return 1
  # shellcheck disable=SC2012  # page names are release-approval-<hex>[-<n>].md, no blank or line break in any
  n="$(ls -t "$dir"/release-approval-"${head:0:8}"*.md 2>/dev/null | while IFS= read -r f; do
    /usr/bin/grep -q "^release-approval/v1|plan=.*|head=$head|" "$f" 2>/dev/null || continue
    sed -n 's/^release-approval\/v1|dec=\([0-9][0-9]*\)|key=approve:merge-unproved|.*/\1/p' "$f" 2>/dev/null | head -1
    break
  done)"
  [ -n "$n" ] || return 1
  printf '%s\n' "$n"
}

# proof_unproved_needs <plan> <tree> <head> [<step>] -> the exit of a merge the whole suite has not run at, one line.
# THE EXIT IS THE STEP'S: at step 7 no release card can exist yet, so the exit is the pass:
# `needs: the pass — wait for it (the tick starts it once no row is ready), or start it: session-poker.sh regression-run`.
# At step 8, or with no step, it is the card's reply:
# `needs: the user — reply <n> on the release card (merge without a whole run at this head), or wait for the pass`,
# <n> the decision number the newest release card rendered at <head> gives `approve:merge-unproved` (its replay table,
# `release-approval/v1|dec=<n>|key=…`), or `<n>` while no card at that head holds it.
proof_unproved_needs() {
  local plan="$1" tree="$2" head="$3" step="${4:-}" n
  if [ "$step" = 7 ]; then
    printf 'needs: the pass — wait for it (the tick starts it once no row is ready), or start it: session-poker.sh regression-run\n'
    return 0
  fi
  n="$(proof_merge_decision "$plan" "$tree" "$head")" || n=""
  printf 'needs: the user — reply %s on the release card (merge without a whole run at this head), or wait for the pass\n' "${n:-<n>}"
}

# _proof_floor_judge <plan> <tree> <head> -> the floor's state at <head>, one line: `covered`, `owed<TAB><suites>`
# or `uncovered<TAB><reason>` (wave-35 T9; D8, D9, AC-1.3 to AC-1.6). THE JUDGE, which proof_state and facts_state
# both ask. The plan's last `kind=regression` proof names F and the suites its whole run left red (`owed=`); a suite
# the plan carries as inherited debt (`proof_inherited`) is not owed. At F the reds decide. Past F (`_proof_past_f`),
# each commit on the first-parent line after F is excused (its tree is its parent's, it changed docs only, or it is a
# release-set commit with a passing check) or is a landing whose row's suites are green at it, and each red F left
# is closed by a later green landing verdict of that suite; no second whole run is owed. A verdict is keyed by the
# commit it ran at, or by the row head a merge brought in. THE REDS ARE READ FIRST: a red still open answers owed
# whatever the commits past F hold, since the person's word covers a missing proof and never a known red; where no
# close can be placed (F or the head is no commit, or F is not behind the head) every red stays open. Only a floor
# with no open red asks the commits, and reads covered or uncovered. BOTH CALLERS ASK
# `proof_floor_absent` FIRST and answer an absent floor themselves, so the judge never sees a plan with no floor
# line; the call it made here never decided (wave-36 T12; C35). Should one reach it, the empty head is no commit
# and the answer is uncovered, the safe direction.
# _proof_floor_base <plan> <tree> -> 0 with _PF_H, the last regression proof's head as a commit, and _PF_OWED, the
# suites that proof's whole run left red less the plan's inherited debt; 1, _PF_H empty, when that head is no commit here,
# _PF_OWED read all the same: the reds are the proof line's own, readable with no git. THE ONE READING OF F the judge
# and the owed set share (wave-39 T24).
_proof_floor_base() {
  local plan="$1" tree="$2" h inh
  _PF_H=""
  _PF_OWED="$(_proof_last_read "$plan" regression owed)"
  inh="$(proof_inherited "$plan")" || return 1
  [ -z "$_PF_OWED" ] || [ -z "$inh" ] || _PF_OWED="$(PROOF_I=",$inh," awk -F, '{ for (i = 1; i <= NF; i++) if ($i != "" && !index(ENVIRON["PROOF_I"], "," $i ",")) o = o (o == "" ? "" : ",") $i; print o }' <<PROOF_OWED_IN
$_PF_OWED
PROOF_OWED_IN
)"
  h="$(proof_last "$plan" regression)"
  _PF_H="$(git -C "$tree" rev-parse --verify -q "${h}^{commit}" 2>/dev/null)" || { _PF_H=""; return 1; }
  return 0
}

_proof_floor_judge() {
  _proof_tree_key "$1" "$2" "$3" && _proof_derive_ready "$1" || _PROOF_TREE_KEY=""
  _proof_derive _proof_floor_judge "$_PROOF_TREE_KEY" _proof_floor_made "$@"
}
_proof_floor_made() {
  local plan="$1" tree="$2" c="$3" h owed why based=1 behind=0
  _proof_floor_base "$plan" "$tree" || based=0
  h="$_PF_H"; owed="$_PF_OWED"
  c="$(git -C "$tree" rev-parse --verify -q "${c}^{commit}" 2>/dev/null)" || c=""
  [ "$based" = 0 ] || [ -z "$c" ] || [ "$h" = "$c" ] || ! git -C "$tree" merge-base --is-ancestor "$h" "$c" 2>/dev/null || behind=1
  # Only the closes are asked here, never the commits: a commit no run proved must not hide a red still open.
  [ -z "$owed" ] || [ "$behind" = 0 ] || owed="$(_proof_open_reds "$plan" "$tree" "$h" "$c" "$owed")"
  [ -z "$owed" ] || { printf 'owed\t%s\n' "$owed"; return 0; }
  [ "$based" = 1 ] || { printf 'uncovered\tthe proved head is not a commit here\n'; return 0; }
  [ -n "$c" ] || { printf 'uncovered\tthe head %s is not a commit here\n' "$3"; return 0; }
  [ "$h" != "$c" ] || { printf 'covered\n'; return 0; }
  [ "$behind" = 1 ] \
    || { printf 'uncovered\tthe last whole run read %.12s, which is not in the history of %.12s\n' "$h" "$c"; return 0; }
  why="$(_proof_past_f "$plan" "$tree" "$h" "$c" "")" && { printf 'covered\n'; return 0; }
  printf 'uncovered\t%s\n' "${why:-the commits since ${h:0:12} cannot be read}"
}

# _proof_past_f <plan> <tree> <F> <head> <owed> [<only>] -> exit 0, printing nothing, when every commit on the first-parent line
# F..<head> is excused or proved and every suite of <owed> (comma-joined) is closed; exit 2 printing the suites still
# open, comma-joined; exit 1 printing one sentence naming the first commit that is not proved and what it lacks.
# EXCUSED: its class on the walk (`_proof_path_walk`) is prose, a tree that is its first parent's among them; or
# release, and a check passed at it (`proof_check_passes`).
# PROVED: each suite its row's landing names (the row's last `ready` before the `published` event naming the commit;
# with no such event, the suites the landing verdicts at it name) has a newest record at it that is green. A record is
# at the commit it ran at, or at the row head a merge commit brought in as its second parent.
# CLOSED: a red of F has a newest landing verdict (never a stamp, never a whole run) green at a commit after F.
# With <only> `closes` the commits are not judged: exit 0 or 2 says only which suites of <owed> are still open.
_proof_past_f() {
  local plan="$1" tree="$2" from="$3" to="$4" owed="${5:-}" only="${6:-}" walk rec recs chk
  walk="$(git -C "$tree" log --first-parent --reverse --format='W%x09%H%x09%T%x09%P' "$from..$to" 2>/dev/null)" || {
    printf 'git cannot list the commits from %.12s to %.12s' "$from" "$to"; return 1; }
  rec="$(proof_debt_record "$plan" "$tree" 2>/dev/null)" || rec=""
  recs="$(_proof_records "$tree" "$rec")"
  # The closes alone ask nothing of the paths or the checks: each commit's proof is skipped below.
  [ "$only" != closes ] || { printf '%s\n%s\n' "$walk" "$recs" | _proof_past_f_awk closes "$owed"; return $?; }
  _proof_roots_load
  chk="$(proof_check_passes "$plan" "$tree")" || { printf 'the run'"'"'s facts cannot be read, so no check at a commit past %s is known' "${from:0:12}"; return 1; }
  _proof_path_walk "$tree" "$from" "$to" || :
  printf '%s\n%s\n%s\n%s\n' "$walk" "$recs" "$_PROOF_WALK" "$(printf '%s\n' "$chk" | sed '/^$/d; s/^/K	/')" \
    | _proof_past_f_awk all "$owed"
}

# _proof_path_walk <tree> <from> <to> -> 0, _PROOF_WALK a `C<TAB><commit><TAB><prose><TAB><release>` line per
# first-parent commit past <from>, oldest first, a class 1 when every path it touched is prose (`prose_path`) or in the
# release set (`_proof_release_path`), so CHANGELOG.md spoils neither; 1, empty, when git cannot list the range. THE
# ONE WALK of the cover (`_facts_walk`) and the regression (`_proof_past_f`), in the caller's shell.
_proof_path_walk() {
  local tree="$1" files f c="" prose=1 rel=1 plist
  _PROOF_WALK=""
  # The prose list, the docs homes among its entries, is read once for the walk and asked per path with no fork.
  _proof_prose_load
  plist="$(prose_list "$tree" 2>/dev/null)"
  files="$(git -C "$tree" log --reverse --first-parent -m --no-renames --name-only --format='%x01%H' "$2..$3" 2>/dev/null)" || return 1
  while IFS= read -r f; do
    case "$f" in
      '') continue ;;
      $'\001'*) [ -z "$c" ] || _PROOF_WALK="$_PROOF_WALK"$'\n'"C	$c	$prose	$rel"; c="${f#?}"; prose=1; rel=1; continue ;;
    esac
    [ "$rel" = 0 ] || _proof_release_path "$f" || rel=0
    [ "$prose" = 0 ] || prose_path "$f" "$plist" || prose=0
  done <<PROOF_PATH_WALK
$files
PROOF_PATH_WALK
  [ -z "$c" ] || _PROOF_WALK="$_PROOF_WALK"$'\n'"C	$c	$prose	$rel"
}

# _proof_past_f_awk <all|closes> <owed> -> the fold `_proof_past_f` judges its walk, records, paths and checks with, on
# stdin; at `closes` each commit's proof is skipped and only the closes of <owed> are read, as the health line asks.
_proof_past_f_awk() {
  PROOF_ONLY="$1" PROOF_OWED_SET="$2" awk -F'\t' '
    $1 == "W" { n++; wc[n] = $2; wt[n] = $3; np = split($4, p, " "); wp[n] = p[1]; wq[n] = (np > 1 ? p[2] : ""); tof[$2] = $3; next }
    $1 == "K" { chk[$2] = 1; next }
    $1 == "O" { if ($3 != "" && index($3, "—") != 1) orow[$2] = $3; if ($4 != "" && $4 != "-") osu[$2] = $4; next }
    $1 == "R" {
      k = $3 SUBSEP $4
      if (!(k in rat) || $2 >= rat[k]) { rat[k] = $2; rres[k] = $5 }
      if ($6 == "verdict") { if (!(k in vat) || $2 >= vat[k]) { vat[k] = $2; vres[k] = $5 }; vs[$3] = vs[$3] "," $4 }
      next
    }
    $1 == "C" { touched[$2] = 1; if ($3 != 1) nondoc[$2] = 1; if ($4 != 1) notrel[$2] = 1; next }
    function at(c, q, s,   r) { r = ""; if ((c SUBSEP s) in rat) { r = rres[c, s]; w = rat[c, s] }
      if (q != "" && (q SUBSEP s) in rat && (r == "" || rat[q, s] >= w)) r = rres[q, s]; return r }
    END {
      for (i = 1; i <= n && ENVIRON["PROOF_ONLY"] != "closes"; i++) {
        c = wc[i]
        if (!(c in touched) || !(c in nondoc)) continue
        if (!(c in notrel) && (c in chk)) continue
        su = (c in osu) ? osu[c] : substr(vs[c] (wq[i] != "" ? vs[wq[i]] : ""), 2)
        who = (c in orow) ? "row " orow[c] : "no landing row"
        lead = "commit " substr(c, 1, 12) " (" who ") is not proved: "
        m = split(su, a, ","); lack = ""; split("", seen)
        if (m == 0) { print lead "no run of its row\047s suites is recorded at it"; exit 1 }
        for (x = 1; x <= m; x++) {
          s = a[x]; sub(/.*\//, "", s); if (s == "" || s == "?" || (s in seen)) continue; seen[s] = 1
          r = at(c, wq[i], s)
          if (r == "green") continue
          lack = lack (lack == "" ? "" : "; ") s (r == "" ? " has no run recorded at it" : " is red at it")
        }
        if (lack != "") { print lead lack; exit 1 }
      }
      no = split(ENVIRON["PROOF_OWED_SET"], o, ","); open = ""
      for (x = 1; x <= no; x++) {
        s = o[x]; if (s == "") continue; r = ""; w = ""
        for (i = 1; i <= n; i++) for (j = 0; j < 2; j++) {
          q = (j == 0) ? wc[i] : wq[i]; if (q == "" || !((q SUBSEP s) in vat)) continue
          if (w == "" || vat[q, s] >= w) { w = vat[q, s]; r = vres[q, s] }
        }
        if (r != "green") open = open (open == "" ? "" : ",") s
      }
      if (open != "") { printf "%s", open; exit 2 }
    }'
}

# _proof_open_reds <plan> <tree> <F> <head> <owed> -> the suites of <owed> still open past F, F behind <head>, by
# `_proof_past_f`'s closes; all of them when those cannot be read. THE ONE FOLD of the judge and the health line.
_proof_open_reds() {
  local open
  open="$(_proof_past_f "$@" closes)"
  case $? in 0) : ;; 2) printf '%s\n' "$open" ;; *) printf '%s\n' "$5" ;; esac
}

# proof_health_line <plan> <tree> [<record plan>] -> the matrix head's `stack-health:` value, one line, exit 0: the judge's
# fact about the plan's last regression proof, rendered, so every writer of the line writes the same words.
#   pending                                                     the plan has no regression proof
#   green head=<F>[ pass=<n> total=<m>] evidence=<logs>          the whole run at F left nothing owed
#   red head=<F>[ pass=<n> total=<m>] owed=<open>[ closed=<closed>] evidence=<logs>   otherwise
# GREEN MEANS THE FULL PASS RAN GREEN AT THAT HEAD: a landing that greens a suite F left red closes it (`closed=`, the
# judge's own closes, `_proof_open_reds`) and drops it from `owed=`, which may end empty, and the line stays red.
# The owed set is the proof line's own, inherited debt included, since the pass at F was not green with it. pass= and
# total= are summed over the proof's logs (`proof_run_counts`) and dropped when any log carries no `Gating:` count. The
# closes are read from F to the working branch's head; a head git cannot place after F closes nothing. <record plan> is
# the plan whose landing record and working branch are read, for a <plan> that is the copy a verb writes (default <plan>).
proof_health_line() {
  local plan="${1:-}" tree="${2:-}" rplan="${3:-${1:-}}" f fc owed ev docs log n pass=0 total=0 counted=1 open="" closed="" c
  # The proof is the run's, read from the plan whose record holds its log (a verb's copy names none), with the proof the
  # verb is registering pending in it (`proof_pending`).
  f="$(proof_last "$rplan" regression)" && owed="$(_proof_last_read "$rplan" regression owed)" \
    && ev="$(_proof_last_read "$rplan" regression evidence)" || return 2
  [ -n "$f" ] || { printf 'pending\n'; return 0; }
  _proof_roots_load
  ! declare -F docs_root >/dev/null 2>&1 || docs="$(docs_root "$tree" 2>/dev/null)"
  while IFS= read -r log; do
    [ -n "$log" ] || continue
    case "$log" in /*) : ;; *) log="${docs:-.}/$log" ;; esac
    n="$(proof_run_counts "$log")"
    if [ -z "$n" ]; then counted=0; continue; fi
    pass=$(( pass + ${n%% *} )); total=$(( total + ${n#* } ))
  done <<PROOF_HEALTH_LOGS
$(printf '%s\n' "$ev" | tr ',' '\n')
PROOF_HEALTH_LOGS
  [ -n "$ev" ] || counted=0
  n=""; [ "$counted" = 0 ] || n=" pass=$pass total=$total"
  if [ -z "$owed" ]; then printf 'green head=%s%s evidence=%s\n' "$f" "$n" "$ev"; return 0; fi
  open="$owed"
  fc="$(git -C "$tree" rev-parse --verify -q "${f}^{commit}" 2>/dev/null)" || fc=""
  c="$(proof_branch_head "$rplan" "$tree" 2>/dev/null)" || c=""
  if [ -n "$fc" ] && [ -n "$c" ] && [ "$fc" != "$c" ] && git -C "$tree" merge-base --is-ancestor "$fc" "$c" 2>/dev/null; then
    open="$(_proof_open_reds "$rplan" "$tree" "$fc" "$c" "$owed")"
  fi
  closed="$(PROOF_O=",$open," awk -F, '{ for (i = 1; i <= NF; i++) if ($i != "" && !index(ENVIRON["PROOF_O"], "," $i ",")) o = o (o == "" ? "" : ",") $i; print o }' <<PROOF_HEALTH_OWED
$owed
PROOF_HEALTH_OWED
)"
  printf 'red head=%s%s owed=%s%s evidence=%s\n' "$f" "$n" "$open" "${closed:+ closed=$closed}" "$ev"
}

# proof_owed_suites <plan> <tree> [<head>] -> `*` when <head> (default: the working branch's ref, `proof_branch_head`)
# owes a whole run: it is not F, the head of the regression's newest link (`_proof_floor_base`), or there is none.
# Nothing at F; a waiver makes its own head F. No suite is ever named: the suites F's whole run left red (`owed=`)
# are the judge's.
# Exit 0; 1 when the plan or the head cannot be read.
proof_owed_suites() {
  local plan="${1:-}" tree="${2:-}" c="${3:-}"
  [ -f "$plan" ] || return 1
  [ -n "$c" ] || c="$(proof_branch_head "$plan" "$tree" 2>/dev/null)" || return 1
  c="$(git -C "$tree" rev-parse --verify -q "${c}^{commit}" 2>/dev/null)" || return 1
  _proof_floor_base "$plan" "$tree" && [ "$_PF_H" = "$c" ] && return 0
  printf '*\n'
}

# _proof_run_load -> lib/run.sh loaded unless its working-branch reader is; exit 0 whether or not it could be.
_proof_run_load() { bionic_need run.sh plan_working_branch; return 0; }

# proof_regression <plan> -> `no` when the plan's leading frontmatter says `regression: no`, else `yes`;
# exit 0 (wave-31 T27; REQ-12 AC-12.2; D4). THE REGRESSION IS A STEP-0 SETTING: `session-poker.sh
# regression` writes the key, and at `no` the run owes no floor. AN ABSENT KEY, OR ANY VALUE BUT `no`,
# READS `yes`, fail-closed as an absent `walk:` reads `required`: only the explicit word relaxes
# anything. The key's sibling `regression-override:` records who chose against the scale default; it is
# never read here. One reading for facts_owed below and lib/units.sh's integrate default; the Step-5
# arm (lib/walls.sh validate_tests_block), dispatch preflight and the card read the same key through
# the same function, lib/run.sh `plan_regression` (wave-33 T15), which this only maps to a word.
proof_regression() {
  bionic_need run.sh plan_regression
  if [ "$(plan_regression "${1:-}")" = no ]; then printf 'no\n'; else printf 'yes\n'; fi
}

# facts_owed <rigor> <scale> [<tree>] [<plan>] -> one line per fact a run owes, exit 0; nothing and
# exit 1 when <rigor> is not one PROOF_DEALING knows or <scale> is no row of the scale profile
# (wave-27 T9; D2):
#
#     floor                                          the full run, proof_state's question; not
#                                                    dealt when <plan> reads `regression: no`
#                                                    (proof_regression, wave-31 T27; REQ-12 AC-12.2)
#     review<TAB><question><TAB><role><TAB>piece     each question, for the role the rigor deals it
#     review<TAB><question><TAB><role><TAB>whole     one more per code question where the scale's
#                                                    dealing cell reads piece+whole (D10; wave-38
#                                                    T16, D25: lib/scale.sh, the wave row)
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
  local owed r="" floor=1 dealing
  # THE WORD IS READ AS ITS LEVEL (wave-28 T44; wave-30 T11, D1). The dealing is keyed by the level
  # words themselves, so the plan's word is read through lib/run.sh `rigor_level` and a word that is
  # no level deals nothing. A copy of this file read where run.sh cannot be found (a suite's
  # doctored copy) reads the word as written.
  bionic_need run.sh rigor_level
  if ! declare -F rigor_level >/dev/null 2>&1; then
    r="${1:-}"
  else
    r="$(rigor_level "${1:-}" 2>/dev/null)" || r=""
  fi
  [ -z "${4:-}" ] || [ "$(proof_regression "$4")" != no ] || floor=0
  # THE SCALE'S READS ARE ITS DEALING CELL (wave-38 T16; D25): `piece`, or `piece+whole` for one more
  # read of the whole per code question, from lib/scale.sh. WHO reads stays PROOF_DEALING's, per rigor.
  # A scale the profile does not hold deals nothing. A copy of this file read where scale.sh cannot
  # be found (a suite's doctored copy, as for run.sh above) has no profile to ask: it deals a piece
  # read per question for a non-empty scale word, the reading with no row's extra read in it.
  bionic_need scale.sh scale_cell
  if declare -F scale_cell >/dev/null 2>&1; then
    dealing="$(scale_cell "${2:-}" dealing 2>/dev/null)" || return 1
  else
    [ -n "${2:-}" ] || return 1
    dealing=piece
  fi
  owed="$(PROOF_D="$PROOF_DEALING" PROOF_Q="$PROOF_QUESTIONS" PROOF_C="$PROOF_CODE_QUESTIONS" awk -v r="$r" -v dealing="$dealing" -v floor="$floor" '
    BEGIN {
      n = split(ENVIRON["PROOF_D"], d, " ")
      for (i = 1; i <= n; i++) if (r != "" && index(d[i], r "=") == 1) roles = substr(d[i], length(r) + 2)
      if (roles == "") exit 1
      m = split(ENVIRON["PROOF_Q"], q, " "); split(roles, role, ",")
      if (floor == 1) print "regression"
      for (i = 1; i <= m; i++) print "review\t" q[i] "\t" role[i] "\tpiece"
      if (dealing == "piece+whole")
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
# landing record owes, in the order the record first names them. A DEBT IS OWED BECAUSE `land` WROTE IT: the log's
# `admitted` events (lib/worktree.sh `_wt_debt_write`, before the merge) that no `void` event names. A `landed red:` line in the plan is
# not read: missing, misshapen or hand-edited, it changes nothing. <tree> is the plan's checkout
# root, read from the plan's directory when not given.
proof_debts() {
  local rec
  rec="$(proof_debt_record "${1:-}" "${2:-}")" || return 0
  proof_debts_read "$rec" | awk -F'\t' '{ print "debt\t" $1 "\t" $2 }'
}

# proof_debt_record <plan> [<tree>] -> `<docs-root>/record/<the plan's name less .plan.md>/run.log`,
# the run's log, the record `land` writes for that plan (lib/worktree.sh `_wt_proofs_path`, the
# same rule: this file does not load worktree.sh). rc 1 when no path can be named. It takes a plan path and no
# session, since the judge asks it with none.
proof_debt_record() {
  local plan="${1:-}" tree="${2:-}" slug
  [ -f "$plan" ] || return 1
  slug="$(proof_plan_slug "$plan")" || return 1
  [ -n "$tree" ] || tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$tree" ] || return 1
  _proof_roots_load
  declare -F docs_root >/dev/null 2>&1 && _proof_reader_load || return 1
  printf '%s' "$(reader_log_in "$(docs_root "$tree")/record/$slug")"
}

# proof_plan_slug <plan> -> the plan's slug, the directory its run's records live in, `<docs-root>/record/<slug>/`:
# every site in the hooks and the scripts that names a run's landing record, ledger,
# brief or continuation from a plan path asks it, and it asks the record's one name rule, lib/reader.sh `reader_slug`
# (an epic's plan is named for its folder), so a second slug is never derived beside it. It reads the name it is
# given: a file named `X.plan.md.anything` reads its own name, not X's record. The file need not exist. rc 1 when the
# name leaves no slug or the rule cannot be loaded.
proof_plan_slug() {
  declare -F reader_slug >/dev/null 2>&1 || _proof_reader_load || return 1
  reader_slug "${1:-}"
}

# proof_debts_read <record> -> `<suite><TAB><token><TAB><time>` once per suite and token with an
# `admitted` event of the run's log no `void` event names (lib/line.sh `line_lines`), the time the NEWEST of
# those events' `at=`: each red landing is a
# debt of its own, and two on one suite and token are both covered
# only by a green run after the later one. A line whose `at=` is no <ISO-UTC> leaves the time empty,
# and an empty time is never covered.
proof_debts_read() {
  _proof_fields && line_held "${1:-}" || return 0
  # no field read here (an id, a suite, a token, an instant) holds a blank, so a blank splits as a bar does
  line_lines "$1" | awk -F'[| ]' "$_LINE_FIELDS_AWK"'
    { e = line_ev() }
    e == "void" { v = line_kv("id"); if (v != "") voided[v] = 1; next }
    e == "admitted" { n++; id[n] = line_kv("id"); su[n] = line_kv("suite"); tk[n] = line_kv("token"); at[n] = line_kv("at") }
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
    }' 2>/dev/null
}

# proof_debts_open <debts> < <approval and proof lines> -> `debt<TAB><suite><TAB><token>` for each of <debts>
# (`proof_debts_read`'s lines, `<suite><TAB><token><TAB><time>`, what `land` wrote) that the run's lines on stdin
# leave open. This is the commit
# gate's predicate (lib/walls.sh `_eg_reading_gaps`), over two facts it is handed: the debts its
# collector read from the landing record (hooks/bash-walls.sh) and the run's approvals and proofs
# (`proof_approval_lines`, `proof_lines`). A debt stays open until a `proved: kind=floor` or `kind=task` line
# carries an `at=` STRICTLY later than its threshold: the red landing's own time, and for an
# `approval:<name>` debt the later of that and the first `approved: <name> by <who> <ISO-UTC> …`
# line, with none of which it stays open. A debt with no time is never cleared. Whether a task log
# shows the suite green is the judge's to read (`_facts_debt`), not this text's.
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
      '"$(_proof_alias_norm kind k)"'
      if ((k == "regression" || k == "task") && at ~ iso && at > latest) latest = at
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
#     unproved<TAB><state><TAB><exit>
#                              the regression only: the landings past the whole run cover <head>, no pass ran
#                              at it and the person gave no word at it; the whole suite's state and the exit
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
# order they were written. `proof_attested` held each reading, when the verb wrote
# it, to start at or before its question's last head, and a question's first reading at or before
# the plan's base, refusing it on a plan with no base (wave-27 T45; review pass 13 F1, F9). So the
# judge, too, judges only a plan whose base-sha: is a commit: with none, the start of no chain can be
# held, and it exits 2, for every dealing owes a reading. <head> must resolve to a commit, or it exits
# 2, and each line's head is compared with the commit it resolves to, never as a string (F10). The
# chain holds at <head> when its newest link is no failing reading and that link's head is
# <head>, or every commit past it holds by the one cover rule (the COVER block below
# `facts_state`): its paths are all prose (the docs root, or a path on the prose list, lib/prose.sh), or every
# path is in the release set and a release check passes at it, or it is the landing of a row born of a
# registered reading's finding (any question's) or of the floor's red. Any other commit owes, whatever its row was declared to be; `facts_cover` prints each commit's basis. A waiver covers its
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
# regression proof it is absent. A covered or uncovered floor holds only where the whole suite ran green at <head> or
# the person gave their word at it (`proof_merge_ask`); past F otherwise it is
#     unproved<TAB><the whole suite's state, proof_whole_text's><TAB><its exit, proof_unproved_needs's>
# the merge-without-a-pass the release card asks. An owed floor is owed<TAB><suites><TAB><its exit, proof_owed_needs's>.
# <head> is the caller's, read from the working branch's ref (`proof_branch_head`), never a checkout's.
# An owed line this judge has no rule for answers absent (the safe direction).
# A FINDING RE-RATED BY A MOVE (wave-28 T42; D34): a reading's result is the one its findings give at
# their effective ratings (`_proof_reading_result`). No check holds the step: a reader's rating is
# final, and a `check:` line in a plan is not read.
# IT READS GIT, so a verb, the tick and close-out call it, never a wall: a wall is handed its answer
# (the freeze, .claude/rules/hook-authoring.md).
# ONE ANSWER A HEAD, A COMMAND (`_proof_held_dir`): inside a held command the judge's answer at a head is computed once
# and served to every later ask of the same plan at the same commit, over the same fold and the same pending lines: in
# this shell, and through the command's directory in its subshells and other processes. Its print, its words on stderr
# and its exit are served as they were made. The key names the head as the commit it resolves to, so a branch that
# moves is a new key; and the fold it names is the log's, so a decider is never served an answer made of the kept file.
# Outside a held command it is computed at every ask, as before.
_FS_HELD_KEY=""; _FS_HELD=""
facts_state() {
  local _fs_k="" _fs_f="" _fs_got="" _fs_tmp _fs_e
  # A judgment's entry inside a held command: its first ask sums the log (`_proof_facts_held`), so it judges the log as
  # it stands now.
  ! _proof_held_dir || local _PROOF_FRESH=1
  if _proof_held_dir && _facts_state_key "${1:-}" "${2:-}"; then
    _fs_k="$_FS_KEY"
    if [ "$_FS_HELD_KEY" = "$_fs_k" ]; then _fs_got="$_FS_HELD"
    else
      _fs_f="$_PROOF_HELD_DIR/facts-$(printf '%s' "$_fs_k" | cksum | tr -c '0-9\n' '-')"
      if [ -f "$_fs_f" ] && _fs_got="$(cat "$_fs_f"; printf x)" && [ "${_fs_got:0:${#_fs_k}}" = "$_fs_k" ]; then
        _fs_got="${_fs_got%x}"; _fs_got="${_fs_got:${#_fs_k}}"; _FS_HELD_KEY="$_fs_k"; _FS_HELD="$_fs_got"
      else _fs_got=""; fi
    fi
    if [ -n "$_fs_got" ]; then _facts_state_replay "$_fs_got"; return; fi
  fi
  [ -z "${BIONIC_COUNT:-}" ] || printf 'facts facts_state\n' 2>/dev/null >>"$BIONIC_COUNT" || :
  [ -n "$_fs_k" ] || { _facts_state_judge "$@"; return; }
  _fs_e="$(mktemp "$_fs_f.e.XXXXXX" 2>/dev/null)" || { _facts_state_judge "$@"; return; }
  # The print is taken whole, its last newline too, by the mark after it; the exit rides after the mark.
  _fs_got="$(_facts_state_judge "$@" 2>"$_fs_e"; printf '\036%s' "$?")"
  _fs_got="${_fs_got##*$'\036'}"$'\n'"${_fs_got%$'\036'*}"$'\036'"$(cat "$_fs_e"; printf x)"; _fs_got="${_fs_got%x}"
  rm -f "$_fs_e"
  _FS_HELD_KEY="$_fs_k"; _FS_HELD="$_fs_got"
  _fs_tmp="$(mktemp "$_fs_f.XXXXXX" 2>/dev/null)" \
    && { { printf '%s' "$_fs_k"; printf '%s' "$_fs_got"; } > "$_fs_tmp" && mv -f "$_fs_tmp" "$_fs_f" 2>/dev/null || rm -f "$_fs_tmp"; }
  _facts_state_replay "$_fs_got"
}
# _facts_state_key <plan> <head> -> 0 with _FS_KEY the held answer's key, the plan's fold taken in this shell; 1 when
# the plan, its tree or the head cannot be read, or the fold is not the log's, and the judge is then asked unheld.
_facts_state_key() {
  local tree c
  _FS_KEY=""
  [ -f "$1" ] && [ -n "$2" ] && _proof_reader_load || return 1
  tree="$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$tree" ] || return 1
  c="$(git -C "$tree" rev-parse --verify -q "$2^{commit}" 2>/dev/null)" && [ -n "$c" ] || return 1
  _proof_facts "$1" >/dev/null 2>&1 && [ -n "$_PROOF_FACTS_KEY" ] && [ -n "$_PROOF_FACTS_LOG" ] || return 1
  _FS_KEY="facts_state $1 at=$c lib=$_READER_LIB_DIR fold=$_PROOF_FACTS_KEY"$'\n'"${_PROOF_PENDING:-}"$'\n'"$_PROOF_DRY"$'\n'$'\035'$'\n'
}
_facts_state_replay() {  # <exit, a newline, the print, \036, the words on stderr> -> each given back, the exit last
  local rc="${1%%$'\n'*}" rest="${1#*$'\n'}"
  printf '%s' "${rest%%$'\036'*}"
  rest="${rest#*$'\036'}"; [ -z "$rest" ] || printf '%s' "$rest" >&2
  return "$rc"
}
_facts_state_judge() {
  local plan="${1:-}" head="${2:-}" rigor scale owed tree droot="" pfx chains fact kind q role scope st rc=0
  local x pt pr ph pe wt wr we wh cb ws fixed="" born="" chk="" walked="|"
  [ -f "$plan" ] || { printf 'facts_state: %s is not a plan file\n' "$plan" >&2; return 2; }
  bionic_need run.sh plan_frontmatter_get
  # THE DOCS ROOT IS PROSE TO THE WALK (wave-36 T31; A-T28-9): the judge loads lib/roots.sh itself, as facts_cover
  # does, so no caller needs a load of its own for `docs_root`.
  _proof_roots_load
  # WHAT IS OWED IS THE ONE DEALING (facts_owed) OVER THE PLAN'S HEADER, read by the reader; WHAT STANDS IS THE
  # READER'S REVIEWS ANSWER, below. The rule stays in facts_owed, so the judge and the reader cannot deal two ways.
  _proof_reader_load
  rigor="$(reader_q_header "$plan" rigor 2>/dev/null)"; rigor="${rigor#rigor=}"
  scale="$(reader_q_header "$plan" scale 2>/dev/null)"; scale="${scale#scale=}"
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
  # FACTS THAT COULD NOT BE READ ARE NO ANSWER: every read of them below exits 2 with the judge's line, never absent.
  x="$(_proof_ask "$plan" reader_q_reviews "$plan")" || { _facts_unread "$plan"; return; }
  chains="$(printf '%s' "$x" | awk -F'|' -v qs="$PROOF_QUESTIONS" "$(proof_fact_awk)"'
    proof_fact() && PROOF_KIND == "review" && PROOF_QUESTION != "" {
      q = PROOF_QUESTION; pt[q] = "fact"; pr[q] = PROOF_RESULT; ph[q] = PROOF_HEAD; pe[q] = PROOF_EVIDENCE
      if (PROOF_SCOPE == "whole") { wt[q] = "fact"; wr[q] = PROOF_RESULT; we[q] = pe[q]; wh[q] = PROOF_HEAD }
      next
    }
    ev() == "waiver" {
      q = line_kv("question"); h = line_kv("head")
      if (q == "" || h !~ /^[0-9a-f]+$/ || length(h) < 7 || length(h) > 40) next
      pt[q] = "waiver"; pr[q] = ""; ph[q] = h; pe[q] = ""; wt[q] = "waiver"; wr[q] = ""; we[q] = ""; wh[q] = h
    }
    END {
      n = split(qs, Q, " ")
      for (i = 1; i <= n; i++) { q = Q[i]; printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n", q, pt[q], pr[q], ph[q], pe[q], wt[q], wr[q], we[q], wh[q] }
    }')"
  # THE FIXED FINDINGS, read once (wave-33 T13; REQ-5 AC-5.2, D6): the readings below derive without them.
  # THE BORN LANDINGS, read once (wave-36 T7; D9): the commits the walk holds as a born row's landing, the fixed
  # findings' green landings among them.
  case "$owed" in review"	"*|*"
review	"*) fixed="$(proof_fixed "$plan" "$tree")" || { _facts_unread "$plan"; return; }; born="$(_facts_born_landings "$plan" "$tree" "$fixed")" || { _facts_unread "$plan"; return; }
                   chk="$(_proof_release_proved "$plan" "$tree")" || { _facts_unread "$plan"; return; } ;; esac
  while IFS= read -r fact; do
    [ -n "$fact" ] || continue
    case "$fact" in
      regression)
        # THE FLOOR AT <head> (wave-35 T9; D8, AC-1.3; A-orch-45): the judge itself, at the head handed in, never
        # a checkout's: owed while a red of the whole run is open, uncovered F..<head> with the reason only for
        # a commit it cannot prove.
        x="$(proof_last "$plan" regression)" || { _facts_unread "$plan"; return; }
        if [ -z "$x" ] && proof_floor_absent "$plan" >/dev/null; then st=absent
        else
          st="$(_proof_floor_judge "$plan" "$tree" "$head" 2>/dev/null | awk 'NR == 1')"
          # GREEN MEANS THE WHOLE SUITE RAN HERE: a head with no pass at it, covered by its landings or uncovered by
          # a landing no run proved, holds only on the person's word given at this head (`approved: merge-unproved …
          # head=<head>`), and is unproved until then, naming that word and the pass as its two exits; the card asks
          # that word by the same rule (`proof_merge_ask`). A red the whole run left open is no such head: the word
          # never waives a suite, and the owed line names the pass as its one exit.
          case "$st" in
            covered|uncovered"	"*)
              ws="$(proof_merge_ask "$plan" "$tree" "$head")"
              case $? in
                0) st="unproved	$ws	$(proof_unproved_needs "$plan" "$tree" "$head")" ;;
                1) st=covered ;;
              esac ;;
            owed"	"?*) st="$st	$(proof_owed_needs "${st#owed	}")" ;;
          esac
          case "$st" in
            covered|owed"	"?*|unproved"	"?*) : ;;
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
        if [ "$wt" = fact ]; then _proof_reading_result_var "$plan" "$droot" "$we" "$wr" "$wh" "$tree" "$fixed" || { _facts_unread "$plan"; return; }; wr="$PROOF_DERIVED"; fi
        if [ "$pt" = fact ]; then _proof_reading_result_var "$plan" "$droot" "$pe" "$pr" "$ph" "$tree" "$fixed" || { _facts_unread "$plan"; return; }; pr="$PROOF_DERIVED"; fi
        # THE QUESTION'S CHAIN: its newest link, whole or piece, covered to its head and extended by the walk
        # (wave-36 T7; D9), on which a review-born landing holds whichever registered reading bore it (wave-39 D7,
        # ADR-062). One walk per question and head, however many lines of the question ask it.
        if [ -z "$pt" ]; then st=absent
        elif [ "$pt" = fact ] && [ "$pr" = fail ]; then st="failing	$pe"
        else
          case "$walked" in
            *"|$q@$ph=0|"*) st=covered ;;
            *"|$q@$ph=1|"*) st="uncovered	$ph..$head" ;;
            *) if _facts_holds "$tree" "$pfx" "$ph" "$head" "$born" "$q" "$chk"; then st=covered; walked="$walked$q@$ph=0|"
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
        x="$(_facts_check_at "$plan" "$head" "${x:-$head}")" || { _facts_unread "$plan"; return; }
        # The reviews part rendered fresh on the checked head is the release the check passed: judged at that head.
        case "$x" in
          covered|failing"	"*|'') : ;;
          *) [ -z "$tree" ] || { cb="$(proof_part_base "$plan" "$tree" "$head")"
               [ "$cb" = "$head" ] || x="$(_facts_check_at "$plan" "$cb" "$cb")" || { _facts_unread "$plan"; return; }; } ;;
        esac
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
        st="$(_facts_debt "$plan" "$tree" "$q" "$x")" || { _facts_unread "$plan"; return; } ;;
      *) st=absent ;;
    esac
    printf '%s\t%s\n' "$fact" "$st"
    [ "$st" = covered ] || rc=1
  done <<PROOF_FACTS
$owed
PROOF_FACTS
  return "$rc"
}
_facts_unread() {  # <plan> -> the judge's line for facts that could not be read, on stderr; exit 2, its "could not deal"
  printf 'facts_state: the facts of %s could not be read, so no fact it owes is judged; ask again\n' "$1" >&2
  return 2
}

# _facts_check_at <plan> <head> <head in full> -> the check fact's state at <head> from the run's check proofs, as the
# reader holds them (`_proof_facts`): `covered`, `failing<TAB><evidence>` when the last line at <head> carries result=fail, else the newest line's
# head (nothing when there is none), which the caller reads as uncovered from it; exit 2 when the facts could not be read.
_facts_check_at() {
  local facts
  proof_facts_at "$1" || return 2
  _proof_facts_awk -F'|' -v h="$2" -v hh="$3" "$(proof_fact_awk)"'
    proof_fact() && PROOF_KIND == "check" {
      last = PROOF_HEAD
      if (last == h || last == hh) { at = 1; fail = (PROOF_RESULT == "fail"); evd = PROOF_EVIDENCE }
    }
    END { if (at && fail) print "failing\t" evd; else if (at) print "covered"; else print last }'
}

# _facts_debt <plan> <tree> <suite> <token> -> `covered`, or `absent` with any reason after a tab, for
# one declared debt (wave-27 T31, T67; D23; A-orch-85, A-orch-120). Covered only when a regression proof, or
# a task proof whose log shows <suite> green, carries an `at=` STRICTLY later than the debt's
# threshold, which is never earlier than the red landing (the newest debt line's `at=` in the
# landing record, `proof_debts_read`):
#   - no debt line of <suite> and <token> carries an <ISO-UTC> `at=`: never covered, and it says so;
#   - `approval:<name>`: the later of the red landing and the instant of the standing approval of
#     <name> (`proof_approval_lines`); until one is given, absent;
#   - `ext:<slug>`: the red landing's own time, for a row holds no outside wait. Nothing dates a
#     clearing, so the green run is held to be later than the red landing;
#   - any other token: absent.
# A log shows <suite> green by the runner's `<suite> … PASS` line or the suite's own
# `<suite>: <n>/<n> passed, 0 failed` tally.
_facts_debt() {
  local plan="$1" tree="$2" suite="$3" tok="$4" clear landed droot ev x pl
  x="$(proof_debt_record "$plan" "$tree")" || x=""
  landed="$(proof_debts_read "$x" | awk -F'\t' -v s="$suite" -v t="$tok" '$1 == s && $2 == t { print $3; exit }')"
  if [ -z "$landed" ]; then
    printf 'absent\tits debt line in the landing record carries no at=<ISO-UTC>, so no green run can be dated after the red landing'
    return 0
  fi
  case "$tok" in
    approval:?*)
      clear="$(proof_approval_lines "$plan" | awk -v n="${tok#approval:}" '
        { m = split($0, w, /[ \t]+/); if (m < 3 || w[2] != n || w[3] != "by") next
          for (i = 4; i <= m; i++) if (w[i] ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) { print w[i]; exit } }')"
      # The later of the approval and the red landing (wave-27 T67; review pass 46 B1).
      if [ -n "$clear" ] && [[ "$landed" > "$clear" ]]; then clear="$landed"; fi ;;
    ext:?*) clear="$landed" ;;
    *) clear="" ;;
  esac
  [ -n "$clear" ] || { printf 'absent'; return 0; }
  pl="$(proof_lines "$plan")" || return 2
  droot=""; [ -z "$tree" ] || ! declare -F docs_root >/dev/null 2>&1 || droot="$(docs_root "$tree" 2>/dev/null)"
  while IFS='	' read -r x ev; do
    case "$x" in
      regression) printf 'covered'; return 0 ;;
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
$(printf '%s\n' "$pl" | awk -v t="$clear" "$(proof_awk)"'
  proof_fields($0) && (PROOF_KIND == "regression" || PROOF_KIND == "task") {
    m = split($0, f, /[ \t]+/); at = ""
    for (i = 2; i <= m; i++) if (f[i] ~ /^at=/) at = substr(f[i], 4)
    if (at > t) print PROOF_KIND "\t" PROOF_EVIDENCE
  }')
PROOF_LATER
  printf 'absent'
}

# ---------- COVER: HOW FAR A READING REACHES PAST ITS HEAD (wave-36 T7; REQ-3 AC-3.2, AC-3.3, AC-3.5; D9, D2, D3) ----------
#
# A reading is covered to its head. A later commit on the head's first-parent line extends it when it holds, and
# each commit's basis is one of five words:
#   prose        every path it touched (a merge as what it brought in, a rename as both its paths) is on the prose list
#                (lib/prose.sh `prose_path`, whose entries hold the docs root and the tracked docs home); a commit that touches nothing is prose too, so a merge whose tree
#                is its first parent's (one from the integration branch resolved to ours) is prose (wave-38 T2; AC-4.1)
#   release      every path it touched is in the release set (`_proof_release_path`), the plan's release check passes at
#                it and its readers are green there (`_proof_release_proved`), on every chain; the regression walk reads
#                the same kind
#   born-review  the landing record names it as the landing of a row whose `- T<n>:` line carries ` born: review …
#                of=<record>#<n>`, or `proof_fixed` names it as a fix row's green landing, AND one of those records is
#                the evidence of a registered reading: a review's fixes are inside the review, so it holds on every
#                question's chain (wave-39 D7, ADR-062; reverses wave-36 D16). A marker naming no registered reading owes.
#   born-floor   the landing record names it as the landing of a row whose `- T<n>:` line carries ` born: floor …`
#   owes         anything else, whatever kind its row declared (a doc row that touched payload/ owes)
# Content is asked first, so a born row's docs-only landing reads prose, and a CHANGELOG.md commit alone prose, not release. `facts_cover` prints the basis, the walk
# below decides it, and `facts_state` asks the same walk, so the line and the verdict never disagree.

# _facts_docs_prefix <tree> -> the docs root as a path relative to <tree> with a trailing `/`, or nothing when it is
# not under <tree> (or roots.sh is not loaded): an argument the walk no longer reads, kept so its callers keep their signature.
_facts_docs_prefix() {
  local tree="${1:-}" droot p
  [ -n "$tree" ] && declare -F docs_root >/dev/null 2>&1 || return 0
  droot="$(docs_root "$tree" 2>/dev/null)"
  case "$droot" in "$tree"/?*) p="${droot#"$tree"/}"; printf '%s/' "${p%/}" ;; esac
}

# _facts_born_landings <plan> <tree> [<proof_fixed lines>] -> `<commit>\t<review|floor>\t<questions>`, one line per
# commit the walk holds as a born row's landing: each `ev=published|row=<T>|commit=<c>` event (lib/line.sh) of the
# run's landing record (`proof_debt_record`) whose row's
# `- <T>:` line carries a born marker (lib/units.sh `units_born_marks`), and each commit `proof_fixed` names,
# review-born. A plan with no marker and no fixed finding asks the units library once.
# THE ASKERS (wave-36 T31; THE PROVENANCE GUARD since wave-39 D7, ADR-062): <questions> names, space-separated, the
# questions whose registered readings bore the row, and is empty for a floor-born one. A review-born landing whose
# list is non-empty holds on every chain (`_facts_basis`); an empty list is the guard. A marker's `of=<record>#<n>`
# (lib/units.sh `units_born_findings`) and a fixed finding's `<record>#<n>` name a record; the registered review
# readings in the run's proofs whose evidence is that record name its question. A rating-form marker, or a record no
# registered reading names, gives no question, so that landing owes on every chain.
_facts_born_landings() {
  _proof_tree_key "$1" "$2" && _proof_derive_ready "$1" || _PROOF_TREE_KEY=""
  _proof_derive _facts_born_landings "${_PROOF_TREE_KEY:+$_PROOF_TREE_KEY$'\035'${3:-}}" _facts_born_made "$@"
}
_facts_born_made() {
  local plan="$1" tree="$2" fixed="${3:-}" marks="" finds="" asks="" rec="" want
  if _proof_units_load && units_born_logged "$plan" && declare -F units_born_marks >/dev/null 2>&1; then
    marks="$(units_born_marks "$plan" 2>/dev/null)"
    if [ -n "$marks" ]; then
      rec="$(proof_debt_record "$plan" "$tree")" && _proof_fields && line_held "$rec" || rec=""
    fi
  fi
  [ -n "$fixed" ] || [ -n "$rec" ] || return 0
  _proof_fields || return 0
  # A fixed finding or a review mark needs the askers; a `case` on the string, never a pipe into a quitting grep (§BP).
  want="$fixed"; case "$marks" in *"	review	"*) want=1 ;; esac
  if [ -n "$want" ]; then
    ! declare -F units_born_findings >/dev/null 2>&1 || finds="$(units_born_findings "$plan" 2>/dev/null)"
    asks="$(proof_lines "$plan")" || return 2
    asks="$(printf '%s\n' "$asks" | awk "$(proof_awk)"'
      proof_fields($0) && PROOF_KIND == "review" && PROOF_QUESTION != "" && PROOF_EVIDENCE != "" {
        print PROOF_EVIDENCE "\t" PROOF_QUESTION
      }')"
  fi
  { printf '\034asks\n%s\n\034fixed\n%s\n\034marks\n%s\n\034finds\n%s\n\034rec\n' "$asks" "$fixed" "$marks" "$finds"
    [ -z "$rec" ] || line_lines "$rec" 2>/dev/null; } | awk -F'|' "$_LINE_FIELDS_AWK"'
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
    part == 5 && line_ev() == "published" {
      r = line_kv("row"); c = line_kv("commit"); if ((r in kind) && c != "") print c "\t" kind[r] "\t" says(r)
    }'
}

# _facts_basis <commit> <prose: 0 or not> <born landings> [<question>] [<release: 1 when every path is in the set>]
# [<release heads>] -> prints `cover <commit> <basis>`; 1 when it owes. A release-set commit is `release` when it is one
# of the heads handed in (`_proof_release_proved`, full commits). A born landing names its commit in full or by a prefix of at least seven hex digits. A floor-born landing holds
# on every chain, and so does a review-born one whose asker list is non-empty, whatever <question> asks (wave-39 D7,
# ADR-062: a review's fixes are inside the review); one with an empty list owes everywhere (the provenance guard).
_facts_basis() {
  local c="$1" b=owes k w qs
  if [ "$2" != 0 ]; then b=prose
  elif [ "${5:-0}" = 1 ] && case $'\n'"${6:-}"$'\n' in *$'\n'"$c"$'\n'*) true ;; *) false ;; esac; then b=release
  elif [ -n "${3:-}" ]; then
    while IFS='	' read -r k w qs; do
      [ "${#k}" -ge 7 ] && [ "${c#"$k"}" != "$c" ] || continue
      case "$w" in
        regression) b=born-regression; break ;;
        review) [ -n "$qs" ] || continue; b=born-review; break ;;
      esac
    done <<PROOF_BORN
$3
PROOF_BORN
  fi
  printf 'cover %s %s\n' "$c" "$b"
  [ "$b" != owes ]
}

# _facts_walk <tree> <docs prefix, unread> <last head> <head> [<born landings>] [<question>] [<release heads>] -> one `_facts_basis` line per
# commit past <last head> on <head>'s first-parent line, oldest first, on <question>'s chain; 0 when none owes. Nothing printed and 0 when <head> is
# <last head>; nothing printed and 1 when <last head> is not on <head>'s history, or git cannot answer: uncovered is
# the safe direction. Both heads are compared as the commits they resolve to, never as strings (T45; review pass 13 F10).
_facts_walk() {
  local tree="$1" born="${5:-}" q="${6:-}" chk="${7:-}" lh hh k c prose rel rc=0
  [ -n "$tree" ] || return 1
  lh="$(git -C "$tree" rev-parse --verify -q "$3^{commit}" 2>/dev/null)" || return 1
  hh="$(git -C "$tree" rev-parse --verify -q "$4^{commit}" 2>/dev/null)" || return 1
  [ "$lh" != "$hh" ] || return 0
  git -C "$tree" merge-base --is-ancestor "$lh" "$hh" 2>/dev/null || return 1
  _proof_path_walk "$tree" "$lh" "$hh" || return 1
  while IFS='	' read -r k c prose rel; do
    [ -z "$c" ] || _facts_basis "$c" "$prose" "$born" "$q" "$rel" "$chk" || rc=1
  done <<PROOF_DOCS_FILES
$_PROOF_WALK
PROOF_DOCS_FILES
  return "$rc"
}

# _facts_holds <tree> <docs prefix> <last head> <head> [<born landings>] [<question>] -> `_facts_walk`'s answer, its
# lines unprinted.
_facts_holds() {
  _facts_walk "$@" >/dev/null
}

# proof_part_base <plan> <tree> <commit> -> <commit>'s parent when <commit> is the release entry's reviews part rendered
# on it, else <commit> itself. A part commit has one parent, changes CHANGELOG.md alone, and its CHANGELOG.md is byte
# for byte what lib/line.sh `line_reviews_state` renders on that parent from the plan as it stands now. The part is
# written after the release check and the approval, from the lines they and the reviews left, so what holds at its
# parent holds at it; any other change to the entry, a hand edit of the part among them, is no fresh render and gets
# nothing from its parent. A plan whose lines changed since the render reads its part commit as stale, which is the
# safe direction.
proof_part_base() {
  local plan="${1:-}" tree="${2:-}" c="${3:-}" p tmp
  p="$(git -C "$tree" rev-parse --verify -q "${c}^1" 2>/dev/null)" \
    && ! git -C "$tree" rev-parse --verify -q "${c}^2" >/dev/null 2>&1 \
    && [ "$(git -C "$tree" diff-tree --no-commit-id --no-renames --name-only -r "$p" "$c" 2>/dev/null)" = CHANGELOG.md ] \
    && _proof_line_load && declare -F line_reviews_state >/dev/null 2>&1 \
    && tmp="$(mktemp "${TMPDIR:-/tmp}/proof-part.XXXXXX")" || { printf '%s\n' "$c"; return 0; }
  if line_reviews_state "$plan" "$tree" "$p" "${p:0:12}" "$tmp" && [ "$LINE_RV_STATE" = renders ] \
     && git -C "$tree" show "${c}:CHANGELOG.md" 2>/dev/null | cmp -s - "$tmp"; then
    rm -f "$tmp"; printf '%s\n' "$p"; return 0
  fi
  rm -f "$tmp"; printf '%s\n' "$c"
}

# proof_prose_past <plan> <from> <to> -> exit 0 when <from> is on <to>'s first-parent line and nothing an approval at
# <from> covers changed after it: every later commit is prose by the walk's basis (`_facts_walk`, no born landing, no
# release check) and no path differs between the two in the release set (`_proof_release_path`), so the release the
# user approved is the one at <to>. A <to> that is the reviews part rendered fresh on its parent (`proof_part_base`) is
# judged at that parent. Exit 1 otherwise, or when the plan or either head cannot be read.
proof_prose_past() {
  local plan="${1:-}" tree f to
  [ -f "$plan" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ] || return 1
  tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)" || return 1
  _proof_roots_load
  to="$(git -C "$tree" rev-parse --verify -q "${3}^{commit}" 2>/dev/null)" || return 1
  to="$(proof_part_base "$plan" "$tree" "$to")"
  _facts_holds "$tree" "$(_facts_docs_prefix "$tree")" "$2" "$to" || return 1
  while IFS= read -r f; do
    [ -z "$f" ] || ! _proof_release_path "$f" || return 1
  done <<PROOF_PROSE_PAST
$(git -C "$tree" diff --no-renames --name-only "$2" "$to" 2>/dev/null)
PROOF_PROSE_PAST
}

# facts_cover <plan> <from> <to> [<question>] -> THE JUDGE'S BASIS (AC-3.3): one `cover <sha> prose|release|born-review|
# born-floor|owes` line per commit on <to>'s first-parent line past <from>, oldest first, the walk `facts_state` holds
# <question>'s reading by. A landing born of a registered reading's finding holds on every chain, with or without
# <question> (wave-39 D7); a born marker naming no registered reading owes on every chain. rc 0 when no commit owes;
# 1 when one does, or when <from> is not on <to>'s history (nothing printed); 2, one sentence on stderr, when the plan or either head cannot be read. A reader
# that prints `review <question> … uncovered <a>..<b>` from facts_state asks `facts_cover <plan> <a> <b> <question>`
# for the commit that owes.
facts_cover() {
  local plan="${1:-}" tree x fixed rel born
  [ -f "$plan" ] || { printf 'facts_cover: %s is not a plan file\n' "$plan" >&2; return 2; }
  tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  for x in "${2:-}" "${3:-}"; do
    [ -n "$tree" ] && [ -n "$x" ] && git -C "$tree" rev-parse --verify -q "$x^{commit}" >/dev/null 2>&1 \
      || { printf 'facts_cover: %s is no commit here\n' "${x:-(none)}" >&2; return 2; }
  done
  _proof_roots_load
  fixed="$(proof_fixed "$plan" "$tree")" && rel="$(_proof_release_proved "$plan" "$tree")" \
    && born="$(_facts_born_landings "$plan" "$tree" "$fixed")" \
    || { printf 'facts_cover: the facts of %s cannot be read\n' "$plan" >&2; return 2; }
  _facts_walk "$tree" "$(_facts_docs_prefix "$tree")" "$2" "$3" "$born" "${4:-}" "$rel"
}

# facts_reviews <plan> <head> [--landings] -> THE ONE READING OF A REVIEW COVERED OR FAILING, one line per review question
# the rigor deals, in the dealing's order: `<question><TAB><role><TAB><state><TAB><landings>`. <state> is the judge's
# (`facts_state`) over every line it owes for the question: `failing` when one reads failing, else `absent` when one
# has no reading, else `uncovered` when a commit past one is not held, else `covered`. Handed --landings, <landings>
# names, for a covered question whose newest reading is behind <head>, each landing born of a review that the walk
# holds it by from the question's newest link (`proof_chain_head`) to <head> (`facts_cover`'s `born-review` lines), oldest first, comma-joined as `<row>@<commit>`, the row `-` when no
# fixed finding names the commit; `-` otherwise. The release card's Reviews lines and the situation report's reviews
# count both read this, so a fix landing that answers a failed reading reads covered on both, and failing only while
# a question is uncovered. rc as facts_state's: 0 when every question is covered, 1 when one is not, 2 (its sentence
# on stderr, nothing printed) when the plan cannot be dealt or <head> is no commit.
facts_reviews() {
  local plan="${1:-}" head="${2:-}" want="${3:-}" out rc tree q role st ph fixed lands rows
  out="$(facts_state "$plan" "$head")"; rc=$?
  [ "$rc" -ne 2 ] || return 2
  rows="$(printf '%s\n' "$out" | awk -F'\t' '
    $1 == "review" { q = $2; if (!(q in st)) { o[++n] = q; role[q] = $3; st[q] = "covered" }
      s = $5; r = (s == "failing") ? 4 : (s == "absent") ? 3 : (s == "uncovered") ? 2 : 1
      c = (st[q] == "failing") ? 4 : (st[q] == "absent") ? 3 : (st[q] == "uncovered") ? 2 : 1
      if (r > c) st[q] = s }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", o[i], role[o[i]], st[o[i]] }')"
  if [ "$want" != --landings ]; then
    printf '%s\n' "$rows" | awk -F'\t' 'NF >= 3 { print $0 "\t-" }'
    return "$rc"
  fi
  tree="$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null)"
  head="$(git -C "$tree" rev-parse --verify -q "$head^{commit}" 2>/dev/null)"
  fixed="$(proof_fixed "$plan" "$tree")"
  while IFS='	' read -r q role st; do
    [ -n "$q" ] || continue
    lands="-"
    if [ "$st" = covered ]; then
      ph="$(proof_chain_head "$plan" "$q")"; ph="${ph%% *}"
      ph="$(git -C "$tree" rev-parse --verify -q "${ph:-none}^{commit}" 2>/dev/null)" || ph=""
      if [ -n "$ph" ] && [ "$ph" != "$head" ]; then
        lands="$(facts_cover "$plan" "$ph" "$head" "$q" 2>/dev/null | FIXED="$fixed" awk '
          BEGIN { n = split(ENVIRON["FIXED"], f, "\n"); for (i = 1; i <= n; i++) { split(f[i], x, "\t"); if (x[3] != "" && !(x[3] in row)) row[x[3]] = x[2] } }
          $1 == "cover" && $3 == "born-review" { printf "%s%s@%s", (k++ ? "," : ""), (($2 in row) ? row[$2] : "-"), $2 }')"
        [ -n "$lands" ] || lands="-"
      fi
    fi
    printf '%s\t%s\t%s\t%s\n' "$q" "$role" "$st" "$lands"
  done <<PROOF_REVIEWS
$rows
PROOF_REVIEWS
  return "$rc"
}

# facts_review_mark <state> <result> -> THE ONE MARK OF A REVIEW QUESTION: `pass`, `fail` or `neither`, from the state
# facts_reviews gives it at the head (empty where the judge cannot deal the plan) and its newest reading's result. The
# cover holds the range, never the result, so only a newest reading that passed is a pass, and only where its range is
# covered or no judge reads coverage. A failing question is a fail, and so, with no judge, is a newest reading that
# failed. Anything else (a covered flag or fail, an uncovered question, one owed a reading) is neither. The release
# card's Reviews marks and the situation report's judged reviews count both read this, so no question counts two ways.
facts_review_mark() {
  case "${1:-}:${2:-}" in
    failing:*|:fail) printf 'fail\n' ;;
    covered:pass|:pass) printf 'pass\n' ;;
    *) printf 'neither\n' ;;
  esac
}

# proof_door_cover <tree> <from> <candidate> -> THE JUDGE'S BASIS OF A CANDIDATE AT ITS DOOR: `release`, `prose`, or
# `owes`, a tab, and each path the range touched outside the release set, comma-joined, read by the walk facts_cover
# reads, over <from>..<candidate>, with the check that has just passed at the door taken as passing at <candidate>.
# A release row's merge first exists at its landing, before any release check line names it, so this is the one
# place a path the set lacks can be named before the judge reads the release as owing. Exit 1, nothing printed, when
# the range cannot be read or holds no commit.
proof_door_cover() {
  local tree="${1:-}" from="${2:-}" c b f out=""
  c="$(git -C "$tree" rev-parse --verify -q "${3:-}^{commit}" 2>/dev/null)" || return 1
  _proof_roots_load
  b="$(_facts_walk "$tree" "$(_facts_docs_prefix "$tree")" "$from" "$c" "" "" "$c" \
    | awk '$3 == "owes" { o = 1 } $3 == "release" { r = 1 } NF { n = 1 } END { if (n) print (o ? "owes" : (r ? "release" : "prose")) }')"
  [ -n "$b" ] || return 1
  [ "$b" = owes ] || { printf '%s\n' "$b"; return 0; }
  while IFS= read -r f; do
    [ -z "$f" ] || _proof_release_path "$f" || case ",$out," in *",$f,"*) ;; *) out="${out:+$out,}$f" ;; esac
  done <<PROOF_DOOR_COVER
$(git -C "$tree" log --first-parent -m --no-renames --name-only --format= "$from..$c" 2>/dev/null)
PROOF_DOOR_COVER
  printf 'owes\t%s\n' "$out"
}


# ---------- THE RUN'S DEBTS ----------
#
# A debt is one `debt` event, concept and kind naming it, its newest event its state:
#
#   debt  concept=<c> kind=<k> sites=<sites> raised-by=<record> touches=<N> [burned=<row>]
#
# ONE WRITER, `proof_debt_event`, called by `session-poker.sh debt` (add, touched, burn, adopt). Its readers ask the
# reader: the dispatch wall's advisory (`proof_debt_hits`), `ready`'s landing report (`proof_debt_row_counts`) and the
# verb's own merge (`proof_debt_items`); close-out reads the reader's debt facts itself.
proof_debt_event() {  # <plan> <field>=<value>… -> one debt event in the plan's run log
  local log
  _proof_event_load && log="$(reader_log "$1" 2>/dev/null)" || return 2
  shift
  RUN_LOG="$log" log_append debt "$@"
}

# proof_debt_items <plan> -> one tab-separated line per debt the run holds, burned or not, in the reader's order:
# `<concept> <kind> <sites> <record> <touches> <burned row, or ->`.
proof_debt_items() {
  [ -f "${1:-}" ] && _proof_reader_load || return 0
  _proof_ask "$1" reader_q_debts "$1" all | awk -F'|' "$_READER_AWK"'{ b = line_kv("burned")
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", line_kv("concept"), line_kv("kind"), line_kv("sites"), line_kv("raised-by"), line_kv("touches"), (b == "" ? "-" : b) }'
}

# proof_debt_hits <plan> <Files cell> -> the items (as proof_debt_items prints them, burned ones too)
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

# proof_debt_row_counts <plan> <row> <Files cell> -> `<burned> <touched>` for one row: the items burned by <row>, and
# the items one of whose sites the row's Files cover.
proof_debt_row_counts() {
  local b t
  b="$(proof_debt_items "${1:-}" | awk -F'\t' -v r="${2:-}" 'r != "" && $6 == r { n++ } END { print n + 0 }')"
  t="$(proof_debt_hits "${1:-}" "${3:-}" | awk 'NF { n++ } END { print n + 0 }')"
  printf '%s %s\n' "$b" "$t"
}

# _proof_units_load -> 0 once lib/units.sh's Files matcher is defined.
_proof_units_load() { bionic_need units.sh _units_files_awk; }
