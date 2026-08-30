# payload/scripts/lib/cmd-class.sh — ONE READER FOR "what kind of command is this".
#
# WHAT IT OWNS. Given the text of a Bash tool call, answer whether any command in it is
# suite-class, bootstrap-class, install-class or build-class — reading argv POSITIONS, the
# way a shell does, and never substrings of the line.
#
# WHY IT EXISTS (B-5, wave-bionic-1.3.2). hooks/farm-out-reminder.sh used to grep one
# flattened string with mid-line anchors, so `make( +[^ ]+)?` reachable after any space
# denied `git commit -m "make the row green"` as class=build, and a heredoc body carrying
# `bash tests/run.sh` denied as class=suite. Both measured:
# .bionic/docs/record/wave-bionic-1.3.2-dogfood-fixes/research-b3-b5-b9-cmd-parsing.md §2.
# The cure is positional: prose, quoted strings and heredoc bodies are never argv[0] of
# anything, so they cannot classify. That is the whole invariant this file exists to hold.
#
# WHO READS IT. hooks/farm-out-reminder.sh (the main-thread wall) and
# hooks/background-suite-guard.sh (the agent-context wall behind agent-context-guard.sh).
# Both source it FAIL-CLOSED — a library that cannot load makes the hook refuse, naming
# the path it could not load, never silently allow (design D1, Chris 2026-08-30). The
# repo convention this replaces was byte-identical copies pinned by
# tests/cross-gate-agreement.test.sh; the removal case in tests/cmd-class.test.sh is what
# pays for the shared file instead.
#
# BASH 3.2. No associative arrays, no `${var^^}`, no `mapfile`. The parsing itself is one
# awk program (POSIX awk — no gensub, no length(array)), because character-at-a-time quote
# tracking in bash is both slower and harder to read than the same loop in awk.
#
# THE READING, in order:
#   1. HEREDOC BODIES ARE DELETED FIRST, terminator included. A `<<TAG` (or `<<-TAG`, or a
#      quoted tag) opens a body that belongs to the command that WROTE it, never to the
#      shell; nothing in it is a command. `<<<` is a here-string and opens nothing.
#   2. THE REST IS SPLIT on `;`, `&&`, `||`, `|`, a bare `&` and newline — outside quotes.
#      A `&` that is part of a redirection (`2>&1`, `&>log`) is not a separator.
#   3. EACH SEGMENT IS UNWRAPPED: leading `VAR=value` assignments (quoted values included),
#      `env`/`nohup`/`command`/`time`, `timeout <n>`; then ONE level of `sh -c`/`bash -c`/
#      `eval`/`bash <(cat FILE)`. An unwrap that yields a chain is re-split and re-read,
#      bounded at depth 2.
#   4. THE RESULT IS TOKENISED with quotes honoured, and argv[0] (plus argv[1], and argv[2]
#      for `npm run build`) decides. A token that carried WHITESPACE INSIDE QUOTES is prose
#      by construction and is replaced with an opaque marker that matches nothing.
#
# `cd <dir> &&` needs no rule of its own: step 2 already makes the command after it a
# segment in its own right.
#
# EXPORTS (all take the command as $1; none write outside their own locals):
#   cmd_strip_heredocs <cmd>  -> the command with every heredoc body removed
#   cmd_class_lines    <cmd>  -> one "<class><TAB><segment>" line per non-empty segment
#   cmd_class          <cmd>  -> the whole command's class, by PRIORITY not by position:
#                                suite > bootstrap > install > build > none. Priority, so
#                                that `make widget && bash tests/run.sh` still routes to
#                                the test-runner, which is how the regex classifier that
#                                came before it ordered its arms.
#
# [WALL: tests/cmd-class.test.sh]

