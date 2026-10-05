#!/bin/bash
# payload/scripts/lib/grant.sh — THE GRANT: who may write and delete what, and the verdict.
#
# WHAT IT OWNS (epic-23 wave-25-never-paused, REQ-2, REQ-3, REQ-4, REQ-7; spec D2, D4, D6;
# ADR-042). A run's authority is a chain of grants: the human grants the run, the run grants
# each agent a workspace, and no grant is wider than its parent. This file holds the last
# link of that chain and the one rule every permission answer is read from:
#
#   grant_roots <class> [<key>=<value>]...
#       Composes a class's roots from facts the caller hands it (D4). Sets three globals,
#       GRANT_WRITE_ROOTS and GRANT_DELETE_ROOTS, newline-separated, and GRANT_MAIN_ROOT;
#       prints nothing. rc 0; rc 2 on an unknown class, an unknown or repeated key, a value
#       carrying a newline or a tab, or a `main=` that cannot be a root (all three globals
#       are left empty). Keys, each optional:
#         scratch=<dir>    the session scratch          every class: write and delete
#         checkout=<dir>   the wave checkout            lead: write and delete
#         tree=<dir>       a tree this session recorded lead: write and delete (repeatable)
#         own=<dir>        the asker's recorded tree    writer: write and delete
#         record=<dir>     the run's record directory   lead: write and delete; writer: write
#         plan=<file>      a plan file of the run       lead: write and delete (repeatable)
#         report=<file>    the asker's declared report  reader: write, only when it lies
#                                                       strictly inside record= or scratch=
#         main=<dir>       the project's main checkout  every class: no root; the carve-outs
#       A reader's report is bounded by its parent's grant (ADR-042 decision 1): the two places
#       the lead holds and hands down are the record directory and the scratch, so a report
#       anywhere else, or one that IS one of them, contributes no root (wave-25 T17). The
#       caller hands the reader the record directory when its session is bound to a run.
#       A fact a class does not take is ignored, so the caller may hand every fact it holds.
#       A missing fact contributes no root. A value that is not an absolute path, that holds
#       a `..` component, or that is `/` contributes no root either: a grant only narrows.
#       `main=` is the exception: it only ever narrows, so an unusable one is rc 2 rather than
#       dropped, and an empty one is no main root. Order is scratch first, so the first delete
#       root is a place to put a script.
#
#   grant_decide <class> <write-roots> <delete-roots> <effects> [<category>] [<main-root>]
#       THE DECISION (D2). Prints exactly one line: `allow`, `deny-fix<TAB><reason><TAB><fix>`
#       or `deny-reserved<TAB><category><TAB><reason>`; rc 0. rc 2, and nothing on stdout,
#       on malformed input: an unknown class, an unknown category, a main root that cannot be
#       a root, or an effect line that is not `W<TAB><path>`, `D<TAB><path>`, `R<TAB><path>`,
#       `RR<TAB><path>` or `?<TAB><reason><TAB><segment>`. An R or RR line is a read (the
#       reader's `reads` mode, wave-25 T16): it is accepted and confines nothing, because a
#       read is not confined by a write root; what a read may reach is the reserved table's
#       question (grant_reserved_effects). The optional fifth argument is what grant_reserved
#       printed for the same action; empty means none. The optional sixth is GRANT_MAIN_ROOT;
#       empty means none, and the decision is then exactly what it was without it. The
#       message an asker reads is the reason, a space, and the fix.
#
#   grant_reserved <tool> <command or path>
#       THE RESERVED TABLE (D6). Prints the category — leaves-the-machine, credentials,
#       production-infrastructure or billing — or nothing. For Bash the second argument is
#       the command; for any other tool it is the path the tool names. Two questions, two
#       rules (wave-25 T13). WHICH PROGRAM a word runs is the shared reader's answer,
#       git-argv.sh's `cmd_word_fold`, and the table keeps no rule of its own: `GH` runs
#       gh, and `EXEC gh …` runs nothing. A path, subcommand or option the table matches
#       in order to REFUSE is matched without regard to case (`~/.SSH`, `gh PR`): a guard
#       that says no matches every spelling that could reach the protected place, and its
#       only allowed error is refusing something harmless (A-orch-29).
#
#   grant_reserved_effects <home> <effect lines>
#       THE RESERVED TABLE, READ BY PLACE (wave-25 T17). Prints `credentials` or nothing; rc
#       0. The caller hands every spelling it holds of every path an action touches: the
#       reader's own lines as typed, and the same lines resolved. A W, D, R or RR path in the
#       shape of a credential store is credentials, so a link into ~/.ssh is refused by where
#       it lands. An RR (a read that descends) of a path that holds a store under <home>, or of
#       `/`, is credentials too: a recursive read of the home directory reaches every store.
#       With no home every RR is credentials, since none can be shown to reach no store. The
#       home directory is a fact the caller hands over, never this lib's own HOME.
#
#   grant_resolve <path>
#   grant_resolve_lines <effect lines>
#       THE ONLY FUNCTIONS HERE THAT TOUCH THE FILESYSTEM. grant_resolve prints the real
#       location of an absolute path, every symlink and `..` resolved, whether or not its last
#       components exist yet; rc 0. A path it cannot resolve (relative, a `..` after a missing
#       directory, a symlink loop) prints `?<TAB><path>`, rc 1 — a mark the decision reads
#       as outside every root even when it is passed on as a path. grant_resolve_lines gives
#       the same answer for every W, D, R and RR line of a list in ONE process, a device sink
#       and every other line passed through as they are; rc 0. One process, not one fork per
#       path: a 2000-operand rm resolved a path per fork and ran past the hook's registration
#       (wave-25 review S3).
#
# THE RULE. Allow if and only if every effect is a resolved path inside the grant, no
# effect is one of bionic's own state files, and no reserved category matched. An empty
# effect list is a pure reader and allows. Checked in this order, and the first failure by
# that order is the one the denial names:
#   1. a reserved category              deny-reserved (it wins over every allow)
#   2. a state file, for every class    deny-fix, before any root is consulted
#      (then a W to a device sink is skipped: it is no effect, for every class)
#   3. an effect the reader marked `?`  deny-fix
#   4. a path that is not resolved      deny-fix (relative, a `..` component, the `?` mark)
#   5. a path the main root keeps from every run's checkout          deny-fix
#   6. a W outside the write roots, or a D not strictly beneath a delete root   deny-fix
# Containment is by path component: root `/x/25-T1` contains `/x/25-T1` and `/x/25-T1/a`,
# never `/x/25-T10/f`. A delete must be STRICTLY beneath a delete root: a root itself (the
# asker's tree, the wave checkout, the scratch) is deleted by no one, and its denial sends
# the asker to the one above its class (wave-25 T17, review N5). bionic's state files are a
# basename `<class>-*` for every class of GRANT_STATE_CLASSES anywhere under a `.bionic/tmp`
# directory, matched without regard to case (a case-blind filesystem writes `Roster-x` into
# `roster-x`); a delete of `.bionic` or `.bionic/tmp` itself takes them all and is one too.
#
# DEVICE SINKS. A W whose path is exactly /dev/null, /dev/stdout, /dev/stderr, /dev/tty or
# /dev/fd/<digits> changes no file (the reader prints one for every `2>/dev/null`), so it is
# no effect for any class. A D of a sink, and any other path under /dev, is judged as usual,
# which puts it outside every root.
#
# THE MAIN ROOT'S CARVE-OUTS (rule 5; AC-2.2, AC-2.7). When a run works in the main checkout,
# its checkout root physically holds three directories no run created: `.bionic` (every run's
# docs, records and state), `.worktrees` (every run's trees) and `.git`. Given the main root:
#   a. a path under <main>/.bionic is granted only by a root itself under <main>/.bionic (the
#      record directory, a plan file, a declared report), never by a checkout, tree or own root;
#   b. a path under <main>/.worktrees is granted only by a root itself under <main>/.worktrees
#      (a recorded tree, the asker's own tree, a linked wave checkout);
#   c. a path under <main>/.git is granted by no root;
#   d. a delete of <main> itself, or of a directory above it, is denied for every class.
# The three names are matched without regard to case, as the state files are. Under a or b, a
# path that no root would have contained anyway is plain rule 6, so its denial reads as before.
#
# A RESERVED ACTION THE TABLE MISSES IS STILL DENIED. The table only changes the wording and
# routes the request to the human. An action it does not recognise is unknown to the reader
# (no publish tool is on its pure-reader list), so its effects carry a `?` line and rule 3
# denies it with a fix. Nothing reaches allow by being missing from this table. A READ is no
# effect, so for a read the table is the only guard: it is asked about every spelling the
# caller holds of every path read, written or deleted (grant_reserved_effects), so a store is
# refused by the place a path reaches, not only by the words it was typed in.
#
# THE FREEZE (.claude/rules/hook-authoring.md). grant_roots, grant_decide, grant_reserved and
# grant_reserved_effects are pure: every fact arrives as an argument, and none of them reads
# a file, the environment or git. A credential path is recognised by its shape (`~/.ssh`,
# `$HOME/.ssh`, `/Users/x/.ssh` alike), never by expanding the reader's HOME. The hook
# collects the facts, resolves every root and effect path through the resolver, and hands
# them over.
#
# Sourced, never executed: function definitions only, plus the one sibling it reads commands
# through (git-argv.sh, for push and for every segment's argv). bash 3.2: no associative
# arrays, no mapfile, no `${v^^}`.
# [WALL: tests/grant.test.sh]

