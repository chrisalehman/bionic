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
#   2. THE REST IS SPLIT on `;`, `&&`, `||`, `|`, a bare `&`, newline and a GROUPING
#      PARENTHESIS — outside quotes. A `&` that is part of a redirection (`2>&1`, `&>log`)
#      is not a separator, and neither is the `(` of `$(…)` or `<(…)`.
#   3. EACH SEGMENT IS UNWRAPPED: leading `VAR=value` assignments (quoted values included),
#      shell openers (`{`, `}`, `!`, `then`, `else`, `elif`, `do`, `if`, `while`, `until`),
#      command-taking prefixes with their own options (`sudo [-u u] [--]`, `time [-p]`,
#      `nice [-n N]`, `env`, `nohup`, `command`, `exec`, `xargs [-I{} -n N …]`,
#      `ssh [opts] <host>`, `find … -exec`), `timeout <n>`; then ONE level of `sh -c`/
#      `bash -c`/`eval`/`bash <(cat FILE)`. An unwrap that yields a chain is re-split and
#      re-read, bounded at depth 2.
#   4. THE RESULT IS TOKENISED with quotes honoured, and argv[0] (plus argv[1], and argv[2]
#      for `npm run build`) decides. A token that carried WHITESPACE INSIDE QUOTES is prose
#      by construction and is replaced with an opaque marker that matches nothing. A SCRIPT
#      at argv[0] decides too: `./tests/run.sh` runs the suite as surely as
#      `bash tests/run.sh` does.
#
# THE SUPERSET RULE (R-12, critic C-1 2026-08-30). Steps 2 and 3 together exist so that this
# reading is a superset of the `(^|[;&| ])bash +tests/run\.sh` string match bionic 1.3.1
# used. Positional reading alone is NARROWER: `sudo bash tests/run.sh` and
# `( bash tests/run.sh )` put the runner at argv[1..n] where nothing looked, and four walls
# lost spellings 1.3.1 refused. Any new arm here is a wall — measure both directions.
#
# `cd <dir> &&` needs no rule of its own for the path form: step 2 already makes the command
# after it a segment. It does license one thing — the BASENAME form `bash run.sh`, which is
# a real suite invocation only once a cd has put the shell in that directory.
#
# EXPORTS (all take the command as $1; none write outside their own locals):
#   cmd_strip_heredocs <cmd>  -> the command with every heredoc body removed
#   cmd_class_lines    <cmd>  -> one "<class><TAB><segment>" line per non-empty segment
#   cmd_suite_targets  <cmd> [<root>]
#                             -> for each suite-class segment that names a suite FILE, its
#                                basename, one per line, in position order and deduplicated.
#                                `bash tests/a.test.sh && ./tests/run.sh` prints two lines;
#                                `pytest` and `make test` are suite-class and print none,
#                                because they name no file this repo budgets by. GIVEN A
#                                REPO ROOT the answer is scoped to that repo's tests/ and a
#                                `--dry-run` segment names nothing — see the function.
#   cmd_suite_claims   <cmd> [<root>]
#                             -> what each suite-class segment CLAIMS, one
#                                `<kind>\t<target>\t<run>` line per segment: kind `file`
#                                with the suite basename (the line above's answer), or kind
#                                `run` with the collapsed command, for a segment that runs a
#                                suite naming no file this repo budgets by. The budget arm
#                                reads this: `suites_allowed=` is compared to the first,
#                                `re_executes=` to the second (REQ-1 AC-1.5).
#   cmd_class          <cmd>  -> the whole command's class, by PRIORITY not by position:
#                                suite > bootstrap > install > build > none. Priority, so
#                                that `make widget && bash tests/run.sh` still routes to
#                                the test-runner, which is how the regex classifier that
#                                came before it ordered its arms.
#   cmd_backgrounded   <cmd>  -> exit 0 when the TEXT backgrounds it (D8, REQ-6): a bare
#                                `&` control operator outside quotes, never one folded
#                                into `&&` or a redirect, or a `nohup`/`setsid` wrapper.
#                                The `run_in_background` TOOL FLAG is a different fact,
#                                read by the caller (lib/walls.sh ARM 1) and OR'd with
#                                this one — a command can background itself either way.
#
# [WALL: tests/cmd-class.test.sh]

