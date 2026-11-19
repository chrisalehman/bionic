#!/bin/bash
# payload/scripts/lib/seal.sh — THE SEAL: the record that vouches for a run's plan and log.
#
# WHAT IT OWNS. One plain record per open run, kept where the project's own tools do not reach: the
# plan's canonical path and digest, the log's path, length and digest, and a state, clean or changed.
# A run whose files no longer match their seal is a CHANGED run, and the seal names what changed (the
# plan or the log) and how (gone, changed, shortened or added to). Six functions:
#
#   seal_verify <plan>
#       prints ONE line and exits by it:
#         clean                                0  the plan and the log match the seal
#         changed what=<plan|log> how=<how>    1  they do not, or a change caught earlier still stands
#         none                                 2  no seal stands for this plan
#         nohome                               3  the plan is in no git repository, so it has no seal
#         busy                                 75 the lock could not be had; nothing was read
#       <how> is `gone` or `changed` for the plan, and `gone`, `changed`, `shortened` or `added` for
#       the log. `added` means the log as sealed is still there, whole, with lines after it; a longer
#       log whose sealed part differs is `changed`. A log sealed while absent reads as an empty one, so
#       a log made where there was none is `added`. When the files show a difference now, that is
#       the line; when they match but the seal holds a change caught earlier, the caught one is.
#       The line is also left in the caller's shell as SEAL_LINE, and the log the seal names as
#       SEAL_LOG (empty when no seal was read), so a caller that runs it in its own shell can name
#       the log even when the plan that would lead to it is gone.
#
#   seal_write [--vouch plan|run] <plan> <log> [<command> [<arg>…]]
#       under the lock: checks the run against its seal, runs <command> if one is given, then seals
#       the plan and the log as they then stand. The check comes FIRST so that an honest write made
#       after a change cannot vouch for the change: whatever the check caught is written into the
#       new seal as `state=changed`, and a seal already changed stays changed. So a writer that
#       wraps its own write in this call is sealed with it, and a change made around the tool is
#       not. Only `--vouch run` (the person's word on the run as it stands) seals it clean again,
#       and never a run whose plan is gone. `--vouch plan` is the write hook's, after a plan write
#       it admitted: the plan's new digest is taken without being counted as a change, while the log
#       is still checked and a change already caught is kept. A run with no seal is sealed as found.
#       Exits: 0 sealed clean; 1 sealed changed; 2 nothing sealed (no seal stood and there is no plan,
#       or no home, or the seal could not be written); 64 a call out of shape; 75 the lock could not
#       be had, and then <command> was NOT run. With no home the command still runs: there is no
#       seal to keep, and the caller's act is not the seal's to refuse.
#       Two values are left in the caller's shell: SEAL_WAS, the line `seal_verify` would have printed
#       before the write (`none` when no seal stood, the cue to log the sealing as found; `nohome`),
#       and SEAL_RC, the command's exit (0 when none was given).
#
#   seal_remove <plan>
#       under the lock, removes the run's seal. 0 removed or none stood; 2 no home; 75 the lock
#       could not be had.
#
#   seal_stands <plan>
#       0 when a seal in shape stands for the plan, 1 when none does (a seal out of shape is none, as
#       verify reads it), 2 no home. It takes no lock: a seal is replaced whole by one mv, so a read
#       sees a whole one, and a writer that acts on the answer is checked again under the lock by
#       seal_write.
#
#   seal_vouched <plan>
#       under the lock, prints the log as it was last vouched for: its first bytes, as many as were
#       sealed clean, when they still hold the digest they were sealed with. 0 printed (nothing, for
#       a log vouched for empty); 1 those bytes no longer stand (the log was cut, rewritten or
#       removed), and nothing is printed; 2 no seal; 3 no home; 75 the lock could not be had. A
#       caught change seals the files as they then stand, so without this the bytes the person last
#       vouched for, and the sessions they bound, would be lost at the first catch: a line added by
#       hand would read as the run's own once a commit had been refused.
#
#   seal_owe <plan> <line>
#       leaves a NOTE beside the seal that <line> is an honest line about to be appended without the
#       lock: the appender's call when the lock could not be had, made before its line is written.
#       0 left; 1 not written; 2 no home. It takes no lock: each note is its own file, made whole by
#       one mv. `seal_write --vouch plan` leaves the plan's kind of note itself when it meets the lock.
#
# NOTES OWED BY HONEST WRITERS THAT MET THE LOCK. A writer that cannot have the lock in its wait (many
# writers at once, a slow machine) still writes, since its act is not the seal's to refuse; without a
# note the next check would read its line, or its plan, as changed around the tool, and every commit of
# the run would be refused for an honest act. So a check reads the notes standing for the seal: lines
# past the sealed length are no change when each is one a note holds, each note paying for one line,
# and a plan is no change when a note holds its digest as it now stands. A line or a plan no note
# accounts for is caught as before, beside honest ones too, and a note once paid by a seal is removed,
# so the same bytes appended again by hand are caught. A note is
# `<seal file>.owed.<pid>.<n>`, one line: `log|<the line>` or `plan|<cksum of the plan>`. Notes no
# seal paid within a minute are dropped at the next seal, and every note goes with the seal. A note is
# written where the seal is, by the library alone: whoever can write one could rewrite the seal itself.
#
#   AND THE BINDING, in the same home: which plan each session is bound to, written by
#   lib/binding.sh `bind_plan` and believed by lib/run.sh `session_plan` (`seal_binding_*`, see
#   THE BINDING below).
#
# WHERE IT LIVES. `<common git dir>/bionic-seal/`, the common directory as lib/root.sh's
# `git_common_dir` resolves it from the plan's own directory: the same directory from the main
# checkout and from every linked worktree, outside every tree's files and outside the project's state
# folder, so neither a wipe of that folder nor a tool writing in a tree touches it. Never a tree's own
# git directory (`.git/worktrees/<name>`): a seal there would be seen from one tree only. One file a
# run, `<plan basename>.<cksum of the canonical plan path, crc-length>.seal`, line by line:
#
#   seal/v1
#   plan=<canonical plan path>
#   plan_sum=<cksum of the plan: crc length>     `-` when the plan was gone at the sealing
#   log=<log path, its directory resolved>
#   log_len=<bytes>                              0 for a log absent at the sealing
#   log_sum=<cksum crc of the log>
#   state=clean|changed
#   what=<plan|log>                              both empty while clean
#   how=<gone|changed|shortened|added>
#   vouched=<cksum crc> <bytes>                  only while changed: the log as last sealed clean
#
# A seal out of that shape, or one naming another plan, is read as no seal at all: removing the
# seal has the same effect, and the seal is a trail, not a lock.
#
# THE DIGEST is `cksum`, the one every kept key in the library already uses: it costs about 0.03 s on
# the largest log in the record, and its length field is the log's length, so one fork gives both.
#
# THE LOCK is lib/slots.sh's `_slots_lock` over the home (`<home>/.reap`): an mkdir held for the few
# milliseconds of a check, a write and a seal, given up after about two seconds, and taken over from
# a holder that died or that has held it past a minute. A hook has ten seconds in all, so its wait is
# a fraction of them; the gate's own lock waits about ten and cannot be reused here. verify takes it
# too: without it, a reader between a writer's append and its new seal would read `added`.
#
# THE PLAN PATH is canonical: its directory resolved with `pwd -P` while it exists, as the bind
# function stores it, so a plan reached through a linked directory finds the same seal. A plan whose
# directory is gone is taken as given, which is why callers hand over the canonical spelling they
# hold.
#
# Sourcing defines functions and sets constants; it prints nothing. bash 3.2.

