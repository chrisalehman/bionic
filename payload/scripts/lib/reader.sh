#!/bin/bash
# payload/scripts/lib/reader.sh — THE ONE READER OF A RUN'S LOG.
#
#   reader_main <plan> <question> [args]   answers one question of the closed list over the plan's run.
#
# THE LOG. A plan at `<docs>/plans/<epic>/<wave>.plan.md` owns `<docs>/record/<wave>/run.log` (every
# place a plan may sit is `reader_record`'s), joined by name alone: no key in the plan points at it, so
# neither can drift from the other. `reader_events` is the one place a run's lines are read from; a
# source of events for a run kept in older homes is added there, and every question then answers over
# it unchanged. The plan's own text is never read here.
#
# THE FOLD. `reader_facts` turns the lines into facts, in the order they happened:
#   - two lines equal in every field but `at=` are one fact; the repeat changes nothing, not even the place,
#     save a step's: a step written again is the run taken back to it, so the step a run stands at is the last written;
#   - a later line with the same identifying fields and another value replaces the earlier, and takes its place;
#   - a discarded verdict replaces no earlier verdict, whatever its commit, and one with none before it stands
#     as the discarded run it was; a red or a green after it replaces it as any later line does;
#   - `cancel` retracts the fact it names (`of=<event type>` and that fact's identifying fields); a later
#     line may assert it again.
# A type's identifying fields are its `reader_identity` entry; a type with none is identified by all its
# fields but `at=`, so its lines only ever repeat. Every field is read by name, never by place, and a fact
# is printed in one form, `run/v1|ev=<type>|<fields sorted by name>|at=<its line's instant>`, so the order
# a writer put its fields in can never change an answer.
#
# THE QUESTIONS. Each is one `reader_question <name> <form> <function>` entry beside its one function,
# so a question is added without touching another. The function takes the plan and the question's
# arguments. The form is how it answers:
#   yes    by exit code alone, 0 yes and 1 no; anything it prints is dropped here, so it cannot print;
#   value  `key=value` lines;
#   list   one fact per line, in the log's line shape.
# A question not in the table, or a call with no plan, exits 2 and prints the list. A question missing
# an argument it needs exits 2.
#
# bash 3.2 (ADR-001).

_READER_LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P )"
if [ -z "${_LINE_FIELDS_AWK:-}" ]; then
  # shellcheck source=/dev/null
  . "$_READER_LIB_DIR/line.sh"
fi
# line.sh's field reader, read by name; `ev()` is its event, for the `run/v1` shape the fold prints.
_READER_AWK="${_LINE_FIELDS_AWK}"'
function ev() { return line_kv("ev") }
'

READER_QUESTIONS=""
reader_question() {  # <name> <yes|value|list> <function> -> the question joins the closed list
  READER_QUESTIONS="${READER_QUESTIONS} $1:$2:$3"
}
READER_IDENTITY=""
reader_identity() {  # <event type> <field>… -> the fields that name one fact of that type
  local t="$1"; shift
  READER_IDENTITY="${READER_IDENTITY} ${t}=$(printf '%s,' "$@")"
}
reader_identity step n
reader_identity approval key
reader_identity proof kind head question
reader_identity ask key round
reader_identity published row commit

# THE RECORD is joined to a plan by name, at every place the run walk (lib/run.sh `_run_candidates`)
# admits a run's plan: in the docs root's plans/ or incidents/, or one folder below either. It is
# `<docs>/record/<the plan's file name less .plan.md>/`, the name every library's record path takes,
# so the reader and the writers can never name two directories for one run. The folder one below is
# tried first, so an epic folder named plans/ joins as it always has. Any other place is no run's plan.
# This is the one rule here; lib/translate.sh asks it for the record's other homes.
reader_record() {  # <plan> -> its record directory; 2 when the plan sits where the walk admits none; above 2 when the lookup died
  local name="${1##*/}" dir up rc
  case "$name" in *.md) ;; *) return 2 ;; esac
  # A folder that cannot be entered is no run's plan; a shell that died entering it (a process refused) is no answer,
  # and its exit is passed on, so a caller can tell "no record" from "not looked up".
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || { rc=$?; [ "$rc" -gt 2 ] || rc=2; return "$rc"; }
  up="${dir%/*}"
  case "${up##*/}" in plans|incidents) dir="$up" ;;
    *) case "${dir##*/}" in plans|incidents) ;; *) return 2 ;; esac ;; esac
  printf '%s/record/%s\n' "${dir%/*}" "${name%.plan.md}"
}