if [ -n "${GRANT_LIB_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi

case "${BASH_SOURCE[0]}" in
  */*) _GRANT_LIB_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) _GRANT_LIB_DIR="." ;;
esac
if ! declare -F git_argv_expand >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_GRANT_LIB_DIR/git-argv.sh" || return 1
fi
GRANT_LIB_LOADED=1

GRANT_TAB=$'\t'
GRANT_NL=$'\n'
GRANT_WRITE_ROOTS=""
GRANT_DELETE_ROOTS=""
GRANT_MAIN_ROOT=""

# ── roots ────────────────────────────────────────────────────────────────────────────────

# _grant_clean_root <path> — prints the root with trailing slashes removed; rc 1, nothing
# printed, when the path cannot be a root.
_grant_clean_root() {
  local p="${1-}"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in
    /) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  case "$p" in
    */../*|*/..) return 1 ;;
  esac
  printf '%s' "$p"
}

# _grant_add <w|wd> <path> — appends one root to the write list, and to the delete list
# for `wd`. An empty or unusable path adds nothing.
_grant_add() {
  local r
  r="$(_grant_clean_root "${2-}")" || return 0
  GRANT_WRITE_ROOTS="${GRANT_WRITE_ROOTS:+$GRANT_WRITE_ROOTS$GRANT_NL}$r"
  if [ "$1" = wd ]; then
    GRANT_DELETE_ROOTS="${GRANT_DELETE_ROOTS:+$GRANT_DELETE_ROOTS$GRANT_NL}$r"
  fi
}