_SEAL_LIB_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P )"
# shellcheck source=/dev/null
declare -F git_common_dir >/dev/null 2>&1 || . "$_SEAL_LIB_DIR/root.sh"
# shellcheck source=/dev/null
declare -F _slots_lock >/dev/null 2>&1 || . "$_SEAL_LIB_DIR/slots.sh"

SEAL_HOME_NAME=bionic-seal
_SEAL_EMPTY=4294967295   # POSIX cksum's crc of no bytes: the digest of a log sealed absent or empty

_seal_canon() {  # <path> -> absolute, its directory symlink-resolved when that directory exists
  local p="$1" d
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  d="${p%/*}"
  if [ -n "$d" ] && [ -d "$d" ] && ! _bionic_root_phys "$d"; then
    d="$(cd "$d" 2>/dev/null && pwd -P)" || d="${p%/*}"
  fi
  printf '%s/%s' "${d%/}" "${p##*/}"
}

_seal_place() {  # <plan> -> _SEAL_PLAN, _SEAL_HOME, _SEAL_FILE; rc 1 when the plan has no home
  local c sum
  _SEAL_PLAN="$(_seal_canon "$1")"
  c="$(git_common_dir "${_SEAL_PLAN%/*}")" || return 1
  _SEAL_HOME="$c/$SEAL_HOME_NAME"
  sum="$(printf '%s' "$_SEAL_PLAN" | cksum)"
  _SEAL_FILE="$_SEAL_HOME/${_SEAL_PLAN##*/}.${sum// /-}.seal"
}

_seal_lock() { _slots_lock "$_SEAL_HOME"; }
_seal_unlock() { rm -rf "$_SEAL_HOME/.reap"; }

_seal_read() {  # <seal file> -> the _S_* fields; rc 1 when it is absent, out of shape, or another plan's
  local l head=""
  _S_PLAN="" _S_PLAN_SUM="" _S_LOG="" _S_LOG_LEN="" _S_LOG_SUM="" _S_STATE="" _S_WHAT="" _S_HOW="" _S_VOUCHED=""
  [ -f "$1" ] || return 1
  while IFS= read -r l; do
    case "$l" in
      seal/v1)    head=1 ;;
      plan=*)     _S_PLAN="${l#plan=}" ;;
      plan_sum=*) _S_PLAN_SUM="${l#plan_sum=}" ;;
      log=*)      _S_LOG="${l#log=}" ;;
      log_len=*)  _S_LOG_LEN="${l#log_len=}" ;;
      log_sum=*)  _S_LOG_SUM="${l#log_sum=}" ;;
      state=*)    _S_STATE="${l#state=}" ;;
      what=*)     _S_WHAT="${l#what=}" ;;
      how=*)      _S_HOW="${l#how=}" ;;
      vouched=*)  _S_VOUCHED="${l#vouched=}" ;;
    esac
  done < "$1"
  [ -n "$head" ] && [ "$_S_PLAN" = "$_SEAL_PLAN" ] && [ -n "$_S_LOG" ] || return 1
  case "$_S_LOG_LEN" in ''|*[!0-9]*) return 1 ;; esac
  case "$_S_STATE" in clean|changed) ;; *) return 1 ;; esac
}