reader_log() {  # <plan> -> the path of its run log; 2 when the plan sits where the walk admits none; above 2 when the lookup died
  local rec
  rec="$(reader_record "${1:-}")" || return
  printf '%s/run.log\n' "$rec"
}

reader_events() {  # <plan> -> the run's lines, in the order they were written
  local log
  log="$(reader_log "$1")" || return 2
  if [ -f "$log" ]; then cat "$log"; return; fi
  # A run with no log keeps its state in the version-14 homes, so those are read as events instead;
  # a run with a log is read from the log alone, so no fact is ever counted from both.
  if ! declare -F translate >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$_READER_LIB_DIR/translate.sh" || return 2
  fi
  translate "$1" events
}

reader_facts() {  # <plan> -> one line per standing fact, in the order the facts were last set
  reader_events "$1" | awk -F'|' -v ids="$READER_IDENTITY" '
    BEGIN { n = split(ids, a, " "); for (i = 1; i <= n; i++) { e = index(a[i], "="); idk[substr(a[i], 1, e - 1)] = substr(a[i], e + 1) } }
    $1 != "run/v1" { next }
    {
      split("", f); nk = 0
      for (i = 2; i <= NF; i++) {
        e = index($i, "="); if (e < 2) continue
        k = substr($i, 1, e - 1); if (k in f) continue
        f[k] = substr($i, e + 1); key[++nk] = k
      }
      t = f["ev"]; if (t == "") next
      for (i = 2; i <= nk; i++) for (j = i; j > 1 && key[j - 1] > key[j]; j--) { k = key[j]; key[j] = key[j - 1]; key[j - 1] = k }
      body = ""
      for (i = 1; i <= nk; i++) if (key[i] != "ev" && key[i] != "at" && !(t == "cancel" && key[i] == "of")) body = body "|" key[i] "=" f[key[i]]
      named = (t == "cancel") ? f["of"] : t
      id = named
      if (named in idk) { m = split(idk[named], ik, ","); for (i = 1; i < m; i++) id = id SUBSEP ik[i] "=" f[ik[i]] }
      else id = id SUBSEP body
      # two review records are two readings, even of one question at one head and scope; a later run of a check
      # or a regression at a head still replaces the earlier one
      if (named == "proof" && f["kind"] == "review") id = id SUBSEP "evidence=" f["evidence"]
      if (t == "cancel") { delete live[id]; next }
      # a discarded run was killed, not judged: it must not unseat the verdict a run already gave
      if (t == "verdict" && f["result"] == "discarded" && (id in live)) next
      if (named == "step" && (id in live) && fact[id] == body) delete live[id]
      if ((id in live) && fact[id] == body) next
      live[id] = 1; fact[id] = body; type[id] = t; stamp[id] = f["at"]; place[id] = ++seq
    }
    END {
      for (id in live) ord[place[id]] = id
      for (p = 1; p <= seq; p++) if (p in ord) { id = ord[p]; print "run/v1|ev=" type[id] fact[id] "|at=" stamp[id] }
    }'
}

# The closed list is split on blanks whatever IFS the caller holds, as the translation splits its sources.
reader_list() {  # -> one line per question: <name> <form>
  local e IFS=$' \t\n'
  for e in $READER_QUESTIONS; do
    e="${e%:*}"; printf '%s %s\n' "${e%%:*}" "${e#*:}"
  done
}

reader_main() {  # <plan> <question> [args] -> the answer in its form; 2 refused; a fold that failed is the question's exit
  local plan="${1:-}" q="${2:-}" e form fn rc pf=on IFS=$' \t\n'
  for e in $READER_QUESTIONS; do
    [ "${e%%:*}" = "$q" ] || continue
    fn="${e##*:}"; form="${e#*:}"; form="${form%%:*}"
    if [ ! -f "$plan" ] || ! reader_log "$plan" >/dev/null; then
      printf 'reader: %s is not a plan in plans/ or incidents/, or one folder below\n' "$plan" >&2; return 2
    fi
    shift 2
    # Each question pipes the fold into its reading, so a fold that failed would answer as a run with no fact: the
    # question runs under pipefail, its caller's setting put back after, and the failure is its exit in-process too.
    shopt -qo pipefail || pf=off
    set -o pipefail
    if [ "$form" = yes ]; then "$fn" "$plan" "$@" >/dev/null; else "$fn" "$plan" "$@"; fi; rc=$?
    [ "$pf" = on ] || set +o pipefail
    return "$rc"
  done
  printf 'reader: no question %s. usage: reader <plan> <question> [args]; the questions:\n' "'$q'" >&2
  reader_list >&2
  return 2
}

