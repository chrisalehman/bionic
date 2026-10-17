#!/bin/bash
# payload/scripts/lib/roots.sh — ONE RESOLVER PER ROOT, for the whole of bionic.
#
# WHAT IT OWNS (epic-22 wave-01 REQ-N1, ADR-003). Every question of the form
# "where is X" that more than one file asked, asked once here:
#
#   project_root [cwd]    the project this cwd belongs to        (root.sh, re-exported)
#   bionic_root  <root>   <root>/.bionic — the state directory
#   docs_root    <root>   <root>/<docs-root:>, else <root>/.bionic/docs
#   tmp_root     <root>   <root>/.bionic/tmp — session-keyed state
#   archive_root <root>   <archive-root:>, else $HOME/bionic-archive
#   plugin_root           this payload's own root
#   claude_home           the CLI's config directory
#   worktree_root [dir]   the MAIN checkout, from anywhere inside the repository
#   transcripts_dir       where the CLI keeps session transcripts
#   config_value <root> <key> <default>
#                         the one reader of <root>/.bionic/config.yaml
#
# WHY. Before this file the tree carried FIVE docs-root implementations (four in
# hooks/, held byte-for-byte by tests/cross-gate-agreement.test.sh §R, and a fifth
# in lib/run.sh that §R's `hooks/`-scoped glob could not see), THREE claude-home
# copies, TWO plugin-root copies, THREE main-root resolvers, and no tmp resolver at
# all — 41 bare `.bionic/tmp` literals across 26 files. None of the duplicate sets
# but the first had an agreement test, and the one that did could not see its own
# fifth copy. A wall and a script that disagree about where a contracted artifact
# lives is not a cosmetic defect: epic-17 W6 S15 measured three readers of one
# sentence, two of them wrong, and one task wrote a duplicate file at the repo root
# to satisfy the reader that was wrong. (Surfaces map §C.1–C.4.)
#
# THE PIN. tests/cross-gate-agreement.test.sh §Roots asserts each name below is
# defined exactly ONCE across hooks/, payload/scripts/ and payload/scripts/lib/, and
# proves the assertion discriminates by planting a second definition in a scratch
# copy and requiring red. That section replaces §R, which retired with the four
# hook copies it held.
#
# project_root IS THE ONE EXCEPTION, AND DELIBERATELY. Its implementation is the
# ancestor walk in lib/root.sh (`_bionic_root_report` and the candidate tags doctor
# and the SessionStart report both render), with its own suite in tests/root.test.sh.
# Re-defining it here would be the second definition this file exists to forbid, so
# root.sh stays the single owner and this file SOFT-SOURCES it: a caller that has
# roots.sh has project_root, and there is still exactly one `project_root()` in the
# tree.
#
# SOURCED, NEVER EXECUTED. Two things run at source time and nothing else prints:
# the soft source of a sibling, which defines functions and reads nothing (the idiom
# lib/detect.sh already uses for lib/deps.sh and lib/checks.sh for lib/patrol.sh),
# and the resolution of this file's own directory to an absolute path — see C-3 at
# `_ROOTS_LIB_DIR` below for why that cannot wait until a resolver is called.
#
# ONE OUTPUT CONTRACT: every resolver here prints its answer with `printf '%s\n'`,
# one line, trailing newline included. Callers read through `$( )`, which strips it,
# so the rule costs nothing and buys a reader one shape to learn instead of three
# (Step-6 review R-2, which found `printf '%s'`, `echo` and a bare `pwd -P` sharing
# this file). tests/roots.test.sh §1d holds it, WITHOUT command substitution — the
# byte under test is the one `$( )` removes.
#
# BASH 3.2. No associative arrays, no `${var^^}`, no `mapfile`.
#
# NO `dirname`/`basename` IN THE SELF-LOCATOR, for lib/detect.sh's reason: a library
# that cannot be sourced without coreutils dies on the half-broken machine it is
# most needed on.
#
# [WALL: tests/roots.test.sh]

