# payload/scripts/lib/owed.sh — WHAT THE PERSON OWES THE RUN (epic-23 wave-33-workhorse, T11;
# REQ-2 AC-2.2, AC-2.3; spec D2, ADR-052).
#
# [WALL: tests/notify.test.sh]
#
# WHY IT EXISTS. No code decided "this turn ends blocked on the person": the blocks lived as
# separate printed lines (a Step card's question, the tick's GATE, an approval a row reads), and
# nothing remembered which of them the person had already been told about. This is that memory,
# declared at the source: the code that leaves the person a decision opens an item, the verb
# that records the answer closes it, and the one sender (lib/notify.sh) sends each open item
# at least once: a send that fails, a timeout after the service accepted it included, is sent
# again by the next caller, so the person may hear of an item twice and never not at all
# (wave-34 T5; D10 "1").
#
# THE STORE IS THE RUN'S. An ask belongs to the run it holds, not to the session that raised it. Each act on it (an
# opening, an answer, a send marked or taken back, a close) is one `ask` event appended to the run's log,
# `<docs>/record/<run>/run.log`, <run> the plan's file name less `.plan.md`, through the one appender (lib/log.sh) and
# at this library's clock. The register beside it, `asks.state`, is never written again: it is the run's history, and
# every read reads it, then the log, as one list. Every session acting for the run, a helper's stand-in session
# included, writes there and reads there, so an ask answered in one session is closed for all of them. It lives under
# record/, not tmp/, so an ask raised late in a run survives the tmp wipe and the close-out can still read it. A session
# acting for no run keeps `.bionic/tmp/owed-<session>.state`, session-keyed like every other `<class>-<session>.state`
# there, wiped with them, and written the same way: its events appended after any register lines it held. A session
# file written before its run had a register is not read as the run's.
#
# THE ONE LIST (`_owed_lines`) is one line per round of an item in the order the rounds opened, the last line of a key
# its current state, in the register's shape:
#
#   owed/v1|key=<key>|state=open|sent=<ISO-UTC or ->|at=<ISO-UTC>|title=<title>|reply=<line>[|round=<n>][|answer=<word>|answered=<ISO-UTC>|event=<what or ->]
#   owed/v1|key=<key>|state=closed|by=<closer>|at=<ISO-UTC>|opened=<the open line's at>[|round=<n>][|answer=…|answered=…|event=…]
#
# The register's lines stand as written. An event names its round by `round=<n>` from the second on, as the register
# does, and sets on it the fields it carries: `sent=` and `title=`; `prompt=`, the line the run printed (the register's
# reply=); `answer=` and `event=`, answered at the event's instant; and `reply=`, the closer's words, which close the
# round at the event's instant. That is the shape lib/translate.sh reads the register in, so the reader reads an ask in
# either home alike. A run brought forward is read from its log alone, as the reader reads it.
#
# The bracketed answer fields are an answer the user gave the open ask (THE ANSWER, below); a closed line keeps them.
#
# EVERY ROUND IS KEPT. An item opened again after it closed (a decision put again after its ruling) is a new round
# beside the closed one, carrying `round=<n>`, the first round's 1 implicit. A key holds at most ONE OPEN round, always
# its last, so every reader of the current state reads a key's last line, and the closer closes that round. The closed
# rounds stay, because the minutes the person stood on each are the run's clock (`owed_rounds`).
#
# An append is one write, so two writers never interleave and no lock is held: two writers of one act write one round
# twice and the list reads it once. A `|`, a tab, a CR or a LF in a value is folded to a space on the way in: no value
# can forge a field. A key is
# `<kind>:<id>` (`approve:step1`, `gate:<hash>`), letters, digits and `:._-` only.
#
# A DECISION HAS ONE KEY, `decide:D<n>`. A row that waits on a numbered decision reads it as
# `approval:D<n>`, so the tick and the dispatch wall open `approve:D<n>` and the approve verb closes
# it, while the pages owe the same decision from the design ledger's put. One reply answers both,
# so `owed_key` folds the approval spelling onto the decision's key on every read and write here:
# every writer opens the same item, every closer closes it, and the person is owed it once.
#
# THE ITEM IS A NEED, NEVER THE DECISION. The title is a short ASCII label (it becomes a push
# notification's Title header), the reply is the one line the run printed for the block. What
# the person decided is recorded by the verb that heard it, in the plan, as before (wave-29's
# "nothing written per decision" stands).
#
# WHERE IT RESOLVES. The root is `OWED_ROOT`, else `BIONIC_ROOT` (a hook's context), else
# `project_root` of the working directory; the session is `OWED_SID`, else `BIONIC_SID`, else
# `CLAUDE_CODE_SESSION_ID`. The run is the plan `OWED_PLAN` names, else the session's bound plan
# (lib/run.sh `session_plan`); a caller that acts for a plan under a session no marker binds to it
# (the close-out's dry commits) names the plan. A plan names a run only while it is a file whose name
# ends `.plan.md`: a scratch copy, an archived run or a plan that is gone names none, and its asks stay
# with the session. No session, no root, or a store or its directory that is a symlink: every
# function returns 1 and writes nothing. Silent at source time; nothing here prints on stderr, so a
# caller's output is the same with or without a store.
#
# BASH 3.2. No associative arrays.