_reader_needs() {  # <question> <usage> <value> -> 0 when the value is given, else 2 with the usage
  [ -n "$3" ] && return 0
  printf 'reader: usage: reader <plan> %s %s\n' "$1" "$2" >&2; return 2
}

reader_question step value reader_q_step
reader_q_step() {  # <plan> -> n=<the current step>, state=open|delivered|abandoned
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    ev() == "step" { n = line_kv("n") }
    ev() == "abandon" { gone = 1 }
    END { if (n != "") print "n=" n; print "state=" (gone ? "abandoned" : (n == "9" ? "delivered" : "open")) }'
}

reader_question approved yes reader_q_approved
reader_q_approved() {  # <plan> <key> -> 0 when an approval of <key> stands
  _reader_needs approved '<key>' "${2:-}" || return 2
  reader_facts "$1" | awk -F'|' -v k="$2" "$_READER_AWK"'
    ev() == "approval" && line_kv("key") == k { f = 1 } END { exit !f }'
}

reader_question proof list reader_q_proof
reader_q_proof() {  # <plan> <head> [kind] -> the proofs standing at <head>, of <kind> when named
  _reader_needs proof '<head> [kind]' "${2:-}" || return 2
  reader_facts "$1" | awk -F'|' -v h="$2" -v k="${3:-}" "$_READER_AWK"'
    ev() == "proof" && line_kv("head") == h && (k == "" || line_kv("kind") == k)'
}

reader_question green yes reader_q_green
reader_q_green() {  # <plan> <head> -> 0 when the whole run's proof at <head> stands at rc=0
  _reader_needs green '<head>' "${2:-}" || return 2
  reader_facts "$1" | awk -F'|' -v h="$2" "$_READER_AWK"'
    ev() == "proof" && line_kv("kind") == "regression" && line_kv("head") == h && line_kv("rc") == "0" { f = 1 }
    END { exit !f }'
}

reader_question landed list reader_q_landed
reader_q_landed() {  # <plan> [row] -> each landing, of <row> when named
  reader_facts "$1" | awk -F'|' -v r="${2:-}" "$_READER_AWK"'
    ev() == "published" && (r == "" || line_kv("row") == r)'
}

reader_question asks list reader_q_asks
reader_q_asks() {  # <plan> -> each ask still open: no reply on it, and no approval of its `approve:` key since
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    ev() == "ask" {
      id = line_kv("key") SUBSEP line_kv("round")
      if (line_kv("reply") != "") { delete open[id]; next }
      if (!(id in seen)) { seen[id] = 1; ord[++n] = id }
      open[id] = $0
    }
    ev() == "approval" { for (id in open) if (index(id, "approve:" line_kv("key") SUBSEP) == 1) delete open[id] }
    END { for (i = 1; i <= n; i++) if (ord[i] in open) print open[ord[i]] }'
}

# The questions below answer from the log. holds, stop, status and ready also join the plan's Tasks table
# through lib/plan-read.sh, the plan's one parser; reviews still answers the log's half alone, and its
# comment names the half the plan holds.
reader_identity finding ref
reader_identity debt concept kind
reader_identity admitted id
reader_identity dispatch row name
reader_identity verdict row commit suite
# One order and one handoff stand at a time: each line replaces the last, so an order given again with
# the words of an earlier one, after a lift, answers given.
reader_identity order
reader_identity handoff

_reader_of() {  # <plan> <type> [<field> <value>] -> the standing facts of <type>, of <field>=<value> when a value is given
  reader_facts "$1" | awk -F'|' -v t="$2" -v k="${3:-}" -v v="${4:-}" "$_READER_AWK"'
    ev() == t && (v == "" || line_kv(k) == v)'
}

_reader_last() {  # <plan> <type> -> the latest standing fact of <type>, its fields as key=value lines, `ev=` dropped
  reader_facts "$1" | awk -F'|' -v t="$2" "$_READER_AWK"'
    ev() == t { l = $0 }
    END { n = split(l, p, "|"); for (i = 2; i <= n; i++) if (index(p[i], "ev=") != 1) print p[i] }'
}