_roots_self_dir() {
  local self="${BASH_SOURCE[0]}"
  case "$self" in */*) echo "${self%/*}" ;; *) echo "." ;; esac
}

# THE TWO ABSOLUTE PATHS THIS FILE NEEDS, RESOLVED AT SOURCE TIME (Step-6 review C-3).
# `_roots_self_dir` returns `${BASH_SOURCE[0]%/*}`, which is RELATIVE when the file was
# sourced by a relative path; a resolver that re-ran it at CALL time answered against
# whatever the caller's cwd had become — `/` after a `cd`, silently, which is the
# fail-dangerous direction for a root. The four sibling libraries (refuse.sh, patrol.sh,
# worktree.sh, detect.sh) all resolve theirs on the way in, and this file now does too.
# UNCONDITIONAL, and deliberately not inside the soft-source guard below: a caller that
# already sourced root.sh still needs `plugin_root` to have an answer.
_ROOTS_LIB_DIR="$(cd "$(_roots_self_dir)" && pwd -P)"
_ROOTS_PAYLOAD_DIR="$(cd "$_ROOTS_LIB_DIR/../.." && pwd -P)"

# root.sh, THE SOFT SOURCE — see the header. Guarded on the function and not on the
# file, so a caller that already sourced root.sh pays nothing.
if ! declare -F project_root >/dev/null 2>&1; then
  # shellcheck source=/dev/null
  . "$_ROOTS_LIB_DIR/root.sh"
fi

# ─── The one config reader ───────────────────────────────────────────────────
#
# config_value <root> <key> <default> -> the FIRST `<key>:` value in
# <root>/.bionic/config.yaml with surrounding whitespace and one layer of quotes
# removed; <default> when the file does not exist, does not carry the key, or
# carries it with an empty value.
#
# MOVED HERE FROM lib/run.sh (epic-22 wave-01, N1). It arrived there for
# `live-window:` alone, with a comment pinning the conversion of `docs-root:` OUT of
# that wave — "the pipeline below is deliberately the SAME SHAPE as the one above
# rather than a tidier parser", six lines duplicated so the two readings of one file
# would agree about indentation, quoting, trailing space and duplicate lines. They
# are one reading now, so the agreement is structural rather than maintained.
# tests/run-predicate.test.sh §R9's twelve behaviours are unchanged and still hold
# this function.
#
# FOUR KEYS STILL HAND-ROLL THEIR OWN PIPELINE — `rigor-floor:` in
# canonical-sdlc-governing-skill.sh, `farm-out-mode:` in farm-out-reminder.sh,
# `poker-interval:` in session-poker.sh. Those hooks are other tasks' files in this
# wave; the conversion is named in this task's report and is not taken here.
config_value() {
  local root="$1" key="$2" default="$3"
  local config="$root/.bionic/config.yaml"
  local value=""
  if [ -f "$config" ]; then
    value=$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$config" 2>/dev/null \
      | head -1 \
      | sed -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
      | sed -E "s/^['\"]//;s/['\"]\$//" \
      | sed -E 's/[[:space:]]+$//')
  fi
  if [ -n "$value" ]; then
    printf '%s\n' "$value"
    return 0
  fi
  printf '%s\n' "$default"
}

# config_section <root> <key> -> the items of the YAML list `<key>:` in <root>/.bionic/config.yaml,
# one per line, in file order; nothing when the file, the key or its items are absent. Always rc 0.
#
# THE ONE READER OF A LIST IN config.yaml (wave-38 T18; REQ-7 AC-7.1), config_value's sibling: that
# one reads a flat `key: value`, this one the `- ` items under a top-level `key:` — the key at column
# 0 with nothing after the colon but a comment — until the next flush-left key. An item is one line,
# indented or flush-left (both are YAML); blank lines and `#` lines are skipped, a trailing CR is
# dropped, one matching pair of quotes around the whole item is stripped, and anything after a `|`
# stays verbatim (a standing order's `| refuse: <class>` tail is the Bash wall's to read, below). A
# key carrying a flat value is not a list and prints nothing; the FIRST `key:` line decides, as
# config_value's head -1 does.
#
# PURE BASH, NO FORK: hooks/bash-walls.sh reads `standing-orders:` on every Bash call, and
# session-start's command counts are pinned (tests/session-start.test.sh §16).
config_section() {
  local config="${1:-}/.bionic/config.yaml" key="${2:-}" line t rest in=0
  [ -n "$key" ] && [ -f "$config" ] && [ -r "$config" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$in" = 0 ]; then
      case "$line" in
        "$key:"*)
          rest="${line#"$key:"}"
          case "$rest" in ''|[[:space:]]*) ;; *) continue ;; esac   # `key:x` / `keyx:` is another key
          rest="${rest#"${rest%%[![:space:]]*}"}"
          case "$rest" in ''|'#'*) in=1 ;; *) return 0 ;; esac ;;
      esac
      continue
    fi
    t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in ''|'#'*) continue ;; esac
    case "$t" in
      '-'|'- '*|-$'\t'*) ;;
      *) case "$line" in [[:space:]]*) continue ;; *) return 0 ;; esac ;;   # an indented non-item, or the next key
    esac
    t="${t#-}"; t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    case "$t" in
      \"*\"|\'*\') [ "${#t}" -ge 2 ] && t="${t:1:${#t}-2}" ;;
    esac
    [ -n "$t" ] && printf '%s\n' "$t"
  done < "$config"
  return 0
}

# THE CLASSES A STANDING ORDER'S `refuse:` CLAUSE MAY NAME — lib/cmd-class.sh `cmd_class`'s answers,
# all but `none` (a lock on "every command no class names" would refuse ordinary work). An order
# naming anything else is a config error: session-start says so and the Bash wall enforces it never.
STANDING_ORDER_CLASSES="suite bootstrap install build"

# standing_order_split <item> -> sets STANDING_ORDER_TEXT, STANDING_ORDER_REFUSES (0|1) and
# STANDING_ORDER_CLASS. An item `<text> | refuse: <class>` refuses: the text is the words before its
# last `|`, the class the word after `refuse:` (possibly empty, which no class is). Any other item is
# all text and refuses nothing. A string function: it reads no file.
standing_order_split() {
  local item="${1-}" tail
  STANDING_ORDER_TEXT="$item"; STANDING_ORDER_REFUSES=0; STANDING_ORDER_CLASS=""
  case "$item" in *'|'*) ;; *) return 0 ;; esac
  tail="${item##*|}"; tail="${tail#"${tail%%[![:space:]]*}"}"; tail="${tail%"${tail##*[![:space:]]}"}"
  case "$tail" in refuse:*) ;; *) return 0 ;; esac
  tail="${tail#refuse:}"; tail="${tail#"${tail%%[![:space:]]*}"}"
  STANDING_ORDER_CLASS="$tail"; STANDING_ORDER_REFUSES=1
  STANDING_ORDER_TEXT="${item%|*}"
  STANDING_ORDER_TEXT="${STANDING_ORDER_TEXT%"${STANDING_ORDER_TEXT##*[![:space:]]}"}"
  return 0
}

# standing_order_class_known <class> -> rc 0 when <class> is one of STANDING_ORDER_CLASSES.
standing_order_class_known() {
  case " $STANDING_ORDER_CLASSES " in *" ${1:-} "*) [ -n "${1:-}" ] ;; *) return 1 ;; esac
}

# _roots_join <root> <value> -> <value> if absolute, else <root>/<value>.
# The joining rule every configurable root shares: an absolute override stands, a
# relative one hangs off the project. One rule, so `docs-root: /srv/docs` and
# `archive-root: ../archives` cannot come to mean different things.
_roots_join() {
  case "${2:-}" in
    /*) printf '%s\n' "$2" ;;
    *)  printf '%s\n' "$1/$2" ;;
  esac
}

# ─── The project's own roots ─────────────────────────────────────────────────

# bionic_root <root> -> <root>/.bionic, the state directory.
bionic_root() {
  printf '%s\n' "$1/.bionic"
}

# docs_root <root> -> the absolute docs root for <root>: its .bionic/config.yaml's
# `docs-root:` value if set (relative values are joined onto <root>; absolute values
# pass through unchanged), else <root>/.bionic/docs.
#
# THE FIVE COPIES THIS RETIRES: resolve_docs_root() in canonical-sdlc-evidence-gate.sh
# (the §R origin), canonical-sdlc-governing-skill.sh, session-sweeper.sh and
# stop-check.sh, and docs_root() in lib/run.sh. Every one of them is now a caller.
docs_root() {
  local root="$1" override
  override="$(config_value "$root" "docs-root" "")"
  if [ -n "$override" ]; then
    _roots_join "$root" "$override"
    return 0
  fi
  printf '%s\n' "$(bionic_root "$root")/docs"
}

# tmp_root <root> -> <root>/.bionic/tmp, where every session-keyed state file lives.
# NEW: this root had no resolver at all and 41 bare literals. This task converts the
# call sites it already touches for another resolver; the rest are named in its
# report as later work.
tmp_root() {
  printf '%s\n' "$(bionic_root "$1")/tmp"
}

# archive_root <root> -> where a CLOSED run's directory is moved (ADR-003): the
# `archive-root:` config value if set, else $HOME/bionic-archive. Relative values
# join onto <root>, the same rule docs_root uses.
archive_root() {
  local root="$1" override
  override="$(config_value "$root" "archive-root" "")"
  if [ -n "$override" ]; then
    _roots_join "$root" "$override"
    return 0
  fi
  printf '%s\n' "${HOME:-/nonexistent}/bionic-archive"
}

# ─── The machine's roots ─────────────────────────────────────────────────────

# claude_home -> the CLI's config directory, through the override chain every
# library here already read. DELETES `_wt_claude_home` (worktree.sh) and
# `_patrol_claude_home` (patrol.sh); `_dep_claude_home` (deps.sh) SURVIVES as a
# one-line shim that calls this function, kept for its nine call sites in that file
# rather than re-spelled at each of them. So there are two NAMES for this question
# and still one ANSWER — which is the property that mattered — and a reader who greps
# for the second name finds a delegation rather than a second copy (Step-6 review R-1).
claude_home() {
  printf '%s\n' "${BIONIC_CLAUDE_HOME:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}"
}

# transcripts_dir -> where the CLI writes session transcripts, one directory per
# slugged cwd. The slug rule belongs to the CLI and is deliberately not reproduced:
# callers SCAN this directory rather than derive a path into it.
transcripts_dir() {
  printf '%s\n' "$(claude_home)/projects"
}

# plugin_root -> THIS PAYLOAD's own root: the override if one is set, else the
# directory two levels above this library (lib -> scripts -> payload root).
# RETIRES `_detect_plugin_root` (detect.sh) and `_dep_plugin_root` (deps.sh), which
# were byte-identical and each explained itself by saying the other existed.
#
# NOT the same question as detect.sh's public `detect_plugin_root`, which asks the
# CLI's install REGISTRY where bionic was installed and refuses loudly when the
# registry cannot answer. That is "which copy did the CLI install", this is "which
# copy is running"; on a developer machine driving a directory source they routinely
# differ, and collapsing them would make doctor report the registry's answer for the
# files it is actually reading. See this task's report, Assumptions.
plugin_root() {
  if [ -n "${BIONIC_PLUGIN_ROOT:-}" ]; then printf '%s\n' "$BIONIC_PLUGIN_ROOT"; return; fi
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then printf '%s\n' "$CLAUDE_PLUGIN_ROOT"; return; fi
  printf '%s\n' "$_ROOTS_PAYLOAD_DIR"
}

# worktree_root [dir] -> the MAIN checkout's root from anywhere inside the
# repository, including from inside a linked worktree where --show-toplevel would
# answer with the linked tree. --git-common-dir is the shared .git of the whole
# repository; its parent is the main working tree.
#
# RETIRES `_wt_main_root` (worktree.sh) and `resolve_main_root`
# (spawn-worktree.sh). The <dir> argument and the `cd "$dir"` before the second
# rev-parse are `_wt_main_root`'s and are kept: git < 2.31 has no --path-format, and
# its answer is then relative to the cwd the question was asked in.
worktree_root() {
  local d="${1:-.}" common
  common="$( cd "$d" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null )"
  [ -n "$common" ] || common="$( cd "$d" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null )"
  [ -n "$common" ] || return 1
  ( cd "$d" 2>/dev/null && cd "$common/.." 2>/dev/null && pwd -P )
}