# _seal_check [plan|run] — the run against the seal just read: _SEAL_LINE, rc 0 clean, rc 1 changed.
# The files are compared first, so a difference the files show now is the one named; a change the
# seal already holds is named only when they show none.
_seal_check() {
  local v="${1:-}" cur len crc pre
  _SEAL_LINE=clean _SEAL_PAID=""
  [ "$v" != run ] || return 0
  if [ ! -f "$_S_PLAN" ]; then
    _SEAL_LINE="changed what=plan how=gone"; return 1
  fi
  if [ "$v" != plan ]; then
    cur="$(cksum < "$_S_PLAN")"
    if [ "$cur" != "$_S_PLAN_SUM" ] && ! _seal_owed plan "$cur"; then
      _SEAL_LINE="changed what=plan how=changed"; return 1
    fi
  fi
  if [ -f "$_S_LOG" ]; then
    cur="$(cksum < "$_S_LOG")"; crc="${cur%% *}"; len="${cur##* }"
  elif [ "$_S_LOG_LEN" -gt 0 ]; then
    _SEAL_LINE="changed what=log how=gone"; return 1
  else
    crc="$_S_LOG_SUM"; len=0
  fi
  if [ "$len" -lt "$_S_LOG_LEN" ]; then
    _SEAL_LINE="changed what=log how=shortened"; return 1
  elif [ "$len" -eq "$_S_LOG_LEN" ]; then
    [ "$crc" = "$_S_LOG_SUM" ] || { _SEAL_LINE="changed what=log how=changed"; return 1; }
  else
    pre="$_SEAL_EMPTY"
    [ "$_S_LOG_LEN" -eq 0 ] || pre="$(head -c "$_S_LOG_LEN" < "$_S_LOG" | cksum)"
    if [ "${pre%% *}" != "$_S_LOG_SUM" ]; then _SEAL_LINE="changed what=log how=changed"; return 1; fi
    _seal_owed log || { _SEAL_LINE="changed what=log how=added"; return 1; }
  fi
  if [ "$_S_STATE" = changed ]; then
    _SEAL_LINE="changed what=$_S_WHAT how=$_S_HOW"; return 1
  fi
  return 0
}