_owed_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}
_OWED_LIB_DIR="$(cd "$(_owed_self_dir)" && pwd -P)"
if ! declare -F project_root >/dev/null 2>&1 && [ -r "$_OWED_LIB_DIR/root.sh" ]; then
  # shellcheck source=/dev/null
  . "$_OWED_LIB_DIR/root.sh"
fi
if ! declare -F session_plan >/dev/null 2>&1 && [ -r "$_OWED_LIB_DIR/run.sh" ]; then
  # shellcheck source=/dev/null
  . "$_OWED_LIB_DIR/run.sh"
fi
if ! declare -F notify_send >/dev/null 2>&1 && [ -r "$_OWED_LIB_DIR/notify.sh" ]; then
  # shellcheck source=/dev/null
  . "$_OWED_LIB_DIR/notify.sh"
fi

OWED_SCHEMA="owed/v1"

# owed_register <root> <plan> -> the run's register, `<docs>/record/<run>/asks.state`, on stdout; rc 1 when
# <plan> names no run: not a file, or a name that does not end `.plan.md` (a scratch copy's does not).
owed_register() {
  local root="${1:-}" plan="${2:-}" run docs
  [ -n "$root" ] && [ -n "$plan" ] || return 1
  case "$plan" in *.plan.md) ;; *) return 1 ;; esac
  [ -f "$plan" ] || return 1
  run="${plan##*/}"; run="${run%.plan.md}"
  case "$run" in ''|.*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  declare -F docs_root >/dev/null 2>&1 || return 1
  docs="$(docs_root "$root" 2>/dev/null)" && [ -n "$docs" ] || return 1
  printf '%s/record/%s/asks.state\n' "$docs" "$run"
}

# owed_file -> the store's absolute path on stdout: the run's register, else the session's own file; rc 1
# when there is no session or no root. The session is required even where the run names the store, so a
# caller that sets an invalid session to write nothing (a preview) writes nothing.
owed_file() {
  local root sid plan
  sid="${OWED_SID:-${BIONIC_SID:-${CLAUDE_CODE_SESSION_ID:-}}}"
  [ -n "$sid" ] || return 1
  case "$sid" in *[!A-Za-z0-9._-]*|.|..) return 1 ;; esac
  root="${OWED_ROOT:-${BIONIC_ROOT:-}}"
  if [ -z "$root" ] && declare -F project_root >/dev/null 2>&1; then
    root="$(project_root "$PWD" 2>/dev/null)"
  fi
  [ -n "$root" ] || return 1
  plan="${OWED_PLAN:-}"
  if [ -z "$plan" ] && declare -F session_plan >/dev/null 2>&1; then
    plan="$(session_plan "$root" "$sid" 2>/dev/null)" || plan=""
  fi
  owed_register "$root" "$plan" && return 0
  printf '%s/.bionic/tmp/owed-%s.state\n' "$root" "$sid"
}