grant_roots() {
  local cls="${1-}" kv key val p r bound=""
  local scratch="" checkout="" own="" record="" report="" trees="" plans="" main="" seen=" "
  GRANT_WRITE_ROOTS=""
  GRANT_DELETE_ROOTS=""
  GRANT_MAIN_ROOT=""
  case "$cls" in
    lead|writer|reader|unbound) ;;
    *) printf 'grant_roots: unknown class: %s\n' "$cls" >&2; return 2 ;;
  esac
  shift
  for kv in "$@"; do
    case "$kv" in
      *=*) ;;
      *) printf 'grant_roots: not key=value: %s\n' "$kv" >&2; return 2 ;;
    esac
    key="${kv%%=*}"
    val="${kv#*=}"
    case "$val" in
      *"$GRANT_NL"*|*"$GRANT_TAB"*)
        printf 'grant_roots: %s carries a newline or a tab\n' "$key" >&2; return 2 ;;
    esac
    case "$key" in
      scratch|checkout|own|record|report|main)
        case "$seen" in
          *" $key "*) printf 'grant_roots: %s given twice\n' "$key" >&2; return 2 ;;
        esac
        seen="$seen$key "
        ;;
    esac
    case "$key" in
      scratch) scratch="$val" ;;
      checkout) checkout="$val" ;;
      own) own="$val" ;;
      record) record="$val" ;;
      report) report="$val" ;;
      main) main="$val" ;;
      tree) trees="$trees$GRANT_NL$val" ;;
      plan) plans="$plans$GRANT_NL$val" ;;
      *) printf 'grant_roots: unknown fact: %s\n' "$key" >&2; return 2 ;;
    esac
  done
  if [ -n "$main" ]; then
    main="$(_grant_clean_root "$main")" || {
      printf 'grant_roots: main is not an absolute directory other than /\n' >&2; return 2; }
  fi
  GRANT_MAIN_ROOT="$main"
  _grant_add wd "$scratch"
  case "$cls" in
    lead)
      _grant_add wd "$checkout"
      while IFS= read -r p; do _grant_add wd "$p"; done <<< "$trees"
      _grant_add wd "$record"
      while IFS= read -r p; do _grant_add wd "$p"; done <<< "$plans"
      ;;
    writer)
      _grant_add wd "$own"
      _grant_add w "$record"
      ;;
    reader)
      # Only strictly inside what the lead holds: never wider than the parent's grant.
      r="$(_grant_clean_root "$record")" && bound="$r"
      r="$(_grant_clean_root "$scratch")" && bound="${bound:+$bound$GRANT_NL}$r"
      if r="$(_grant_clean_root "$report")" && _grant_beneath "$r" "$bound"; then
        _grant_add w "$r"
      fi
      ;;
  esac
  return 0
}

# ── the decision ─────────────────────────────────────────────────────────────────────────

# _grant_inside <path> <roots> — rc 0 when a root contains the path, by path component.
_grant_inside() {
  local p="$1" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$p" in
      "$r"|"$r"/*) return 0 ;;
    esac
  done <<< "$2"
  return 1
}

# _grant_trim <path> — sets _GRANT_P to the path with every trailing `/` and `/.` taken off,
# so `<root>/` and `<root>/.` read as the root they name. A global, not a print: the decision
# calls it once per delete, and a subshell per effect is what S3 measured.
_GRANT_P=""
_grant_trim() {
  _GRANT_P="${1-}"
  while :; do
    case "$_GRANT_P" in
      ?*/) _GRANT_P="${_GRANT_P%/}" ;;
      ?*/.) _GRANT_P="${_GRANT_P%/.}" ;;
      *) return 0 ;;
    esac
  done
}

# _grant_beneath <path> <roots> — rc 0 when a root contains the path STRICTLY, by path
# component: a root is never beneath itself. The path is taken as _grant_trim leaves it.
_grant_beneath() {
  local r
  _grant_trim "$1"
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$_GRANT_P" in
      "$r"/?*) return 0 ;;
    esac
  done <<< "$2"
  return 1
}

# _grant_unresolved <path> — rc 0 when the path is not a resolved absolute path: relative
# (the resolver's `?` mark included), or carrying a `..` component.
_grant_unresolved() {
  case "$1" in
    /*) ;;
    *) return 0 ;;
  esac
  case "$1" in
    */../*|*/..) return 0 ;;
  esac
  return 1
}

# THE SESSION-STATE CLASSES: every `<class>-<session id>.state` bionic keeps under
# `.bionic/tmp`. Owned by payload/scripts/lib/patrol.sh's PATROL_STATE_CLASSES, which this
# lib may not source (the freeze: the decision reads nothing), so it holds the same words and
# tests/grant.test.sh §G19 fails the moment the two lists differ.
GRANT_STATE_CLASSES="roster preflight engaged sweeper patrol stop-orders tick-digest workspaces gate start-clock"

# _grant_is_state <W|D> <path> — rc 0 when the path is one of bionic's own state files.
# Case-blind: the directory by bracket patterns, the class under nocasematch, which is put
# back as the caller had it on the one way out.
_grant_is_state() {
  local p="$2" c nc=0 hit=1
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in
    */.[Bb][Ii][Oo][Nn][Ii][Cc]|*/.[Bb][Ii][Oo][Nn][Ii][Cc]/[Tt][Mm][Pp])
      [ "$1" = D ] && return 0
      return 1
      ;;
    */.[Bb][Ii][Oo][Nn][Ii][Cc]/[Tt][Mm][Pp]/*) ;;
    *) return 1 ;;
  esac
  p="${p##*/}"
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  for c in $GRANT_STATE_CLASSES; do
    case "$p" in
      "$c"-*) hit=0; break ;;
    esac
  done
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  return "$hit"
}