# _seal_owed plan <cksum> | log — 0 when the notes standing for the seal just read account for the
# difference: a note holding the plan's digest as it is now, or, for the lines past the sealed length,
# one note each. The notes used are added to _SEAL_PAID. No note, no fork.
_seal_owed() {
  local kind="$1" want="${2:-}" lead="" used
  set -- "$_SEAL_FILE".owed.*
  [ -f "$1" ] || return 1
  if [ "$kind" = plan ]; then
    used="$(LC_ALL=C awk -v w="plan|$want" '$0 "" == w { print FILENAME; exit }' "$@" 2>/dev/null)"
  else
    # An appender writing after a log that ends mid-line opens its write with a line break.
    [ "$_S_LOG_LEN" -eq 0 ] || [ -z "$(head -c "$_S_LOG_LEN" < "$_S_LOG" | tail -c 1)" ] || lead=1
    used="$(tail -c +"$((_S_LOG_LEN + 1))" < "$_S_LOG" | LC_ALL=C awk -v k="$#" -v lead="$lead" '
      FNR == 1 { f++ }
      f <= k { if (substr($0, 1, 4) == "log|") { n++; note[n] = substr($0, 5); file[n] = FILENAME } next }
      { t++ }
      t == 1 && lead && $0 == "" { next }
      { for (i = 1; i <= n; i++) if (!paid[i] && note[i] "" == $0 "") break
        if (i > n) { bad = 1; exit 1 }
        paid[i] = 1; out = out file[i] "\n" }
      END { if (bad || out == "") exit 1; printf "%s", out }' "$@" - 2>/dev/null)" || return 1
  fi
  [ -n "$used" ] || return 1
  _SEAL_PAID="$_SEAL_PAID$used
"
}

_seal_note() {  # <note line> -> a note beside _SEAL_FILE, made whole by one mv
  local tmp="$_SEAL_HOME/.new.$$.$RANDOM"
  { printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$_SEAL_FILE.owed.$$.$RANDOM"; } 2>/dev/null || { rm -f "$tmp"; return 1; }
}

seal_owe() {  # <plan> <line> -> 0 the note left, 1 not, 2 no home
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 64
  case "$2" in *$'\n'*) return 64 ;; esac
  _seal_place "$1" && mkdir -p "$_SEAL_HOME" 2>/dev/null || return 2
  _seal_note "log|$2"
}

# _seal_settle [all] — after a seal is written, under the lock: the notes it paid go, every note
# with `all` (the person's word covers the run as it stands), and any note no seal paid in a minute.
_seal_settle() {
  local f
  set -- "$1" "$_SEAL_FILE".owed.*
  [ -f "$2" ] || return 0
  if [ "$1" = all ]; then shift; rm -f "$@"; return 0; fi
  while IFS= read -r f; do [ -z "$f" ] || rm -f "$f"; done <<< "$_SEAL_PAID"
  find "$_SEAL_HOME" -maxdepth 1 -name "${_SEAL_FILE##*/}.owed.*" -mmin +1 -exec rm -f {} + 2>/dev/null
}

