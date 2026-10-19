#!/bin/bash
# payload/scripts/lib/alias.sh — THE REGRESSION'S OLD SPELLINGS: WHAT IS STILL READ, AND WHAT IS REFUSED
# (epic-23 wave-38 T8, REQ-9, D6; wave-39 T18, REQ-13 AC-13.1, D2).
#
# WHAT IT OWNS. Until 1.21.0 the full regression's verbs, keys and record tokens spelled "floor". They spell
# "regression" now. Wave-38 kept each old spelling working for one release; 1.22.0 keeps only the half a plan carries.
# A rename never invalidates a record already written (D2): writers drop the old word, readers keep it, and a spelling
# that is no longer read is REFUSED, naming the new one, never accepted silently.
#
# TWO TABLES, ONE FOR EACH HALF. A spelling is either a token a 1.20.0 TOOL wrote into a plan, or one a PERSON types or
# a config file carries (A-T8-1). Telling them apart is the whole design:
#
#   ALIAS_MAP   the plan-read rows, still read, silently: a plan is a record, so the plan still judges and nobody is
#               told to edit it. They are read inside an awk program through `alias_awk_norm`/`alias_alt`, or by
#               `alias_read`/`alias_token`, and never print a word.
#                 kind      floor     -> regression       a proof line's kind=, lib/proof.sh proof_fields (alias_awk_norm)
#                 reads     proof:floor -> proof:regression  a reads cell the plan carries, lib/units.sh (alias_awk_norm)
#                 born      floor     -> regression       a born marker, lib/units.sh and lib/proof.sh (alias_alt)
#                 born-of   floor     -> regression       the marker's backing, written only
#   ALIAS_GONE  the typed and config rows, refused: each is asked of a function below at the one seam its token has, and
#               answers with a sentence naming the new spelling, `<old as written> is gone; write <new as written>`.
#                 verb          floor-run      -> regression-run      hooks/session-poker.sh, after `VERB="$1"`
#                 proof-kind    floor          -> regression          hooks/session-poker.sh, after `PF_KIND="$1"`
#                 born-operand  floor:         -> regression:         hooks/session-poker.sh task-add --born
#                 reads         proof:floor    -> proof:regression    a reads cell TYPED to task-add or task-set reads=
#                 config        floor          -> regression-command  .bionic/config.yaml, read by regression-run
#                 log           floor-run-     -> regression-run-     the whole-run log's name, the second-run glob
#                 rigor-key     rigor-floor    -> rigor-minimum       hooks/canonical-sdlc-governing-skill.sh, twice
#
# `reads` is in both tables: the same token is silent in a plan and refused in a person's typing.
# Every seam asks the one table (tests/regression-rename.test.sh §AGREE), and no line of production code outside this
# file spells an old token.
#
# Sourced, never executed. bash 3.2: no associative arrays.

# <kind>|<old>|<new>|<old as written>|<new as written>
ALIAS_MAP='kind|floor|regression|kind=floor|kind=regression
reads|proof:floor|proof:regression|proof:floor|proof:regression
born|floor|regression|born: floor|born: regression
born-of|floor|regression|of=floor|of=regression'

ALIAS_GONE='verb|floor-run|regression-run|floor-run|regression-run
proof-kind|floor|regression|proof-add floor|proof-add regression
born-operand|floor:|regression:|--born floor:|--born regression:
reads|proof:floor|proof:regression|proof:floor|proof:regression
config|floor|regression-command|floor:|regression-command:
log|floor-run-|regression-run-|floor-run-<sha>.log|regression-run-<sha>.log
rigor-key|rigor-floor|rigor-minimum|rigor-floor:|rigor-minimum:'

# --------------------------------------------------------------------- the plan-read rows: silent

# alias_read <kind> <value> -> ALIAS_TOKEN, the value's canonical spelling: the new one for an old spelling of <kind> in
# ALIAS_MAP, the value itself otherwise. Silent.
alias_read() {
  local k="${1:-}" v="${2:-}" mk mo mn mos mns
  ALIAS_TOKEN="$v"
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] && [ "$mo" = "$v" ] || continue
    ALIAS_TOKEN="$mn"
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

