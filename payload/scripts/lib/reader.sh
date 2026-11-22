#!/bin/bash
# payload/scripts/lib/reader.sh — THE ONE READER OF A RUN'S LOG.
#
#   reader_main <plan> <question> [args]   answers one question of the closed list over the plan's run.
#
# THE LOG. A plan at `<docs>/plans/<epic>/<wave>.plan.md` owns `<docs>/record/<wave>/run.log` (every
# place a plan may sit is `reader_record`'s), joined by name alone: no key in the plan points at it, so
# neither can drift from the other. `reader_events` is the one place a run's lines are read from, and every
# question answers over them. The plan's own text is never read here.
#
# THE FOLD. `reader_facts` turns the lines into facts, in the order they happened:
#   - two lines equal in every field but `at=` are one fact; the repeat changes nothing, not even the place,
#     save a step's: a step written again is the run taken back to it, so the step a run stands at is the last written;
#     and save a hand's: an act taken by hand again at another time is another act, so two timed ones are two facts;
#   - a row's tree is one fact, so a tree made again after its removal stands; an untimed tree line keeps all its
#     fields as its identity, so it replaces no timed one;
#   - a later line with the same identifying fields and another value replaces the earlier, and takes its place;
#   - a discarded verdict replaces no earlier verdict, whatever its commit, and one with none before it stands
#     as the discarded run it was; a red or a green after it replaces it as any later line does;
#   - `cancel` retracts the fact it names (`of=<event type>` and that fact's identifying fields), a hand's at every
#     time it was taken; a later line may assert it again.
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
# shellcheck source=/dev/null
. "$_READER_LIB_DIR/fields.sh"
# The reader calls nothing of the landing library, but its callers find that library loaded through it: their guards
# read a set field reader as the landing library loaded, and call its record readers on that word.
# shellcheck source=/dev/null
declare -F line_lines >/dev/null 2>&1 || . "$_READER_LIB_DIR/line.sh"
# The record's field reader, read by name; `ev()` is its event, for the `run/v1` shape the fold prints.
_READER_AWK="${_LINE_FIELDS_AWK}"'
function ev() { return line_kv("ev") }
function is_pr() { return ev() == "published" && line_kv("part") == "pr" }
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
# A criterion's proof names it by `ac=`, so two criteria proved at one head by one kind are two facts, not one
# replacing the other; `scope=` keeps a proof of one scope from replacing another's at the same head.
reader_identity proof kind head question ac scope
reader_identity ask key round
# A part of the release is told from a row's landing and from another part by `part=`: the reviews part's commit is the
# head a publish pushes, so the two name one commit and are still two facts.
reader_identity published row commit part

# THE RECORD'S NAME is one rule, and every library that names a run's record asks it (lib/proof.sh `proof_plan_slug`,
# the name thirty-odd call sites ask, among them): the plan's file name less .plan.md, but an epic's plan,
# `epic.plan.md` in a folder under plans/, is named for its folder, as an incident's plan is, so two epics in one docs
# root never share a log. A name rule: the file need not exist; an epic's folder is resolved when it can be entered.
_reader_slug() {  # <the plan's folder, resolved> <its file name> -> READER_SLUG, the record's name
  READER_SLUG="${2%.plan.md}"
  [ "$2" = epic.plan.md ] || return 0
  case "${1%/*}" in */plans|plans) READER_SLUG="${1##*/}" ;; esac
}
reader_slug() {  # <plan> -> the name of its record; 1 when the name leaves none
  local d="." n="${1##*/}"
  case "$1" in */*) d="${1%/*}" ;; esac
  [ "$n" != epic.plan.md ] || d="$(cd "$d" 2>/dev/null && pwd -P)" || d="${1%/*}"
  _reader_slug "$d" "$n"; [ -n "$READER_SLUG" ] || return 1
  printf '%s' "$READER_SLUG"
}

# THE RECORD is joined to a plan by that name, at every place the run walk (lib/run.sh `_run_candidates`)
# admits a run's plan: in the docs root's plans/ or incidents/, or one folder below either. It is
# `<docs>/record/<the record's name>/`, so the reader and the writers can never name two directories for one run.
# The folder one below is tried first, so an epic folder named plans/ joins as it always has. Any other place is no
# run's plan.
reader_record() {  # <plan> -> its record directory; 2 when the plan sits where the walk admits none; above 2 when the lookup died
  local name="${1##*/}" dir up rc
  case "$name" in *.md) ;; *) return 2 ;; esac
  # A folder that cannot be entered is no run's plan; a shell that died entering it (a process refused) is no answer,
  # and its exit is passed on, so a caller can tell "no record" from "not looked up".
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || { rc=$?; [ "$rc" -gt 2 ] || rc=2; return "$rc"; }
  _reader_slug "$dir" "$name"; up="${dir%/*}"
  case "${up##*/}" in plans|incidents) dir="$up" ;;
    *) case "${dir##*/}" in plans|incidents) ;; *) return 2 ;; esac ;; esac
  printf '%s/record/%s\n' "${dir%/*}" "$READER_SLUG"
}