seal_verify() {  # <plan> -> one line: clean | changed what= how= | none | nohome | busy
  local rc
  SEAL_LINE="" SEAL_LOG=""
  [ -n "${1:-}" ] || return 64
  _seal_place "$1" || { SEAL_LINE=nohome; printf 'nohome\n'; return 3; }
  [ -f "$_SEAL_FILE" ] || { SEAL_LINE=none; printf 'none\n'; return 2; }
  _seal_lock || { SEAL_LINE=busy; printf 'busy\n'; return 75; }
  if ! _seal_read "$_SEAL_FILE"; then
    _seal_unlock; SEAL_LINE=none; printf 'none\n'; return 2
  fi
  _seal_check; rc=$?
  _seal_unlock
  SEAL_LINE="$_SEAL_LINE" SEAL_LOG="$_S_LOG"
  printf '%s\n' "$_SEAL_LINE"
  return "$rc"
}

seal_write() {  # [--vouch plan|run] <plan> <log> [<command> [<arg>…]] -> 0 clean, 1 changed, 2 none
  local vouch="" plan log was state=clean what="" how="" psum lsum llen lpath tmp kept=""
  if [ "${1:-}" = --vouch ]; then
    [ "$#" -ge 2 ] || return 64
    vouch="$2"; shift 2
  fi
  case "$vouch" in ''|plan|run) ;; *) return 64 ;; esac
  plan="${1:-}"; log="${2:-}"
  [ -n "$plan" ] && [ -n "$log" ] || return 64
  case "$plan$log" in *$'\n'*) return 64 ;; esac
  shift 2
  SEAL_WAS="" SEAL_RC=0 _SEAL_PAID=""
  if ! _seal_place "$plan" || ! mkdir -p "$_SEAL_HOME" 2>/dev/null; then
    SEAL_WAS=nohome
    if [ "$#" -gt 0 ]; then "$@"; SEAL_RC=$?; fi
    return 2
  fi
  if ! _seal_lock; then
    # The plan the write hook admitted is on disk now: its digest is owed, so that this honest
    # write is not read as a plan changed around the tool.
    [ "$vouch" != plan ] || [ ! -f "$_SEAL_PLAN" ] || _seal_note "plan|$(cksum < "$_SEAL_PLAN")"
    return 75
  fi
  # A gone plan is never vouched for: it can only be sealed as gone.
  [ -f "$_SEAL_PLAN" ] || vouch=""
  if _seal_read "$_SEAL_FILE"; then
    if _seal_check "$vouch"; then was=clean; else was="$_SEAL_LINE"; fi
  else
    was=none
  fi
  if [ "$#" -gt 0 ]; then "$@"; SEAL_RC=$?; fi
  SEAL_WAS="$was"
  if [ "$was" = none ] && [ ! -f "$_SEAL_PLAN" ]; then
    _seal_unlock; return 2
  fi
  # The log as last vouched for is carried through every changed seal: taken from the clean seal at
  # the catch, kept from the changed one after it. Whether its bytes still stand is the reader's to ask.
  case "$was" in
    changed*) state=changed; what="${was#*what=}"; what="${what%% *}"; how="${was##*how=}"
      kept="$_S_VOUCHED"; [ "$_S_STATE" = changed ] || kept="$_S_LOG_SUM $_S_LOG_LEN" ;;
  esac
  psum=-
  [ ! -f "$_SEAL_PLAN" ] || psum="$(cksum < "$_SEAL_PLAN")"
  lpath="$(_seal_canon "$log")"
  if [ -f "$lpath" ]; then
    lsum="$(cksum < "$lpath")"; llen="${lsum##* }"; lsum="${lsum%% *}"
  else
    llen=0; lsum="$_SEAL_EMPTY"
  fi
  tmp="$_SEAL_HOME/.new.$$.$RANDOM"
  if ! printf 'seal/v1\nplan=%s\nplan_sum=%s\nlog=%s\nlog_len=%s\nlog_sum=%s\nstate=%s\nwhat=%s\nhow=%s\n%s' \
       "$_SEAL_PLAN" "$psum" "$lpath" "$llen" "$lsum" "$state" "$what" "$how" "${kept:+vouched=$kept
}" > "$tmp" 2>/dev/null \
     || ! mv -f "$tmp" "$_SEAL_FILE" 2>/dev/null; then
    rm -f "$tmp"; _seal_unlock; return 2
  fi
  _seal_settle "$([ "$vouch" = run ] && echo all)"
  _seal_unlock
  [ "$state" = clean ]
}

