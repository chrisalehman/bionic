#!/bin/bash
# payload/scripts/lib/handoff.sh — where a handoff document goes, how it is found, and how its composed half is read.
#
# WHAT IT OWNS. The home of the handoff document, one file per run or session per day under the handoffs folder of
# the project's docs record, never a tracked path; the plan's `## Handoff` pointer, the one line `handoff: <path>
# written <local time>` that session-poker.sh `handoff` and close-out.sh write there; and the two filters every
# composed section passes through before it is written.
#
#     handoff_home_file <root> <slug>
#                        <root>/<the handoffs folder>/<date>-<slug>.md, the date the local day of now (BIONIC_NOW_EPOCH
#                        when it is a number, the clock otherwise), so the verb and close-out name one file.
#     handoff_slug <text>
#                        the text as a file-name word: lower case, every other character a hyphen, runs of them one,
#                        none at either end, at most 48 characters; nothing for a text with no letter or digit.
#     handoff_pointer_of <plan> [<root>]
#                        the absolute path the pointer names; nothing when the plan carries no pointer (an older plan's
#                        in-place section, or no ## Handoff at all). Always rc 0.
#     handoff_default_of <plan> [<root>]
#                        the run's home file, handoff_home_file of the plan's own slug (lib/proof.sh `proof_plan_slug`,
#                        the one slug reader). rc 1 when the plan's name leaves no slug.
#     handoff_file_of <plan> [<root>]
#                        the run's handoff file: the pointer's path, else the default.
#     handoff_line <file> <label>
#                        the first `<label>: ` line of a written document, its fold joined back.
#     handoff_compose
#                        stdin, the sections a session composed, to `<section> TAB <item>` lines on stdout; see THE
#                        COMPOSED HALF below.
#     handoff_redact <count file>
#                        stdin to stdout with every secret and mail address replaced; the number replaced written to
#                        <count file>; see THE REDACTION below.
#
#     <root> is the project root the pointer is relative to; absent, the project root of the plan's own directory
#     (lib/root.sh `project_root`), physical.
#
# THE ONE READER OF THE POINTER. The poker's readers (adopt's STALE note, launch-sync's mark, the verb) and
# close-out's closed form call these, and tests/handoff-file.test.sh §POINTER-AGREE holds them to one answer.
#
# THE SECTION TEST, `_HANDOFF_SEC_AWK`: `ho_track(line)` is 1 for a line inside `## Handoff`, the heading, fences and
# fenced lines excluded. Every awk that looks in the section prepends it, the poker's in-place rewrites included.
#
# NEEDS lib/root.sh and lib/roots.sh (both callers source them); loads lib/proof.sh from beside itself when
# `proof_plan_slug` is not yet defined. Sourced, never executed; bash 3.2.

_HANDOFF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
HANDOFF_HOME=".bionic/docs/record/handoffs"
HANDOFF_SECTIONS="Summary|Goal|State|Findings|Decisions|Ruled out|Open|Suggested skills|Next|Resume"