# THE LOG'S PATH has one home, here: a record directory holds the run's log under one name, and every place that wants
# the path asks one of these two, so no second spelling of it can drift from the reader's.
reader_log_in() {  # <record directory> -> the path of the run log it holds
  printf '%s/run.log\n' "${1%/}"
}
reader_log() {  # <plan> -> the path of its run log; 2 when the plan sits where the walk admits none; above 2 when the lookup died
  local rec
  rec="$(reader_record "${1:-}")" || return
  reader_log_in "$rec"
}

# A KEY OF A FOLD THAT READS NO TURN'S END: a stop event comes at every turn, so the log is summed less those alone. Only
# a line in the appender's whole shape of one is left out, so any other line, a malformed stop among them, still changes
# the sum: a key fails toward a fold, never toward a stale answer.
reader_log_stamp() (  # <log> -> its `cksum` less its stop events; 2 when it cannot be read
  set -o pipefail
  { LC_ALL=C grep -vE '^run/v1\|ev=stop\|session=[^|]*\|turn=[^|]*\|current=[^|]*\|state=[^|]*\|ceiling=[^|]*\|width=[^|]*\|open=[^|]*\|free=[^|]*\|ready=[^|]*\|launched=[^|]*\|declined=[^|]*\|missed=[^|]*\|idle=[^|]*\|room=[^|]*\|at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$1"
    [ "$?" -le 1 ]; } | cksum || exit 2
)

# A RUN IS ITS LOG: no other file of its record, and no line of its plan, holds a fact of it, so a plan with no log has
# no event. A plan that is no file is refused as a plan the walk admits none of.
reader_events() {  # <plan> -> the run's lines, in the order they were written; 2 when it is no plan
  [ -z "${BIONIC_COUNT:-}" ] || printf 'log reader_events\n' 2>/dev/null >>"$BIONIC_COUNT" || :
  local log
  [ -f "${1:-}" ] || return 2
  log="$(reader_log "$1")" || return 2
  [ ! -f "$log" ] || cat "$log"
}

reader_facts() {  # <plan> -> one line per standing fact, in the order the facts were last set
  # Lines handed in on `-` are an overlay, pending lines laid over facts already folded, and are counted apart from a
  # fold of the run's log.
  [ -z "${BIONIC_COUNT:-}" ] || { if [ "${1:-}" = - ]; then printf 'overlay reader_facts\n'; else printf 'fold reader_facts\n'; fi; } 2>/dev/null >>"$BIONIC_COUNT" || :
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
      if (t == "tree" && f["at"] == "") id = id SUBSEP body
      # two review records are two readings, even of one question at one head and scope; a later run of a check
      # or a regression at a head still replaces the earlier one
      if (named == "proof" && f["kind"] == "review") id = id SUBSEP "evidence=" f["evidence"]
      # an act by hand is counted each time it is taken, so its time names it; an untimed line has nothing to tell
      # it from its twin and stays one. A cancel names the act by its other fields and retracts it at every time.
      if (t == "hand" && f["at"] != "") { act[id SUBSEP "at=" f["at"]] = id; id = id SUBSEP "at=" f["at"] }
      if (t == "cancel" && named == "hand") for (x in live) if (act[x] == id) delete live[x]
      if (t == "cancel") { delete live[id]; next }
      # a discarded run was killed, not judged: it must not unseat the verdict a run already gave
      if (t == "verdict" && f["result"] == "discarded" && (id in live)) next
      # a step or an approval given again stands at its new place: the run went back to it, or a person approved again
      if ((named == "step" || named == "approval") && (id in live) && fact[id] == body) delete live[id]
      if ((id in live) && fact[id] == body) next
      live[id] = 1; fact[id] = body; type[id] = t; stamp[id] = f["at"]; place[id] = ++seq
    }
    END {
      for (id in live) ord[place[id]] = id
      for (p = 1; p <= seq; p++) if (p in ord) { id = ord[p]; print "run/v1|ev=" type[id] fact[id] "|at=" stamp[id] }
    }'
}

