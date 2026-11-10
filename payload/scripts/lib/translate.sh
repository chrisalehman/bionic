#!/bin/bash
# payload/scripts/lib/translate.sh — A VERSION-14 RUN'S OLD HOMES, READ AS EVENTS.
#
#   translate <plan> events   the run's facts as `run/v1` lines, in the order they happened;
#   translate <plan> gaps     one `gap/v1|ev=<type>|<id>=<value>|field=<name>|why=<why>` line per fact
#                             the old homes do not hold (why=absent) or a line cannot carry (why=bar:
#                             the value holds a `|`; why=repeated: one key given two values).
#
# NOTHING IS MADE UP. Every value written is text found in its home; a field with no text is left out
# and named on the gaps list, never filled. A line whose home gives no instant still ends `at=`, empty,
# because a run's line always closes on its instant and an invented one would be a false fact. An
# instant is kept as written (to the minute, the day, or in local time): rewriting it to seconds would
# add precision the home never had.
#
# ORDER. Lines are sorted by their instant read as UTC. A line whose instant is not a UTC time takes
# the place of the line of its own type before it in the same home (so Steps 4 to 7, which carry no
# time, stay between Step 3 and Step 8), and with none before it goes after every timed line. The sort
# is stable, so lines at one place keep their order in the home.
#
# THE SOURCES. Each home is one function, registered by `translate_source <function>`; it takes the
# plan and prints records for the entry point to sort: `e<TAB><sort key><TAB><run/v1 line>` per event
# and `g<TAB><TAB><gap line>` per gap. A source is an awk program over its home that starts each event
# with `begin(type, id key, id value)`, adds fields with `put(key, value)` (an empty value becomes a
# gap), names a field its home never holds with `lack(key)`, and ends with `emit(instant)`; the helpers
# are _TRANSLATE_AWK; a line whose home already holds it in the log's shape is passed whole with
# `carry(type, fields, separator)`. The plan's homes come first, then the record's (the landing record,
# the asks register, the fill ledger); another file adds its homes the same way once it is sourced
# after this one.
#
# bash 3.2 (ADR-001).

TRANSLATE_SOURCES=""
translate_source() {  # <function> -> the function's home joins the translation
  TRANSLATE_SOURCES="${TRANSLATE_SOURCES} $1"
}