_owed_key_ok() {  # <key>
  case "${1:-}" in
    ''|*[!A-Za-z0-9:._-]*) return 1 ;;
    *:*) return 0 ;;
  esac
  return 1
}

# owed_key <key> -> the key the store files it under: `approve:D<n>` is `decide:D<n>`, every other key itself.
owed_key() {
  case "${1:-}" in
    approve:D[0-9]*) case "${1#approve:D}" in *[!0-9]*) printf '%s\n' "$1" ;; *) printf 'decide:%s\n' "${1#approve:}" ;; esac ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

_owed_clean() {  # <value> -> the value with | TAB CR LF folded to a space
  printf '%s' "${1:-}" | tr '|\t\r\n' '    '
}

# owed_now -> the instant every line here is stamped with, ISO-UTC: BIONIC_NOW_EPOCH when it is a number (the clock
# seam the poker's readers honour, so a suite fixes every instant it reads), else the clock. A verb that writes an
# instant beside the register's own (the plan's approval) takes it from here, so the two agree to the second.
owed_now() {
  case "${BIONIC_NOW_EPOCH:-}" in
    ''|*[!0-9]*) date -u +%Y-%m-%dT%H:%M:%SZ ;;
    *) date -u -r "$BIONIC_NOW_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$BIONIC_NOW_EPOCH" +%Y-%m-%dT%H:%M:%SZ ;;
  esac
}

# _owed_dir_ok <store path> -> 0 when its directory may be written: neither it nor the store is a
# link. The worktree's `.bionic` link to the main checkout is the one link a tree carries, and it
# is followed as the rest of bionic's writers follow it; the store's own directory (tmp/, or the
# run's record directory) may not be.
_owed_dir_ok() {
  local d="${1%/*}"
  [ -L "$d" ] && return 1
  [ -L "$1" ] && return 1
  return 0
}

# The fields of one line, by name, and a line's key as `owed_key` files it: the awk every reader and
# writer below shares, so a line written under the approval spelling of a decision reads as the decision.
_OWED_AWK_FIELD='function fld(line, name,   n, i, a, p) {
  n = split(line, a, "|"); p = name "="
  for (i = 2; i <= n; i++) if (index(a[i], p) == 1) return substr(a[i], length(p) + 1)
  return ""
}
function key_of(line,   k) {
  k = fld(line, "key")
  return (k ~ /^approve:D[0-9]+$/) ? "decide:" substr(k, 9) : k
}'

# _owed_lines <store> -> THE ONE LIST of the store (above): a run's register, then its log; a session's file, which holds
# both shapes. rc 1 when it cannot be read. A home that is a link is not read.
_owed_lines() {
  local f="${1:-}" log="" h
  case "$f" in */asks.state) log="${f%/*}/run.log"
    if [ -d "${f%/*}/kept" ]; then
      declare -F reader_brought_at >/dev/null 2>&1 || . "$_OWED_LIB_DIR/reader.sh" >/dev/null 2>&1 || return 1
      ! reader_brought_at "${f%/*}" || f=""
    fi ;;
  esac
  set --
  for h in "$f" "$log"; do [ -n "$h" ] && [ -f "$h" ] && [ ! -L "$h" ] && set -- "$@" "$h"; done
  [ "$#" -gt 0 ] || return 0
  awk "$_OWED_AWK_FIELD"'
    function round(k, r,   i) { i = k SUBSEP r; if (!(i in ST)) { ord[++m] = i; ST[i] = "open"; SE[i] = "-" } return i }
    index($0, "owed/v1|") == 1 { k = key_of($0); n[k]++; r = fld($0, "round"); i = round(k, (r == "") ? n[k] : r)
      ST[i] = fld($0, "state"); RD[i] = fld($0, "answer"); AD[i] = fld($0, "answered"); EV[i] = fld($0, "event")
      if (ST[i] == "open") { SE[i] = fld($0, "sent"); OP[i] = fld($0, "at"); TI[i] = fld($0, "title"); PR[i] = fld($0, "reply") }
      else { BY[i] = fld($0, "by"); CL[i] = fld($0, "at"); OP[i] = fld($0, "opened") }
      next }
    index($0, "run/v1|ev=ask|") != 1 { next }
    { a = fld($0, "at"); r = fld($0, "round"); i = round(key_of($0), (r == "") ? 1 : r); if (OP[i] == "") OP[i] = a
      if ((v = fld($0, "sent")) != "") SE[i] = v
      if ((v = fld($0, "title")) != "") TI[i] = v
      if ((v = fld($0, "prompt")) != "") PR[i] = v
      if ((v = fld($0, "answer")) != "") { RD[i] = v; AD[i] = a; EV[i] = fld($0, "event") }
      if ((v = fld($0, "reply")) != "") { ST[i] = "closed"; BY[i] = v; CL[i] = a } }
    END { for (j = 1; j <= m; j++) { i = ord[j]; split(i, p, SUBSEP)
        rs = (p[2] + 0 > 1) ? "|round=" p[2] : ""; an = (RD[i] != "") ? "|answer=" RD[i] "|answered=" AD[i] "|event=" EV[i] : ""
        if (ST[i] == "open") printf "owed/v1|key=%s|state=open|sent=%s|at=%s|title=%s|reply=%s%s%s\n", p[1], SE[i], OP[i], TI[i], PR[i], rs, an
        else printf "owed/v1|key=%s|state=closed|by=%s|at=%s|opened=%s%s%s\n", p[1], BY[i], CL[i], OP[i], rs, an } }' "$@" 2>/dev/null
}