reader_question holds list reader_q_holds
reader_q_holds() {  # <plan> -> each open ask that holds something, with `holds=` on its line
  # An ask holds what its writer wrote in `holds=`, and a step's approval holds the next step. Otherwise
  # it holds rows of the plan that have not landed: an `approve:<key>` or a `decide:<D>` each row that
  # waits on approval:<key> or approval:<D>, and a waiver, a finding or a hold the integrate rows. A row an
  # older table drops is owed no more, so no ask holds it.
  { plan_read_waits "$1" 2>/dev/null; printf '\034\n'; reader_q_landed "$1"; printf '\035\n'; reader_q_asks "$1"; } \
  | awk -F'|' -v drop=" $(plan_read_dropped "$1" 2>/dev/null | tr '\n' ' ') " "$_READER_AWK"'
    function rows(k,   a, i, r, o) {
      if (k ~ /^(approve|decide):/) a = "approval:" substr(k, index(k, ":") + 1); else if (k !~ /^(waive|finding|row|hold):/) return ""
      for (i = 1; i <= n; i++) { r = ord[i]; if (!(r in landed) && !index(drop, " " r " ") && (a == "" ? knd[r] == "integrate" : ((r, a) in waits))) o = o (o == "" ? "" : ", ") r }
      return o
    }
    $0 == "\034" || $0 == "\035" { part++; next }
    !part { split($0, w, "\t"); if (w[2] == "kind") { ord[++n] = w[1]; knd[w[1]] = w[3] } else if (w[2] == "wait") waits[w[1], w[3]] = 1; next }
    part == 1 { landed[line_kv("row")] = 1; next }
    line_kv("holds") != "" { print; next }
    { k = line_kv("key"); h = (k ~ /^approve:step[0-9]+$/) ? "step " (substr(k, 13) + 1) : rows(k) }
    h != "" {
      h = "holds=" h; m = split($0, p, "|"); o = p[1]; put = 0
      for (i = 2; i <= m; i++) { f = substr(p[i], 1, index(p[i], "=") - 1)
        if (!put && (f == "at" || f > "holds")) { o = o "|" h; put = 1 }
        o = o "|" p[i] }
      print o
    }'
}

reader_question reviews list reader_q_reviews
reader_q_reviews() {  # <plan> [head] -> the review proofs and the waivers of a question standing, at <head> when named
  # Which reviews a run owes is its rigor, a header key of the plan; this lists what the log holds.
  reader_facts "$1" | awk -F'|' -v h="${2:-}" "$_READER_AWK"'
    (ev() == "proof" && line_kv("kind") == "review" || ev() == "waiver" && line_kv("question") != "") && (h == "" || line_kv("head") == h)'
}

reader_question ledger list reader_q_ledger
reader_q_ledger() {  # <plan> [d] -> each decision round in order, put and ruled alike, of decision <d> when named
  _reader_of "$1" decision d "${2:-}"
}

reader_question findings list reader_q_findings
reader_q_findings() {  # <plan> [to] -> each finding where it stands now, of those moved to <to> when named
  _reader_of "$1" finding to "${2:-}"
}

reader_question debts list reader_q_debts
reader_q_debts() {  # <plan> -> each debt open: a debt not burned, an admitted red no void names, a finding carried
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    { e = ev(); id = line_kv("id") }
    e == "debt" && line_kv("burned") == "" || e == "finding" && line_kv("to") == "carried" { o[++n] = $0 }
    e == "admitted" { o[++n] = $0; a[id] = n }
    e == "void" && (id in a) { delete o[a[id]] }
    END { for (i = 1; i <= n; i++) if (i in o) print o[i] }'
}

reader_question stop value reader_q_stop
reader_q_stop() {  # <plan> -> the last stop's fields, then order=, asks= (the open count) and ready=, the plan's ready rows
  # The ready rows are ready's answer over every row of the plan, in table order; the `ready=` a stop line
  # wrote is what was ready then, so it is not printed as what is ready now.
  _reader_last "$1" stop | grep -v '^ready='
  reader_q_order "$1" | grep '^order='
  printf 'asks=%s\n' "$(reader_q_asks "$1" | grep -c .)"
  printf 'ready=%s\n' "$(_reader_ready_rows "$1" | tr '\n' ' ' | sed 's/ $//')"
}

reader_question order value reader_q_order
reader_q_order() {  # <plan> -> order=given with the standing order's words and instant, else order=none
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    ev() == "order" { a = line_kv("act"); s = line_kv("said"); t = line_kv("at") }
    END { if (a == "given") { print "order=given"; print "said=" s; print "at=" t } else print "order=none" }'
}