# The closed list is split on blanks whatever IFS the caller holds.
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
    # INSIDE A HELD COMMAND (lib/proof.sh `_proof_held_dir`) the question reads the command's one fold of the log by
    # its file, the same facts a fold here would make, and no pending line laid over them: no second fold is made for it.
    if declare -F _proof_held_dir >/dev/null 2>&1 && _proof_held_dir && _proof_facts_held "$plan" 2>/dev/null \
       && [ -n "$_PROOF_HELD_FOLD" ] && [ -n "$_PROOF_FACTS_LOG" ] && [ "${_PROOF_FACTS_KEY%% *}" = "$plan" ]; then
      ( _PROOF_READ_FILE="$_PROOF_HELD_FOLD"; reader_facts() { cat "$_PROOF_READ_FILE"; }
        if [ "$form" = yes ]; then "$fn" "$plan" "$@" >/dev/null; else "$fn" "$plan" "$@"; fi )
    elif [ "$form" = yes ]; then "$fn" "$plan" "$@" >/dev/null
    else "$fn" "$plan" "$@"; fi
    rc=$?
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

# A STEP'S OWN FIELDS are what no other event and no line a person wrote holds: what the close cleaned at 8, and at 9
# what was delivered, where it was archived and the three of a deploy. Every other part of a step's evidence is asked
# of the event that holds it. The writer refuses any other field (lib/proof.sh `proof_step_event`), and the step's
# answer prints them.
READER_STEP_FIELDS="8:cleanup,tmp-wiped,tasks-completed 9:delivered,archived,deployed,verified,monitored"
reader_step_fields() {  # <step> -> the fields that step's event may carry, blank-separated; nothing for none
  local e IFS=$' \t\n'
  for e in $READER_STEP_FIELDS; do [ "${e%%:*}" = "${1%[ab]}" ] && printf '%s\n' "${e#*:}" | tr ',' ' '; done
  return 0
}