_TRANSLATE_AWK='
function inst(s) {
  if (match(s, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z/)) return substr(s, RSTART, RLENGTH)
  return ""
}
function ukey(at) {
  if (at !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z$/) return ""
  return substr(at, 1, 16) (length(at) == 20 ? substr(at, 17, 3) : ":00")
}
function quoted(s,   a, b) {
  a = index(s, "\""); if (!a) return ""
  b = index(substr(s, a + 1), "\"")
  return b ? substr(s, a + 1, b - 1) : ""
}
function nq(s,   c) { c = s; return gsub(/"/, "", c) }
function kv(s,   n, w, i, e, odd) {
  NP = 0; HEAD = ""; odd = 0; n = split(s, w, " ")
  for (i = 1; i <= n; i++) {
    if (!odd && w[i] ~ /^[a-z][a-z0-9_-]*=/) { e = index(w[i], "="); PK[++NP] = substr(w[i], 1, e - 1); PV[NP] = substr(w[i], e + 1) }
    else if (NP == 0) { HEAD = HEAD (HEAD == "" ? "" : " ") w[i]; continue }
    else PV[NP] = PV[NP] " " w[i]
    odd = (odd + nq(w[i])) % 2
  }
  for (i = 1; i <= NP; i++) if (PV[i] ~ /^".*"$/ && length(PV[i]) > 1) PV[i] = substr(PV[i], 2, length(PV[i]) - 2)
}
function byline(s,   b) {
  b = index(s, " by "); PRE = (b ? substr(s, 1, b - 1) : s); s = (b ? substr(s, b + 4) : "")
  AT = inst(s); SAID = quoted(s)
  BY = (AT != "" && index(s, " " AT)) ? substr(s, 1, index(s, " " AT) - 1) : ""
  MID = (AT != "") ? substr(s, index(s, AT) + length(AT)) : ""
  if (index(MID, "\"")) MID = substr(MID, 1, index(MID, "\"") - 1)
}
function begin(t, k, v) { T = t; IDK = k; IDV = v; L = "run/v1|ev=" t; NG = 0; split("", SEEN); put(k, v) }
function gap(k, why) { G[++NG] = "gap/v1|ev=" T "|" IDK "=" IDV "|field=" k "|why=" why }
function lack(k) { gap(k, "absent") }
function put(k, v) {
  if (v == "") { lack(k); return }
  if (k in SEEN) { if (SEEN[k] != v) gap(k, "repeated"); return }
  if (index(v, "|")) { gap(k, "bar"); return }
  SEEN[k] = v; L = L "|" k "=" v
}
function slot(t, at,   key) { key = ukey(at); if (key == "") key = (t in LAST) ? LAST[t] : "~"; LAST[t] = key; return key }
function emit(at,   i) {
  if (at == "") lack("at")
  printf "e\t%s\t%s|at=%s\n", slot(T, at), L, at
  for (i = 1; i <= NG; i++) printf "g\t\t%s\n", G[i]
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function none(s) { s = trim(s); gsub(/—|–|-/, "", s); return s == "" }
function carry(t, s, sep,   n, w, i, k, at, out) {
  n = split(s, w, sep); out = ""; at = ""
  for (i = 1; i <= n; i++) {
    k = substr(w[i], 1, index(w[i], "=") - 1)
    if (k == "at") { at = substr(w[i], 4); continue }
    if (k !~ /^[a-z][a-z0-9_-]*$/ || k == "ev" || index(w[i], "|")) { whole(t, w[1], "shape"); return }
    out = out "|" w[i]
  }
  printf "e\t%s\trun/v1|ev=%s%s|at=%s\n", slot(t, at), t, out, at
}
function whole(t, id, why) { printf "g\t\tgap/v1|ev=%s|%s|field=ev|why=%s\n", t, id, why }
'

translate() {  # <plan> <events|gaps> -> the translation in that form; 2 refused
  local plan="${1:-}" want="${2:-}" fn
  [ -f "$plan" ] || return 2
  case "$want" in events|gaps) ;; *) return 2 ;; esac
  for fn in $TRANSLATE_SOURCES; do "$fn" "$plan"; done | if [ "$want" = gaps ]; then
    awk -F'\t' '$1 == "g" && !seen[$3]++ { print $3 }'
  else
    awk -F'\t' -v OFS='\t' '$1 == "e" { print $2, NR, $3 }' | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n | cut -f3-
  fi
}

_translate_section() {  # <plan> <heading> -> the lines under `## <heading>`, to the next `## `
  awk -v h="## $2" '$0 == h { on = 1; next } /^## / { on = 0 } on' "$1"
}

translate_source _translate_state
_translate_state() {  # <plan> -> the SDLC State lines: steps, approvals, sessions, proofs, findings, waivers, orders
  _translate_section "$1" "SDLC State" | awk "$_TRANSLATE_AWK"'
    /^current: / { cur = trim(substr($0, 10)); next }
    /^approved-by: / { byline("x by " substr($0, 14)); begin("approval", "key", "step3"); put("by", BY); put("said", SAID); emit(AT); next }
    /^approved: / { byline(substr($0, 11)); begin("approval", "key", trim(PRE)); put("by", BY); kv(MID)
      for (i = 1; i <= NP; i++) put(PK[i], PV[i]); put("said", SAID); emit(AT); next }
    /^waived: / { byline(substr($0, 9)); kv(PRE); begin("waiver", PK[1], PV[1])
      for (i = 2; i <= NP; i++) put(PK[i], PV[i]); put("by", BY); put("said", SAID); emit(AT); next }
    /^- Step [0-9]+: / {
      n = substr($0, 8, index($0, ":") - 8); text = substr($0, index($0, ":") + 2); at = ""
      if (match(text, /(approved|configured) at [^ ]+ (by|via) /)) {
        ap = substr(text, RSTART, RLENGTH); split(ap, w, " "); at = w[3]; rest = substr(text, RSTART + RLENGTH)
        if (n + 0 <= 2) { begin("approval", "key", "step" n); put("by", (index(rest, " \"") ? substr(rest, 1, index(rest, " \"") - 1) : ""))
          put("said", quoted(rest)); emit(at) }
      }
      if (at == "") at = inst(text)
      begin("step", "n", n); emit(at); steps[n] = 1; next
    }
    /^- session: / { split(substr($0, 12), w, " "); begin("bind", "session", w[1]); put("by", w[5]); emit(w[3]); next }
    /^proved: / { kv(substr($0, 9)); begin("proof", PK[1], PV[1]); at = ""
      for (i = 2; i <= NP; i++) if (PK[i] == "at") at = PV[i]; else put(PK[i], PV[i]); emit(at); next }
    /^moved: / { kv(substr($0, 8)); begin("finding", "ref", HEAD); at = ""
      for (i = 1; i <= NP; i++) if (PK[i] == "at") at = PV[i]; else put(PK[i], PV[i]); emit(at); next }
    /^deferred: / { kv(substr($0, 11)); split(HEAD, w, " "); begin("finding", "ref", w[1]); put("severity", w[2]); put("to", "deferred")
      put("title", quoted(HEAD)); for (i = 1; i <= NP; i++) put(PK[i], PV[i]); lack("by"); emit(""); next }
    /^order: / { split(substr($0, 8), w, " "); begin("order", "act", w[1]); put("said", quoted($0)); emit(w[2]); next }
    END { if (cur != "" && !(cur in steps)) { begin("step", "n", cur); emit("") } }'
}

translate_source _translate_ledger
_translate_ledger() {  # <plan> -> the dispatch ledger's landings and born stamps
  _translate_section "$1" "SDLC State" | awk -v rec="$(_translate_landed_rows "$1") " "$_TRANSLATE_AWK"'
    /^- T[0-9A-Za-z.]*: / {
      row = substr($0, 3, index($0, ":") - 3); text = substr($0, index($0, ":") + 2)
      own = !index(rec, " " row " ")
      if (own && match(text, /^landed [0-9a-f]+ /)) { split(text, w, " "); begin("published", "row", row); put("commit", w[2]); emit(inst(text)) }
      else if (own && index(text, "landed-by-hand: ") == 1) { split(substr(text, 17), w, " "); begin("published", "row", row)
        put("kind", "hand"); put("by", w[1]); put("why", quoted(text)); lack("commit")
        if (match(text, /judged-by=[^ ]+/)) put("judged-by", substr(text, RSTART + 10, RLENGTH - 10)); emit(inst(text)) }
      if (match(text, /(added by task-add|split from [^ ]+) at [^ ]+/)) {
        ad = substr(text, RSTART, RLENGTH); begin("born", "row", row)
        why = (index(ad, "split from ") == 1) ? substr(ad, 1, index(ad, " at ") - 1) : ""; b = index(text, " born: "); NP = 0
        if (b) { kv(substr(text, b + 7)); why = HEAD }
        put("reason", why); for (i = 1; i <= NP; i++) if (PK[i] == "of") { split(PV[i], w, " "); put("finding", w[1]) }
        emit(inst(ad))
      }
    }'
}

translate_source _translate_tasks
_translate_tasks() {  # <plan> -> the Tasks rows: the agent cell's dispatch, the worktree and base cells' tree, a landing with no ledger line
  local plan="$1"
  { _translate_section "$plan" "SDLC State" | awk '/^- T[0-9A-Za-z.]*: landed/ { print "L", substr($0, 3, index($0, ":") - 3) }'
    for r in $(_translate_landed_rows "$plan"); do printf 'L %s\n' "$r"; done
    _translate_section "$plan" "Tasks"; } | awk -F'|' "$_TRANSLATE_AWK"'
    /^L / { led[substr($0, 3)] = 1; next }
    /^\| *id *\|/ { for (i = 2; i < NF; i++) col[trim($i)] = i; next }
    /^\| *T[0-9]/ && ("id" in col) {
      row = trim($(col["id"]))
      if (("agent" in col) && !none($(col["agent"]))) { begin("dispatch", "row", row); put("name", trim($(col["agent"]))); lack("session"); lack("tool_use_id"); emit("") }
      if (("worktree" in col) && !none($(col["worktree"]))) { begin("tree", "row", row); put("path", trim($(col["worktree"])))
        if (("base" in col) && !none($(col["base"]))) put("base", trim($(col["base"]))); else lack("base"); lack("branch"); lack("by"); emit("") }
      if (("status" in col) && trim($(col["status"])) == "landed" && !(row in led)) { begin("published", "row", row); lack("commit"); emit("") }
    }'
}

translate_source _translate_handoff
_translate_handoff() {  # <plan> -> the Handoff pointer: its path and the local time it was written
  _translate_section "$1" "Handoff" | awk "$_TRANSLATE_AWK"'
    /^handoff: / { s = substr($0, 10); w = index(s, " written ")
      begin("handoff", "path", (w ? substr(s, 1, w - 1) : s)); emit(w ? substr(s, w + 9) : "") }'
}

translate_source _translate_matrix
_translate_matrix() {  # <plan> -> the Verification Matrix rows: a discharged row's proof, a waived row's waiver
  # The table's cells are named by its own header line, never counted by place. A row says only its criterion,
  # its state and what its evidence and auditor cells hold, so that is all its event carries: the head, the
  # kind, the author and the instant are gaps. A pending or blocked row is no event. A criterion that a
  # `proved:` or `waived:` line of the SDLC State names by `ac=` is that line's fact, with the head and the
  # instant the row lacks; the row then writes nothing of that type, so one fact is never read as two.
  { _translate_section "$1" "SDLC State" | awk '/^(proved|waived): / && match($0, / ac=[^ ]+/) { print "S", $1, substr($0, RSTART + 4, RLENGTH - 4) }'
    _translate_section "$1" "Verification Matrix"; } | awk -F'|' "$_TRANSLATE_AWK"'
    /^S / { split($0, w, " "); stated[(w[2] == "proved:" ? "proof" : "waiver") SUBSEP w[3]] = 1; next }
    !/^\|/ { if (nh) done = 1; next }
    done { next }
    !nh { for (i = 2; i < NF; i++) { k = tolower(trim($i)); gsub(/[ \t]+/, "-", k); col[k] = i }; nh = 1; next }
    /^\|[-:| \t]+$/ || !("ac" in col) || !("status" in col) { next }
    {
      ac = trim($(col["ac"])); s = trim($(col["status"])); t = (s == "discharged") ? "proof" : (s == "waived") ? "waiver" : ""
      if (t == "" || ac == "" || ((t SUBSEP ac) in stated)) next
      begin(t, "ac", ac)
      for (j = split("evidence auditor", w, " "); j > 0; j--) c[w[j]] = ((w[j] in col) && !none($(col[w[j]]))) ? trim($(col[w[j]])) : ""
      put("evidence", c["evidence"]); put("auditor", c["auditor"])
      if (t == "proof") lack("kind"); else lack("by")
      lack("head"); emit("")
    }'
}

# The plan's header is read through its one parser.
if ! declare -F plan_read_header >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/plan-read.sh"
fi

translate_source _translate_abandon
_translate_abandon() {  # <plan> -> the header's `abandoned:` as the run's abandon: its words, and a leading day as written
  # An abandon has no identifying field, so its gaps are named by the run, the plan's own name; who
  # abandoned it is never parsed out of free words, so it is a gap.
  local wave="${1##*/}"
  plan_read_header "$1" abandoned | awk -v run="${wave%.plan.md}" "$_TRANSLATE_AWK"'
    { v = trim(substr($0, 11)); at = ""
      if (match(v, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9](T[0-9:]+Z)?/)) {
        at = substr(v, 1, RLENGTH); v = trim(substr(v, RLENGTH + 1)); sub(/^(—|–|-|:|;|,)[ \t]*/, "", v) }
      T = "abandon"; IDK = "run"; IDV = run; L = "run/v1|ev=abandon"; NG = 0; split("", SEEN)
      put("why", v); lack("by"); emit(at) }'
}