reader_question hands list reader_q_hands
reader_q_hands() {  # <plan> -> each act taken by hand: a hand event, or a landing made by hand
  # A roster act (an amend, a hold, an extension, an adoption) is session-only until its writer writes a
  # hand event, and a version-14 kind no ruled type carries is a gap of the translation, not a fact here.
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    ev() == "hand" || ev() == "published" && line_kv("kind") == "hand"'
}

reader_question status value reader_q_status
reader_q_status() {  # <plan> <row> -> state= of the row, then its dispatch contract, its tree and its landing commit
  # state is the latest of dispatched, candidate, ready, returned, stalled and landed; pending when the
  # log holds none. A row the plan's Tasks table lacks has no status, so a wrong id never reads as pending.
  # A dispatch is its row's first fact, so one with no instant (an older table's agent cell, placed after
  # every timed line) sets the state only while no other fact of the row stands. A row an older table
  # drops is dropped unless it landed.
  _reader_needs status '<row>' "${2:-}" || return 2
  plan_read_row "$1" Tasks id "$2" >/dev/null || return 1
  reader_facts "$1" | awk -F'|' -v r="$2" -v drop=" $(plan_read_dropped "$1" | tr '\n' ' ') " "$_READER_AWK"'
    line_kv("row") != r { next }
    { e = ev() }
    e == "published" { s = "landed"; c = line_kv("commit") }
    e == "dispatch" && line_kv("at") == "" && s != "" { e = "" }
    e == "dispatch" || e == "candidate" || e == "ready" || e == "returned" || e == "stalled" { s = (e == "dispatch") ? "dispatched" : e }
    ev() == "dispatch" { d = $0 }
    e == "tree" { t = line_kv("path"); b = line_kv("branch"); o = line_kv("base") }
    END {
      if (s != "landed" && index(drop, " " r " ")) s = "dropped"
      print "state=" (s == "" ? "pending" : s)
      n = split(d, p, "|"); for (i = 2; i <= n; i++) if (p[i] !~ /^(ev|row|at)=/) print p[i]
      if (t != "") { print "tree=" t; print "branch=" b; print "base=" o }
      if (c != "") print "commit=" c
    }'
}

reader_question ready yes reader_q_ready
reader_q_ready() {  # <plan> <row> [dep…] -> 0 when the row has not landed, no dispatch of it stands, and each wait is met
  # With no deps named, a row's waits are the plan's (plan_read_waits), judged by _reader_ready_rows; a
  # row the plan lacks is never ready. Deps a caller names are used as given, each a row that must land.
  _reader_needs ready '<row> [dep…]' "${2:-}" || return 2
  local plan="$1" row="$2" deps; shift 2
  deps="$*"
  if [ -z "$deps" ]; then
    [ "$(_reader_ready_rows "$plan" "$row")" = "$row" ]; return
  fi
  reader_facts "$plan" | awk -F'|' -v r="$row" -v deps="$deps" -v drop=" $(plan_read_dropped "$plan" | tr '\n' ' ') " "$_READER_AWK"'
    ev() == "published" { landed[line_kv("row")] = 1 }
    ev() == "dispatch" && line_kv("row") == r { held = 1 }
    END { if ((r in landed) || held || index(drop, " " r " ")) exit 1
      n = split(deps, d, " "); for (i = 1; i <= n; i++) if (!(d[i] in landed) && !index(drop, " " d[i] " ")) exit 1 }'
}

reader_question handoff value reader_q_handoff
reader_q_handoff() {  # <plan> -> the latest handoff: path= and at=
  _reader_last "$1" handoff
}

reader_question verdicts list reader_q_verdicts
reader_q_verdicts() {  # <plan> [row] -> each suite's verdict standing, of <row> when named
  _reader_of "$1" verdict row "${2:-}"
}

# THE PLAN'S AUTHORED PARTS. lib/plan-read.sh is their one parser; the four questions below only ask it,
# so the plan's text is still never read in this file. A plan and its run are joined by the plan's own
# name (`reader_log`), so no header key is followed to find either: `header` prints such a key as words.
# A row answers its authored cells alone, in either shape of the Tasks table: state is the log's.
# shellcheck source=/dev/null
. "$_READER_LIB_DIR/plan-read.sh"

reader_question header value reader_q_header
reader_q_header() {  # <plan> [key] -> key=value per header key, or the one named; 1 when it is absent
  plan_read_header "$1" "${2:-}"
}

