# payload/scripts/lib/notify.sh — THE ONE SENDER (epic-23 wave-33-workhorse, T11; REQ-2 AC-2.2,
# AC-2.5; spec D2, ADR-052).
#
# [WALL: tests/notify.test.sh]
#
# WHY IT EXISTS. The harness's own push reaches a phone only while Remote Control is connected,
# and the tick's GATE sentence told the orchestrator to use "the human's own notify channel",
# which nothing defined. This is that channel, and the only code in bionic that sends anything
# off the machine on the person's behalf. lib/owed.sh's `owed_send` is its one caller for the
# person's ledger; T12's setup sends its one test through it.
#
# THE CHANNEL IS DECLARED ONCE, AT USER LEVEL: `<claude home>/bionic/notify` (claude home is
# `$CLAUDE_CONFIG_DIR`, else `~/.claude`, the same rule lib/roots.sh's `claude_home` keeps), lines
#
#   topic-from=cron.env:BIONIC_NTFY_TOPIC
#   title-prefix=<a word or two>
#
# THE TOPIC IS NEVER STORED HERE. `topic-from=<file>:<VAR>` names a file in the claude home and a
# variable in it; the value is read at send time (`VAR=…` or `export VAR=…`, quotes stripped,
# the file never sourced), so the user's one copy of the topic stays where it already is. A topic
# is letters, digits, `_` and `-`; anything else is refused as a failed send, never put in a URL.
#
# THE SEND. `curl -s -f --max-time 5 -H "Title: <prefix> <title>" --data-raw <body>
# https://ntfy.sh/<topic>` — `--data-raw`, because `-d @x` would read a file named by the body.
# Bounded at five seconds, so a dead network costs a Stop (ten seconds) at most one attempt.
#
# NEVER FATAL, NEVER LOUD. `notify_send` returns 0 whatever happens and prints nothing on stdout
# or stderr, so a send can neither change a verb's exit code nor its output (AC-2.5). The outcome
# is in `NOTIFY_RC`: 0 sent, 1 no channel declared (a no-op), 2 failed. A failure is one line in
# the project's audit stream (lib/root.sh's `audit_path`), `notify-failed`, naming why and the
# ledger key the caller set in `NOTIFY_KEY`.
#
# SOURCED, NEVER EXECUTED, AND SILENT AT SOURCE TIME. BASH 3.2.

NOTIFY_RC=1

_notify_home() {
  if declare -F claude_home >/dev/null 2>&1; then claude_home; return 0; fi
  printf '%s\n' "${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-${HOME:-/nonexistent}/.claude}}"
}

# notify_file -> the channel file's path.
notify_file() { printf '%s/bionic/notify\n' "$(_notify_home)"; }

# notify_declared -> rc 0 when the channel file is there to read.
notify_declared() {
  local f; f="$(notify_file)"
  [ -f "$f" ] && [ -r "$f" ]
}

_notify_value() {  # <file> <key> -> the first `<key>=` line's value
  awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$1" 2>/dev/null \
    | tr -d '\r'
}

# _notify_topic -> the topic on stdout, read through the channel file's `topic-from=`; rc 1 with
# the reason on stdout when it cannot be had.
_notify_topic() {
  local from src var path val
  from="$(_notify_value "$(notify_file)" topic-from)"
  src="${from%%:*}"; var="${from#*:}"
  if [ -z "$from" ] || [ "$src" = "$from" ] || [ -z "$src" ] || [ -z "$var" ]; then
    printf 'the channel file names no topic-from=<file>:<VAR>'; return 1
  fi
  case "$src" in */*|.|..) printf 'topic-from names %s, not a file in the claude home' "$src"; return 1 ;; esac
  case "$var" in [A-Za-z_]*) : ;; *) printf 'topic-from names no variable'; return 1 ;; esac
  case "$var" in *[!A-Za-z0-9_]*) printf 'topic-from names no variable'; return 1 ;; esac
  path="$(_notify_home)/$src"
  [ -r "$path" ] || { printf '%s is not readable' "$src"; return 1; }
  val="$(awk -v v="$var" '{
      l = $0; sub(/^[ \t]+/, "", l); sub(/^export[ \t]+/, "", l)
      if (index(l, v "=") == 1) { val = substr(l, length(v) + 2) }
    } END { print val }' "$path" 2>/dev/null | tr -d '\r')"
  val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
  case "$val" in
    '') printf '%s carries no %s' "$src" "$var"; return 1 ;;
    *[!A-Za-z0-9_-]*) printf '%s in %s is not an ntfy topic (letters, digits, _ and -)' "$var" "$src"; return 1 ;;
  esac
  printf '%s' "$val"
}

_notify_fail() {  # <why> -> one line in the project's audit stream; nothing printed
  local root f line
  declare -F audit_path >/dev/null 2>&1 || return 0
  root="${OWED_ROOT:-${BIONIC_ROOT:-}}"
  if [ -z "$root" ] && declare -F project_root >/dev/null 2>&1; then
    root="$(project_root "$PWD" 2>/dev/null)"
  fi
  [ -n "$root" ] || return 0
  f="$(audit_path "$root" 2>/dev/null)" || return 0
  line="- $(date -u +%Y-%m-%dT%H:%M:%SZ) notify notify-failed: $1 key=${NOTIFY_KEY:--}"
  mkdir -p "${f%/*}" 2>/dev/null && printf '%s\n' "$(printf '%s' "$line" | tr '\r\n' '  ')" >> "$f" 2>/dev/null
  return 0
}

# notify_send <title> <body> -> rc 0, always; NOTIFY_RC says what happened (see the header).
notify_send() {
  local title body topic prefix t rc=0
  title="$(printf '%s' "${1:-}" | tr '\r\n' '  ')"
  body="${2:-}"
  NOTIFY_RC=1
  notify_declared || return 0
  if ! topic="$(_notify_topic)"; then
    NOTIFY_RC=2
    _notify_fail "$topic"
    return 0
  fi
  prefix="$(_notify_value "$(notify_file)" title-prefix | tr '\r\n' '  ')"
  t="${prefix:+$prefix }${title}"
  curl -s -f --max-time 5 -o /dev/null -H "Title: ${t}" --data-raw "$body" \
    "https://ntfy.sh/${topic}" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    NOTIFY_RC=0
  else
    NOTIFY_RC=2
    _notify_fail "curl exited $rc"
  fi
  return 0
}