# _owed_last <store> <key> -> the key's last round as <state> TAB <round> TAB <sent>; nothing when it has none; rc 1
# when the store cannot be read
_owed_last() {
  local l
  l="$(_owed_lines "$1")" || return 1
  printf '%s\n' "$l" | awk -v key="$2" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") == 1 && key_of($0) == key { n++; r = fld($0, "round"); s = fld($0, "state") "\t" (r == "" ? n : r) "\t" fld($0, "sent") }
    END { if (n) print s }'
}

# _owed_act <store> <ISO-UTC or -> <key> <round> <field>... -> rc 0 with one ask event on <key>'s round appended to the
# store's log (a run's register names the run.log beside it; a session's file is its own), at <ISO-UTC> or this
# library's clock. rc 1, nothing written, when the store, its directory or the log is a link or the append fails.
_owed_act() {
  local f="$1" at="$2" key="$3" r="$4" log
  shift 4
  case "$f" in */asks.state) log="${f%/*}/run.log" ;; *) log="$f" ;; esac
  _owed_dir_ok "$f" && [ ! -L "$log" ] || return 1
  declare -F log_append >/dev/null 2>&1 || . "$_OWED_LIB_DIR/log.sh" >/dev/null 2>&1 || return 1
  [ "$at" != - ] || at="$(owed_now)"
  [ "$r" -gt 1 ] 2>/dev/null && set -- "round=$r" "$@"
  RUN_LOG="$log" LOG_AT="$at" log_append ask "key=$key" "$@" >/dev/null 2>&1
}
_owed_round() { local r="${1#*	}"; printf '%s\n' "${r%%	*}"; }  # <_owed_last line> -> its round

# owed_open <key> <title> <reply> -> rc 0. IDEMPOTENT PER KEY: an item already open is left as it
# is (sent or not) and nothing is written, so a card rendered twice is one item and one send. A key that
# was never seen is opened unsent; a key whose last round is closed is opened as a new round, unsent,
# after the rounds before it, which stay as they are: a new block on an old key is a new need, and the
# old one's minutes are kept.
owed_open() {
  local key="${1:-}" title reply f st
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  title="$(_owed_clean "${2:-}")"
  reply="$(_owed_clean "${3:-}")"
  f="$(owed_file)" || return 1
  _owed_dir_ok "$f" || return 1
  st="$(_owed_last "$f" "$key")" || return 1
  case "$st" in open*) return 0 ;; esac
  _owed_act "$f" - "$key" $(( ${st:+$(_owed_round "$st")} + 1 )) sent=- "title=$title" "prompt=$reply"
}