reader_question row value reader_q_row
reader_q_row() {  # <plan> <id> -> the row's nine authored cells as key=value, in their order; 1 no such row
  _reader_needs row '<id>' "${2:-}" || return 2
  local cells
  cells="$(plan_read_row "$1" Tasks id "$2")" || return 1
  printf '%s\n' "$cells" | awk -v want="id step kind task deps size serves files artifact" '
    { e = index($0, "="); v[substr($0, 1, e - 1)] = substr($0, e + 1) }
    END { n = split(want, w, " "); for (i = 1; i <= n; i++) print w[i] "=" v[w[i]] }'
}

reader_question criterion value reader_q_criterion
reader_q_criterion() {  # <plan> <id> -> its Eval design row as key=value, one per column; 1 no such criterion
  _reader_needs criterion '<id>' "${2:-}" || return 2
  plan_read_row "$1" 'Eval design' Criterion "$2"
}

# A criterion's proof names it by `ac=`, so two criteria proved at one head by one kind are two facts, not
# one replacing the other. This later entry for the type is the one the fold reads.
reader_identity proof kind head question ac scope
reader_question cell value reader_q_cell
reader_q_cell() {  # <plan> <criterion> -> state=discharged and by=<event type>, or state=pending; 1 not in the plan
  _reader_needs cell '<criterion>' "${2:-}" || return 2
  plan_read_row "$1" 'Eval design' Criterion "$2" >/dev/null || return 1
  # Discharged only by a standing event that names the criterion: an approval by its key, a waiver or a
  # proof by `ac=`; a proof that failed (rc other than 0, or result=fail) discharges nothing.
  reader_facts "$1" | awk -F'|' -v c="$2" "$_READER_AWK"'
    ev() == "approval" && line_kv("key") == c { by = "approval" }
    ev() == "waiver" && line_kv("ac") == c { by = "waiver" }
    ev() == "proof" && line_kv("ac") == c && line_kv("rc") ~ /^0?$/ && line_kv("result") != "fail" { by = "proof" }
    END { print "state=" (by == "" ? "pending" : "discharged"); if (by != "") print "by=" by }'
}

_reader_ready_rows() {  # <plan> [row] -> the rows ready now, in table order, or <row> alone when it is; 1 the plan lacks it
  # A row is ready when it has not landed, no dispatch of it stands, and every wait plan_read_waits names
  # is met by the standing facts: a row by its landing; approval:<key> by an approval of <key>, and
  # approval:plan by Step 3's approval once the run is at Step 4; a proof by one of its kind that did not
  # fail; step:<n> by the run reaching Step <n>. Any other wait (an external token, an id the table
  # lacks) is never met here. A row an older table drops is owed no more, as the fill has it: it is
  # never ready, and a wait on it is met.
  local waits
  waits="$(plan_read_waits "$1" "${2:-}")" || return 1
  { printf '%s\n\034\n' "$waits"; reader_facts "$1"; } | awk -F'|' -v drop=" $(plan_read_dropped "$1" | tr '\n' ' ') " "$_READER_AWK"'
    function met(t, v) {
      if (t == "row") return (v in landed) || index(drop, " " v " ")
      if (v == "approval:plan") return (("step3" in appr) && cur ~ /^[0-9]+$/ && cur + 0 >= 4)
      if (v ~ /^approval:/) return (substr(v, 10) in appr)
      if (v ~ /^proof:/) return (substr(v, 7) in proved)
      if (v ~ /^step:/) return (cur ~ /^[0-9]+$/ && cur + 0 >= substr(v, 6) + 0)
      return 0
    }
    $0 == "\034" { facts = 1; next }
    !facts { split($0, w, "\t"); if (w[2] == "kind") ord[++n] = w[1]; else { nw[w[1]]++; wt[w[1], nw[w[1]]] = w[2]; wv[w[1], nw[w[1]]] = w[3] }; next }
    ev() == "published" { landed[line_kv("row")] = 1 }
    ev() == "dispatch" { held[line_kv("row")] = 1 }
    ev() == "approval" { appr[line_kv("key")] = 1 }
    ev() == "step" { cur = line_kv("n") }
    ev() == "proof" && line_kv("rc") ~ /^0?$/ && line_kv("result") != "fail" { proved[line_kv("kind")] = 1 }
    END {
      for (i = 1; i <= n; i++) {
        r = ord[i]; if ((r in landed) || (r in held) || index(drop, " " r " ")) continue
        for (k = 1; k <= nw[r]; k++) if (!met(wt[r, k], wv[r, k])) break
        if (k > nw[r]) print r
      }
    }'
}
