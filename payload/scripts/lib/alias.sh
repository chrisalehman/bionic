#!/bin/bash
# payload/scripts/lib/alias.sh — THE REGRESSION'S OLD SPELLINGS, MAPPED ONCE (epic-23 wave-38 T8; REQ-9, D6).
#
# WHAT IT OWNS. Until 1.21.0 the full regression's verbs, keys and record tokens spelled "floor". They spell
# "regression" now, and each old spelling is an alias for one release: it still works, and a person or a config
# that types it is told once, on stderr,
#
#     deprecated: <old> is <new>; the old spelling works until 1.22.0
#
# ALIAS_MAP below is the one table of pairs. Every reader asks it through a function of this file at the one seam
# its token has, so the old and the new spelling reach one implementation (tests/regression-rename.test.sh §AGREE):
#
#     verb          floor-run           regression-run       hooks/session-poker.sh, after `VERB="$1"`
#     proof-kind    floor               regression           hooks/session-poker.sh, after `PF_KIND="$1"`
#     config        floor               regression-command   hooks/session-poker.sh regression-run (alias_config)
#     kind          floor               regression           lib/proof.sh proof_fields (alias_awk_norm)
#     reads         proof:floor         proof:regression     lib/units.sh's tokenizer and validator (alias_awk_norm)
#     born          floor               regression           lib/units.sh units_born_marks and lib/proof.sh (alias_alt)
#     born-operand  floor:              regression:          hooks/session-poker.sh task-add --born
#     born-of       floor               regression           the marker's backing, written only
#     log           floor-run-          regression-run-      hooks/session-poker.sh's second-run glob (alias_spellings)
#     rigor-key     rigor-floor         rigor-minimum        hooks/canonical-sdlc-governing-skill.sh (alias_keyed)
#
# TYPED AND WRITTEN ARE TOLD APART (A-T8-1). A spelling a person types (a verb, an operand, a reads cell given to a
# verb) or a config file carries is read with `alias_read`/`alias_cell`/`alias_config`/`alias_keyed`, which print the
# deprecation line. A token a 1.20.0 tool wrote into a plan (a proof line, a reads cell, a born marker) is read inside
# an awk program through `alias_awk_norm`/`alias_alt`, silently: the plan still judges, and every hook that reads
# the plan would otherwise print the line on every call. What is written from now on carries the new spelling.
#
# ONCE PER PROCESS, PER SPELLING. `_ALIAS_SAID` remembers the old spellings already reported. A reader run inside
# `$( … )` reports in that subshell, so the seams call `alias_read` in the shell that runs the verb.
#
# Sourced, never executed. bash 3.2: no associative arrays.

ALIAS_UNTIL="1.22.0"
# <kind>|<old>|<new>|<old as written>|<new as written>
ALIAS_MAP='verb|floor-run|regression-run|floor-run|regression-run
proof-kind|floor|regression|proof-add floor|proof-add regression
config|floor|regression-command|floor:|regression-command:
kind|floor|regression|kind=floor|kind=regression
reads|proof:floor|proof:regression|proof:floor|proof:regression
born|floor|regression|born: floor|born: regression
born-operand|floor:|regression:|--born floor:|--born regression:
born-of|floor|regression|of=floor|of=regression
log|floor-run-|regression-run-|floor-run-<sha>.log|regression-run-<sha>.log
rigor-key|rigor-floor|rigor-minimum|rigor-floor:|rigor-minimum:'
_ALIAS_SAID="${_ALIAS_SAID:-}"

# alias_read <kind> <value> -> ALIAS_TOKEN, the value's canonical spelling: the new one for an old spelling of
# <kind>, the value itself otherwise. An old spelling prints its deprecation line to stderr, once per process.
alias_read() {
  local k="${1:-}" v="${2:-}" mk mo mn mos mns
  ALIAS_TOKEN="$v"
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] && [ "$mo" = "$v" ] || continue
    ALIAS_TOKEN="$mn"
    case " $_ALIAS_SAID " in
      *" $k:$mo "*) : ;;
      *) _ALIAS_SAID="${_ALIAS_SAID:+$_ALIAS_SAID }$k:$mo"
         printf 'deprecated: %s is %s; the old spelling works until %s\n' "$mos" "$mns" "$ALIAS_UNTIL" >&2 ;;
    esac
    return 0
  done <<ALIAS_MAP_EOF