# owed_close <key> <by> [<at ISO-UTC>] -> rc 0. Closes an open item, its one open round, at <at> when given (a verb that
# wrote the same instant elsewhere), else now; a key that is not open is left alone. The closed round keeps its opening
# as `opened=`, so the minutes the item stood open can still be counted once it is closed, and its answer, so what the
# item waited on once answered reads the same once it is closed.
owed_close() {
  local key="${1:-}" by at f st
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  by="$(_owed_clean "${2:-}")"
  at="${3:-}"
  case "$at" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;; *) at="$(owed_now)" ;; esac
  f="$(owed_file)" || return 1
  st="$(_owed_last "$f" "$key")" || return 1
  case "$st" in open*) ;; *) return 0 ;; esac
  _owed_act "$f" "$at" "$key" "$(_owed_round "$st")" "reply=${by:--}"
}

_owed_list_file() {  # <store> -> owed_list's lines for that store, read as one list
  local l
  l="$(_owed_lines "$1")" || return 1
  printf '%s\n' "$l" | awk "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    fld($0, "state") == "open" { printf "%s\t%s\t%s\t%s\n", key_of($0), fld($0, "sent"), fld($0, "title"), fld($0, "reply") }
  '
}

# owed_lines [<plan> <root>] -> THE ONE LIST (above) of the run's register <plan> names under <root>, else of
# `owed_file`; rc 1 when there is no store or it cannot be read.
owed_lines() {
  local f
  f="$(_owed_store_for "${1:-}" "${2:-}")" || return 1
  _owed_lines "$f"
}

# owed_list -> one line per OPEN item: <key> TAB <sent ISO or -> TAB <title> TAB <reply>.
owed_list() {
  local f
  f="$(owed_file)" || return 1
  _owed_list_file "$f"
}

# owed_rounds <key ERE> [<plan> <root>] -> one line per round of every key the extended regular expression matches
# whole, open or closed, in the order they were opened: <key> TAB <round> TAB <open|closed> TAB <opened ISO or -> TAB
# <closed ISO, or - while open>; read as one list from the run <plan> names under <root>, else from `owed_file`. A round's
# number is its line's round=, else its place among the key's lines. A closed line written before closed lines kept
# their opening reads `-` for it.
owed_rounds() {
  local l
  [ -n "${1:-}" ] || return 1
  l="$(owed_lines "${2:-}" "${3:-}")" || return 1
  printf '%s\n' "$l" | OWED_P="^(${1})\$" awk "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    { k = key_of($0) }
    k !~ ENVIRON["OWED_P"] { next }
    { n[k]++; r = fld($0, "round"); if (r == "") r = n[k] }
    fld($0, "state") == "open" { printf "%s\t%s\topen\t%s\t-\n", k, r, fld($0, "at"); next }
    { o = fld($0, "opened"); printf "%s\t%s\tclosed\t%s\t%s\n", k, r, (o == "" ? "-" : o), fld($0, "at") }
  '
}

# owed_list_plan <plan> <root> -> owed_list's lines for the run <plan> names, read from its register under <root>,
# never the caller's session. rc 1 when there is no plan or no root; nothing printed when <plan> names no run or its
# register holds no open item.
owed_list_plan() {
  local f
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 1
  f="$(owed_register "$2" "$1")" || return 0
  _owed_list_file "$f"
}


# THE ANSWER AND WHAT AN ASK WAITS ON. An answer is what the user has said to an ask that is not yet closed: `no` to a
# waiver, `carry` to a finding. It is stored on the open round, its line's last fields, and it never closes the ask:
#
#   owed/v1|key=<key>|state=open|sent=…|at=…|title=…|reply=…|answer=<word>|answered=<ISO-UTC>|event=<what or ->
#
# The ask closes at the event the answer names, where it closes today: a waiver when its review passes, is waived or a
# born row's landing settles it; a finding carried to a row at that row's landing (lib/line.sh); a finding carried with
# no row at the release approval card's reply. Because `owed_open` leaves an open line as it is, the re-open a failing
# pass makes keeps the answer, and a fresh open after a close starts with none. What an ask waits on is never stored:
# `ask_waits_on` derives it from the key's kind and its answer, so every reader asks the one function and no opener
# has a field to forget.