# _grant_is_sink <path> — rc 0 when the path is exactly one of the device sinks.
_grant_is_sink() {
  case "$1" in
    /dev/null|/dev/stdout|/dev/stderr|/dev/tty) return 0 ;;
    /dev/fd/*)
      case "${1#/dev/fd/}" in
        ""|*[!0-9]*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

# _grant_shared <path> <main> <bionic|worktrees|git> — rc 0 when the path is <main>/.<name>
# or under it, the name matched without regard to case.
_grant_shared() {
  local p="$1" seg
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in
    "$2"/*) ;;
    *) return 1 ;;
  esac
  seg="${p#"$2"/}"
  seg="${seg%%/*}"
  case "$3:$seg" in
    bionic:.[Bb][Ii][Oo][Nn][Ii][Cc]) return 0 ;;
    worktrees:.[Ww][Oo][Rr][Kk][Tt][Rr][Ee][Ee][Ss]) return 0 ;;
    git:.[Gg][Ii][Tt]) return 0 ;;
  esac
  return 1
}

# _grant_holds_main <path> <main> — rc 0 when the path is the main root or a directory above it.
_grant_holds_main() {
  local p="$1"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  [ "$p" = / ] && return 0
  case "$2" in
    "$p"|"$p"/*) return 0 ;;
  esac
  return 1
}

# _grant_list <roots> — the roots as prose: `a`, `a and b`, `a, b and c`.
_grant_list() {
  local r out="" last="" n=0
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ -n "$last" ]; then out="${out:+$out, }$last"; fi
    last="$r"
    n=$((n + 1))
  done <<< "$1"
  if [ "$n" -le 1 ]; then printf '%s' "$last"; else printf '%s and %s' "$out" "$last"; fi
}

# _grant_who <class> — the asker as a sentence names it.
_grant_who() {
  case "$1" in
    lead) printf 'the lead' ;;
    unbound) printf 'this session' ;;
    reader) printf 'this read-only agent' ;;
    *) printf 'this %s' "$1" ;;
  esac
}

# _grant_roots_text <class> <write-roots> <delete-roots> — one sentence naming the grant.
_grant_roots_text() {
  local who
  who="$(_grant_who "$1")"
  case "$who" in
    the*) who="The${who#the}" ;;
    this*) who="This${who#this}" ;;
  esac
  if [ -z "$2" ]; then
    printf '%s has no workspace recorded.' "$who"
  elif [ "$2" = "$3" ]; then
    printf '%s may write and delete under %s.' "$who" "$(_grant_list "$2")"
  elif [ -z "$3" ]; then
    printf '%s may write only to %s.' "$who" "$(_grant_list "$2")"
  else
    printf '%s may write under %s, and delete under %s.' "$who" "$(_grant_list "$2")" "$(_grant_list "$3")"
  fi
}

# _grant_category_words <category> — the category as the reason reads it.
_grant_category_words() {
  case "$1" in
    leaves-the-machine) printf 'leaves the machine' ;;
    credentials) printf 'touches credentials' ;;
    production-infrastructure) printf 'acts on production infrastructure' ;;
    billing) printf 'touches billing' ;;
  esac
}

grant_decide() {
  local cls="${1-}" wr_in="${2-}" dr_in="${3-}" effects="${4-}" cat="${5-}" main="${6-}"
  local line rest reason r wr="" dr="" kind path seg how ewr edr
  local wr_b="" dr_b="" wr_t="" dr_t=""
  local worst=9 rank n_fail=0 f_kind="" f_path="" f_seg="" f_how=""
  case "$cls" in
    lead|writer|reader|unbound) ;;
    *) printf 'grant_decide: unknown class: %s\n' "$cls" >&2; return 2 ;;
  esac
  case "$cat" in
    ""|leaves-the-machine|credentials|production-infrastructure|billing) ;;
    *) printf 'grant_decide: unknown category: %s\n' "$cat" >&2; return 2 ;;
  esac
  if [ -n "$main" ]; then
    main="$(_grant_clean_root "$main")" || {
      printf 'grant_decide: main root is not an absolute directory other than /\n' >&2; return 2; }
  fi

  # Every line is checked for shape before any is judged: malformed anywhere is rc 2.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "W$GRANT_TAB"?*|"D$GRANT_TAB"?*|"R$GRANT_TAB"?*|"RR$GRANT_TAB"?*) continue ;;
      "?$GRANT_TAB"*)
        rest="${line#\?"$GRANT_TAB"}"
        reason="${rest%%"$GRANT_TAB"*}"
        if [ -n "$reason" ] && [ "$reason" != "$rest" ]; then continue; fi
        ;;
    esac
    printf 'grant_decide: malformed effect line: %s\n' "$line" >&2
    return 2
  done <<< "$effects"

  # 1. Reserved wins over everything, and its reason carries no route but the lead.
  if [ -n "$cat" ]; then
    printf 'deny-reserved\t%s\tThis action %s, a category reserved for the human: it is the human'"'"'s to act on, not this agent'"'"'s. Do not retry it or work around it; report it to the lead, who will raise it with the human.\n' \
      "$cat" "$(_grant_category_words "$cat")"
    return 0
  fi

  # Only usable roots count; a root the composer would have refused grants nothing here too.
  while IFS= read -r line; do
    r="$(_grant_clean_root "$line")" && wr="${wr:+$wr$GRANT_NL}$r"
  done <<< "$wr_in"
  while IFS= read -r line; do
    r="$(_grant_clean_root "$line")" && dr="${dr:+$dr$GRANT_NL}$r"
  done <<< "$dr_in"

  # 5a, 5b. Inside a shared directory, only the roots that are themselves inside it count.
  if [ -n "$main" ]; then
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      if _grant_shared "$r" "$main" bionic; then wr_b="${wr_b:+$wr_b$GRANT_NL}$r"
      elif _grant_shared "$r" "$main" worktrees; then wr_t="${wr_t:+$wr_t$GRANT_NL}$r"
      fi
    done <<< "$wr"
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      if _grant_shared "$r" "$main" bionic; then dr_b="${dr_b:+$dr_b$GRANT_NL}$r"
      elif _grant_shared "$r" "$main" worktrees; then dr_t="${dr_t:+$dr_t$GRANT_NL}$r"
      fi
    done <<< "$dr"
  fi

  # 2–6. Rank every effect; the denial names the first of the lowest rank.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="${line%%"$GRANT_TAB"*}"
    # A read confines nothing: it is the reserved table's, never a root's.
    case "$kind" in R|RR) continue ;; esac
    rest="${line#*"$GRANT_TAB"}"
    rank=0
    how=""
    if [ "$kind" = "?" ]; then
      path="${rest%%"$GRANT_TAB"*}"
      seg="${rest#*"$GRANT_TAB"}"
      rank=3
    else
      path="$rest"
      seg=""
      ewr="$wr"
      edr="$dr"
      if [ -n "$main" ]; then
        if _grant_shared "$path" "$main" bionic; then ewr="$wr_b"; edr="$dr_b"; how=bionic
        elif _grant_shared "$path" "$main" worktrees; then ewr="$wr_t"; edr="$dr_t"; how=worktrees
        elif _grant_shared "$path" "$main" git; then how=git
        elif [ "$kind" = D ] && _grant_holds_main "$path" "$main"; then how=holds
        fi
      fi
      if _grant_is_state "$kind" "$path"; then
        rank=2
      elif [ "$kind" = W ] && _grant_is_sink "$path"; then
        rank=0
      elif _grant_unresolved "$path"; then
        rank=4
      elif [ "$how" = git ] || [ "$how" = holds ]; then
        rank=5
      elif [ "$kind" = W ]; then
        if ! _grant_inside "$path" "$ewr"; then
          rank=6
          _grant_inside "$path" "$wr" && rank=5
        fi
      elif ! _grant_beneath "$path" "$edr"; then
        # Not strictly beneath a delete root: the root itself, a write-only place, a
        # carved-out one, or plain outside, in that order.
        rank=6
        if _grant_inside "$_GRANT_P" "$edr"; then how=root
        elif _grant_inside "$_GRANT_P" "$ewr"; then how=add-only
        elif _grant_beneath "$path" "$dr"; then rank=5
        fi
      fi
    fi
    [ "$rank" -gt 0 ] || continue
    n_fail=$((n_fail + 1))
    if [ "$rank" -lt "$worst" ]; then
      worst=$rank; f_kind="$kind"; f_path="$path"; f_seg="$seg"; f_how="$how"
    fi
  done <<< "$effects"

  if [ "$n_fail" -eq 0 ]; then
    printf 'allow\n'
    return 0
  fi

  # The reason: what could not be shown inside, then the grant.
  case "$worst" in
    2) reason="$f_path is one of bionic's own state files, which are in no workspace." ;;
    3)
      [ "${#f_seg}" -le 200 ] || f_seg="${f_seg:0:200}..."
      reason="Could not tell what this command writes or deletes ($f_path) in: $f_seg."
      ;;
    4) reason="Could not resolve $f_path to a real location, so it cannot be shown to be inside the workspace." ;;
    5)
      case "$f_how" in
        holds)
          if _grant_holds_main "$main" "$f_path"; then
            reason="$f_path is the project's main checkout, and the project's shared directories are not part of a run's checkout, so no one may delete it."
          else
            reason="$f_path holds the whole project at $main, and the project's shared directories are not part of a run's checkout, so no one may delete it."
          fi
          ;;
        git) reason="$f_path is in $main/.git, and the project's shared directories are not part of a run's checkout: nothing in .git is in any workspace." ;;
        *) reason="$f_path is in $main/.$f_how, and the project's shared directories are not part of a run's checkout: only what this run recorded inside them is in a workspace." ;;
      esac
      ;;
    6)
      if [ "$f_kind" = W ]; then
        reason="$f_path is outside the workspace of $(_grant_who "$cls")."
      elif [ "$f_how" = root ]; then
        reason="$f_path is a root of the workspace of $(_grant_who "$cls"): what is inside it may be deleted, the root itself may not."
      elif [ "$f_how" = add-only ]; then
        reason="$f_path is in a place $(_grant_who "$cls") may add to but not delete from."
      else
        reason="$f_path is outside where $(_grant_who "$cls") may delete."
      fi
      ;;
  esac
  if [ "$n_fail" -gt 1 ]; then
    reason="$reason $((n_fail - 1)) more of its effects could not be shown inside either."
  fi
  reason="$reason $(_grant_roots_text "$cls" "$wr" "$dr")"

  # The fix: one step, toward the first place the asker may both write and delete. A fix
  # never tells an asker to ask itself: a writer or a read-only agent is sent to the lead,
  # and the lead and an unbound session, which have no lead above them, to the human.
  local dir="${dr%%"$GRANT_NL"*}" fix up="the lead"
  case "$cls" in lead|unbound) up="the human" ;; esac
  if [ -z "$dir" ]; then
    fix="Report to $up that this asker has no workspace to work in, and wait for one."
  else
    case "$worst" in
      2) fix="Leave the file untouched, and ask $up if the task needs that state changed." ;;
      3) fix="Put the commands in a script file under $dir and run it from there with bash." ;;
      4) fix="Name the target by its full real path under $dir." ;;
      5)
        if [ "$f_kind" = W ]; then
          fix="Write it under $dir instead."
        elif [ "$up" = "the human" ]; then
          fix="Leave it in place, and report it to the human if it must go."
        else
          fix="Leave it in place and ask the lead to remove it if it must go."
        fi
        ;;
      6)
        if [ "$f_kind" = W ]; then
          fix="Write it under $dir instead."
        elif [ "$f_how" = add-only ]; then
          fix="Leave it in place and write a new file beside it instead."
        elif [ "$up" = "the human" ]; then
          fix="Leave it in place, and report it to the human if it must go."
        else
          fix="Leave it in place and ask the lead to remove it if it must go."
        fi
        ;;
    esac
  fi
  printf 'deny-fix\t%s\t%s\n' "$reason" "$fix"
  return 0
}

# ── the reserved table ───────────────────────────────────────────────────────────────────

# THE CREDENTIAL STORES, the one list every credential match is built from. One word per
# store, as it sits under a home directory: a word ending in `/` is a directory, and it and
# everything beneath it is the store; any other word is a file (`*` stands for any run of a
# file name's characters). A store earns a line when a tool in common use keeps a secret
# there BY DEFAULT, so reading the file hands the secret over to anyone; a secret kept under
# a name of the project's own choosing is not recognisable by shape and is not listed. A path
# matches a store wherever the store's words sit in it (`/x/.ssh/k`, `~/.ssh`, `.ssh`), and a
# recursive read of a directory that holds a home's store reaches it (grant_reserved_effects).
GRANT_CREDENTIAL_STORES=".ssh/ .aws/ .config/gh/ .gnupg/ .config/gcloud/ .azure/ .kube/config .docker/config.json .cargo/credentials.toml .netrc .npmrc .pypirc .git-credentials .env .env.*"

# _grant_build_stores — built once, at load, from the list above: _GRANT_CRED_RE, the regular
# expression a path matches when it names a store, and _GRANT_CRED_SCREEN, the first word of
# every store for the reserved table's screen (a looser match is all a screen needs).
_GRANT_CRED_RE=""
_GRANT_CRED_SCREEN=""
_grant_build_stores() {
  local s e hadf=0
  _GRANT_CRED_RE=""
  _GRANT_CRED_SCREEN=""
  case "$-" in *f*) hadf=1 ;; esac
  set -f
  for s in $GRANT_CREDENTIAL_STORES; do
    e="${s%/}"
    e="${e//./\\.}"
    e="${e//\*/[^/]*}"
    case "$s" in
      */) e="(^|/)$e(/|\$)" ;;
      *) e="(^|/)$e\$" ;;
    esac
    _GRANT_CRED_RE="${_GRANT_CRED_RE:+$_GRANT_CRED_RE|}$e"
    e="${s%%/*}"
    e="${e%%\**}"
    e="${e//./\\.}"
    case "|$_GRANT_CRED_SCREEN|" in
      *"|$e|"*) ;;
      *) _GRANT_CRED_SCREEN="${_GRANT_CRED_SCREEN:+$_GRANT_CRED_SCREEN|}$e" ;;
    esac
  done
  [ "$hadf" -eq 1 ] || set +f
}
_grant_build_stores

