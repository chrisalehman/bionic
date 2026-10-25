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
# THE STORE IS THE RUN'S REGISTER. An ask belongs to the run it holds, not to the session that raised
# it: `<docs>/record/<run>/asks.state`, <run> the plan's file name less `.plan.md`. Every session acting
# for the run, a helper's stand-in session included, writes it there and every reader reads it there,
# so an ask answered in one session is closed for all of them. It lives under record/, not tmp/, so an
# ask raised late in a run survives the tmp wipe and the close-out can still read it. A session acting
# for no run keeps `.bionic/tmp/owed-<session>.state`, session-keyed like every other
# `<class>-<session>.state` there. A session file written before its run had a register is not read
# as the run's. One line per item, the last word on a key winning:
#
#   owed/v1|key=<key>|state=open|sent=<ISO-UTC or ->|at=<ISO-UTC>|title=<title>|reply=<line>[|answer=<word>|answered=<ISO-UTC>|event=<what or ->]
#   owed/v1|key=<key>|state=closed|by=<closer>|at=<ISO-UTC>|opened=<the open line's at>[|answer=…|answered=…|event=…]
#
# The bracketed fields are an answer the user gave the open ask (THE ANSWER, below); a closed line keeps them.
#
# The file is rewritten whole, beside-then-rename, under a mkdir lock, so a reader never sees a
# half-written line and two writers cannot lose each other's item. A `|`, a tab, a CR or a LF in
# a value is folded to a space on the way in: no value can forge a field. A key is
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

_owed_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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

_owed_lock() {  # <store> -> rc 0 holding <store>.lock; rc 1 when it cannot be had in about two seconds
  local lk="$1.lock" i=0
  while ! mkdir "$lk" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -ge 100 ]; then
      # A lock older than a minute is a writer that died holding it: taken over once.
      if [ -n "$(find "$lk" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        rmdir "$lk" 2>/dev/null
        mkdir "$lk" 2>/dev/null && return 0
      fi
      return 1
    fi
    sleep 0.02
  done
  return 0
}
_owed_unlock() { rmdir "$1.lock" 2>/dev/null; return 0; }