# alias_spellings <kind> -> the new spelling, then each old one, one per line, of a plan-read row: what a reader's
# pattern walks. Nothing for a kind that has no plan-read row.
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

# --------------------------------------------------------------------- the typed and config rows: refused

ALIAS_GONE_SAID=""

# _alias_gone_row <kind> <old> -> exit 0 and ALIAS_GONE_SAID set to the row's sentence when <old> is a gone spelling of
# <kind>; exit 1 and ALIAS_GONE_SAID empty otherwise. The one place a sentence is made.
_alias_gone_row() {
  local k="${1:-}" v="${2:-}" mk mo mn mos mns
  ALIAS_GONE_SAID=""
  [ -n "$v" ] || return 1
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] && [ "$mo" = "$v" ] || continue
    ALIAS_GONE_SAID="$mos is gone; write $mns"
    return 0
  done <<ALIAS_GONE_EOF
$ALIAS_GONE
ALIAS_GONE_EOF
  return 1
}

# alias_gone <kind> <value> -> exit 0 and ALIAS_GONE_SAID, the refusal's sentence naming the new spelling, when <value>
# is the old spelling of <kind> (a verb, a proof kind, a born operand); exit 1, nothing set, otherwise.
alias_gone() {
  _alias_gone_row "${1:-}" "${2:-}"
}

# alias_gone_say <kind> -> exit 0 and ALIAS_GONE_SAID, the sentence of <kind>'s first row, for a caller that found the
# old spelling by its own means (a log's name found by a glob).
alias_gone_say() {
  local k="${1:-}" mk mo mn mos mns
  ALIAS_GONE_SAID=""
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] || continue
    ALIAS_GONE_SAID="$mos is gone; write $mns"
    return 0
  done <<ALIAS_GONE_EOF
$ALIAS_GONE
ALIAS_GONE_EOF
  return 1
}

# alias_gone_names <kind> -> the old spellings of <kind>, one per line: what a glob walks to find what is refused.
alias_gone_names() {
  local k="${1:-}" mk mo mn mos mns
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] && printf '%s\n' "$mo"
  done <<ALIAS_GONE_EOF
$ALIAS_GONE
ALIAS_GONE_EOF
  return 0
}

# alias_gone_cell <kind> <cell> -> as alias_gone, for a comma-separated cell a person typed: each token trimmed, a
# `live:` prefix dropped. Exit 0 and the sentence at the first token that is gone.
alias_gone_cell() {
  local k="${1:-}" rest="${2:-}" t
  ALIAS_GONE_SAID=""
  while :; do
    t="${rest%%,*}"
    t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    t="${t#live:}"
    _alias_gone_row "$k" "$t" && return 0
    case "$rest" in *,*) rest="${rest#*,}" ;; *) break ;; esac
  done
  return 1
}

# alias_gone_text <kind> <text> -> exit 0 and the sentence when a line of <text> (a config file's, a frontmatter's)
# opens with the old key of <kind>, `<key>:`; exit 1, nothing set, otherwise. The key is matched whole, so a longer key
# that begins with the same word is another key. The value is never read.
alias_gone_text() {
  local k="${1:-}" text="${2:-}" mk mo mn mos mns
  ALIAS_GONE_SAID=""
  while IFS='|' read -r mk mo mn mos mns; do
    [ "$mk" = "$k" ] || continue
    if printf '%s\n' "$text" | awk -v k="$mo" '
        { sub(/\r$/, ""); t = $0; sub(/^[ \t]+/, "", t) }
        index(t, k) == 1 { r = substr(t, length(k) + 1); sub(/^[ \t]+/, "", r); if (substr(r, 1, 1) == ":") { found = 1; exit } }
        END { exit found ? 0 : 1 }'; then
      ALIAS_GONE_SAID="$mos is gone; write $mns"
      return 0
    fi
  done <<ALIAS_GONE_EOF
$ALIAS_GONE
ALIAS_GONE_EOF
  return 1
}