seal_remove() {  # <plan> -> 0 removed or none stood, 2 no home, 75 the lock not had
  [ -n "${1:-}" ] || return 64
  _seal_place "$1" || return 2
  [ -f "$_SEAL_FILE" ] || return 0
  _seal_lock || return 75
  rm -f "$_SEAL_FILE" "$_SEAL_FILE".owed.*
  _seal_unlock
}

seal_stands() {  # <plan> -> 0 a seal stands, 1 none, 2 no home
  [ -n "${1:-}" ] || return 64
  _seal_place "$1" || return 2
  _seal_read "$_SEAL_FILE" || return 1
}

seal_vouched() {  # <plan> -> the log as last vouched for, on stdout: 0; 1 its bytes no longer stand; 2 none; 3 nohome
  local v len pre
  [ -n "${1:-}" ] || return 64
  _seal_place "$1" || return 3
  [ -f "$_SEAL_FILE" ] || return 2
  _seal_lock || return 75
  _seal_read "$_SEAL_FILE" || { _seal_unlock; return 2; }
  # A changed seal with no bytes kept (one written before they were kept) vouches for none.
  v="$_S_LOG_SUM $_S_LOG_LEN"; [ "$_S_STATE" = clean ] || v="${_S_VOUCHED:-$_SEAL_EMPTY 0}"
  len="${v##* }"
  case "$len" in ''|*[!0-9]*) _seal_unlock; return 1 ;; esac
  pre="$_SEAL_EMPTY 0"
  [ "$len" -eq 0 ] || pre="$(head -c "$len" < "$_S_LOG" 2>/dev/null | cksum)"
  if [ "$pre" != "${v%% *} $len" ]; then _seal_unlock; return 1; fi
  [ "$len" -eq 0 ] || head -c "$len" < "$_S_LOG"
  _seal_unlock
}

# ─── THE BINDING: which plan a session is bound to, kept in the seal's home ───
#
# The engaged file in the project's state folder is where any tool can remove, link or rewrite
# it, so the plan a session is bound to is also recorded here, beside the seals, and the one
# question of which run a session is in (lib/run.sh `session_plan`) believes this record over
# that file. lib/binding.sh `bind_plan` is its one writer, on every binding it makes, to `none`
# too. A session with no record (one that never bound, or a synthetic dry session that writes an
# engaged file and never calls `bind_plan`) is answered from its engaged file, as before.
#
#   seal_binding_put  <root> <sid> <plan|none>  0 written · 1 not written · 2 no home · 64 out of shape
#   seal_binding_get  <root> <sid>              the plan or `none` on stdout, 0; 1 when no record stands
#   seal_binding_drop <root> <sid>              0 removed or none stood · 1 not removed · 2 no home
#   seal_binding_warm <root>                    resolves the root's home once, in the caller's shell
#
# ONE FILE A SESSION AND STATE FOLDER: `<home>/<sid>.<cksum of the state folder, crc-length>.binding`,
#
#   binding/v1
#   session=<sid>
#   state=<the root's .bionic, symlinks resolved>
#   plan=<canonical plan path | none>
#
# KEYED BY THE STATE FOLDER, RESOLVED, and not by the root's spelling: a writer's tree links its
# `.bionic` to the main checkout's, so the main checkout and every linked tree read one record for
# a session, and a dispatched agent, which carries its parent's session id, is answered on its
# parent's run. Two roots of one repository with state folders of their own hold two records. A
# record out of shape, or naming another session or state folder, is no record.
#
# NO LOCK. Each record has one writer at a time (the session's own binding act) and is written as a
# temporary file and moved, so a reader never sees half of one; the seals' lock is not waited on.
#
# THE HOME IS RESOLVED ONCE A SHELL. `git_common_dir` is a git fork; the hooks ask this question
# several times a call, so the answer for the last root asked is kept in _SB_ROOT/_SB_COMMON/_SB_STATE
# and `seal_binding_warm` fills it where command substitutions below inherit it.