# _grant_is_credential <word> — rc 0 when the word names a credential store by its shape.
# An option's value (`--key=~/.ssh/id`) is read past its `=`. A refusing match: the caller
# holds nocasematch on, so `~/.SSH` is `~/.ssh` (grant_reserved, grant_reserved_effects).
_grant_is_credential() {
  local w="${1-}"
  case "$w" in
    -*=*) w="${w#*=}" ;;
  esac
  while [ "${#w}" -gt 1 ] && [ "${w%/}" != "$w" ]; do w="${w%/}"; done
  # Every store begins with a dot-named component, so a word holding none is passed over
  # before the expression is matched (measured: a seventh of the cost per path).
  case "$w" in
    .*|*/.*) ;;
    *) return 1 ;;
  esac
  [[ "$w" =~ $_GRANT_CRED_RE ]]
}

# _grant_reaches_store <path> <home> — rc 0 when a recursive read of the path reaches a store
# under the home directory: the path is `/`, or a store's place under home is the path or lies
# beneath it. With no home, or a path that is not absolute, it may reach one, so rc 0. Runs
# under the caller's nocasematch, so `/users/ALICE` reaches `/Users/alice/.ssh`.
_grant_reaches_store() {
  local p="$1" h="$2" s hadf=0 hit=1
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  while [ "${#h}" -gt 1 ] && [ "${h%/}" != "$h" ]; do h="${h%/}"; done
  [ "$p" = / ] && return 0
  [ -n "$h" ] || return 0
  case "$p" in /*) ;; *) return 0 ;; esac
  case "$-" in *f*) hadf=1 ;; esac
  set -f
  for s in $GRANT_CREDENTIAL_STORES; do
    s="$h/${s%/}"
    case "$s" in
      "$p"|"$p"/*) hit=0; break ;;
    esac
  done
  [ "$hadf" -eq 1 ] || set +f
  return "$hit"
}

# _grant_verb <word>... — prints the first word that is not an option, stepping over the
# value of the options that take one in the package tools this table reads. It runs under
# the caller's nocasematch, so `-c` here is `-C` too.
_grant_verb() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --prefix|-c|--cwd|--dir|--workspace|-w|--filter|-f|--manifest-path|-z|--config|--color|--registry)
        shift
        [ $# -gt 0 ] && shift
        ;;
      -*) shift ;;
      *) printf '%s' "$1"; return 0 ;;
    esac
  done
}

# _grant_reserved_segment <segment-line> — sets _GRANT_CAT to the category of one segment,
# or to empty. It sets a global rather than printing, so a long script costs no subshell
# per segment. Called with nocasematch off, and returns with it off.
#
# IDENTITY FIRST, THEN THE REFUSAL. Everything the shared reader answers (is this git, and
# which subcommand; which words are prefixes; which program the first word runs) is asked
# with nocasematch off, so the reader's rule is the only one: it folds `GH` and `SUDO`, and
# leaves `EXEC` and `THEN` as typed, because the shell matches those case-exactly and runs
# nothing for them. Only then is nocasematch turned on, for the matches made to refuse: the
# push, every credential path, and the subcommands and options of the program found. No
# shared-reader call is made inside that block.
_GRANT_CAT=""
_grant_reserved_segment() {
  local line="$1" oldifs="$IFS" hadf=0 w tool="" verb sub=""
  _GRANT_CAT=""
  git_argv_parse "$line" && sub="$GIT_SUB"
  _git_argv_skip "$line"
  if [ -n "$GIT_ARGV_REST" ]; then
    w="${GIT_ARGV_REST%%"$GIT_ARGV_US"*}"
    cmd_word_fold "${w##*/}"
    case "$CMD_WORD_FOLDED" in
      gh|npm|pnpm|yarn|cargo|gem|twine|security) tool="$CMD_WORD_FOLDED" ;;
      terraform|kubectl|vercel|aws|gcloud|az) tool=infra ;;
    esac
  fi
  case "$-" in *f*) hadf=1 ;; esac
  set -f
  IFS="$GIT_ARGV_US"
  # shellcheck disable=SC2086  # deliberate split on US with globbing disabled
  set -- $line
  IFS="$oldifs"
  [ "$hadf" -eq 1 ] || set +f

  shopt -s nocasematch
  case "$sub" in
    push) _GRANT_CAT=leaves-the-machine ;;
  esac
  if [ -z "$_GRANT_CAT" ]; then
    # Every credential shape holds a dot, so a word without one is passed over unread.
    for w in "$@"; do
      case "$w" in
        *.*) if _grant_is_credential "$w"; then _GRANT_CAT=credentials; break; fi ;;
      esac
    done
  fi
  if [ -z "$_GRANT_CAT" ] && [ -n "$tool" ]; then
    # The program's own words, as the reader left them; splitting asks the reader nothing.
    set -f
    IFS="$GIT_ARGV_US"
    # shellcheck disable=SC2086
    set -- $GIT_ARGV_REST
    IFS="$oldifs"
    [ "$hadf" -eq 1 ] || set +f
    shift
    case "$tool" in
      gh)
        while [ $# -gt 0 ]; do
          case "$1" in
            -r|--repo) shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        case "${1-}" in
          pr|issue|release|repo|api) _GRANT_CAT=leaves-the-machine ;;
          auth) _GRANT_CAT=credentials ;;
        esac
        ;;
      npm|pnpm|yarn)
        verb="$(_grant_verb "$@")"
        if [ "$tool" = yarn ] && [[ "$verb" == npm ]]; then
          while [ $# -gt 0 ] && [[ "$1" != npm ]]; do shift; done
          shift
          verb="$(_grant_verb "$@")"
        fi
        case "$verb" in
          publish|unpublish) _GRANT_CAT=leaves-the-machine ;;
          login|logout|adduser|token) _GRANT_CAT=credentials ;;
        esac
        ;;
      cargo)
        case "$(_grant_verb "$@")" in
          publish|yank|owner) _GRANT_CAT=leaves-the-machine ;;
          login|logout) _GRANT_CAT=credentials ;;
        esac
        ;;
      gem)
        case "$(_grant_verb "$@")" in
          push|yank|owner) _GRANT_CAT=leaves-the-machine ;;
          signin) _GRANT_CAT=credentials ;;
        esac
        ;;
      twine)
        case "$(_grant_verb "$@")" in
          upload|register) _GRANT_CAT=leaves-the-machine ;;
        esac
        ;;
      security) _GRANT_CAT=credentials ;;
      infra)
        _GRANT_CAT=production-infrastructure
        for w in "$@"; do
          case "$w" in
            billing|ce|budgets|consumption) _GRANT_CAT=billing; break ;;
          esac
        done
        ;;
    esac
  fi
  shopt -u nocasematch
  return 0
}