reader_question step value reader_q_step
reader_q_step() {  # <plan> -> n=<the current step>, its own fields as key=value, state=open|delivered|abandoned
  # step 9 is the delivery, save one whose step event says `delivered=no`. A page
  # at 15 that no step has moved stands at step 0, as a row nothing has dispatched is pending: its planner wrote it,
  # and binding it and its first advance both ask where it stands. Abandoned before a step, it is abandoned at none.
  local v15=""
  [ "$(plan_read_header "$1" canonical_sdlc_version 2>/dev/null)" != canonical_sdlc_version=15 ] || v15=1
  reader_facts "$1" | awk -F'|' -v sf="$READER_STEP_FIELDS" -v v15="$v15" "$_READER_AWK"'
    BEGIN { m = split(sf, s, " "); for (i = 1; i <= m; i++) { k = substr(s[i], 1, index(s[i], ":") - 1); fl[k] = substr(s[i], index(s[i], ":") + 1) } }
    ev() == "step" { n = line_kv("n"); held = (line_kv("delivered") == "no"); f = ""
      k = n; sub(/[ab]$/, "", k); c = split(fl[k], w, ",")
      for (i = 1; i <= c; i++) if ((v = line_kv(w[i])) != "") f = f w[i] "=" v "\n" }
    ev() == "abandon" { gone = 1 }
    END { if (n == "" && v15 && !gone) n = 0; if (n != "") print "n=" n; printf "%s", f; print "state=" (gone ? "abandoned" : (n == "9" && !held ? "delivered" : "open")) }'
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

# An ask's round, by key and round (absent, 1); a decision has one key, approve:D<n> read as decide:D<n>.
_READER_ASK_AWK='
function ask_round(   k, r) { k = line_kv("key"); if (k ~ /^approve:D[0-9]+$/) k = "decide:" substr(k, 9); r = line_kv("round")
  return k SUBSEP (r == "" ? 1 : r) }
'

reader_question asks list reader_q_asks
reader_q_asks() {  # <plan> -> each ask still open: its round open in the rounds
  # Whether a round is closed is the rounds' one rule (`reader_ask_rounds`), and the asks library's register lists the
  # same rounds: so the open asks a sheet counts are the ones it lists. An approval closes no ask; its reply does.
  { reader_ask_rounds "$1"; printf '\034\n'; reader_facts "$1"; } | awk -F'|' "$_READER_AWK$_READER_ASK_AWK"'
    $0 == "\034" { facts = 1; next }
    !facts { if (line_kv("state") == "open") round_open[ask_round()] = 1; next }
    ev() == "ask" {
      id = line_kv("key") SUBSEP line_kv("round")
      if (!(ask_round() in round_open)) { delete open[id]; next }
      if (!(id in seen)) { seen[id] = 1; ord[++n] = id }
      open[id] = $0
    }
    END { for (i = 1; i <= n; i++) if (ord[i] in open) print open[ord[i]] }'
}

# AN ASK'S ROUNDS, WHOLE. The fold keeps an ask's latest event, so it loses when the round opened, when it was sent and
# answered; this folds every event of a round, by key and round (absent, 1), into one line, in the order the rounds
# opened. Each act sets what it carries: sent=, title=, prompt=, an answer at its instant, and the closer's reply=,
# which closes the round: this is the one rule of a round closed, which the open list (`reader_q_asks`) asks. No
# approval closes a round here: a round closes by its reply alone, so the asks library's list is the asks its writers
# left open.
#   run/v1|ev=ask|key=<k>|state=open|sent=<ISO or ->|at=<opened>|title=<t>|prompt=<p>|round=<n>[|answer=<w>|answered=<ISO>|event=<e>]
#   run/v1|ev=ask|key=<k>|state=closed|by=<reply>|at=<closed>|opened=<ISO or empty>|sent=<ISO or ->|round=<n>[|answer=…]
# Given a plan, the run's ask events; given `-`, the lines on stdin, which is how a session's own store, no run's, is
# read.
# A read that failed is its exit, never a run with no ask: the pipe runs under pipefail, in its own shell.
reader_ask_rounds() (  # <plan|-> -> one line per round; 2 when the plan's events cannot be read
  set -o pipefail
  { if [ "${1:-}" = - ]; then cat; else reader_events "$1"; fi; } \
  | awk -F'|' "$_READER_AWK$_READER_ASK_AWK"'
    ev() == "ask" { i = ask_round(); a = line_kv("at")
      if (!(i in ST)) { ord[++m] = i; ST[i] = "open"; SE[i] = "-" }
      # opened is the first act that is no close: an untimed opening a home gives is sorted after the close it precedes
      if (!(i in OS) && line_kv("reply") == "") { OS[i] = 1; OP[i] = a }
      if ((v = line_kv("sent")) != "") SE[i] = v
      if ((v = line_kv("title")) != "") TI[i] = v
      if ((v = line_kv("prompt")) != "") PR[i] = v
      if ((v = line_kv("answer")) != "") { RD[i] = v; AD[i] = a; EV[i] = line_kv("event") }
      if ((v = line_kv("reply")) != "") { ST[i] = "closed"; BY[i] = v; CL[i] = a } }
    END { for (j = 1; j <= m; j++) { i = ord[j]; split(i, p, SUBSEP)
        an = (RD[i] != "") ? "|answer=" RD[i] "|answered=" AD[i] "|event=" EV[i] : ""
        if (ST[i] == "open") printf "run/v1|ev=ask|key=%s|state=open|sent=%s|at=%s|title=%s|prompt=%s|round=%s%s\n", p[1], SE[i], OP[i], TI[i], PR[i], p[2], an
        else printf "run/v1|ev=ask|key=%s|state=closed|by=%s|at=%s|opened=%s|sent=%s|round=%s%s\n", p[1], BY[i], CL[i], OP[i], SE[i], p[2], an } }'
)

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
# One drop stands per row: a drop said again with other words replaces the first.
reader_identity drop row
# One tree stands per row: a removal is the row's tree event with an empty path, and a tree made again replaces it.
reader_identity tree row

# A ROW'S WORK IS NO LONGER OWED when a drop of it stands and it has not landed. This is the one rule: the questions
# below and the fill (lib/units.sh `_units_live`) put it before their own program over the facts they already fold, so
# its two rules see every fact line theirs see, and they ask `dropped(<row>)`.
_READER_DROP_AWK='
ev() == "drop" { _dropped[line_kv("row")] = 1 }
ev() == "published" { _landed[line_kv("row")] = 1 }
function dropped(r) { return (r in _dropped) && !(r in _landed) }
'

# A ROW'S STATE AND ITS TREE ARE FOLDED HERE ONCE, and `status` and the fill (lib/units.sh `_units_live`) put this before
# their own program, as they put the drop rule. Per row, in fact order: `_row_state` the latest of dispatched, candidate,
# ready, returned, stalled and landed; `_row_held` the latest of a timed launch (active) and a landing, the scheduler's
# own; `_row_name` the timed launch's name; `_row_dispatch` the last dispatch line; `_row_commit` the landing's commit;
# `_row_tree` the last tree line, `_row_tree_nr` its place among the facts, and `_row_tree_held` the last one with an
# instant, the scheduler's own.
_READER_ROW_AWK='
{ _r = line_kv("row"); _e = (_r == "") ? "" : ev() }
_r != "" && !(_r in _row_seen) { _row_seen[_r] = 1; _row_order[++_rows] = _r }
_e == "dispatch" { _row_dispatch[_r] = $0 }
# an untimed dispatch: the act that brought an older run forward to 15 wrote one per agent cell, after every timed line,
# so it launches nothing and sets the state only while no other fact of the row stands
_e == "dispatch" && line_kv("at") == "" { if (!(_r in _row_state)) _row_state[_r] = "dispatched"; _e = "" }
_e == "dispatch" { _row_state[_r] = "dispatched"; _row_held[_r] = "active"; _row_name[_r] = line_kv("name") }
_e == "published" { _row_state[_r] = _row_held[_r] = "landed"; _row_commit[_r] = line_kv("commit") }
_e == "candidate" || _e == "ready" || _e == "returned" || _e == "stalled" { _row_state[_r] = _e }
# an untimed tree line: the same act wrote one per tree cell, so it records the tree and holds none for the scheduler
_e == "tree" { _row_tree[_r] = $0; _row_tree_nr[_r] = NR; if (line_kv("at") != "") _row_tree_held[_r] = $0 }
'

# A ROW'S TREE IS ASKED HERE by every site outside the reader that needs one, so a tree is the same row's tree to the
# commit gate, to its step 8 and to the close: the row fold's latest tree line of each row, in the order those lines
# were set, which is the order two rows naming one tree are named in.
reader_trees() {  # <plan> -> each row's latest tree fact, in fact order; 2 when the facts cannot be read
  local f
  f="$(reader_facts "$1")" || return 2
  printf '%s\n' "$f" | awk -F'|' "$_READER_AWK$_READER_ROW_AWK"'
    END { for (r in _row_tree) at[_row_tree_nr[r]] = r; for (i = 1; i <= NR; i++) if (i in at) print _row_tree[at[i]] }'
}

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
  # waits on approval:<key> or approval:<D>, and a waiver, a finding or a hold the integrate rows. A dropped row
  # is owed no more, so no ask holds it.
  { plan_read_waits "$1" 2>/dev/null; printf '\034\n'; reader_facts "$1" | awk -F'|' "$_READER_AWK"'ev() == "published" || ev() == "drop"'
    printf '\035\n'; reader_q_asks "$1"; } \
  | awk -F'|' "$_READER_AWK$_READER_DROP_AWK"'
    function rows(k,   a, i, r, o) {
      if (k ~ /^(approve|decide):/) a = "approval:" substr(k, index(k, ":") + 1); else if (k !~ /^(waive|finding|row|hold):/) return ""
      for (i = 1; i <= n; i++) { r = ord[i]; if (!(r in landed) && !dropped(r) && (a == "" ? knd[r] == "integrate" : ((r, a) in waits))) o = o (o == "" ? "" : ", ") r }
      return o
    }
    $0 == "\034" || $0 == "\035" { part++; next }
    !part { split($0, w, "\t"); if (w[2] == "kind") { ord[++n] = w[1]; knd[w[1]] = w[3] } else if (w[2] == "wait") waits[w[1], w[3]] = 1; next }
    part == 1 { if (ev() == "published") landed[line_kv("row")] = 1; next }
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
reader_q_debts() {  # <plan> [all] -> each debt open: a debt not burned, an admitted red no void names, a finding carried; with all, every debt, burned or not
  [ "${2:-}" != all ] || { _reader_of "$1" debt; return; }
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
  # Every hand event is written by the line library's one writer with its reason; a waiver is its own type, not
  # answered here.
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    ev() == "hand" || ev() == "published" && line_kv("kind") == "hand"'
}

# A ROW'S STATUS IS PRINTED HERE, by one function both questions below call over the row fold, so the one pass over
# every row and the ask of one row cannot answer a row two ways. state is the latest of dispatched, candidate, ready,
# returned, stalled and landed, pending when the log holds none; a dropped row is dropped whatever else stands of it.
_READER_STATUS_AWK='
function row_status(r,   s, n, p, i) {
  s = dropped(r) ? "dropped" : _row_state[r]
  print "state=" (s == "" ? "pending" : s)
  n = split(_row_dispatch[r], p, "|"); for (i = 2; i <= n; i++) if (p[i] !~ /^(ev|row|at)=/) print p[i]
  $0 = _row_tree[r]; if (line_kv("path") != "") { print "tree=" line_kv("path"); print "branch=" line_kv("branch"); print "base=" line_kv("base") }
  if (_row_commit[r] != "") print "commit=" _row_commit[r]
}
'

reader_question status value reader_q_status
reader_q_status() {  # <plan> <row> -> state= of the row, then its dispatch contract, its tree and its landing commit
  [ -z "${BIONIC_COUNT:-}" ] || printf 'status reader_q_status\n' 2>/dev/null >>"$BIONIC_COUNT" || :
  # A row the plan's Tasks table lacks has no status, so a wrong id never reads as pending.
  _reader_needs status '<row>' "${2:-}" || return 2
  plan_read_row "$1" Tasks id "$2" >/dev/null || return 1
  reader_facts "$1" | awk -F'|' -v r="$2" "$_READER_AWK$_READER_DROP_AWK$_READER_ROW_AWK$_READER_STATUS_AWK"'
    END { row_status(r) }'
}

# EVERY ROW'S STATUS IN ONE PASS, for a caller that asks of many rows: one fold read and one awk, where an ask a row
# reads the fold and parses the plan once a row. It answers from the facts alone and reads no table: each row a fact
# names opens with `row=<id>`, in the order the facts first name it, and its lines follow as `status` prints them. The
# caller joins it against the Tasks rows it already holds: a row of the table no fact names is pending, and a row
# named here that the table lacks has no status.
reader_question statuses value reader_q_statuses
reader_q_statuses() {  # <plan> -> per row the facts name: row=<id>, then the row's status lines; 2 when the facts cannot be read
  [ -z "${BIONIC_COUNT:-}" ] || printf 'status reader_q_statuses\n' 2>/dev/null >>"$BIONIC_COUNT" || :
  local f
  f="$(reader_facts "$1")" || return 2
  [ -n "$f" ] || return 0
  printf '%s\n' "$f" | awk -F'|' "$_READER_AWK$_READER_DROP_AWK$_READER_ROW_AWK$_READER_STATUS_AWK"'
    END { for (i = 1; i <= _rows; i++) { print "row=" _row_order[i]; row_status(_row_order[i]) } }'
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
  reader_facts "$plan" | awk -F'|' -v r="$row" -v deps="$deps" "$_READER_AWK$_READER_DROP_AWK"'
    ev() == "dispatch" && line_kv("row") == r { held = 1 }
    END { if ((r in _landed) || held || dropped(r)) exit 1
      n = split(deps, d, " "); for (i = 1; i <= n; i++) if (!(d[i] in _landed) && !dropped(d[i])) exit 1 }'
}

# THE RUN'S PULL REQUEST is a published fact of its own part, `part=pr`, written by the publish verb with the request's
# address, the branch it carries, the head pushed and the base it is against. A later publish at another head is another
# fact; the newest stands. Its state, open, merged or closed, is the host's, and no line of the log holds it.
reader_question pr value reader_q_pr
reader_q_pr() {  # <plan> -> the newest request's fields as key=value lines, `ev=` and `part=` dropped; nothing, 1, for none
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    is_pr() { l = $0 }
    END { if (l == "") exit 1; n = split(l, p, "|"); for (i = 2; i <= n; i++) if (p[i] !~ /^(ev|part)=/) print p[i] }'
}

# THE JUDGE THE PERSON NAMED is an approval of its own key, `key=judge`, written by `check-from` on words they typed: the
# commit whose copy of the release check judges what lands after it (`head=`), and who typed them (`by=`, `said=`,
# `session=`). The approval's identity is its key, so the newest word stands and replaces every earlier one.
reader_question judge value reader_q_judge
reader_q_judge() {  # <plan> -> the standing judge's fields as key=value lines, `ev=` and `key=` dropped; nothing, 1, for none
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'
    ev() == "approval" && line_kv("key") == "judge" { l = $0 }
    END { if (l == "") exit 1; n = split(l, p, "|"); for (i = 2; i <= n; i++) if (p[i] !~ /^(ev|key)=/) print p[i] }'
}

reader_question handoff value reader_q_handoff
reader_q_handoff() {  # <plan> -> the latest handoff: path= and at=
  _reader_last "$1" handoff
}

# A session is bound to a run once: a later binding act of the same session is no new fact of the run's, so the answer is
# each session's first bind, and the writer appends none for a session the run holds (lib/binding.sh `bind_record_session`).
reader_question sessions list reader_q_sessions
reader_q_sessions() {  # <plan> -> each session the run holds, once, by the act that first bound it, in the order they bound
  reader_facts "$1" | awk -F'|' "$_READER_AWK"'ev() == "bind" && !seen[line_kv("session")]++'
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
# A criterion's tier is its eval type through the scale profile's one map.
# shellcheck source=/dev/null
declare -F scale_tier_awk >/dev/null 2>&1 || . "$_READER_LIB_DIR/scale.sh"

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

reader_question cell value reader_q_cell
reader_q_cell() {  # <plan> <criterion> -> state=discharged and by=<event type>, or state=pending; 1 not in the plan
  _reader_needs cell '<criterion>' "${2:-}" || return 2
  local all
  all="$(reader_cells "$1")" || return
  printf '%s\n' "$all" | awk -F'\037' -v c="$2" '
    $1 == c { print "state=" $2; if ($3 != "") print "by=" $3; f = 1; exit }
    END { exit !f }'
}

# reader_cells <plan> [head] -> one line per criterion, `<criterion>\037<state>\037<by>\037<tier>\037<evidence>\037
# <auditor>\037<confirmed>\037<serves>`: the Eval design's criteria in its order. ONE FOLD answers every criterion, so a
# caller that judges them all asks once; the cell question answers through it, and no question prints the further
# fields: the bed pins the cell answer over the closed runs, and the fields are what the gate, the judge and the cards
# weigh, never a fact a person asks for.
#   state, by   discharged only by a standing event naming the criterion: an approval by its key, a waiver or a
#               proof by `ac=`; a proof that failed (rc other than 0, or result=fail) discharges nothing; a proof
#               with no instant does not displace a waiver the log holds with one. An approval discharges only a
#               criterion nothing else does: a person confirms after the proof, and their word never unseats the
#               proof or waiver that came first.
#   tier        the Eval design's eval type through lib/scale.sh.
#   evidence    the discharging proof's or waiver's `evidence=`.
#   auditor     the `auditor=` its discharging proof carries when that proof has no instant, else the evidence review
#               standing at <head>, CONFIRMED when it passed and REFUTED when not. An untimed proof is one the act
#               wrote from an older row, whose verdict stood from then on; the appender stamps every line it writes,
#               so a verdict named on a proof written since is never read as one.
#   confirmed   the approval naming the criterion, as `<by> <day> <its words>`, its giver folded to one word and the
#               criterion standing for words it holds none of.
#   serves      the Eval design's requirement.
# 1 when the plan names no criterion; the fold's failure is its exit.
reader_cells() {
  # Its names are its own: a caller that hands it the facts names its copy `facts`, which a local of that name would hide.
  local _rc_plan="$1" _rc_head="${2:-}" _rc_eval _rc_facts
  _rc_eval="$(plan_read_rows "$_rc_plan" 'Eval design' criterion 2>/dev/null)" || _rc_eval=""
  [ -n "$_rc_eval" ] || return 1
  _rc_facts="$(reader_facts "$_rc_plan")" || return
  printf 'E\n%s\nF\n%s\n' "$_rc_eval" "$_rc_facts" | awk -F'|' -v h="$_rc_head" "$_READER_AWK$(scale_tier_awk)"'
    function cell(s, k,   n, i, c) { n = split(s, c, "\t"); for (i = 1; i <= n; i++) if (index(c[i], k "=") == 1) return substr(c[i], length(k) + 2); return "" }
    $0 == "E" || $0 == "F" { part = $0; next }
    $0 == "" { next }
    part == "E" { c = cell($0, "criterion"); if (c == "" || (c in seen)) next; seen[c] = 1; ord[++n] = c; tier[c] = tier_of(cell($0, "eval-type")); req[c] = cell($0, "requirement"); next }
    { e = ev(); c = (e == "approval") ? line_kv("key") : line_kv("ac") }
    e == "proof" && line_kv("kind") == "review" && line_kv("question") == "evidence" && h != "" && line_kv("head") == h { review = (line_kv("result") == "pass") ? "CONFIRMED" : "REFUTED" }
    c == "" || !(c in seen) { next }
    e == "approval" { if (by[c] == "") by[c] = "approval"; g = line_kv("by"); gsub(/[^A-Za-z0-9._-]+/, "-", g); sub(/^-+/, "", g); sub(/-+$/, "", g)
      ok[c] = g " " substr(line_kv("at"), 1, 10) " " (line_kv("said") != "" ? line_kv("said") : c) }
    e == "proof" && line_kv("at") == "" && by[c] == "waiver" && at_[c] != "" { next }
    e == "waiver" || e == "proof" && line_kv("rc") ~ /^0?$/ && line_kv("result") != "fail" {
      by[c] = e; ev_[c] = line_kv("evidence"); aud[c] = line_kv("auditor"); at_[c] = line_kv("at") }
    END {
      for (i = 1; i <= n; i++) {
        c = ord[i]; b = by[c]
        ev1 = (b == "proof" || b == "waiver") ? ev_[c] : ""; a = (b == "proof" && at_[c] == "" && aud[c] != "") ? aud[c] : review
        print c "\037" (b == "" ? "pending" : "discharged") "\037" b "\037" tier[c] "\037" ev1 "\037" a "\037" ok[c] "\037" req[c]
      }
    }'
}

# reader_criteria <plan> -> each criterion reader_cells lists, one id per line in its order, with no fold: the list is
# the plan's alone, so a caller that needs which criteria there are and not where they stand reads no fact.
reader_criteria() {  # 1 when the plan names none
  ( reader_facts() { :; }; reader_cells "$1" ) | awk -F'\037' '{ print $1; f = 1 } END { exit !f }'
}

_reader_ready_rows() {  # <plan> [row] -> the rows ready now, in table order, or <row> alone when it is; 1 the plan lacks it
  # A row is ready when it has not landed, no dispatch of it stands, and every wait plan_read_waits names
  # is met by the standing facts: a row by its landing; approval:<key> by an approval of <key>, and
  # approval:plan by Step 3's approval once the run is at Step 4; a proof by one of its kind that did not
  # fail; step:<n> by the run reaching Step <n>. Any other wait (an external token, an id the table
  # lacks) is never met here. A dropped row is owed no more, as the fill has it: it is never ready, and
  # a wait on it is met as a landing meets it. An integrate row is not ready once the run's pull request is
  # published: its act is done and what is left is the merge, which is the person's and the close's.
  local waits
  waits="$(plan_read_waits "$1" "${2:-}")" || return 1
  { printf '%s\n\034\n' "$waits"; reader_facts "$1"; } | awk -F'|' "$_READER_AWK$_READER_DROP_AWK"'
    function met(t, v) {
      if (t == "row") return (v in landed) || dropped(v)
      if (v == "approval:plan") return (("step3" in appr) && cur ~ /^[0-9]+$/ && cur + 0 >= 4)
      if (v ~ /^approval:/) return (substr(v, 10) in appr)
      if (v ~ /^proof:/) return (substr(v, 7) in proved)
      if (v ~ /^step:/) return (cur ~ /^[0-9]+$/ && cur + 0 >= substr(v, 6) + 0)
      return 0
    }
    $0 == "\034" { facts = 1; next }
    !facts { split($0, w, "\t"); if (w[2] == "kind") { ord[++n] = w[1]; kd[w[1]] = w[3] } else { nw[w[1]]++; wt[w[1], nw[w[1]]] = w[2]; wv[w[1], nw[w[1]]] = w[3] }; next }
    ev() == "published" { landed[line_kv("row")] = 1 }
    is_pr() { pr = 1 }
    ev() == "dispatch" { held[line_kv("row")] = 1 }
    ev() == "approval" { appr[line_kv("key")] = 1 }
    ev() == "step" { cur = line_kv("n") }
    ev() == "proof" && line_kv("rc") ~ /^0?$/ && line_kv("result") != "fail" { proved[line_kv("kind")] = 1 }
    END {
      for (i = 1; i <= n; i++) {
        r = ord[i]; if ((r in landed) || (r in held) || dropped(r)) continue
        if (pr && kd[r] == "integrate") continue
        for (k = 1; k <= nw[r]; k++) if (!met(wt[r, k], wv[r, k])) break
        if (k > nw[r]) print r
      }
    }'
}