$ALIAS_MAP
ALIAS_MAP_EOF
  return 0
}

# alias_token <kind> <value> -> prints alias_read's answer.
alias_token() {
  alias_read "$@"
  printf '%s\n' "$ALIAS_TOKEN"
}

# alias_spellings <kind> -> the new spelling, then each old one, one per line: what a glob or a key reader walks.
alias_spellings() {
  local k="${1:-}" mk mo mn mos mns first=""
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] || continue
    [ -n "$first" ] || { first=1; printf '%s\n' "$mn"; }
    printf '%s\n' "$mo"
  done <<ALIAS_MAP_EOF
$ALIAS_MAP
ALIAS_MAP_EOF
}

# alias_alt <kind> -> the spellings as one ERE alternation, `new|old…`, for a reader's pattern.
alias_alt() {
  alias_spellings "${1:-}" | paste -sd'|' -
}

# alias_cell <kind> <cell> -> ALIAS_TOKEN, a comma-separated cell with each token read through alias_read (a `live:`
# prefix kept); a cell that carries no old token comes back byte for byte, one that does is joined with `, `.
alias_cell() {
  local k="${1:-}" cell="${2:-}" out="" t p changed="" rest
  rest="$cell"
  while :; do
    t="${rest%%,*}"
    t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    p=""; case "$t" in live:*) p="live:"; t="${t#live:}" ;; esac
    alias_read "$k" "$t"
    [ "$ALIAS_TOKEN" = "$t" ] || changed=1
    [ -z "$p$ALIAS_TOKEN" ] || out="${out:+$out, }$p$ALIAS_TOKEN"
    case "$rest" in *,*) rest="${rest#*,}" ;; *) break ;; esac
  done
  if [ -n "$changed" ]; then ALIAS_TOKEN="$out"; else ALIAS_TOKEN="$cell"; fi
}

# alias_config <root> <kind> [<default>] -> ALIAS_VALUE, the value of the key <kind> names in <root>'s
# .bionic/config.yaml, read by lib/roots.sh `config_value`: the new key first, then each old key, whose value is read
# with its deprecation line; <default> when no spelling is written.
alias_config() {
  local root="${1:-}" k="${2:-}" key v
  ALIAS_VALUE="${3:-}"
  if ! declare -F config_value >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/roots.sh" >/dev/null 2>&1 || return 0
  fi
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    v="$(config_value "$root" "$key" "" 2>/dev/null)"
    [ -n "$v" ] || continue
    alias_read "$k" "$key"; ALIAS_VALUE="$v"; return 0
  done <<ALIAS_KEYS_EOF
$(alias_spellings "$k")
ALIAS_KEYS_EOF
  return 0
}

# alias_keyed <kind> <text> -> ALIAS_VALUE, the value on the first `<key>:` line of <text> (a file's or a
# frontmatter's lines), its trailing blanks and CR dropped: the new key first, then each old key, read with its
# deprecation line; empty when no spelling is written.
alias_keyed() {
  local k="${1:-}" text="${2:-}" key v
  ALIAS_VALUE=""
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    v="$(printf '%s\n' "$text" | awk -v k="$key" '
      { sub(/\r$/, "") }
      index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }')"
    [ -n "$v" ] || continue
    alias_read "$k" "$key"; ALIAS_VALUE="$v"; return 0
  done <<ALIAS_KEYS_EOF
$(alias_spellings "$k")
ALIAS_KEYS_EOF
  return 0
}

# alias_awk_norm <kind> <awk variable> -> awk statements, for an awk program's text, that set the variable to its
# canonical spelling when it holds an old one of <kind>: the map's rows written out, no function, so a program may
# paste them anywhere and as often as it likes. For `reads`, the `live:` form of each token too. Silent: the awk
# readers read what a plan carries (A-T8-1).
alias_awk_norm() {
  local k="${1:-}" var="${2:-}" mk mo mn mos mns
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] || continue
    printf ' if (%s == "%s") %s = "%s";' "$var" "$mo" "$var" "$mn"
    [ "$k" != reads ] || printf ' if (%s == "live:%s") %s = "live:%s";' "$var" "$mo" "$var" "$mn"
  done <<ALIAS_MAP_EOF
$ALIAS_MAP
ALIAS_MAP_EOF
  printf ' '
}