# THE SCREEN. Every word the table recognises is spelled in the command's own text once its
# quotes, backslashes and line continuations are taken out: the reader builds each argv
# word from those characters and no others, so a command whose text holds none of these
# can match no row, and is answered without reading a segment. Its word edges are loose on
# purpose, and it is matched without regard to case (a word is only ever over-matched, which
# costs a full read and nothing else). The credential part is the first word of every store
# on the one list, so a store added there is screened in without a second edit here.
_GRANT_SCREEN_RE='push|'"$_GRANT_CRED_SCREEN"'|(^|[^[:alnum:]_.-])(gh|npm|pnpm|yarn|cargo|gem|twine|security|terraform|kubectl|vercel|aws|gcloud|az)([^[:alnum:]_.-]|$)'
# A runner (`sh -c`, `eval`, `env -S`) is the one segment whose string the reader re-reads;
# only a command that holds one pays for git_argv_expand's re-reading.
_GRANT_RUNNER_RE='(^|[^[:alnum:]_.-])(sh|bash|zsh|dash|ksh|ash|eval|env)([^[:alnum:]_.-]|$)'

# nocasematch is process state: grant_reserved saves the caller's, reads with it off (so the
# shared reader answers by its own rule alone), and puts the caller's back on every return,
# whatever path _grant_reserved left by.
grant_reserved() {
  local nc=0
  shopt -q nocasematch && nc=1
  shopt -u nocasematch
  _grant_reserved "$@"
  shopt -u nocasematch
  [ "$nc" -eq 0 ] || shopt -s nocasematch
  return 0
}

