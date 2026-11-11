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
# ORDER. Lines are sorted by their instant read as UTC. A line the plan states to follow another fact
# stands at its own instant only when that instant is a UTC time no earlier than the fact's place, and
# otherwise at the fact's place. Two blocks of the SDLC State are written in order, so a line follows
# the one above it in its block (the first follows the run's start): the Step lines, because a run's
# step is a sequence and not an instant; and the proved: and waived: lines, because each is appended to
# the block's end (lib/proof.sh proof_add_line), so a proof registered late with its run's earlier
# instant is still the newer fact. A deferral follows its review's proof, under which it is written.
# An instant orders a line only against lines that follow no such fact, and against other homes. Any
# other line whose instant is not a UTC time takes the place of the line of its own type before it in
# the same home, and with none before it goes after every timed line. The place is only the sort key:
# the line keeps the instant it holds, and an absent one stays a gap. The sort is stable, so lines at
# one place keep their order in the home.
#
# THE SOURCES. Each home is one function, registered by `translate_source <function>`; it takes the
# plan and prints records for the entry point to sort: `e<TAB><sort key><TAB><run/v1 line>` per event
# and `g<TAB><TAB><gap line>` per gap. A source is an awk program over its home that starts each event
# with `begin(type, id key, id value)`, adds fields with `put(key, value)` (an empty value becomes a
# gap), names a field its home never holds with `lack(key)`, and ends with `emit(instant)`; the helpers
# are _TRANSLATE_AWK; a line whose home already holds it in the log's shape is passed whole with
# `carry(type, fields, separator)`. The plan's homes come first (the SDLC State and its dispatch ledger,
# the Tasks rows, the Handoff, the Verification Matrix, the header's abandoned:, the inherited: lines, a
# dropped row), then the record's (the landing record, the asks register, the fill ledger, the design
# ledger, the debt ledger), and last the run's log, read with them until the run is brought forward (lib/reader.sh
# `reader_events`); another file adds its homes the same way once it is sourced after this one.
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
function after(place) { AFTER = place; FOLLOWS = 1 }
function inblock(b) { BLOCK = b; after(PREV[b]) }
function slot(t, at,   key) {
  key = ukey(at)
  if (FOLLOWS) { if (key < AFTER) key = AFTER } else if (key == "") key = (t in LAST) ? LAST[t] : "~"
  if (BLOCK != "") PREV[BLOCK] = key
  BLOCK = ""; FOLLOWS = 0; LAST[t] = key; return key
}
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
  # The sources are split on blanks whatever IFS the caller holds: a caller reading tab fields calls this inside its
  # command substitution, and a tab-only IFS would make the list one word and skip every source.
  local plan="${1:-}" want="${2:-}" fn IFS=$' \t\n'
  [ -f "$plan" ] || return 2
  case "$want" in events|gaps) ;; *) return 2 ;; esac
  # A source that failed (a process refused under memory pressure) left its home short: the translation stops there
  # and exits non-zero, its pipes under pipefail, so no reader takes the other homes for the whole run. Every source
  # exits 0 on a home it read, an absent one included.
  ( set -o pipefail
    for fn in $TRANSLATE_SOURCES; do "$fn" "$plan" || exit; done | _translate_form "$want" )
}

_translate_form() {  # <events|gaps> -> stdin's source records in that form: events in their order, gaps once each
  if [ "$1" = gaps ]; then
    awk -F'\t' '$1 == "g" && !seen[$3]++ { print $3 }'
  else
    awk -F'\t' -v OFS='\t' '$1 == "e" { print $2, NR, $3 }' | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2n | cut -f3-
  fi
}

_translate_section() {  # <plan> <heading> -> the lines under `## <heading>`, to the next `## `
  # Fenced text is an example, never a fact, as every reader of the plan holds it. A CRLF or CR-only plan is read in
  # lines, as the gates read it: a line end left in would hide every heading and value from the match.
  awk '{ sub(/\r$/, ""); gsub(/\r/, "\n"); print }' "$1" \
    | awk -v h="## $2" '/^[ \t]*```/ { f = !f; next } f { next } $0 == h { on = 1; next } /^## / { on = 0 } on'
}