# _owed_rewrite <store> <awk program> [awk -v assignments...] -> the store rewritten through the
# program, beside-then-rename, under the lock. rc 1 when it could not be written.
_owed_rewrite() {
  local f="$1" prog="$2" tmp rc=0
  shift 2
  _owed_dir_ok "$f" || return 1
  mkdir -p "${f%/*}" 2>/dev/null || return 1
  _owed_lock "$f" || return 1
  tmp="$f.new.$$"
  if [ -f "$f" ]; then
    awk "$@" "$prog" "$f" > "$tmp" 2>/dev/null || rc=1
  else
    awk "$@" "$prog" /dev/null > "$tmp" 2>/dev/null || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    chmod 600 "$tmp" 2>/dev/null
    mv -f "$tmp" "$f" 2>/dev/null || rc=1
  fi
  rm -f "$tmp" 2>/dev/null
  _owed_unlock "$f"
  return "$rc"
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

# owed_open <key> <title> <reply> -> rc 0. IDEMPOTENT PER KEY: an item already open is left as it
# is (sent or not), so a card rendered twice is one item and one send. A key that is closed, or
# was never seen, is opened afresh and unsent: a new block on an old key is a new need.
owed_open() {
  local key="${1:-}" title reply f
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  title="$(_owed_clean "${2:-}")"
  reply="$(_owed_clean "${3:-}")"
  f="$(owed_file)" || return 1
  # The title and the reply go in through the environment, never `-v`, which would read a
  # backslash in a printed line as an escape and store a different line than the one printed.
  OWED_T="$title" OWED_R="$reply" _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    { if (key_of($0) == key) { last = $0; next } print }
    END {
      if (last != "" && fld(last, "state") == "open") print last
      else printf "owed/v1|key=%s|state=open|sent=-|at=%s|title=%s|reply=%s\n", key, now, ENVIRON["OWED_T"], ENVIRON["OWED_R"]
    }' -v key="$key" -v now="$(_owed_now)"
}

# owed_close <key> <by> -> rc 0. Closes an open item; a key that is not open is left alone. The closed line keeps
# the open line's instant as `opened=`, so the minutes the item stood open can still be counted once it is closed, and
# its answer fields, last, so what the item waited on once answered reads the same once it is closed.
owed_close() {
  local key="${1:-}" by f
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  by="$(_owed_clean "${2:-}")"
  f="$(owed_file)" || return 1
  [ -f "$f" ] || return 0
  awk -v key="$key" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") == 1 && key_of($0) == key && fld($0, "state") == "open" { y = 1; exit }
    END { exit !y }' "$f" 2>/dev/null || return 0
  OWED_B="$by" _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    key_of($0) == key && fld($0, "state") == "open" {
      a = (fld($0, "answer") != "") ? sprintf("|answer=%s|answered=%s|event=%s", fld($0, "answer"), fld($0, "answered"), fld($0, "event")) : ""
      printf "owed/v1|key=%s|state=closed|by=%s|at=%s|opened=%s%s\n", key, ENVIRON["OWED_B"], now, fld($0, "at"), a; next
    }
    { print }' -v key="$key" -v now="$(_owed_now)"
}

_owed_list_file() {  # <store> -> owed_list's lines for that store
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  awk "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    fld($0, "state") == "open" { printf "%s\t%s\t%s\t%s\n", key_of($0), fld($0, "sent"), fld($0, "title"), fld($0, "reply") }
  ' "$1" 2>/dev/null
}

# owed_list -> one line per OPEN item: <key> TAB <sent ISO or -> TAB <title> TAB <reply>.
owed_list() {
  local f
  f="$(owed_file)" || return 1
  _owed_list_file "$f"
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
# waiver, `carry` to a finding. It is stored on the open line, after every other field, and it never closes the ask:
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

# owed_answer <key> <word> [<event>] -> rc 0 with the answer on the key's open line, the instant it was given and the
# event it waits on (`-` when none is named); a later answer replaces an earlier one. rc 1, nothing written, when the
# key is not open, the word is not one word of letters, digits and `._-`, or there is no store.
owed_answer() {
  local key="${1:-}" word="${2:-}" event f
  _owed_key_ok "$key" || return 1
  case "$word" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  key="$(owed_key "$key")"
  event="$(_owed_clean "${3:-}")"
  f="$(owed_file)" || return 1
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  awk -v key="$key" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") == 1 && key_of($0) == key && fld($0, "state") == "open" { y = 1; exit }
    END { exit !y }' "$f" 2>/dev/null || return 1
  # The answer fields are always the last on the line and no value holds a `|`, so cutting at `|answer=` drops an
  # earlier answer and nothing else.
  OWED_W="$word" OWED_E="${event:--}" _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    key_of($0) == key && fld($0, "state") == "open" {
      l = $0; i = index(l, "|answer="); if (i) l = substr(l, 1, i - 1)
      printf "%s|answer=%s|answered=%s|event=%s\n", l, ENVIRON["OWED_W"], now, ENVIRON["OWED_E"]; next
    }
    { print }' -v key="$key" -v now="$(_owed_now)"
}

_owed_answers_file() {  # <store> [any] -> owed_answers' lines for that store; with `any`, closed items' answers too
  [ -f "$1" ] && [ ! -L "$1" ] || return 0
  awk -v any="${2:-}" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    (any == "any" || fld($0, "state") == "open") && fld($0, "answer") != "" {
      printf "%s\t%s\t%s\t%s\n", key_of($0), fld($0, "answer"), fld($0, "answered"), fld($0, "event")
    }' "$1" 2>/dev/null
}

# owed_answers [<plan> <root>] -> one line per OPEN item that holds an answer: <key> TAB <word> TAB <answered ISO> TAB
# <event or ->, read from the run's register <plan> names under <root>, else from `owed_file`.
owed_answers() {
  local f
  f="$(_owed_store_for "${1:-}" "${2:-}")" || return 1
  _owed_answers_file "$f"
}

# owed_answer_of <key> [<plan> <root>] -> the key's answer, `<word> TAB <answered ISO> TAB <event or ->`, from its line
# open or closed, since a closed line keeps the answer it was given; nothing when it was never answered. A fresh open
# after a close replaces the closed line, so it reads none.
owed_answer_of() {
  local key f
  key="$(owed_key "${1:-}")"
  f="$(_owed_store_for "${2:-}" "${3:-}")" || return 0
  _owed_answers_file "$f" any 2>/dev/null | awk -F'\t' -v k="$key" '$1 == k { print $2 "\t" $3 "\t" $4; exit }'
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

# owed_mark_sent <key> -> rc 0. Stamps an open item sent, now.
owed_mark_sent() {
  local key="${1:-}" f
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  f="$(owed_file)" || return 1
  [ -f "$f" ] || return 1
  _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    key_of($0) == key && fld($0, "state") == "open" && fld($0, "sent") == "-" { sub(/\|sent=-\|/, "|sent=" now "|") }
    { print }' -v key="$key" -v now="$(_owed_now)"
}

# owed_unmark_sent <key> -> rc 0. Takes back the sent mark of an open item, so the next caller sends
# it: `owed_send`'s answer to a send that failed. Only the caller that marked it calls this, and no
# other caller marks an item already marked, so the mark it takes back is its own.
owed_unmark_sent() {
  local key="${1:-}" f
  _owed_key_ok "$key" || return 1
  key="$(owed_key "$key")"
  f="$(owed_file)" || return 1
  [ -f "$f" ] || return 1
  _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    key_of($0) == key && fld($0, "state") == "open" && fld($0, "sent") != "-" { sub(/\|sent=[^|]*\|/, "|sent=-|") }
    { print }' -v key="$key"
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
