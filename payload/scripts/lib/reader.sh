#!/bin/bash
# payload/scripts/lib/reader.sh — THE ONE READER OF A RUN'S LOG.
#
#   reader_main <plan> <question> [args]   answers one question of the closed list over the plan's run.
#
# THE LOG. A plan at `<docs>/plans/<epic>/<wave>.plan.md` owns `<docs>/record/<wave>/run.log`, joined by
# name alone: no key in the plan points at it, so neither can drift from the other. `reader_events` is
# the one place a run's lines are read from; a source of events for a run kept in older homes is added
# there, and every question then answers over it unchanged. The plan's own text is never read here.
#
# THE FOLD. `reader_facts` turns the lines into facts, in the order they happened:
#   - two lines equal in every field but `at=` are one fact; the repeat changes nothing, not even the place;
#   - a later line with the same identifying fields and another value replaces the earlier, and takes its place;
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

reader_log() {  # <plan> -> the path of its run log; 2 when the plan is not plans/<epic>/<wave>.plan.md
  local plan="${1:-}" dir wave
  dir="$(cd "$(dirname "$plan")" 2>/dev/null && pwd -P)" || return 2
  plan="$dir/${plan##*/}"
  case "$plan" in */plans/*/*.plan.md) ;; *) return 2 ;; esac
  wave="${plan##*/}"
  printf '%s/record/%s/run.log\n' "${plan%/plans/*/*}" "${wave%.plan.md}"
}

reader_events() {  # <plan> -> the run's lines, in the order they were written
  local log
  log="$(reader_log "$1")" || return 2
  [ ! -f "$log" ] || cat "$log"
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
      if (t == "cancel") { delete live[id]; next }
      if ((id in live) && fact[id] == body) next
      live[id] = 1; fact[id] = body; type[id] = t; stamp[id] = f["at"]; place[id] = ++seq
    }
    END {
      for (id in live) ord[place[id]] = id
      for (p = 1; p <= seq; p++) if (p in ord) { id = ord[p]; print "run/v1|ev=" type[id] fact[id] "|at=" stamp[id] }
    }'
}

reader_list() {  # -> one line per question: <name> <form>
  local e
  for e in $READER_QUESTIONS; do
    e="${e%:*}"; printf '%s %s\n' "${e%%:*}" "${e#*:}"
  done
}

reader_main() {  # <plan> <question> [args] -> the answer in its form; 2 refused
  local plan="${1:-}" q="${2:-}" e form fn
  for e in $READER_QUESTIONS; do
    [ "${e%%:*}" = "$q" ] || continue
    fn="${e##*:}"; form="${e#*:}"; form="${form%%:*}"
    if [ ! -f "$plan" ] || ! reader_log "$plan" >/dev/null; then
      printf 'reader: %s is not a plan at plans/<epic>/<wave>.plan.md\n' "$plan" >&2; return 2
    fi
    shift 2
    if [ "$form" = yes ]; then "$fn" "$plan" "$@" >/dev/null; return; fi
    "$fn" "$plan" "$@"; return
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