# _owed_store_for [<plan> <root>] -> the store a reader reads: the run's register <plan> names under <root> when both
# are given, else `owed_file`. rc 1 when there is none.
_owed_store_for() {
  if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then owed_register "$2" "$1"; return; fi
  owed_file
}

# owed_answer <key> <word> [<event>] -> rc 0 with the answer on the key's open round, the instant it was given and the
# event it waits on (`-` when none is named); a later answer replaces an earlier one. rc 1, nothing written, when the
# key is not open, the word is not one word of letters, digits and `._-`, or there is no store.
owed_answer() {
  local key="${1:-}" word="${2:-}" event f st
  _owed_key_ok "$key" || return 1
  case "$word" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  key="$(owed_key "$key")"
  event="$(_owed_clean "${3:-}")"
  f="$(owed_file)" || return 1
  st="$(_owed_last "$f" "$key")" || return 1
  case "$st" in open*) ;; *) return 1 ;; esac
  _owed_act "$f" - "$key" "$(_owed_round "$st")" "answer=$word" "event=${event:--}"
}

_owed_answers_file() {  # <store> -> owed_answers' lines for that store, read as one list
  local l
  l="$(_owed_lines "$1")" || return 1
  printf '%s\n' "$l" | awk "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    fld($0, "state") == "open" && fld($0, "answer") != "" {
      printf "%s\t%s\t%s\t%s\n", key_of($0), fld($0, "answer"), fld($0, "answered"), fld($0, "event")
    }'
}

# owed_answers [<plan> <root>] -> one line per OPEN item that holds an answer: <key> TAB <word> TAB <answered ISO> TAB
# <event or ->, read as one list from the run <plan> names under <root>, else from `owed_file`.
owed_answers() {
  local f
  f="$(_owed_store_for "${1:-}" "${2:-}")" || return 1
  _owed_answers_file "$f"
}

# owed_answer_of <key> [<plan> <root>] -> the key's answer, `<word> TAB <answered ISO> TAB <event or ->`, from its last
# line, open or closed, since a closed line keeps the answer it was given; nothing when it was never answered. A new
# round after a close is the key's last line and starts with no answer, so it reads none.
owed_answer_of() {
  local key l
  key="$(owed_key "${1:-}")"
  l="$(owed_lines "${2:-}" "${3:-}")" || return 1
  printf '%s\n' "$l" | awk -v key="$key" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") == 1 && key_of($0) == key { l = $0 }
    END { if (l != "" && fld(l, "answer") != "") print fld(l, "answer") "\t" fld(l, "answered") "\t" fld(l, "event") }'
}

# ask_waits_on <key> [<plan> <root>] -> `user` or `event <what>` on one line, rc 0, from the key's kind and its answer,
# read from its line open or closed.
# An unanswered waiver or finding, and every kind the user rules (a decision, a goal declared missed, an approval, a
# gate, a ruling, a matrix row), wait on the user; so does a kind this function does not know, because doubt is the
# user's. A waiver answered no waits on its review's next run; a finding answered carry on the event its answer names,
# else on the release card; a carry the run chose on the release card; a delivery on the close-out; a held merge on
# what the open waivers holding it wait on, the user while one is unanswered or none is open.
ask_waits_on() {
  local key ans word ev
  key="$(owed_key "${1:-}")"
  case "$key" in
    carry:*) printf 'event release card\n'; return 0 ;;
    delivered:*) printf 'event close-out\n'; return 0 ;;
    hold:merge) _owed_hold_waits "${2:-}" "${3:-}"; return 0 ;;
    waive:*|finding:*) : ;;
    *) printf 'user\n'; return 0 ;;
  esac
  ans="$(owed_answer_of "$key" "${2:-}" "${3:-}")"
  word="${ans%%	*}"; ev="${ans##*	}"; [ "$ev" != - ] || ev=""
  case "$key|$word" in
    waive:*\|no) printf 'event %s\n' "${ev:-review ${key#waive:} re-run}" ;;
    finding:*\|carry) printf 'event %s\n' "${ev:-release card}" ;;
    *) printf 'user\n' ;;
  esac
  return 0
}