translate_source _translate_inherited
_translate_inherited() {  # <plan> -> each `inherited: <suite> base= head= …` line of the SDLC State, named a gap
  # No ruled event type carries a suite and its base field for field, so the line is not written as one.
  _translate_section "$1" "SDLC State" | awk '/^inherited:[ \t]+[^ \t|]/ { split($0, w, " "); printf "g\t\tgap/v1|ev=inherited|suite=%s|field=ev|why=unruled\n", w[2] }'
}

# THE RECORD'S HOMES sit in the plan's record directory, `<docs>/record/<wave>/`, joined to the plan by
# name as its run log is. Each line of a ruled type is carried with its first field renamed and every
# other field as written, an empty value too: the field-for-field rename is what makes it the same fact.
_TRANSLATE_LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P )"
_translate_record() {  # <plan> <file> -> the path of <file> in the plan's record directory; 1 when there is none
  local dir wave="${1##*/}"
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/record/%s/%s\n' "${dir%/plans/*}" "${wave%.plan.md}" "$2"
  [ -f "${dir%/plans/*}/record/${wave%.plan.md}/$2" ]
}

# A LANDING IS READ FROM ITS RECORD. The landing record is written by the landing itself, and the plan's
# ledger line and Tasks status are copies written after it; a hand landing's copy also drops the commit,
# which names the landing, so reading both would make one landing two facts. A row the record holds a
# landing of is read from the record alone; a row only the plan holds as landed is read from the plan.
_translate_landed_rows() {  # <plan> -> the rows the landing record holds a landing of, space-separated
  local f
  f="$(_translate_record "$1" landing-proofs.log)" || return 0
  awk '/^line\/v1\|ev=published\|/ || /^landed: / { if (match($0, /row=[^| ]+/)) printf " %s", substr($0, RSTART + 4, RLENGTH - 4) }' "$f"
}