# The awk program. `mode=heredoc` stops after step 1; `mode=lines` runs the whole reading.
_cmd_class_awk() {  # <mode> ; command on stdin
  awk -v mode="$1" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function base(p) { sub(/.*\//, "", p); return p }

    # ---------- 1. heredocs ----------
    # The tag opened by this line, or "" — quote-aware, so a `<<` inside a string is text.
    function heredoc_tag(s,   i, c, q, L, j, t, ch) {
      q = ""; L = length(s)
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == q) q = ""
          else if (c == "\\" && q == "\"") i++
          continue
        }
        if (c == "'"'"'" || c == "\"") { q = c; continue }
        if (c == "\\") { i++; continue }
        if (c == "<" && substr(s, i + 1, 1) == "<") {
          if (substr(s, i + 2, 1) == "<") { i += 2; continue }   # here-STRING: no body
          j = i + 2
          if (substr(s, j, 1) == "-") j++
          while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
          ch = substr(s, j, 1)
          if (ch == "'"'"'" || ch == "\"") j++
          t = ""
          while (j <= L) {
            c = substr(s, j, 1)
            if (c ~ /[A-Za-z0-9_]/) { t = t c; j++ } else break
          }
          if (t != "") return t
          i = j - 1
        }
      }
      return ""
    }

    # ---------- 2. segmentation ----------
    function segments(s, arr,   i, c, L, q, cur, k, nx, pv) {
      L = length(s); q = ""; cur = ""; k = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          cur = cur c
          if (c == q) q = ""
          else if (c == "\\" && q == "\"") { i++; cur = cur substr(s, i, 1) }
          continue
        }
        if (c == "'"'"'" || c == "\"") { q = c; cur = cur c; continue }
        if (c == "\\") { cur = cur c; i++; cur = cur substr(s, i, 1); continue }
        if (c == "\n" || c == ";") { arr[++k] = cur; cur = ""; continue }
        if (c == "&") {
          nx = substr(s, i + 1, 1); pv = (i > 1 ? substr(s, i - 1, 1) : "")
          if (nx == "&") { arr[++k] = cur; cur = ""; i++; continue }
          # a redirection, not a separator: 2>&1, >&2, &>log
          if (nx == ">" || pv == ">" || pv == "<") { cur = cur c; continue }
          arr[++k] = cur; cur = ""; continue
        }
        if (c == "|") {
          nx = substr(s, i + 1, 1)
          if (nx == "|" || nx == "&") { arr[++k] = cur; cur = ""; i++; continue }
          arr[++k] = cur; cur = ""; continue
        }
        cur = cur c
      }
      arr[++k] = cur
      return k
    }

    # ---------- 3. unwrapping ----------
    # The remainder of s after the value that starts at j (quoted values included).
    function consume_value(s, j,   c, L) {
      L = length(s); c = substr(s, j, 1)
      if (c == "'"'"'" || c == "\"") {
        j++
        while (j <= L && substr(s, j, 1) != c) j++
        j++
      } else {
        while (j <= L && substr(s, j, 1) != " " && substr(s, j, 1) != "\t") j++
      }
      return substr(s, j)
    }
    function strip_leading(s,   t) {
      s = trim(s)
      for (;;) {
        t = s
        if (match(s, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
          s = trim(consume_value(s, RLENGTH + 1))
        } else if (match(s, /^(env|nohup|command|time)[ \t]+/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^g?timeout[ \t]+(-[^ \t]+[ \t]+)*[0-9]+[smhd]?[ \t]+/)) {
          s = trim(substr(s, RLENGTH + 1))
        }
        if (s == t) break
      }
      return s
    }
    function dequote_whole(s,   c) {
      s = trim(s); c = substr(s, 1, 1)
      if ((c == "'"'"'" || c == "\"") && length(s) > 1 && substr(s, length(s), 1) == c)
        return substr(s, 2, length(s) - 2)
      return s
    }
    function unwrap_runner(s,   inner, j) {
      if (match(s, /^(ba|z|k|da)?sh[ \t]+-[a-z]*c[ \t]+/))
        return dequote_whole(substr(s, RLENGTH + 1))
      if (match(s, /^eval[ \t]+/))
        return dequote_whole(substr(s, RLENGTH + 1))
      # `bash <(cat FILE)` is `bash FILE` with a reader in the way; collapse to the script
      # that actually runs, or the workaround walks straight past the suite arm.
      if (match(s, /^(ba)?sh[ \t]+<\(/)) {
        inner = substr(s, RLENGTH + 1)
        j = index(inner, ")")
        if (j > 0) inner = substr(inner, 1, j - 1)
        sub(/^(cat|tac)[ \t]+/, "", inner)
        return "bash " trim(inner)
      }
      return s
    }

    # ---------- 4. argv ----------
    # A token quoted around whitespace is prose: it becomes \001, which matches nothing.
    function argv_tok(s, a,   i, L, c, q, cur, k, spaced, started) {
      L = length(s); q = ""; cur = ""; k = 0; spaced = 0; started = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (c == q) q = ""
          else { if (c == " " || c == "\t") spaced = 1; cur = cur c }
          continue
        }
        if (c == "'"'"'" || c == "\"") { q = c; started = 1; continue }
        if (c == " " || c == "\t") {
          if (cur != "" || started) { a[++k] = (spaced ? "\001" : cur); cur = ""; spaced = 0; started = 0 }
          continue
        }
        if (c == "\\") { i++; cur = cur substr(s, i, 1); continue }
        cur = cur c
      }
      if (cur != "" || started) a[++k] = (spaced ? "\001" : cur)
      return k
    }

    function classify_argv(s,   a, n, i, a1, a2, b0, b1) {
      n = argv_tok(s, a)
      if (n == 0) return "none"
      b0 = base(a[1])
      if (b0 == "bash" || b0 == "sh" || b0 == "zsh") {
        # skip the runner s own options: `bash -x tests/run.sh` runs the same suite
        i = 2
        while (i <= n && substr(a[i], 1, 1) == "-") i++
        a1 = (i <= n ? a[i] : ""); b1 = base(a1)
        if (b1 ~ /^claude-(bootstrap|reset)\.sh$/) return "bootstrap"
        if (b1 == "test.sh" || b1 ~ /\.test\.sh$/) return "suite"
        if (b1 == "run.sh" && index(a1, "/") > 0) return "suite"
        return "none"
      }
      a1 = (n >= 2 ? a[2] : ""); a2 = (n >= 3 ? a[3] : "")
      if (b0 ~ /^claude-(bootstrap|reset)\.sh$/) return "bootstrap"
      if (b0 == "pytest") return "suite"
      if (b0 == "npm" || b0 == "pnpm" || b0 == "yarn") {
        if (a1 == "test") return "suite"
        if (a1 == "install" || a1 == "add" || a1 == "ci") return "install"
        if (a1 == "run" && a2 == "build") return "build"
        return "none"
      }
      if (b0 == "go" || b0 == "cargo") {
        if (a1 == "test") return "suite"
        if (a1 == "build") return "build"
        return "none"
      }
      # `make clean` is trivial and stays silent; `make test`/`make check` are the suite;
      # bare `make` and every other target is a build.
      if (b0 == "make") {
        if (a1 == "test" || a1 == "check") return "suite"
        if (a1 == "clean") return "none"
        return "build"
      }
      if (b0 == "pip" || b0 == "pip3") return (a1 == "install" ? "install" : "none")
      if (b0 == "uv")   return ((a1 == "sync" || a1 == "pip") ? "install" : "none")
      if (b0 == "brew") return (a1 == "install" ? "install" : "none")
      if (b0 == "docker") return (a1 == "build" ? "build" : "none")
      return "none"
    }

    function class_seg(seg, depth,   u0, u, m, sub_, i, c) {
      u0 = strip_leading(seg)
      u = unwrap_runner(u0)
      if (u != u0 && depth < 2) {
        m = segments(u, sub_)
        for (i = 1; i <= m; i++) {
          c = class_seg(sub_[i], depth + 1)
          if (c != "none") return c
        }
        return "none"
      }
      return classify_argv(strip_leading(u))
    }

    { line[++nl] = $0 }
    END {
      out = ""; intag = 0; tag = ""
      for (i = 1; i <= nl; i++) {
        if (intag) { if (trim(line[i]) == tag) intag = 0; continue }
        out = out line[i] "\n"
        tag = heredoc_tag(line[i])
        if (tag != "") intag = 1
      }
      if (mode == "heredoc") { printf "%s", out; exit }
      k = segments(out, seg)
      for (i = 1; i <= k; i++) {
        t = trim(seg[i])
        if (t == "") continue
        printf "%s\t%s\n", class_seg(t, 0), t
      }
    }
  '
}

cmd_strip_heredocs() {  # <command> -> the command with every heredoc body removed
  printf '%s' "${1-}" | _cmd_class_awk heredoc
}

cmd_class_lines() {  # <command> -> "<class>\t<segment>" per non-empty segment
  printf '%s' "${1-}" | _cmd_class_awk lines
}

cmd_class() {  # <command> -> suite|bootstrap|install|build|none, by priority
  local classes c
  classes=$(cmd_class_lines "${1-}" | awk -F'\t' '{print $1}')
  for c in suite bootstrap install build; do
    if printf '%s\n' "$classes" | grep -qx "$c"; then printf '%s' "$c"; return 0; fi
  done
  printf 'none'
}