translate_source _translate_state
_translate_state() {  # <plan> -> the SDLC State lines: steps, approvals, sessions, proofs, findings, waivers, orders
  # A deferral holds no instant, and its finding is raised by its review: it stands at the place of the first
  # review proof whose evidence is the finding's file, never at its neighbour's, and its instant stays a gap.
  { _translate_section "$1" "SDLC State" | awk '/^proved: / && / kind=review / && match($0, / evidence=[^ ]+/) {
      e = substr($0, RSTART + 10, RLENGTH - 10); if (match($0, / at=[^ ]+/)) printf "\035%s %s\n", e, substr($0, RSTART + 4, RLENGTH - 4) }'
    _translate_section "$1" "SDLC State"; } | awk "$_TRANSLATE_AWK"'
    /^\035/ { split(substr($0, 2), w, " "); if (!(w[1] in rev)) rev[w[1]] = ukey(w[2]); next }
    # current: in each form a gate reads it: indented, unspaced, its blanks dropped, and the first line of two
    /^[ \t]*current[ \t]*:/ { if (!curseen) { cur = $0; sub(/^[ \t]*current[ \t]*:/, "", cur); gsub(/[ \t]/, "", cur); curseen = 1 }; next }
    # approved-by: bulleted or indented too, as the fill and the scheduler read it; a blank value approves nothing
    /^[ \t]*-?[ \t]*approved-by[ \t]*:/ { v = $0; sub(/^[ \t]*-?[ \t]*approved-by[ \t]*:/, "", v); if (trim(v) == "") next
      byline("x by " trim(v)); begin("approval", "key", "step3"); put("by", BY); put("said", SAID); emit(AT); next }
    /^approved: / { byline(substr($0, 11)); begin("approval", "key", trim(PRE)); put("by", BY); kv(MID)
      for (i = 1; i <= NP; i++) put(PK[i], PV[i]); put("said", SAID); emit(AT); next }
    /^waived: / { byline(substr($0, 9)); kv(PRE); begin("waiver", PK[1], PV[1]); inblock("proofs")
      for (i = 2; i <= NP; i++) put(PK[i], PV[i]); put("by", BY); put("said", SAID); emit(AT); next }
    /^- Step [0-9]+: / {
      n = substr($0, 8, index($0, ":") - 8); text = substr($0, index($0, ":") + 2); at = ""
      # A Step held "(pending)" is a step not reached when the line was written: no fact, so no step.
      if (trim(text) == "(pending)") { whole("step", "n=" n, "pending"); next }
      # Step 9 is reached only by its delivery, which close-out writes on that line; a note there on a parked plan, written
      # before close-out runs, delivers nothing, and read as a step it would close the run that close-out has not closed.
      if (n == "9" && !index(text, "delivered:")) { whole("step", "n=9", "undelivered"); undelivered = 1; next }
      # An approval is written at-then-by or by-then-at, and both are read; the words follow either.
      if (match(text, /(approved|configured) at [^ ]+ (by|via) /)) {
        ap = substr(text, RSTART, RLENGTH); split(ap, w, " "); at = w[3]; rest = substr(text, RSTART + RLENGTH)
        by = index(rest, " \"") ? substr(rest, 1, index(rest, " \"") - 1) : ""
      } else if (match(text, /approved by [^";]+ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z/)) {
        ap = substr(text, RSTART, RLENGTH); at = inst(ap); by = trim(substr(ap, 13, length(ap) - 12 - length(at))); rest = substr(text, RSTART + RLENGTH)
      }
      if (at != "" && n + 0 <= 2) { begin("approval", "key", "step" n); put("by", by); put("said", quoted(rest)); emit(at) }
      if (at == "") at = inst(text)
      begin("step", "n", n); inblock("steps"); emit(at); last = n; nseen[++ns] = n; next
    }
    /^- session: / { split(substr($0, 12), w, " "); begin("bind", "session", w[1]); put("by", w[5]); emit(w[3]); next }
    /^proved: / { kv(substr($0, 9)); begin("proof", PK[1], PV[1]); inblock("proofs"); at = ""
      for (i = 2; i <= NP; i++) if (PK[i] == "at") at = PV[i]; else put(PK[i], PV[i]); emit(at); next }
    /^moved: / { kv(substr($0, 8)); begin("finding", "ref", HEAD); at = ""
      for (i = 1; i <= NP; i++) if (PK[i] == "at") at = PV[i]; else put(PK[i], PV[i]); emit(at); next }
    /^deferred: / { s = substr($0, 11); r = index(s, "\"") ? substr(s, index(s, "\"") + length(quoted(s)) + 2) : s; kv(r); split(s, w, " "); begin("finding", "ref", w[1]); put("severity", w[2]); put("reach", w[3]); put("to", "deferred")
      put("title", quoted(s)); for (i = 1; i <= NP; i++) put(PK[i], PV[i]); lack("by"); f = w[1]; sub(/#.*/, "", f); if (rev[f] != "") after(rev[f]); emit(""); next }
    /^order: / { split(substr($0, 8), w, " "); begin("order", "act", w[1]); put("said", quoted($0)); emit(w[2]); next }
    # current: is where the run stands, as the gate writes it, and the Step lines are its history: a current: other than the
    # last Step line is a step written after them all, so a run taken back reads at the step it went back to. At 9 with
    # no delivered Step 9 line the run stands at 9 undelivered, which is open. Step lines with no current: are history
    # with no place: each is retracted after them, so the run has no step and a reader never judges at a guessed one.
    END {
      if (cur == "" && last != "") for (i = 1; i <= ns; i++) { begin("cancel", "of", "step"); put("n", nseen[i]); inblock("steps"); emit("") }
      else if (cur == "9" && last != "9") { begin("step", "n", cur); put("delivered", "no"); inblock("steps"); emit("") }
      else if (cur != "" && cur != last) { begin("step", "n", cur); inblock("steps"); emit("") }
    }'
}

# _TRANSLATE_LANDED_AWK: `landed_at(text)`, a ledger line's text from its landing's marker on when reasons come
# before it, else the text whole
_TRANSLATE_LANDED_AWK='
function landed_at(t,   l, b, h) {
  if (t ~ /^landed/) return t
  l = " " t; b = match(l, /[ \t]landed [0-9a-f]+ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T/) ? RSTART : 0
  h = match(l, /[ \t]landed-by-hand: /) ? RSTART : 0
  if (b && (!h || b < h)) return substr(l, b + 1)
  return h ? substr(l, h + 1) : t
}
'
translate_source _translate_ledger
_translate_ledger() {  # <plan> -> the dispatch ledger's landings and born stamps
  # A landing opens its row's line, or follows the reasons written before it: `landed <sha> <instant>` or
  # `landed-by-hand: <who> <instant> "<why>"`, the earlier of the two when both are named; the words read
  # are the landing's own, from its marker on.
  local rows
  rows="$(_translate_landed_rows "$1")" || return
  _translate_section "$1" "SDLC State" | awk -v rec="$rows " "$_TRANSLATE_AWK$_TRANSLATE_LANDED_AWK"'
    /^- T[0-9A-Za-z.]*: / {
      row = substr($0, 3, index($0, ":") - 3); text = landed_at(substr($0, index($0, ":") + 2))
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
  local plan="$1" IFS=$' \t\n' rows
  rows="$(_translate_landed_rows "$plan")" || return
  { _translate_section "$plan" "SDLC State" | awk "$_TRANSLATE_LANDED_AWK"'/^- T[0-9A-Za-z.]*: / && landed_at(substr($0, index($0, ":") + 2)) ~ /^landed/ { print "L", substr($0, 3, index($0, ":") - 3) }'
    for r in $rows; do printf 'L %s\n' "$r"; done
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
  # instant the row lacks; the row then writes nothing of that type, so one fact is never read as two. A
  # waived row whose criterion's block below the table holds an indented `waiver: <who> <day or instant>
  # "<words>"` line takes its author, instant and words from it, as the block writes them. That line is also a
  # hand act of its own, `what=waive-row`, whatever the row's status says: a person wrote it, so it is counted
  # among the hand acts, while only a row the status marks waived is a waiver the judge honours.
  { _translate_section "$1" "SDLC State" | awk '/^(proved|waived): / && match($0, / ac=[^ ]+/) { print "S", $1, substr($0, RSTART + 4, RLENGTH - 4) }'
    _translate_section "$1" "Verification Matrix" | awk '
      { l = $0; sub(/^[-*+][ \t]+/, "", l) }
      match(l, /^AC-[^ \t:]+:/) { ac = substr(l, 1, RLENGTH - 1); next }
      !/^[ \t]/ { ac = ""; next }
      ac != "" && match($0, /^[ \t]+waiver:[ \t]+[^"]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9](T[0-9][0-9]:[0-9][0-9](:[0-9][0-9])?Z)?[ \t]+"/) {
        s = substr($0, index($0, "waiver:") + 7); q = index(s, "\""); h = substr(s, 1, q - 1); n = split(h, w, /[ \t]+/)
        at = w[n]; if (at == "") at = w[n - 1]; by = substr(h, 1, index(h, at) - 1); sub(/^[ \t]+/, "", by); sub(/[ \t]+$/, "", by)
        r = substr(s, q + 1); said = (index(r, "\"") ? substr(r, 1, index(r, "\"") - 1) : "")
        printf "W\036%s\036%s\036%s\036%s\n", ac, by, at, said }
      ac != "" && match($0, /^[ \t]+user-confirmed[ \t]*:/) { v = substr($0, RLENGTH + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); printf "U\036%s\036%s\n", ac, v }'
    _translate_section "$1" "Verification Matrix"; } | awk -F'|' "$_TRANSLATE_AWK"'
    /^S / { split($0, w, " "); stated[(w[2] == "proved:" ? "proof" : "waiver") SUBSEP w[3]] = 1; next }
    /^W\036/ { split($0, w, "\036"); if (!(w[2] in wat)) { wby[w[2]] = w[3]; wat[w[2]] = w[4]; wsaid[w[2]] = w[5] }
      begin("hand", "ac", w[2]); put("what", "waive-row"); if (w[3] != "") put("by", w[3]); if (w[5] != "") put("said", w[5]); emit(w[4]); next }
    /^U\036/ { split($0, w, "\036"); if (!(w[2] in uc)) uc[w[2]] = w[3]; next }
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
      # A person confirms a criterion in its block; a block with no such line holds no confirmation to name.
      if (ac in uc) put("confirmed", uc[ac])
      if (t == "waiver" && (ac in wat)) { put("by", wby[ac]); put("said", wsaid[ac]); lack("head"); emit(wat[ac]); next }
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
  { plan_read_header "$1" abandoned || [ "$?" -eq 1 ]; } | awk -v run="${wave%.plan.md}" "$_TRANSLATE_AWK"'
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

translate_source _translate_dropped
_translate_dropped() {  # <plan> -> each Tasks row whose status is dropped, named whole on the gaps list
  # A dropped row is the plan's word that its work is no longer owed. No ruled event says that of a row:
  # a cancel retracts a fact the log holds, and a row is authored, never logged; so the status is named,
  # not written. Until a type carries it, only the plan's own cell tells a dropped row from a pending one.
  { plan_read_dropped "$1" 2>/dev/null || [ "$?" -eq 1 ]; } | awk '{ printf "g\t\tgap/v1|ev=dropped|row=%s|field=ev|why=unruled\n", $0 }'
}

# THE RECORD'S HOMES sit in the plan's record directory, `<docs>/record/<wave>/`, joined to the plan by
# name as its run log is, by the reader's one rule (`reader_record`), so the two never name two
# directories for one run. Each line of a ruled type is carried with its first field renamed and every
# other field as written, an empty value too: the field-for-field rename is what makes it the same fact.
_TRANSLATE_LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P )"
if ! declare -F reader_record >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_TRANSLATE_LIB_DIR/reader.sh"
fi
_translate_record() {  # <plan> <file> -> the path of <file> in the plan's record directory, nothing when there is none; non-zero when the lookup died
  local rec rc=0
  rec="$(reader_record "$1")" || rc=$?
  [ "$rc" -eq 0 ] || { [ "$rc" -eq 2 ] && return 0; return "$rc"; }
  [ ! -f "$rec/$2" ] || printf '%s/%s\n' "$rec" "$2"
}

# A LANDING IS READ FROM ITS RECORD. The landing record is written by the landing itself, and the plan's
# ledger line and Tasks status are copies written after it; a hand landing's copy also drops the commit,
# which names the landing, so reading both would make one landing two facts. A row the record holds a
# landing of is read from the record alone; a row only the plan holds as landed is read from the plan.
_translate_landed_rows() {  # <plan> -> the rows the landing record or the run's log holds a landing of, space-separated
  local f l
  f="$(_translate_record "$1" landing-proofs.log)" || return
  l="$(_translate_record "$1" run.log)" || return
  [ -n "$f$l" ] || return 0
  # the log's landings are the landing record's, written to their new home
  awk '/^line\/v1\|ev=published\|/ || /^run\/v1\|/ && /\|ev=published(\||$)/ || /^landed: / { if (match($0, /row=[^| ]+/)) printf " %s", substr($0, RSTART + 4, RLENGTH - 4) }' ${f:+"$f"} ${l:+"$l"}
}

translate_source _translate_landing
_translate_landing() {  # <plan> -> the landing record: ruled lines renamed, the old landing forms read, the rest named
  # A stop-run, a status or task written into the matrix (matrix-set) and a refusal are acts taken by
  # hand, so each is a hand event with what= its kind and the line's own fields. close-out is the
  # Step 9 line the plan already gives, so it is not written again and what it holds beyond the step is
  # named. A stamp/v1 line is a copy of a run line, dropped with no gap, and so is a landed: header that
  # copies a published line of its row and commit: the line is the landing, and it carries the kind.
  # Any other kind no ruled type carries is named whole.
  local f
  f="$(_translate_record "$1" landing-proofs.log)" || return; [ -n "$f" ] || return 0
  [ -n "${LOG_TYPES:-}" ] || . "$_TRANSLATE_LIB_DIR/log.sh" || return 0
  awk -v types="$LOG_TYPES" "$_TRANSLATE_AWK"'
    function word(s, k,   n, w, i) { n = split(s, w, " "); for (i = 1; i <= n; i++) if (index(w[i], k "=") == 1) return substr(w[i], length(k) + 2); return "" }
    FNR == NR { if (index($0, "line/v1|ev=published|") == 1) { split("", g); n = split($0, w, "|")
        for (i = 2; i <= n; i++) g[substr(w[i], 1, index(w[i], "=") - 1)] = substr(w[i], index(w[i], "=") + 1)
        lined[g["row"] SUBSEP g["commit"]] = 1 }
      next }
    /^line\/v1\|ev=/ { t = substr($0, 12); t = substr(t, 1, index(t "|", "|") - 1); s = substr($0, 13 + length(t))
      if (t == "stop-run" || t == "matrix-set" || t == "refusal") carry("hand", "what=" t "|" s, "|")
      else if (t == "close-out") { n = split(s, w, "|")
        for (i = 1; i <= n; i++) if (w[i] !~ /^at=/) printf "g\t\tgap/v1|ev=step|n=9|field=%s|why=unruled\n", substr(w[i], 1, index(w[i], "=") - 1) }
      else if (index(types, " " t " ")) carry(t, s, "|")
      else { split(s, w, "|"); whole(t, w[1], "unruled") }
      next }
    /^landed: / { s = substr($0, 9); if ((word(s, "row") SUBSEP word(s, "merge")) in lined) next
      sub(/ merge=/, " commit=", s); carry("published", s, " "); next }
    /^debt: / { carry("admitted", substr($0, 7), " "); next }
    /^void: / { carry("void", substr($0, 7), " ") }' "$f" "$f"
}

translate_source _translate_asks
_translate_asks() {  # <plan> -> the asks register: each round's opening, and the reply that closed it
  # A closed row is rewritten in place, so it keeps when the round opened and what closed it, never what
  # was sent: the round is an opening at opened= and a reply at its close, the closer's words as reply=.
  # An open row's reply= is the wording the ask prompts for, not a reply given, so it is named, not
  # written: written, it would read as the ask answered.
  local f
  f="$(_translate_record "$1" asks.state)" || return; [ -n "$f" ] || return 0
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
  f="$(_translate_record "$1" fill-ledger.log)" || return; [ -n "$f" ] || return 0
  awk "$_TRANSLATE_AWK"'index($0, "fill-ledger/v1|") == 1 { carry("stop", substr($0, 16), "|") }' "$f"
}

translate_source _translate_decisions
_translate_decisions() {  # <plan> -> the design ledger's rounds
  local f
  f="$(_translate_record "$1" design-ledger.md)" || return; [ -n "$f" ] || return 0
  _translate_ledger_records "$f"
}

translate_ledger() {  # <design-ledger.md> <events|gaps> -> one ledger's rounds in the translation's two forms, read alone
  [ -f "${1:-}" ] || return 2
  case "${2:-}" in events|gaps) ;; *) return 2 ;; esac
  _translate_ledger_records "$1" | _translate_form "$2"
}

# A ROUND is a `## Δ<n> — D<n> [qualifier] <verb> ["<reply>"] (<who> <instant>)[: <title>]` heading, or a `- D<n> …`
# bullet of that shape under a Δ (the rulings a step card folded in). The verbs are put and every word a ruling is
# written with: ruled, re-ruled, amended, amended again, ratified, settled, final and withdrawn. verb= is the word as
# written, a one-word qualifier before it kept with it, because the word is what the person said and the closed list
# of event types does not move with it. A reply is said=; `D<n> ruled: <title> (<who> <instant>)` has none; a go
# ledgered as `D<n> settled by <what> (<who> <instant>): "<reply>"` says its reply after the parenthesis and is
# titled by what settled it. A tail after the parenthesis that is not `: <title>` is the title. A put's wait= is the
# first line under its heading, what `decisions put` writes there. entry= is the Δ the round is written under, so a
# decision put twice in the same words at two instants is two rounds, not one line repeated. The instant is kept as the heading writes it, local
# clock and zone or a bare day: rewritten to UTC it would be a time the heading never held; one holding a `|` cannot
# be written, so it is named. A heading of any other form, a reply not followed by its parenthesis among them, is
# named whole by its first word and writes no round, because a verb or reply read out of other words would be a
# guess. A fenced example is no round and no gap.
_translate_ledger_records() {  # <design-ledger.md> -> its rounds as source records
  awk "$_TRANSLATE_AWK"'
    function stamp(at,   i) { if (!index(at, "|")) { emit(at); return }
      gap("at", "bar"); printf "e\t%s\t%s|at=\n", slot(T, ""), L; for (i = 1; i <= NG; i++) printf "g\t\t%s\n", G[i] }
    function lead(s,   i, n, vs, c) {
      n = split("amended again|amended|re-ruled|ruled|ratified|settled|final|withdrawn|put", vs, "|")
      for (i = 1; i <= n; i++) if (index(s, vs[i]) == 1) { c = substr(s, length(vs[i]) + 1, 1); if (c == " " || c == ":") return vs[i] }
      return ""
    }
    function flush() { if (PD != "") { begin("decision", "d", PD); for (i = 1; i <= RN; i++) put(RK[i], RV[i]); if (PW != "") put("wait", PW); stamp(PA) } PD = "" }
    function round(s, head,   n, rest, verb, qual, reply, hasreply, q, i, depth, inq, ch, fin, c, paren, tail, title, who, by) {
      if (!match(s, /^D[0-9]+ /)) return 0
      n = substr(s, 1, RLENGTH - 1); rest = substr(s, RLENGTH + 1); verb = lead(rest); qual = ""
      if (verb == "") {
        if (!match(rest, /^[A-Za-z][A-Za-z0-9_-]* /)) return 0
        qual = substr(rest, 1, RLENGTH - 1); rest = substr(rest, RLENGTH + 1); verb = lead(rest); if (verb == "") return 0
      }
      rest = substr(rest, length(verb) + 1); hasreply = 0; reply = ""; paren = ""; title = ""
      if (substr(rest, 1, 1) == ":") {
        rest = trim(substr(rest, 2)); if (substr(rest, length(rest)) != ")") return 0
        for (i = length(rest) - 1; i >= 1; i--) {
          if (substr(rest, i, 2) != " (") continue
          c = substr(rest, i + 2, length(rest) - i - 2)
          if (match(c, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) { paren = c; title = substr(rest, 1, i - 1); break }
        }
        if (paren == "") return 0
      } else {
        by = ""
        if (verb == "settled" && index(rest, " by ") == 1) { q = index(substr(rest, 5), " ("); if (q == 0) return 0; by = substr(rest, 5, q - 1); rest = substr(rest, q + 4) }
        if (index(rest, " \"") == 1) { rest = substr(rest, 3); q = index(rest, "\""); if (q == 0) return 0; reply = substr(rest, 1, q - 1); rest = substr(rest, q + 1); hasreply = 1 }
        if (index(rest, " (") != 1) return 0
        rest = substr(rest, 3); depth = 1; inq = 0; fin = 0
        for (i = 1; i <= length(rest); i++) {
          ch = substr(rest, i, 1)
          if (ch == "\"") inq = !inq
          else if (!inq && ch == "(") depth++
          else if (!inq && ch == ")" && --depth == 0) { fin = i; break }
        }
        if (!fin) fin = index(rest, ")")
        if (!fin) return 0
        paren = substr(rest, 1, fin - 1); tail = substr(rest, fin + 1)
        if (index(tail, ": ") == 1) title = substr(tail, 3); else { title = tail; sub(/^[ \t:,;]+/, "", title) }
        if (by != "") {
          if (!hasreply && match(title, /^"[^"]*"[ \t]*$/)) { reply = substr(title, 2, index(substr(title, 2), "\"") - 1); hasreply = 1 }
          title = by
        }
      }
      if (!match(paren, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) return 0
      who = trim(substr(paren, 1, RSTART - 1)); sub(/[ \t,]+$/, "", who); if (who == "") return 0
      flush(); PD = n; RN = 0; PW = ""; PA = trim(substr(paren, RSTART))
      if (DELTA != "") { RK[++RN] = "entry"; RV[RN] = DELTA }
      RK[++RN] = "verb"; RV[RN] = (qual == "" ? "" : qual " ") verb
      if (hasreply) { RK[++RN] = "said"; RV[RN] = reply }
      RK[++RN] = "by"; RV[RN] = who; RK[++RN] = "title"; RV[RN] = trim(title)
      WAIT = (verb == "put" && head); if (!WAIT) flush()
      return 1
    }
    { sub(/\r$/, "") }
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    index($0, "## ") == 1 { WAIT = 0; h = substr($0, 4); s = h; split(h, w, " "); DELTA = (w[1] ~ /^Δ[0-9]/) ? w[1] : ""
      if (sub(/^Δ[0-9]+ — /, "", s) && round(s, 1)) next
      flush(); whole("decision", "heading=" w[1], "shape"); next }
    WAIT && NF { PW = $0; WAIT = 0; flush() }
    /^- D[0-9]+ / { round(substr($0, 3), 0) }
    END { flush() }' "$1"
}

translate_source _translate_debts
_translate_debts() {  # <plan> -> the debt ledger's lines: each a debt, burned= its row when burned
  # A line is `<concept> | <kind> | <sites> | raised-by <record> | touches <n> | burned <row>`, its last
  # cell `—` while open. The ledger holds no instant, so each debt ends `at=`, empty, and is named. A line
  # of any other form, a note in the last cell or prose, is named whole and writes no debt: read as open
  # or burned, it would be a guess.
  local f
  f="$(_translate_record "$1" debt.md)" || return; [ -n "$f" ] || return 0
  awk -F' [|] ' "$_TRANSLATE_AWK"'
    /^#/ || /^[ \t]*$/ { next }
    { split("", c); for (i = 1; i <= NF; i++) c[i] = trim($i); b = c[6] }
    NF != 6 || c[1] == "" || c[4] !~ /^raised-by [^ ]/ || c[5] !~ /^touches [0-9]+$/ || !(none(b) || b ~ /^burned [^ ]+$/) {
      whole("debt", (NF > 1 && c[1] != "") ? "concept=" c[1] : "line=" NR, "shape"); next }
    { begin("debt", "concept", c[1]); put("kind", c[2]); put("sites", c[3]); put("raised-by", substr(c[4], 11))
      put("touches", substr(c[5], 9)); if (!none(b)) put("burned", substr(b, 8)); emit("") }' "$f"
}

# THE LOG is the newest home: each line is carried whole, as written. It sorts by its instant among the old homes'
# lines and after any of them at the same instant, and never before a line written above it in the log, so the log's
# own order stands; a line with no UTC instant takes the place of the line above it, and the first such line goes
# after every timed line.
translate_source _translate_log
_translate_log() {  # <plan> -> the run's log, each line in its place
  local f
  f="$(_translate_record "$1" run.log)" || return; [ -n "$f" ] || return 0
  awk "$_TRANSLATE_AWK"'
    index($0, "run/v1|") != 1 { next }
    { a = ""; n = split($0, w, "|"); for (i = n; i >= 2; i--) if (index(w[i], "at=") == 1) { a = substr(w[i], 4); break }
      k = ukey(a); if (k == "") k = (p == "" ? "~" : p); else if (k < p) k = p; p = k
      printf "e\t%s\t%s\n", k, $0 }' "$f"
}
