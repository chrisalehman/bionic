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
# once.
#
# THE STORE. `.bionic/tmp/owed-<session>.state` under the project root, session-keyed like every
# other `<class>-<session>.state` there. One line per item, the last word on a key winning:
#
#   owed/v1|key=<key>|state=open|sent=<ISO-UTC or ->|at=<ISO-UTC>|title=<title>|reply=<line>
#   owed/v1|key=<key>|state=closed|by=<closer>|at=<ISO-UTC>
#
# The file is rewritten whole, beside-then-rename, under a mkdir lock, so a reader never sees a
# half-written line and two writers cannot lose each other's item. A `|`, a tab, a CR or a LF in
# a value is folded to a space on the way in: no value can forge a field. A key is
# `<kind>:<id>` (`approve:step1`, `gate:<hash>`), letters, digits and `:._-` only.
#
# THE ITEM IS A NEED, NEVER THE DECISION. The title is a short ASCII label (it becomes a push
# notification's Title header), the reply is the one line the run printed for the block. What
# the person decided is recorded by the verb that heard it, in the plan, as before (wave-29's
# "nothing written per decision" stands).
#
# WHERE IT RESOLVES. The root is `OWED_ROOT`, else `BIONIC_ROOT` (a hook's context), else
# `project_root` of the working directory; the session is `OWED_SID`, else `BIONIC_SID`, else
# `CLAUDE_CODE_SESSION_ID`. No session, no root, or a store or tmp directory that is a symlink:
# every function returns 1 and writes nothing. Silent at source time; nothing here prints on
# stderr, so a caller's output is the same with or without a store.
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
if ! declare -F notify_send >/dev/null 2>&1 && [ -r "$_OWED_LIB_DIR/notify.sh" ]; then
  # shellcheck source=/dev/null
  . "$_OWED_LIB_DIR/notify.sh"
fi

OWED_SCHEMA="owed/v1"

# owed_file -> the store's absolute path on stdout; rc 1 when there is no session or no root.
owed_file() {
  local root sid
  sid="${OWED_SID:-${BIONIC_SID:-${CLAUDE_CODE_SESSION_ID:-}}}"
  [ -n "$sid" ] || return 1
  case "$sid" in *[!A-Za-z0-9._-]*|.|..) return 1 ;; esac
  root="${OWED_ROOT:-${BIONIC_ROOT:-}}"
  if [ -z "$root" ] && declare -F project_root >/dev/null 2>&1; then
    root="$(project_root "$PWD" 2>/dev/null)"
  fi
  [ -n "$root" ] || return 1
  printf '%s/.bionic/tmp/owed-%s.state\n' "$root" "$sid"
}

_owed_key_ok() {  # <key>
  case "${1:-}" in
    ''|*[!A-Za-z0-9:._-]*) return 1 ;;
    *:*) return 0 ;;
  esac
  return 1
}

_owed_clean() {  # <value> -> the value with | TAB CR LF folded to a space
  printf '%s' "${1:-}" | tr '|\t\r\n' '    '
}

_owed_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# _owed_dir_ok <store path> -> 0 when its directory may be written: neither it nor the store is a
# link. The worktree's `.bionic` link to the main checkout is the one link a tree carries, and it
# is followed as the rest of bionic's tmp writers follow it; the tmp directory itself may not be.
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

# The fields of one line, by name: the awk every reader and writer below shares.
_OWED_AWK_FIELD='function fld(line, name,   n, i, a, p) {
  n = split(line, a, "|"); p = name "="
  for (i = 2; i <= n; i++) if (index(a[i], p) == 1) return substr(a[i], length(p) + 1)
  return ""
}'

# owed_open <key> <title> <reply> -> rc 0. IDEMPOTENT PER KEY: an item already open is left as it
# is (sent or not), so a card rendered twice is one item and one send. A key that is closed, or
# was never seen, is opened afresh and unsent: a new block on an old key is a new need.
owed_open() {
  local key="${1:-}" title reply f
  _owed_key_ok "$key" || return 1
  title="$(_owed_clean "${2:-}")"
  reply="$(_owed_clean "${3:-}")"
  f="$(owed_file)" || return 1
  # The title and the reply go in through the environment, never `-v`, which would read a
  # backslash in a printed line as an escape and store a different line than the one printed.
  OWED_T="$title" OWED_R="$reply" _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    { k = fld($0, "key"); if (k == key) { last = $0; next } print }
    END {
      if (last != "" && fld(last, "state") == "open") print last
      else printf "owed/v1|key=%s|state=open|sent=-|at=%s|title=%s|reply=%s\n", key, now, ENVIRON["OWED_T"], ENVIRON["OWED_R"]
    }' -v key="$key" -v now="$(_owed_now)"
}

# owed_close <key> <by> -> rc 0. Closes an open item; a key that is not open is left alone.
owed_close() {
  local key="${1:-}" by f
  _owed_key_ok "$key" || return 1
  by="$(_owed_clean "${2:-}")"
  f="$(owed_file)" || return 1
  [ -f "$f" ] || return 0
  /usr/bin/grep -qF "|key=$key|state=open|" "$f" 2>/dev/null || return 0
  OWED_B="$by" _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    fld($0, "key") == key && fld($0, "state") == "open" {
      printf "owed/v1|key=%s|state=closed|by=%s|at=%s\n", key, ENVIRON["OWED_B"], now; next
    }
    { print }' -v key="$key" -v now="$(_owed_now)"
}

# owed_list -> one line per OPEN item: <key> TAB <sent ISO or -> TAB <title> TAB <reply>.
owed_list() {
  local f
  f="$(owed_file)" || return 1
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  awk "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    fld($0, "state") == "open" { printf "%s\t%s\t%s\t%s\n", fld($0, "key"), fld($0, "sent"), fld($0, "title"), fld($0, "reply") }
  ' "$f" 2>/dev/null
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
  f="$(owed_file)" || return 1
  [ -f "$f" ] || return 1
  _owed_rewrite "$f" "$_OWED_AWK_FIELD"'
    index($0, "owed/v1|") != 1 { next }
    fld($0, "key") == key && fld($0, "state") == "open" && fld($0, "sent") == "-" { sub(/\|sent=-\|/, "|sent=" now "|") }
    { print }' -v key="$key" -v now="$(_owed_now)"
}

# owed_send [<key prefix>] -> rc 0, always, and nothing on stdout or stderr. THE ONE SEND LOOP:
# every open item not yet sent (with a prefix, only its keys) is marked sent and then handed to
# notify_send, title and the line the run printed. Marked BEFORE the send, so a caller killed
# mid-send (the Stop's ten seconds) loses at most one notification and never sends one twice. A
# failed send is logged by notify_send and stops the loop: the items after it stay unsent for the
# next caller, so a dead network costs one bounded attempt per turn, not one per item.
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
    [ "${NOTIFY_RC:-0}" = 2 ] && break
  done
  return 0
}