_grant_reserved() {
  local tool="${1-}" what="${2-}" text segs line runner=0
  [ -n "$what" ] || return 0
  if [ "$tool" != Bash ]; then
    shopt -s nocasematch
    _grant_is_credential "$what" && printf 'credentials\n'
    shopt -u nocasematch
    return 0
  fi
  text="$what"
  case "$text" in
    *\\"$GRANT_NL"*) text="${text//\\$GRANT_NL/}" ;;
  esac
  text="$(printf '%s' "$text" | tr -d "'\"\\\\\r")"
  shopt -s nocasematch
  if ! [[ "$text" =~ $_GRANT_SCREEN_RE ]]; then
    shopt -u nocasematch
    return 0
  fi
  [[ "$text" =~ $_GRANT_RUNNER_RE ]] && runner=1
  shopt -u nocasematch
  # The same screen per segment keeps only the segments worth reading: their words are
  # already unquoted, so it is exact there.
  if [ "$runner" -eq 1 ]; then
    segs="$(git_argv_expand "$what" | grep -iE "$_GRANT_SCREEN_RE" || true)"
  else
    segs="$(git_argv_segments "$what" | grep -iE "$_GRANT_SCREEN_RE" || true)"
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _grant_reserved_segment "$line"
    if [ -n "$_GRANT_CAT" ]; then
      printf '%s\n' "$_GRANT_CAT"
      return 0
    fi
  done <<< "$segs"
  return 0
}