# The awk program. `mode=heredoc` stops after step 1; `mode=lines` runs the whole reading.
_cmd_class_awk() {  # <mode> ; command on stdin
  awk -v mode="$1" '
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function base(p) { sub(/.*\//, "", p); return p }
    # ONE RUN, ONE SPELLING (REQ-1 AC-1.5). The same collapse
    # `hooks/dispatch-preflight.sh` applies to an author-marked run before it writes it onto
    # the roster row (its `collapse()`, :1508), so a run typed with wider spacing here and a
    # run declared with narrower spacing there are the same string when the budget arm
    # compares them. Two collapses that disagreed would be a budget nobody could satisfy.
    function ws1(s) { gsub(/[ \t\r\n]+/, " ", s); sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    # NON-EXECUTING RUNNER FLAGS (REQ-5, D13). A TABLE, because the difference between
    # reading a suite and running one is a property of the flag and of nothing else: `-n`
    # (and its long spelling) makes the shell parse the file and stop, `--help`/`--version`
    # make it print and exit, and in every one of them the same words name a suite that is
    # never spent. `-x` and `-v` DO execute, so they are ordinary options and the suite they
    # name is still a real run (AC-5.2). A SHORT CLUSTER IS READ LETTER BY LETTER — `bash
    # -nx` and `bash -xn` are `-n` with a trace folded in, which is how anybody types it —
    # while a LONG option is matched whole, so `--verbose` is never read as a cluster
    # carrying `n`.
    function sh_noexec(w) {
      if (w == "--noexec" || w == "--help" || w == "--version") return 1
      if (w ~ /^-[A-Za-z]+$/ && index(w, "n") > 0) return 1
      return 0
    }

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
    # GROUPING PARENTHESES end a segment (R-12, critic C-1/C-2). Without that,
    # (cd tests; bash run.sh) leaves the closing paren glued to the last word
    # as run.sh) and no arm recognises it. A ( preceded by $ < or > opens a
    # command substitution or a process substitution instead: those are NOT
    # boundaries, so bash <(cat FILE) still reaches unwrap_runner intact, and
    # the matching ) at depth 0 stays an ordinary character.
    function segments(s, arr,   i, c, L, q, cur, k, nx, pv, gd) {
      L = length(s); q = ""; cur = ""; k = 0; gd = 0
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
        if (c == "(") {
          pv = (i > 1 ? substr(s, i - 1, 1) : "")
          if (pv != "$" && pv != "<" && pv != ">") {
            arr[++k] = cur; cur = ""; gd++; continue
          }
          cur = cur c; continue
        }
        if (c == ")" && gd > 0) { arr[++k] = cur; cur = ""; gd--; continue }
        if (c == "\n" || c == ";") { arr[++k] = cur; cur = ""; continue }
        if (c == "&") {
          nx = substr(s, i + 1, 1); pv = (i > 1 ? substr(s, i - 1, 1) : "")
          if (nx == "&") { arr[++k] = cur; cur = ""; i++; continue }
          # a redirection, not a separator: 2>&1, >&2, &>log
          if (nx == ">" || pv == ">" || pv == "<") { cur = cur c; continue }
          # A BARE & IS THE ONLY ONE THAT BACKGROUNDS (D8, REQ-6). `&&` above closes a
          # segment too, but synchronously — nothing after it is detached. SEPKIND is a
          # GLOBAL, deliberately not a local: cmd_backgrounded (mode="bg", below) is the
          # only reader, and it wants to know, for the segment just closed, which control
          # operator closed it — a question no caller of class_seg ever asks, so it costs
          # them nothing.
          arr[++k] = cur; cur = ""; SEPKIND[k] = "&"; continue
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
    # Removes the leading options of a command-taking prefix. An option NAMED in
    # val takes a separate value word, which comes off with it (quoted values
    # included) or the value becomes a phantom argv[0]. A bare -- ends them.
    function skip_opts(s, val,   w) {
      s = trim(s)
      while (s != "") {
        if (substr(s, 1, 1) != "-") break
        if (match(s, /^--([ \t]|$)/)) { s = trim(substr(s, RLENGTH + 1)); break }
        match(s, /^[^ \t]+/)
        w = substr(s, 1, RLENGTH)
        s = trim(substr(s, RLENGTH + 1))
        if (index(val, " " w " ") > 0 && s != "") s = trim(consume_value(s, 1))
      }
      return s
    }
    # Drops one non-option word — the ssh host.
    function drop_word(s) {
      s = trim(s)
      if (s == "") return s
      match(s, /^[^ \t]+/)
      return trim(substr(s, RLENGTH + 1))
    }
    # The command a find runs is after -exec / -execdir, never at argv[1]. A
    # find with no -exec runs nothing, so it yields nothing: that is what keeps
    # find . -name run.sh out of the suite class.
    function after_exec(s) {
      if (match(s, /(^|[ \t])-(exec|execdir|ok|okdir)([ \t]+|$)/))
        return trim(substr(s, RSTART + RLENGTH))
      return ""
    }
    # THE SUPERSET RULE (R-12, critic C-1). Everything before the real argv[0]
    # comes off here: leading assignments, shell OPENERS that start a command
    # without a ; && || | & separator, and command-taking PREFIXES whose own
    # argument is the next command. One loop, so they compose — then sudo bash
    # tests/run.sh and ( time git push ) both read through. Reading argv[0] of a
    # segment WITHOUT this is strictly narrower than the whitespace-anchored
    # string match bionic 1.3.1 used, which is the regression this repairs.
    function strip_leading(s,   t) {
      s = trim(s)
      for (;;) {
        t = s
        if (match(s, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
          s = trim(consume_value(s, RLENGTH + 1))
        } else if (match(s, /^[({})!][ \t]*/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^(then|else|elif|do|done|fi|if|while|until|env|command|exec)([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^(nohup|setsid)([ \t]+|$)/)) {
          # A WRAPPER, NOT JUST AN OPENER (D8, REQ-6). Stripped the same way env/exec are —
          # setsid NOW JOINS nohup so `setsid bash tests/run.sh` reaches the bash/sh arm
          # instead of falling through to none with argv[0]=setsid — but the strip also
          # SETS A FLAG, because cmd_backgrounded (below) needs to know a wrapper was here
          # even though classify_argv never sees the word again. One reading, two answers.
          SAW_WRAPPER = 1
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^time([ \t]+-p)?([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^nice([ \t]+(-n[ \t]*[0-9]+|-[0-9]+|--adjustment[= \t][ \t]*[0-9]+))?([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^(sudo|doas)([ \t]+|$)/)) {
          s = skip_opts(trim(substr(s, RLENGTH + 1)), " -u -g -p -U -C -r -t -h -D -R ")
        } else if (match(s, /^xargs([ \t]+|$)/)) {
          s = skip_opts(trim(substr(s, RLENGTH + 1)), " -I -i -n -L -P -s -E -a -d --replace --max-args --max-procs --max-lines --arg-file --delimiter --eof ")
        } else if (match(s, /^ssh([ \t]+|$)/)) {
          s = drop_word(skip_opts(trim(substr(s, RLENGTH + 1)), " -o -p -i -l -F -L -R -D -b -c -e -m -O -Q -S -W -w -J -E -B -I "))
        } else if (match(s, /^(find|[^ \t]*\/find)([ \t]+|$)/)) {
          s = after_exec(s)
        } else if (match(s, /^g?timeout[ \t]+(-[^ \t]+[ \t]+)*[0-9]+[smhd]?[ \t]+/)) {
          s = trim(substr(s, RLENGTH + 1))
        }
        if (s == t) break
      }
      return s
    }
    # Does this segment change directory? A cd is what makes the bare basename
    # form bash run.sh a real suite invocation two segments later.
    function is_cd(s) {
      s = strip_leading(s)
      return (s ~ /^cd([ \t]|$)/)
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

    # LAST_TARGET is this reading`s SECOND answer, set beside the class rather than
    # derived from the segment afterwards (S13, spec AC-21). The budget guard needs to
    # know WHICH suite a command runs, and the only code that knows is the code that
    # just decided it is a suite at all: re-finding the token with a second matcher
    # outside this function is the twin that drifts, and it would have to re-implement
    # strip_leading, unwrap_runner and the quote-aware tokeniser to see the same argv
    # positions this does. It is set ONLY for the two script forms that name a file —
    # pytest, `npm test`, `go test` and `make test` are suite-class and name no
    # tests/<x>.test.sh, so they leave it empty and the caller reports no target.
    function classify_argv_read(s,   a, n, i, a1, a2, b0, b1, npxshift) {
      LAST_TARGET = ""; LAST_PATH = ""; LAST_DRY = 0
      n = argv_tok(s, a)
      if (n == 0) return "none"
      # `--dry-run` IS A MODE THAT RUNS NOTHING (the walk, A-36a; critic K-2). It is read
      # off the whole segment rather than off argv[1], because the runner takes it after
      # the script and a reader that insisted on a position would miss the one spelling
      # anybody types. The CLASS is untouched: the command still runs the runner.
      for (i = 1; i <= n; i++) if (a[i] == "--dry-run") LAST_DRY = 1
      b0 = base(a[1])
      # A PACKAGE RUNNER IS A PREFIX, NOT A COMMAND (REQ-1 AC-1.5). `npx jest …` runs jest
      # and spends what a jest run spends; `npx create-react-app x` runs something else
      # entirely, and the tier-2 nudge is the wall that speaks for those. The prefix comes
      # off HERE, inside the argv reading, and deliberately not in `strip_leading`: that
      # function feeds `cmd_unwrap_head`, whose whole job is to hand the farm-out nudge the
      # `npx …` head it matches on (B-4a), and stripping it there would take the nudge s
      # subject away from it.
      npxshift = 0
      if (b0 == "npx" || b0 == "bunx" || b0 == "pnpx") npxshift = 1
      else if ((b0 == "npm" || b0 == "pnpm" || b0 == "yarn" || b0 == "bun") && n >= 2 && (a[2] == "dlx" || a[2] == "exec")) npxshift = 2
      if (npxshift > 0 && n > npxshift) {
        for (i = 1; i + npxshift <= n; i++) a[i] = a[i + npxshift]
        n = n - npxshift
        b0 = base(a[1])
      }
      if (b0 == "bash" || b0 == "sh" || b0 == "zsh" || b0 == "dash" || b0 == "ksh") {
        # SKIP THE RUNNER S OWN OPTIONS — BUT READ THEM FIRST (REQ-5, D13). This loop used
        # to skip every leading flag alike, so `bash -n tests/x.test.sh` reached the suite
        # arm with the same target `bash tests/x.test.sh` does and a writer checking a
        # suite s SYNTAX was refused for running it. A non-executing flag ends the reading
        # here: the command names a file it will not run, so it is not suite-class and it
        # names no target for any budget to hold. `-o <mode>` takes its value as a separate
        # word, which comes off with it or the mode word becomes a phantom script.
        i = 2
        while (i <= n && substr(a[i], 1, 1) == "-") {
          if (sh_noexec(a[i])) return "none"
          if (a[i] == "-o") { i++; if (i <= n && a[i] == "noexec") return "none" }
          i++
        }
        a1 = (i <= n ? a[i] : ""); b1 = base(a1)
        if (b1 ~ /^claude-(bootstrap|reset)\.sh$/) return "bootstrap"
        if (b1 == "test.sh" || b1 ~ /\.test\.sh$/) { LAST_TARGET = b1; LAST_PATH = a1; return "suite" }
        # A bare `run.sh` is only a suite invocation when a cd put us in its
        # directory — which is exactly the shape `cd <worktree>/tests && bash
        # run.sh` takes, and the shape the path-component requirement missed
        # (critic C-2). On its own the word says nothing, so it stays none.
        if (b1 == "run.sh" && (index(a1, "/") > 0 || CD_SEEN)) { LAST_TARGET = b1; LAST_PATH = a1; return "suite" }
        return "none"
      }
      a1 = (n >= 2 ? a[2] : ""); a2 = (n >= 3 ? a[3] : "")
      if (b0 ~ /^claude-(bootstrap|reset)\.sh$/) return "bootstrap"
      # A SCRIPT AT ARGV[0] IS THE COMMAND (critic C-2). tests/run.sh is
      # -rwxr-xr-x with a bash shebang, so ./tests/run.sh runs the suite exactly
      # as `bash tests/run.sh` does; before this arm a script at argv[0] fell
      # through every arm to none. The path component is what separates running
      # it from naming it: `ls tests/run.sh` is argv[0] ls and stays none, and a
      # bare `run.sh` word is not something the shell would run either.
      if (index(a[1], "/") > 0 && (b0 == "run.sh" || b0 == "test.sh" || b0 ~ /\.test\.sh$/)) {
        LAST_TARGET = b0
        LAST_PATH = a[1]
        return "suite"
      }
      if (b0 == "pytest") return "suite"
      # `jest` NAMED, the runner the seed and D1 are about. Bare, or behind the `npx`
      # prefix dropped above — both are one run of one project s tests.
      if (b0 == "jest") return "suite"
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

    # EVERY SUITE-CLASS SEGMENT NAMES SOMETHING NOW (REQ-1 AC-1.5). A reading that answered
    # only "this is a suite" left the budget arm in `payload/scripts/lib/walls.sh` with nothing to
    # compare for `pytest`, `npm test`, `go test` and `npx jest` — not a wall that let them
    # through on purpose, a wall that could not see them (research R1 Q2). So a suite-class
    # segment that named no FILE names its RUN instead: the argv text this reading actually
    # read, collapsed, which is the same shape `Re-executes:` puts on the roster row.
    #
    # KIND IS PART OF THE ANSWER, not something a caller re-derives from an empty column. A
    # `file` claim carries a basename the budget compares against `suites_allowed=`; a `run`
    # claim carries a command the budget compares against `re_executes=`. They are different
    # comparisons, and a caller that had to guess which one it held would guess wrong the
    # first time a suite file was named by a runner that is not a shell.
    function classify_argv(s,   c) {
      LAST_RUN = ws1(s)
      c = classify_argv_read(s)
      if (c != "suite") { LAST_KIND = ""; return c }
      if (LAST_TARGET != "") { LAST_KIND = "file"; return c }
      LAST_TARGET = LAST_RUN
      LAST_KIND = "run"
      return c
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
      # mode=head: the WHOLE command reduced to the text classify_argv would
      # read — assignments, openers, command-taking prefixes and ONE runner
      # wrapper removed. farm-out-reminder.sh reads it for its tier-2 matcher,
      # which used to carry its own sed twins of strip_leading/unwrap_runner
      # (review-b B-4a). One reader, one set of rules.
      if (mode == "head") {
        hd0 = trim(out)
        gsub(/\n/, " ", hd0)
        hd1 = strip_leading(hd0)
        printf "%s", strip_leading(unwrap_runner(hd1))
        exit
      }
      # mode=bg: cmd_backgrounded (D8, REQ-6) — "1" when the TEXT backgrounds the
      # command, "0" otherwise. TOP-LEVEL ONLY, no class_seg/unwrap_runner recursion:
      # every AC-6 form types the wrapper or the trailing `&` where segments() already
      # sees it, and going deeper (through an sh -c layer, say) would answer a question
      # nobody asked yet — this predicate reads backgrounding, not suite-ness, and
      # `cmd_class` already owns the "is this a suite at all" half.
      if (mode == "bg") {
        k = segments(out, bgseg)
        bg = 0
        for (i = 1; i <= k; i++) {
          if (SEPKIND[i] == "&") bg = 1
          t = trim(bgseg[i])
          if (t == "") continue
          SAW_WRAPPER = 0
          strip_leading(t)
          if (SAW_WRAPPER) bg = 1
        }
        printf "%s", (bg ? "1" : "0")
        exit
      }
      k = segments(out, seg)
      CD_SEEN = 0
      for (i = 1; i <= k; i++) {
        t = trim(seg[i])
        if (t == "") continue
        LAST_TARGET = ""; LAST_KIND = ""; LAST_RUN = ""
        cls = class_seg(t, 0)
        if (mode == "targets") {
          # ONE LINE PER DISTINCT CLAIM, in position order. A command naming the same
          # suite twice states one budget claim, and the caller compares a set.
          if (cls == "suite" && LAST_TARGET != "" && !LAST_DRY && !(LAST_TARGET in tgt_seen)) {
            tgt_seen[LAST_TARGET] = 1
            # KIND, TARGET, RUN AND PATH, tab-separated. The shell wrappers are the only
            # callers: `cmd_suite_claims` scopes the path to a repository and drops it,
            # `cmd_suite_targets` keeps the basename of the file claims. The path answers
            # "whose suite is this?", which a basename cannot (critic K-2); the run answers
            # "which run is this?", which a basename cannot either.
            #
            # THE PATH IS LAST BECAUSE IT IS THE ONLY ONE THAT CAN BE EMPTY, and a tab is an
            # IFS WHITESPACE character: bash `read` folds a run of them into one delimiter,
            # so an empty column anywhere but the end shifts every column after it by one.
            # Measured here, not reasoned about — a run claim (no path) handed its run to
            # the path variable and left the run empty.
            printf "%s\t%s\t%s\t%s\n", LAST_KIND, LAST_TARGET, LAST_RUN, LAST_PATH
          }
        } else {
          printf "%s\t%s\n", cls, t
        }
        # Left-to-right, so a cd only licenses the basename form in the
        # segments that FOLLOW it.
        if (is_cd(t)) CD_SEEN = 1
      }
    }
  '
}

cmd_strip_heredocs() {  # <command> -> the command with every heredoc body removed
  # THE FORK IS SKIPPED FOR A COMMAND THAT OPENS NO HEREDOC (epic-23 wave-14 REQ-4).
  # `heredoc_tag()` can only return a tag from a `<<` — it scans for exactly that pair
  # and returns "" from every other character — so for a command whose text does not
  # contain `<<` at all, step 1 is the identity and this whole awk pass is 3.3 ms
  # (measured, research R3 §3) spent copying the input to the output. The test is
  # deliberately the CRUDE one: a `<<` inside quotes, or a here-STRING `<<<`, opens no
  # body either, but reading that correctly is the awk's job and misreading it in the
  # fast path is how a wall goes blind. `<<` present means ask awk.
  #
  # AND THE ANSWER IS BYTE-IDENTICAL, not merely equivalent. On this path awk would
  # emit each input record followed by "\n" — the input with one trailing newline
  # guaranteed. Every caller in the tree reads this through `$( )`, which strips
  # trailing newlines from both spellings alike, so the two differ nowhere a caller
  # can see. tests/cmd-class.test.sh's heredoc rows keep both directions honest.
  case "${1-}" in
    *'<<'*) printf '%s' "${1-}" | _cmd_class_awk heredoc ;;
    *)      printf '%s' "${1-}" ;;
  esac
}

cmd_unwrap_head() {  # <command> -> the command reduced to what argv[0] reads
  printf '%s' "${1-}" | _cmd_class_awk head
}

cmd_backgrounded() {  # <command> -> 0 when the TEXT backgrounds it, 1 otherwise (D8, REQ-6)
  # A BARE `&` control operator outside quotes and not folded into `&&` or a redirect
  # (`2>&1`, `&>log`), OR a `nohup`/`setsid` wrapper — READ, never string-matched, by the
  # same segmentation and strip_leading this file uses for everything else. This is the
  # half `.tool_input.run_in_background` cannot see: the CLI only sets that flag for its
  # own `run_in_background: true` parameter, never for a command that backgrounds itself
  # inside the shell. `lib/walls.sh` ARM 1 ORs the two together.
  [ "$(printf '%s' "${1-}" | _cmd_class_awk bg)" = "1" ]
}

cmd_class_lines() {  # <command> -> "<class>\t<segment>" per non-empty segment
  printf '%s' "${1-}" | _cmd_class_awk lines
}

cmd_suite_claims() {  # <command> [<repo root>] -> "<kind>\t<target>\t<run>" per suite-class segment
  # WHAT A SUITE-CLASS COMMAND CLAIMS, which is two different things depending on what it
  # named. `file` carries the suite BASENAME the segment runs — the budget's unit since
  # wave-01 — and `run` carries the collapsed command text, for a segment that runs a suite
  # without naming a file this repository budgets by (`pytest`, `npm test`, `npx jest`).
  # Both carry the run beside the target, because `payload/scripts/lib/walls.sh` holds a
  # rostered agent to `suites_allowed=` AND to `re_executes=` and needs the two keys those
  # two fields are written in.
  #
  # WITH A REPO ROOT THE FILE CLAIMS ARE SCOPED: a segment names a target only when the path
  # it runs resolves to that repository's `tests/<basename>`. Without one the answer is the
  # bare basename, which is what it always was — the reading, not the row, decides. A RUN
  # claim is not scoped, because a run names no path to scope: it is the command itself, and
  # the row that declared it is the only thing that can say whether it belongs here.
  #
  # WHY SCOPING EXISTS (critic K-2, review-a A-7). A bare basename made any file on the
  # machine ending `.test.sh` this row's business: a scratch probe under /tmp and another
  # repository's `tests/run.sh` were both refused against a budget they had nothing to do
  # with, and the refusal named a repository the command never mentioned.
  #
  # SHAPE, NOT EXISTENCE. The resolved path is compared to `<root>/tests/<basename>`; it is
  # never stat'd. Refusing only files the hook can see would let a suite the writer is
  # about to create past the budget, and would make the answer depend on the filesystem at
  # hook time rather than on the command. "A path somewhere else" is visible in the path.
  #
  # TWO SPELLINGS STAY NAMED ON PURPOSE, both because the caller has something to say
  # about them and cannot say it about a target it never hears:
  #   * the cd-licensed basename form (`cd tests && bash run.sh`) records no directory to
  #     resolve against, and the full tree is the one act this budget fails CLOSED on;
  #   * a token carrying `$` or a backtick cannot be resolved at hook time at all — the
  #     guard has a refusal written for exactly that state.
  local _root="${2-}" _k _b _r _p _abs
  printf '%s' "${1-}" | _cmd_class_awk targets | while IFS=$'\t' read -r _k _b _r _p; do
    [ -n "$_k" ] || continue
    if [ "$_k" != "file" ]; then printf '%s\t%s\t%s\n' "$_k" "$_b" "$_r"; continue; fi
    [ -n "$_b" ] || continue
    if [ -z "$_root" ]; then printf 'file\t%s\t%s\n' "$_b" "$_r"; continue; fi
    case "$_p" in
      *'$'*|*'`'*) printf 'file\t%s\t%s\n' "$_b" "$_r"; continue ;;
      */*) : ;;
      *) printf 'file\t%s\t%s\n' "$_b" "$_r"; continue ;;
    esac
    case "$_p" in
      /*) _abs="$_p" ;;
      *)  _abs="$_root/${_p#./}" ;;
    esac
    if [ "$_abs" = "$_root/tests/$_b" ]; then printf 'file\t%s\t%s\n' "$_b" "$_r"; fi
  done
  return 0
}

cmd_suite_targets() {  # <command> [<repo root>] -> the suite BASENAME each suite-class segment runs
  # THE FILE HALF OF `cmd_suite_claims`, and nothing else. It is a projection rather than a
  # second reading for the reason this whole file exists: the scoping rules above are the
  # kind of thing that drifts the moment they are spelled twice. Callers that budget by
  # suite FILE — `hooks/dispatch-preflight.sh`'s derivation round-trip, the full-tree arm —
  # read this; a caller that also holds runner forms reads the claims.
  local _k _b _r
  cmd_suite_claims "${1-}" "${2-}" | while IFS=$'\t' read -r _k _b _r; do
    [ "$_k" = "file" ] || continue
    printf '%s\n' "$_b"
  done
  return 0
}

cmd_class() {  # <command> -> suite|bootstrap|install|build|none, by priority
  # FIVE FORKS LESS THAN IT USED TO COST (epic-23 wave-14 REQ-4; research R3 §3
  # measured 6.4 ms of `classify_tier1`'s 13.1 on this function alone). The reading
  # is unchanged — the SAME lines from the SAME awk, still by priority and not by
  # position — but the class column is now split by parameter expansion and matched
  # by `case`, where it was one `awk -F'\t'` plus one `grep -qx` PER CLASS NAME over
  # a handful of lines. Four greps to ask four questions of one small string is four
  # process spawns on the hottest path in the tree.
  #
  # EXACT-LINE SEMANTICS, WHICH IS WHAT `grep -qx` GAVE. The set is assembled with a
  # newline on BOTH sides of every class word, and each pattern carries a newline on
  # both sides of the word it looks for, so `suite` matches the whole field `suite`
  # and never a field that merely contains it. A `case` pattern would otherwise be a
  # substring test, which is exactly the direction `-x` existed to refuse: without
  # the anchors a class column reading `not-suite` would answer `suite`, and the
  # farm-out wall would deny a command it has no business denying.
  #
  # THE FIELD SPLIT MATCHES awk's. `${line%%<tab>*}` on a line carrying no tab yields
  # the whole line, which is what `awk -F'\t' '{print $1}'` printed for such a line.
  local lines rest line cls seen c
  lines=$(cmd_class_lines "${1-}")
  seen=$'\n'
  rest="$lines"
  while [ -n "$rest" ]; do
    line="${rest%%$'\n'*}"
    case "$rest" in
      *$'\n'*) rest="${rest#*$'\n'}" ;;
      *)        rest="" ;;
    esac
    cls="${line%%$'\t'*}"
    [ -n "$cls" ] || continue
    seen="$seen$cls"$'\n'
  done
  for c in suite bootstrap install build; do
    case "$seen" in
      *$'\n'"$c"$'\n'*) printf '%s' "$c"; return 0 ;;
    esac
  done
  printf 'none'
}