seal_binding_warm() {  # <root> -> 0 when the root has a home; the cache filled in this shell
  local root="${1:-}" c s
  [ -n "$root" ] || return 1
  # Only a found home that still stands is kept: a root asked before its repository exists, or
  # made again without one, is asked again.
  [ "${_SB_ROOT:-}" = "$root" ] && [ -n "${_SB_COMMON:-}" ] && [ -d "$_SB_COMMON" ] && return 0
  c="$(git_common_dir "$root")" || c=""
  s="$(cd "$root/.bionic" 2>/dev/null && pwd -P)" \
    || s="$(cd "$root" 2>/dev/null && pwd -P)/.bionic" || s="$root/.bionic"
  _SB_ROOT="$root" _SB_COMMON="$c" _SB_STATE="$s"
  [ -n "$c" ]
}

_seal_binding_place() {  # <root> <sid> -> _SB_FILE (and the warm cache); 1 no home, 64 a sid out of shape
  local sum
  case "${2:-}" in ''|unknown|*[!A-Za-z0-9_-]*) return 64 ;; esac
  seal_binding_warm "$1" || return 1
  sum="$(printf '%s' "$_SB_STATE" | cksum)"
  _SB_FILE="$_SB_COMMON/$SEAL_HOME_NAME/$2.${sum// /-}.binding"
}

seal_binding_put() {  # <root> <sid> <plan|none>
  local value="${3:-}" tmp rc=0
  case "$value" in ''|*$'\n'*|*$'\r'*) return 64 ;; none|/*) ;; *) return 64 ;; esac
  _seal_binding_place "$1" "${2:-}" || { rc=$?; [ "$rc" -eq 64 ] && return 64; return 2; }
  mkdir -p "${_SB_FILE%/*}" 2>/dev/null || return 1
  tmp="${_SB_FILE%/*}/.new.$$.$RANDOM"
  if ! printf 'binding/v1\nsession=%s\nstate=%s\nplan=%s\n' "$2" "$_SB_STATE" "$value" > "$tmp" 2>/dev/null \
     || ! mv -f "$tmp" "$_SB_FILE" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null; return 1
  fi
}

seal_binding_get() {  # <root> <sid>
  local l head="" ses="" st="" plan="" have=""
  _seal_binding_place "${1:-}" "${2:-}" || return 1
  [ -f "$_SB_FILE" ] && [ ! -L "$_SB_FILE" ] || return 1
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
      binding/v1) head=1 ;;
      session=*)  ses="${l#session=}" ;;
      state=*)    st="${l#state=}" ;;
      plan=*)     plan="${l#plan=}"; have=1 ;;
    esac
  done < "$_SB_FILE"
  [ -n "$head" ] && [ -n "$have" ] && [ "$ses" = "$2" ] && [ "$st" = "$_SB_STATE" ] || return 1
  case "$plan" in none|/*) ;; *) return 1 ;; esac
  case "$plan" in *$'\r'*) return 1 ;; esac
  printf '%s\n' "$plan"
}

seal_binding_drop() {  # <root> <sid>
  _seal_binding_place "${1:-}" "${2:-}" || return 2
  [ -e "$_SB_FILE" ] || [ -L "$_SB_FILE" ] || return 0
  rm -f "$_SB_FILE" 2>/dev/null
}