# The reserved table by place: every path line, every spelling the caller handed over. Saves
# the caller's nocasematch, matches with it on (a refusal is case-blind), and puts it back.
grant_reserved_effects() {
  local home="${1-}" line kind p nc=0 hit=0
  shopt -q nocasematch && nc=1
  shopt -s nocasematch
  while IFS= read -r line; do
    kind="${line%%"$GRANT_TAB"*}"
    case "$kind" in
      W|D|R|RR) ;;
      *) continue ;;
    esac
    p="${line#*"$GRANT_TAB"}"
    case "$p" in
      "?$GRANT_TAB"*) p="${p#\?"$GRANT_TAB"}" ;;
    esac
    if _grant_is_credential "$p"; then hit=1; break; fi
    if [ "$kind" = RR ] && _grant_reaches_store "$p" "$home"; then hit=1; break; fi
  done <<< "${2-}"
  [ "$nc" -eq 1 ] || shopt -u nocasematch
  [ "$hit" -eq 0 ] || printf 'credentials\n'
  return 0
}

# ── the one reach into the filesystem ───────────────────────────────────────────────────

# _grant_resolve_set <path> — the resolver itself. Sets _GRANT_RESOLVED to the real location,
# rc 0, or to `?<TAB><path>`, rc 1. It reads a directory's real name by `cd -P` and `$PWD`,
# with no fork, so it moves the working directory: it is only ever called inside a subshell
# (grant_resolve's and grant_resolve_lines' own bodies). The last directory it read is kept
# (_GRANT_RC_DIR, _GRANT_RC_REAL), because the operands of one command mostly share one.
_GRANT_RESOLVED=""
_GRANT_RC_DIR=""
_GRANT_RC_REAL=""
_grant_resolve_set() {
  local in="${1-}" cur tail="" hops=0 link real part out oldifs="$IFS" hadf=0
  _GRANT_RESOLVED="?$GRANT_TAB$in"
  case "$in" in
    *"$GRANT_NL"*|*"$GRANT_TAB"*) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  cur="$in"
  # Walk up to the deepest part that exists, following a symlink wherever one stands. What
  # is peeled off names nothing that exists, so it holds no symlink to follow.
  while :; do
    while [ "${#cur}" -gt 1 ] && [ "${cur%/}" != "$cur" ]; do cur="${cur%/}"; done
    if [ -d "$cur" ]; then
      if [ -n "$_GRANT_RC_DIR" ] && [ "$cur" = "$_GRANT_RC_DIR" ]; then
        real="$_GRANT_RC_REAL"
      else
        cd -P "$cur" 2>/dev/null || return 1
        real="$PWD"
        _GRANT_RC_DIR="$cur"
        _GRANT_RC_REAL="$real"
      fi
      break
    elif [ -L "$cur" ]; then
      hops=$((hops + 1))
      link="$(readlink "$cur" 2>/dev/null)" || link=""
      if [ "$hops" -gt 40 ] || [ -z "$link" ]; then return 1; fi
      case "$link" in
        /*) cur="$link" ;;
        *) cur="${cur%/*}/$link" ;;
      esac
    else
      tail="${cur##*/}${tail:+/$tail}"
      cur="${cur%/*}"
      [ -n "$cur" ] || cur=/
    fi
  done
  out="$real"
  [ "$out" = / ] && out=""
  case "$-" in *f*) hadf=1 ;; esac
  set -f
  IFS=/
  # shellcheck disable=SC2086  # deliberate split on / with globbing disabled
  set -- $tail
  IFS="$oldifs"
  [ "$hadf" -eq 1 ] || set +f
  for part in "$@"; do
    case "$part" in
      ""|.) ;;
      ..) return 1 ;;
      *) out="$out/$part" ;;
    esac
  done
  _GRANT_RESOLVED="${out:-/}"
  return 0
}

grant_resolve() (
  _grant_resolve_set "${1-}"
  rc=$?
  printf '%s\n' "$_GRANT_RESOLVED"
  exit "$rc"
)

grant_resolve_lines() (
  _GRANT_RC_DIR=""
  _GRANT_RC_REAL=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    kind="${line%%"$GRANT_TAB"*}"
    case "$kind" in
      W|D|R|RR)
        path="${line#*"$GRANT_TAB"}"
        if _grant_is_sink "$path"; then
          printf '%s\n' "$line"
        else
          _grant_resolve_set "$path"
          printf '%s\t%s\n' "$kind" "$_GRANT_RESOLVED"
        fi
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <<< "${1-}"
  exit 0
)