translate_source _translate_landing
_translate_landing() {  # <plan> -> the landing record: ruled lines renamed, the old landing forms read, the rest named
  # A stop-run is an act taken by hand, so it is a hand event with what= its kind. close-out is the
  # Step 9 line the plan already gives, so it is not written again and what it holds beyond the step is
  # named. A stamp/v1 line is a copy of a run line, dropped with no gap. Any other kind no ruled type
  # carries is named whole.
  local f
  f="$(_translate_record "$1" landing-proofs.log)" || return 0
  [ -n "${LOG_TYPES:-}" ] || . "$_TRANSLATE_LIB_DIR/log.sh" || return 0
  awk -v types="$LOG_TYPES" "$_TRANSLATE_AWK"'
    /^line\/v1\|ev=/ { t = substr($0, 12); t = substr(t, 1, index(t "|", "|") - 1); s = substr($0, 13 + length(t))
      if (t == "stop-run") carry("hand", "what=stop-run|" s, "|")
      else if (t == "close-out") { n = split(s, w, "|")
        for (i = 1; i <= n; i++) if (w[i] !~ /^at=/) printf "g\t\tgap/v1|ev=step|n=9|field=%s|why=unruled\n", substr(w[i], 1, index(w[i], "=") - 1) }
      else if (index(types, " " t " ")) carry(t, s, "|")
      else { split(s, w, "|"); whole(t, w[1], "unruled") }
      next }
    /^landed: / { s = substr($0, 9); sub(/ merge=/, " commit=", s); carry("published", s, " "); next }
    /^debt: / { carry("admitted", substr($0, 7), " "); next }
    /^void: / { carry("void", substr($0, 7), " ") }' "$f"
}