_owed_hold_waits() {  # [<plan> <root>] -> what hold:merge waits on: the open waivers' events, or user
  local f k w out="" any=""
  f="$(_owed_store_for "${1:-}" "${2:-}" 2>/dev/null)" || f=""
  for k in $(_owed_list_file "$f" | cut -f1); do
    case "$k" in waive:*) : ;; *) continue ;; esac
    any=1
    w="$(ask_waits_on "$k" "${1:-}" "${2:-}")"
    case "$w" in event\ *) out="${out:+$out, }${w#event }" ;; *) printf 'user\n'; return 0 ;; esac
  done
  if [ -n "$any" ]; then printf 'event %s\n' "$out"; else printf 'user\n'; fi
}

# owed_unsent [<key prefix>] -> the keys of the open items not yet sent, one per line, in the order
# they were opened; with a prefix, only the keys that start with it.
owed_unsent() {
  owed_list | awk -F'\t' -v p="${1:-}" '$2 == "-" && index($1, p) == 1 { print $1 }'
}

# owed_mark_sent <key> -> rc 0. Stamps an open item not yet sent as sent, now; rc 1 when the key has no round.
owed_mark_sent() { _owed_sent "${1:-}" mark; }

# owed_unmark_sent <key> -> rc 0. Takes back the sent mark of an open item, so the next caller sends
# it: `owed_send`'s answer to a send that failed. Only the caller that marked it calls this, and no
# other caller marks an item already marked, so the mark it takes back is its own.
owed_unmark_sent() { _owed_sent "${1:-}" unmark; }

_owed_sent() {  # <key> <mark|unmark> -> the sent mark set or taken back on the key's open round
  local key="${1:-}" f st
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  f="$(owed_file)" || return 1
  st="$(_owed_last "$f" "$key")" && [ -n "$st" ] || return 1
  case "$2|$st" in
    "mark|open	"*"	-") _owed_act "$f" - "$key" "$(_owed_round "$st")" "sent=$(owed_now)" ;;
    "unmark|open	"*) case "$st" in *"	-") return 0 ;; esac; _owed_act "$f" - "$key" "$(_owed_round "$st")" sent=- ;;
  esac
}

# owed_send [<key prefix>] -> rc 0, always, and nothing on stdout or stderr. THE ONE SEND LOOP:
# every open item not yet sent (with a prefix, only its keys) is marked sent and then handed to
# notify_send, title and the line the run printed. Marked BEFORE the send, so a caller killed
# mid-send (the Stop's ten seconds) never sends one twice. A failed send is logged by notify_send,
# its mark is taken back (wave-33 T34; the critic's finding 3 reverses A-T11-3) and the loop stops:
# that item and the ones after it stay unsent for the next caller, so a dead network costs one
# bounded attempt per turn, not one per item, and a working one sends each item at least once: curl's
# timeout can expire after ntfy accepted the message, and that send is retried like any failure.
# No channel declared: returns before reading the store, so nothing is marked and an item still
# open when a channel is declared later is sent then.
owed_send() {
  local prefix="${1:-}" key title reply line
  declare -F notify_send >/dev/null 2>&1 || return 0
  notify_declared || return 0
  for key in $(owed_unsent "$prefix" 2>/dev/null); do
    line="$(owed_list 2>/dev/null | awk -F'\t' -v k="$key" '$1 == k { print; exit }')"
    [ -n "$line" ] || continue
    title="$(printf '%s' "$line" | cut -f3)"
    reply="$(printf '%s' "$line" | cut -f4)"
    owed_mark_sent "$key" >/dev/null 2>&1 || continue
    NOTIFY_KEY="$key" notify_send "$title" "$reply" >/dev/null 2>&1
    if [ "${NOTIFY_RC:-0}" = 2 ]; then
      owed_unmark_sent "$key" >/dev/null 2>&1
      break
    fi
  done
  return 0
}