_HANDOFF_SEC_AWK='
  function ho_track(l) {
    if (l ~ /^[ \t]*```/) { _hf = !_hf; return 0 }
    if (_hf) return 0
    if (l ~ /^##[ \t]/) { _hs = (l ~ /^##[ \t]+Handoff[ \t]*$/); return 0 }
    return _hs
  }'

_handoff_root() {  # <plan> [<root>] -> the root the pointer resolves against
  if [ -n "${2:-}" ]; then printf '%s' "$2"; return 0; fi
  ( cd "$(project_root "$(dirname "$1")")" 2>/dev/null && pwd -P )
}

handoff_home_file() {  # <root> <slug>
  local e day
  case "${BIONIC_NOW_EPOCH:-}" in ''|*[!0-9]*) e="$(date +%s)" ;; *) e="$BIONIC_NOW_EPOCH" ;; esac
  day="$(date -r "$e" +%Y-%m-%d 2>/dev/null || date -d "@$e" +%Y-%m-%d 2>/dev/null)"
  printf '%s/%s/%s-%s.md\n' "$1" "$HANDOFF_HOME" "$day" "$2"
}

handoff_slug() {  # <text>
  printf '%s' "${1:-}" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9' '-' | tr -s '-' \
    | sed -e 's/^-//' -e 's/-$//' | cut -c1-48 | sed 's/-$//'
}

handoff_pointer_of() {  # <plan> [<root>]
  local rel root
  [ -f "${1:-}" ] || return 0
  rel="$(awk "$_HANDOFF_SEC_AWK"'
    ho_track($0) && index($0, "handoff: ") == 1 && $0 ~ / written / { s = substr($0, 10); sub(/ written .*$/, "", s); print s; exit }' "$1" 2>/dev/null)"
  [ -n "$rel" ] || return 0
  case "$rel" in
    /*) printf '%s\n' "$rel" ;;
    *) root="$(_handoff_root "$1" "${2:-}")"
       [ -n "$root" ] && printf '%s/%s\n' "$root" "$rel" ;;
  esac
  return 0
}

handoff_default_of() {  # <plan> [<root>]
  local root slug
  if ! declare -F proof_plan_slug >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    [ -r "$_HANDOFF_LIB_DIR/proof.sh" ] && . "$_HANDOFF_LIB_DIR/proof.sh" >/dev/null 2>&1
  fi
  slug="$(proof_plan_slug "${1:-}")" || return 1
  root="$(_handoff_root "${1:-}" "${2:-}")"
  [ -n "$root" ] || return 1
  handoff_home_file "$root" "$slug"
}

handoff_file_of() {  # <plan> [<root>]
  local f
  f="$(handoff_pointer_of "$@")"
  if [ -n "$f" ]; then printf '%s\n' "$f"; return 0; fi
  handoff_default_of "$@"
}

# THE COMPOSED HALF. A session hands the verb the sections only it knows, in the document's own spelling: a heading
# line that is a section's name, then its items, each opening on `- `, `* ` or `<n>. ` (dropped), indentation ignored
# throughout, so a block pasted from an indented example reads the same. Any other line continues the item above it,
# or opens one when none is open; a blank line closes it. A heading named twice is one section,
# its items in the order given. A fenced block is never copied: it becomes one item, `(a copied block of <n> lines
# was left out: name its file by path)`, in the section it stood in, because a settled artifact is named by its path.
# Lines before any heading are no section's and are dropped. Out: `<section> TAB <item>`, in input order, then
# `@ TAB left=<blocks left out> stray=<lines dropped>`.
handoff_compose() {
  awk -v secs="$HANDOFF_SECTIONS" '
    BEGIN { n = split(secs, h, "|"); for (i = 1; i <= n; i++) H[h[i]] = 1 }
    function close_block() {
      if (sec == "") { stray += nb; return }
      S[++m] = sec; T[m] = "(a copied block of " nb " line" (nb == 1 ? "" : "s") " was left out: name its file by path)"
      left++; open = 0
    }
    { sub(/\r$/, ""); t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
    fence { if (t ~ /^```/) { fence = 0; close_block() } else nb++; next }
    t ~ /^```/ { fence = 1; nb = 0; next }
    (t in H) { sec = t; open = 0; next }
    t == "" { open = 0; next }
    sec == "" { stray++; next }
    t ~ /^([-*]|[0-9]+[.)])[ \t]+/ { sub(/^([-*]|[0-9]+[.)])[ \t]+/, "", t); if (t != "") { S[++m] = sec; T[m] = t; open = 1 }; next }
    open { T[m] = T[m] " " t; next }
    { S[++m] = sec; T[m] = t; open = 1 }
    END {
      if (fence) close_block()
      for (i = 1; i <= m; i++) printf "%s\t%s\n", S[i], T[i]
      printf "@\tleft=%d stray=%d\n", left, stray }'
}

# THE REDACTION. Before a document is written, every token of a known secret shape is replaced by `[redacted]`: model
# and service keys (`sk-ant-…`, `sk-…`), GitHub tokens (`ghp_…` and its kin, `github_pat_…`), AWS access key ids
# (`AKIA…`), Slack tokens (`xox?-…`), JSON web tokens, a bearer token's value, the value of a key, token, secret or
# password assignment (`password=…`), and a private key's armour line; a mail address becomes `[address redacted]`.
# Each shape starts at a word's edge and has a minimum length, so a word like `task-scale` is never one. A commit id
# is no secret, and is kept.
handoff_redact() {  # <count file>
  LC_ALL=C awk -v cf="${1:-/dev/null}" '
    function sweep(s, re, least, rep,    out, m, c) {
      out = ""
      while (match(s, re)) {
        m = substr(s, RSTART, RLENGTH); c = ""
        if (substr(m, 1, 1) ~ /[^A-Za-z0-9_]/) { c = substr(m, 1, 1); m = substr(m, 2) }
        if (length(m) >= least) { out = out substr(s, 1, RSTART - 1) c rep; red++ }
        else out = out substr(s, 1, RSTART + RLENGTH - 1)
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    function assign(s,    out, low, k, v) {
      out = ""
      while (1) {
        low = tolower(s)
        if (!match(low, /(^|[^a-z0-9])(api[_-]?key|access[_-]?key|secret|token|password|passwd)[a-z_]*[ ]*=[ ]*[^ ]+/)) break
        k = substr(s, RSTART, RLENGTH); v = k; sub(/^[^=]*=[ ]*/, "", v); sub(/[ ]*=.*$/, "", k)
        if (length(v) >= 6) { out = out substr(s, 1, RSTART - 1) k "=[redacted]"; red++ }
        else out = out substr(s, 1, RSTART + RLENGTH - 1)
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    {
      s = $0
      if (s ~ /-----BEGIN [A-Z ]*PRIVATE KEY-----/) { print "[redacted]"; red++; next }
      s = sweep(s, "(^|[^A-Za-z0-9_])sk-ant-[A-Za-z0-9_-]+", 20, "[redacted]")
      s = sweep(s, "(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]+", 24, "[redacted]")
      s = sweep(s, "(^|[^A-Za-z0-9_])gh[pousr]_[A-Za-z0-9]+", 24, "[redacted]")
      s = sweep(s, "(^|[^A-Za-z0-9_])github_pat_[A-Za-z0-9_]+", 30, "[redacted]")
      s = sweep(s, "(^|[^A-Za-z0-9_])AKIA[0-9A-Z]+", 20, "[redacted]")
      s = sweep(s, "(^|[^A-Za-z0-9_])xox[abposr]-[A-Za-z0-9-]+", 15, "[redacted]")
      s = sweep(s, "(^|[^A-Za-z0-9_])eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+", 30, "[redacted]")
      s = sweep(s, "[Bb]earer [A-Za-z0-9._~+/=-]+", 23, "Bearer [redacted]")
      s = assign(s)
      s = sweep(s, "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z][A-Za-z]+", 6, "[address redacted]")
      print s
    }
    END { printf "%d\n", red > cf }'
}

# handoff_line <file> <label> -> the first line that starts `<label>: `, its fold joined back: every line after it that
# opens on spaces and is no `  - ` item continues it. The page folds at 92 columns, so a reader of one State line reads
# it whole through here; nothing when the file has no such line.
handoff_line() {
  awk -v k="$2: " '
    f && /^ / && !/^  - / { t = $0; sub(/^ +/, "", t); l = l " " t; next }
    f { exit }
    index($0, k) == 1 { f = 1; l = $0 }
    END { if (f) print l }' "$1" 2>/dev/null
}