translate_source _translate_asks
_translate_asks() {  # <plan> -> the asks register: each round's opening, and the reply that closed it
  # A closed row is rewritten in place, so it keeps when the round opened and what closed it, never what
  # was sent: the round is an opening at opened= and a reply at its close, the closer's words as reply=.
  # An open row's reply= is the wording the ask prompts for, not a reply given, so it is named, not
  # written: written, it would read as the ask answered.
  local f
  f="$(_translate_record "$1" asks.state)" || return 0
  awk -F'|' "$_TRANSLATE_AWK"'
    function fld(k,   i) { for (i = 2; i <= NF; i++) if (index($i, k "=") == 1) return substr($i, length(k) + 2); return "" }
    $1 != "owed/v1" { next }
    { k = fld("key"); r = fld("round"); open = (fld("state") == "open"); begin("ask", "key", k); if (r != "") put("round", r)
      if (open) { put("sent", fld("sent")); put("title", fld("title")) } else { lack("sent"); lack("title") }
      split("reply answer answered event", u, " "); for (i = 1; i <= 4; i++) if (fld(u[i]) != "") gap(u[i], "unruled")
      emit(open ? fld("at") : fld("opened")) }
    !open { begin("ask", "key", k); if (r != "") put("round", r); put("reply", fld("by")); emit(fld("at")) }' "$f"
}

translate_source _translate_fill
_translate_fill() {  # <plan> -> the fill ledger: each stop, its fields as written
  local f
  f="$(_translate_record "$1" fill-ledger.log)" || return 0
  awk "$_TRANSLATE_AWK"'index($0, "fill-ledger/v1|") == 1 { carry("stop", substr($0, 16), "|") }' "$f"
}
