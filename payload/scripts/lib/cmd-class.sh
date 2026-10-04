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
#      is not a separator, and neither is the `(` of `$(…)` or `<(…)`. A `case … in`
#      pattern list is consumed as patterns, so only arm bodies become segments; a
#      variable a literal `for` list or one literal assignment pins is then resolved, one
#      reading per value (sections 5-6 of the awk program, wave-24 D9/D12).
#   3. EACH SEGMENT IS UNWRAPPED: leading `VAR=value` assignments (quoted values included),
#      leading redirections (`2>/dev/null`, `<file`, glued or detached),
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
#   cmd_suite_loop_lines <cmd>
#                             -> one `bash <path>` line per suite a literal `for` header names,
#                                each word put into the path the loop body runs (wave-24 T13,
#                                D10); none when the body reassigns the variable (T26). The
#                                unexpanded-name refusal in lib/walls.sh prints it.
#   cmd_class          <cmd>  -> the whole command's class, by PRIORITY not by position:
#                                suite > bootstrap > install > build > none. Priority, so
#                                that `make widget && bash tests/run.sh` still routes to
#                                the test-runner, which is how the regex classifier that
#                                came before it ordered its arms.
#   cmd_run_norm       <cmd>  -> the RUN a command makes, with its trailing redirections,
#                                `| tee <path>`, `|& tee <path>` and `|| true` removed and
#                                its whitespace collapsed, quoted text kept whole (REQ-7, D7).
#   cmd_runs_norm      <field>-> a `re_executes=` field with each backtick-marked run put
#                                through the same rule inside its own marks.
#   CMD_RUN_NORM_AWK          -> the awk text both of those, `classify_argv` below and
#                                hooks/dispatch-preflight.sh's `collapse()` run: one rule,
#                                pasted into each awk program that needs it, never re-typed.
#   cmd_backgrounded   <cmd>  -> exit 0 when the TEXT backgrounds it (D8, REQ-6): a bare
#                                `&` control operator outside quotes, never one folded
#                                into `&&` or a redirect, whose job no bare `wait` in its
#                                own group and branch collects (wave-24 D12), or a
#                                `nohup`/`setsid` wrapper.
#                                The `run_in_background` TOOL FLAG is a different fact,
#                                read by the caller (lib/walls.sh ARM 1) and OR'd with
#                                this one — a command can background itself either way.
#   cmd_write_targets  <cmd> [<cwd>]
#                             -> every path the command WRITES, resolved, one per line: redirect
#                                targets and the files of tee, sed -i, touch, mkdir, ln, and
#                                the cp/mv destination (wave-24 T12, D16). The memory wall's
#                                collector, hooks/bash-walls.sh, reads it.
#   cmd_effects        <cmd> [<cwd>] [reads]
#                             -> what the command writes (`W<TAB>path`) and deletes
#                                (`D<TAB>path`), absolute, or `?<TAB>reason<TAB>segment` for
#                                anything it cannot read in full (wave-25 T2, D5). The
#                                permission answer reads it and allows only a command with no
#                                `?` line. With the word `reads`, also what it reads
#                                (`R<TAB>path`, `RR<TAB>path` for a read that descends; T16).
#                                See _CMD_EFFECTS_AWK for the reading.
#
# [WALL: tests/cmd-class.test.sh]

# ---------- ONE RUN, ONE SPELLING, BOTH SIDES OF THE ROW (wave-20 T4; REQ-7, D7) ----------
#
# WHAT WAS WRONG. The budget arm (payload/scripts/lib/walls.sh) compares the run a command
# CLAIMS to the runs its brief DECLARED, exactly. The claim was the segment text with its
# redirections still in it, so `npx jest x 2>&1 | tee log` claimed `npx jest x 2>&1` and was
# refused for the run its own brief declared — while `| tee log` alone passed, because the
# segment splitter had already cut it. The spelling every role file prescribes for saving
# evidence was the one the wall refused (triage-B B1, measured there cell by cell).
#
# WHAT IT STRIPS, AND ONLY AT THE END. Redirections and `| tee` change where output goes;
# `|| true` changes whether a failure stops the shell. None changes what runs, so none is
# part of the spend. Stripped, repeatedly, from the END of the text: `[n]> p`, `[n]>> p`,
# `[n]>| p`, `&> p`, `&>> p`, the duplications `[n]>&m` and `[n]>&-`, a pipe or `|&` into
# `tee` and its words, and `|| true`. Anything else at the end stops it — a pipe into
# something that is not tee is a different command, and an INPUT redirection changes what
# runs, so neither is ever taken off.
#
# QUOTES ARE READ, NEVER GUESSED. A character scanner in the discipline `segments()` below
# uses: a `>` or `|` inside quotes is an argument, and a quoted target (`> "a b.log"`) is one
# word. It deliberately does not use `argv_tok`, which maps a token holding a quoted space to
# one opaque marker — through it `jest -t 'a b'` and `jest -t 'c d'` would be the same run.
#
# ONE TEXT, THREE PROGRAMS. The rule is written once, here, as awk source. `_cmd_class_awk`
# pastes it in front of its own program and builds LAST_RUN with it (the claim side);
# `cmd_runs_norm` is what walls.sh runs at its one decode of the declared field; and
# hooks/dispatch-preflight.sh pastes it into the lift, whose `collapse()` calls it before a
# declared run is stored. Three copies of a scanner would disagree the first time one moved.
#
# NO APOSTROPHE MAY APPEAR IN THIS TEXT: every program it is pasted into is one single-quoted
# shell word. The quote characters are written as awk escapes for that reason.
CMD_RUN_NORM_AWK='
    function cmdnorm_ws(s) { gsub(/[ \t\r\n]+/, " ", s); sub(/^ +/, "", s); sub(/ +$/, "", s); return s }
    # Where the quote q opened at i closes: the index of its closing quote, or length + 1 when
    # it never closes. With esc, a backslash inside double quotes hides the character after
    # it. A QUOTED RUN IS FOUND, NEVER WALKED (wave-24 T22): the readers below used to copy a
    # quoted run into their word one character at a time, and awk copies the whole word on
    # every append, so a 52 KB `python3 -c` body cost 0.2 s per reader. index(), never a
    # regex: substr counts bytes, so the byte after a backslash can be half a character, and
    # macOS awk aborts a match() on text that starts there.
    function cmdnorm_qend(s, i, q, esc,   t, j, k, b) {
      j = i + 1
      for (;;) {
        t = substr(s, j)
        k = index(t, q)
        if (esc && q == "\"") { b = index(t, "\\"); if (b > 0 && (k == 0 || b < k)) { j += b + 1; continue } }
        return (k == 0 ? length(s) + 1 : j + k - 1)
      }
    }
    function cmdnorm_run(s,   L, i, c, e, n, T, K, P, cur, cs, st, op, nx, j, w, k, cut, hit) {
      L = length(s); n = 0; cur = ""; cs = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (c == "\047" || c == "\"") {
          if (cur == "") cs = i
          e = cmdnorm_qend(s, i, c, 1); cur = cur substr(s, i, e - i + 1); i = e; continue
        }
        if (c == "\\") { if (cur == "") cs = i; cur = cur c; i++; cur = cur substr(s, i, 1); continue }
        if (c == " " || c == "\t" || c == "\r" || c == "\n") {
          if (cur != "") { n++; T[n] = cur; K[n] = "W"; P[n] = cs; cur = "" }
          continue
        }
        if (c == ">" || (c == "&" && substr(s, i + 1, 1) == ">")) {
          # A NUMBERED STREAM: digits touching the operator are its stream, not a word.
          if (c == ">" && cur ~ /^[0-9]+$/) { st = cs; cur = "" }
          else { if (cur != "") { n++; T[n] = cur; K[n] = "W"; P[n] = cs; cur = "" }; st = i }
          op = ">"
          if (c == "&") { i++; op = "&>" }
          nx = substr(s, i + 1, 1)
          if (nx == ">") { op = op ">"; i++ }
          else if (nx == "|" && op == ">") { op = ">|"; i++ }
          else if (nx == "&" && op == ">") {
            j = i + 2; w = ""
            while (j <= L && substr(s, j, 1) ~ /[0-9]/) { w = w substr(s, j, 1); j++ }
            if (w == "" && substr(s, j, 1) == "-") { w = "-"; j++ }
            if (w != "" && (j > L || substr(s, j, 1) ~ /[ \t\r\n;&|<>()]/)) {
              n++; T[n] = substr(s, st, j - st); K[n] = "D"; P[n] = st; i = j - 1; continue
            }
            i++; op = ">&"
          }
          n++; T[n] = op; K[n] = "R"; P[n] = st; continue
        }
        if (c == "|" || c == "&" || c == ";" || c == "<" || c == "(" || c == ")") {
          if (cur != "") { n++; T[n] = cur; K[n] = "W"; P[n] = cs; cur = "" }
          nx = substr(s, i + 1, 1)
          n++; P[n] = i; K[n] = "O"; T[n] = c
          if (c == "|" && nx == "|") { K[n] = "OR"; T[n] = "||"; i++ }
          else if (c == "|" && nx == "&") { K[n] = "PA"; T[n] = "|&"; i++ }
          else if (c == "|") K[n] = "P"
          else if (c == "&" && nx == "&") { T[n] = "&&"; i++ }
          continue
        }
        if (cur == "") cs = i
        cur = cur c
      }
      if (cur != "") { n++; T[n] = cur; K[n] = "W"; P[n] = cs }
      cut = L + 1
      for (;;) {
        hit = 0
        if (n >= 2 && K[n] == "W" && K[n - 1] == "R") { cut = P[n - 1]; n -= 2; hit = 1 }
        else if (n >= 1 && K[n] == "D") { cut = P[n]; n--; hit = 1 }
        else if (n >= 2 && K[n] == "W" && T[n] == "true" && K[n - 1] == "OR") { cut = P[n - 1]; n -= 2; hit = 1 }
        else {
          for (k = n; k >= 1 && K[k] == "W"; k--) ;
          if (k >= 1 && k < n && (K[k] == "P" || K[k] == "PA") && T[k + 1] == "tee") { cut = P[k]; n = k - 1; hit = 1 }
        }
        if (!hit) break
      }
      return cmdnorm_ws(substr(s, 1, cut - 1))
    }
'

# ---------- A COMMAND NAME, READ THE WAY THE MACHINE RESOLVES IT (wave-25 T12) ----------
#
# THE ONE AWK RULE, pasted into every program `_cmd_class_awk` runs; its shell twin is
# `cmd_word_fold` in git-argv.sh, whose header states the rule in full. The default macOS
# filesystem is case-blind, so `BASH tests/run.sh` runs the suite, `TEE <path>` writes it and
# `RM <path>` deletes it, and every table below that matched the literal name read each of them
# as an unknown word. Every NAME a table recognises (the prefixes and runners the reader
# unwraps, the writers, deleters and pure readers, the suite, build and install runners) is
# compared to `cmd_word_fold` of the word, so the tables hold lower-case names only.
#
# WHAT IS NOT FOLDED: operands, paths, flags and subcommands, at the call sites (`npm TEST` is
# not `npm test`, and `bash TESTS/RUN.SH` names no suite this reader knows), and a script named
# at argv[0] by its path (`./tests/X.TEST.SH`), for the same reason its operand form is not. And,
# inside the fold itself, every word whose effect exists only as a shell builtin or keyword: an
# external program word folds, a builtin-only word does not, because the shell matches its own
# builtins case-exactly and hands only the rest to the case-blind filesystem. The never list is
# cd wait exec eval source pushd popd exit return and the reserved words; git-argv.sh
# `cmd_word_fold` holds the measured table of which names fall on each side.
#
# ASCII ONLY. macOS awk lower-cases a multibyte capital too (`tolower("É")` is `é`), so a word
# with anything outside printable ASCII is folded letter by letter from the 26-letter table.
# A word with no capital, the common case, costs one regex test and is returned as is.
#
# `cmd_head_fold` is the same rule for a TEXT whose first word is the command word (up to the
# first blank): that word folded and the rest untouched. IT NEVER RUNS A REGEX OVER THE TEXT.
# macOS awk walks a regex over the whole string even when it is anchored at `^` (measured: one
# `s ~ /^[^ \t]*[A-Z]/` on 655 KB costs 3.8 ms, a `substr` on it nothing measurable), so a fold
# that asked the text cost a pass per strip step, 50 ms a row on tests/hook-timeout.test.sh
# rows g to j. The word is cut out by `index`, and only the word meets a regex.
#
# NO APOSTROPHE MAY APPEAR IN THIS TEXT, for the reason CMD_RUN_NORM_AWK gives.
CMD_WORD_FOLD_AWK='
    function cmd_word_fold(w,   n, C, i, j, o) {
      if (w !~ /[ABCDEFGHIJKLMNOPQRSTUVWXYZ]/) return w
      if (w ~ /^[!-~]*$/) o = tolower(w)
      else {
        n = split(w, C, ""); o = ""
        for (i = 1; i <= n; i++) {
          j = index("ABCDEFGHIJKLMNOPQRSTUVWXYZ", C[i])
          o = o (j ? substr("abcdefghijklmnopqrstuvwxyz", j, 1) : C[i])
        }
      }
      if (o ~ /^(cd|pushd|popd|wait|exit|return|exec|eval|source|if|then|else|elif|fi|case|esac|for|select|while|until|do|done|in|function)$/) return w
      return o
    }
    function cmd_head_fold(s,   k, w) {
      k = index(s, " "); w = (k ? substr(s, 1, k - 1) : s)
      k = index(w, "\t"); if (k) w = substr(w, 1, k - 1)
      if (w !~ /[ABCDEFGHIJKLMNOPQRSTUVWXYZ]/) return s
      return cmd_word_fold(w) substr(s, length(w) + 1)
    }
'

# The awk program. `mode=heredoc` stops after step 1; `mode=lines` runs the whole reading.
_cmd_class_awk() {  # <mode> ; command on stdin
  # ONLY mode=effects PARSES _CMD_EFFECTS_AWK (wave-25 T2). awk compiles the whole program on
  # every call, and the effects reader is a fifth of this file: pasted into every mode it cost
  # each classifier call 1.7 ms (7.3 -> 9.0 ms, measured). The other modes get one-line stubs
  # of the six names the shared code calls, so each program defines every function once.
  local _fx="$_CMD_EFFECTS_STUBS"
  [ "$1" = effects ] && _fx="$_CMD_EFFECTS_AWK"
  awk -v mode="$1" "$CMD_RUN_NORM_AWK$CMD_WORD_FOLD_AWK$_CMD_WRITES_AWK$_fx"'
    function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function base(p) { sub(/.*\//, "", p); return p }
    # ONE RUN, ONE SPELLING (REQ-1 AC-1.5). The same collapse
    # `hooks/dispatch-preflight.sh` applies to an author-marked run before it writes it onto
    # the roster row (its `collapse()`), so a run typed with wider spacing here and a run
    # declared with narrower spacing there are the same string when the budget arm compares
    # them. Two collapses that disagreed would be a budget nobody could satisfy — which is
    # why both now call `cmdnorm_ws` out of CMD_RUN_NORM_AWK above rather than each typing it.
    function ws1(s) { return cmdnorm_ws(s) }
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
    # THE RUNNER S OWN RUN-NOTHING MODES (wave-24 T5, D12, AC-7.5). `tests/run.sh` with
    # `--dry-run`, `-h`, `--help` or `--list` prints and exits; it is not a suite run, so it
    # is class none and names nothing. Read anywhere after the script, the way LAST_DRY reads
    # `--dry-run`, because the runner takes its flags in any order. `--serial` is not here:
    # alone it is the full tree.
    function runsh_noop(a, from, n,   j) {
      for (j = from; j <= n; j++)
        if (a[j] == "--dry-run" || a[j] == "-h" || a[j] == "--help" || a[j] == "--list") return 1
      return 0
    }
    # WHICH `run.sh` IS THE RUNNER (wave-24 T24, REQ-7). Only the project s own: `tests/run.sh`,
    # `./tests/run.sh`, or a path ending `/tests/run.sh`. The basename alone said nothing, so a
    # scratch `<dir>/run.sh` or `scripts/run.sh` was refused as the full tree.
    function is_runner(p) {
      return (p == "tests/run.sh" || p ~ /\/tests\/run\.sh$/)
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
    #
    # EACH SEGMENT CARRIES THREE FACTS BESIDE ITS TEXT, in GLOBALS indexed like arr (wave-24
    # T5, D9/D12): SEPKIND, the control operator that CLOSED it (`;` `\n` `&&` `||` `|` `|&`
    # `&` `(` `)` `;;` `case`, or "" for the last); SEGGRP, the subshell group it sits in (0
    # outside any, GPAR the parent of each); ARMSTART, 1 on the first segment of a case arm.
    # Globals because only the END block reads them, once, right after its own top-level
    # call — before class_seg recurses into segments() and overwrites them.
    #
    # A CASE PATTERN LIST IS NOT A COMMAND (D12, REQ-7 AC-7.5). `case WORD in` at command
    # position switches to reading patterns: `(pat|pat)` up to its closing paren is consumed
    # as nothing, then the arm body segments as ordinary commands until `;;` (or `;&`,
    # `;;&`), and `esac` ends it. Before this, `pat)` stayed glued to the arm body, so a
    # suite named in a pattern sat at argv[0] and read as a run, while a suite run in a
    # body sat behind `case` and read as none.
    function seg_put(arr, text, sep) {
      arr[++SEG_K] = text
      SEPKIND[SEG_K] = sep
      SEGGRP[SEG_K] = GSTK[SEG_GD]
      ARMSTART[SEG_K] = SEG_ARM; SEG_ARM = 0
    }
    # Is cur (the text so far of the segment being built) still at COMMAND POSITION — empty,
    # or only the openers that precede a command? Only there is `case`/`esac` a keyword.
    function cmdpos(x) {
      sub(/^[ \t\r]+/, "", x)
      while (match(x, /^(do|then|else|elif|if|while|until|!|[{])[ \t\r]+/)) x = substr(x, RLENGTH + 1)
      return x == ""
    }
    # Reads one case pattern starting at j: returns the index just past its closing paren, or
    # sets SEG_ESAC and returns the index of the `esac` that ends the case instead.
    function case_pattern(s, j,   L, c, q, d) {
      L = length(s)
      while (j <= L && substr(s, j, 1) ~ /[ \t\r\n]/) j++
      if (substr(s, j, 4) == "esac" && (j + 4 > L || substr(s, j + 4, 1) ~ /[ \t\r\n;&|)<>]/)) {
        SEG_CASE--; SEG_ESAC = 1; return j
      }
      if (substr(s, j, 1) == "(") j++
      q = ""; d = 0
      for (; j <= L; j++) {
        c = substr(s, j, 1)
        if (q != "") { if (c == q) q = ""; else if (c == "\\" && q == "\"") j++; continue }
        if (c == "\047" || c == "\"") { q = c; continue }
        if (c == "\\") { j++; continue }
        if (c == "(") { d++; continue }
        if (c == ")") { if (d == 0) { SEG_ARM = 1; return j + 1 }; d--; continue }
      }
      return L + 1
    }
    function segments(s, arr,   i, j, c, L, e, cur, nx, pv, hdr) {
      L = length(s); cur = ""
      SEG_K = 0; SEG_GD = 0; GSTK[0] = 0; GID_N = 0; SEG_ARM = 0; SEG_CASE = 0; SEG_ESAC = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (c == "'"'"'" || c == "\"") { e = cmdnorm_qend(s, i, c, 1); cur = cur substr(s, i, e - i + 1); i = e; continue }
        if (c == "\\") { cur = cur c; i++; cur = cur substr(s, i, 1); continue }
        if (c == "c" && cmdpos(cur) && match(substr(s, i), /^case[ \t]+[^ \t\r\n;&|()<>]+[ \t\r\n]+in([ \t\r\n]|$)/)) {
          hdr = cur substr(s, i, RLENGTH); sub(/[ \t\r\n]+$/, "", hdr)
          j = i + RLENGTH
          seg_put(arr, hdr, "case"); cur = ""
          SEG_CASE++
          j = case_pattern(s, j)
          if (SEG_ESAC) { SEG_ESAC = 0; cur = "esac"; i = j + 3; continue }
          i = j - 1; continue
        }
        if (c == "e" && SEG_CASE > 0 && cmdpos(cur) && match(substr(s, i), /^esac([ \t\r\n;&|)<>]|$)/)) {
          SEG_CASE--; cur = cur "esac"; i += 3; continue
        }
        if (c == ";" && SEG_CASE > 0 && (substr(s, i + 1, 1) == ";" || substr(s, i + 1, 1) == "&")) {
          seg_put(arr, cur, ";;"); cur = ""
          i++; if (substr(s, i + 1, 1) == "&") i++
          j = case_pattern(s, i + 1)
          if (SEG_ESAC) { SEG_ESAC = 0; cur = "esac"; i = j + 3; continue }
          i = j - 1; continue
        }
        if (c == "(") {
          pv = (i > 1 ? substr(s, i - 1, 1) : "")
          if (pv != "$" && pv != "<" && pv != ">") {
            seg_put(arr, cur, "("); cur = ""
            SEG_GD++; GID_N++; GPAR[GID_N] = GSTK[SEG_GD - 1]; GSTK[SEG_GD] = GID_N
            continue
          }
          cur = cur c; continue
        }
        if (c == ")" && SEG_GD > 0) { seg_put(arr, cur, ")"); cur = ""; SEG_GD--; continue }
        if (c == "\n" || c == ";") { seg_put(arr, cur, c); cur = ""; continue }
        if (c == "&") {
          nx = substr(s, i + 1, 1); pv = (i > 1 ? substr(s, i - 1, 1) : "")
          if (nx == "&") { seg_put(arr, cur, "&&"); cur = ""; i++; continue }
          # a redirection, not a separator: 2>&1, >&2, &>log
          if (nx == ">" || pv == ">" || pv == "<") { cur = cur c; continue }
          # A BARE & IS THE ONLY ONE THAT BACKGROUNDS (D8, REQ-6). `&&` above closes a
          # segment too, but synchronously — nothing after it is detached.
          seg_put(arr, cur, "&"); cur = ""; continue
        }
        if (c == "|") {
          nx = substr(s, i + 1, 1)
          if (nx == "|" || nx == "&") { seg_put(arr, cur, "|" nx); cur = ""; i++; continue }
          seg_put(arr, cur, "|"); cur = ""; continue
        }
        cur = cur c
      }
      seg_put(arr, cur, "")
      return SEG_K
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
    function strip_leading(s,   t, h) {
      s = trim(s)
      for (;;) {
        t = s
        if (match(s, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
          s = trim(consume_value(s, RLENGTH + 1))
        } else if (match(s, /^[({})!][ \t]*/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^(then|else|elif|do|done|fi|if|while|until|env|command|exec)([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        # FROM HERE ON A NAME, matched on h, the head folded (wave-25 T12, see CMD_WORD_FOLD_AWK).
        # The fold keeps every length, so RLENGTH cuts s where it cut h, and what comes off is
        # always the text as typed. The arm above reads as typed: a reserved word is no name, exec
        # is a builtin the fold never touches, and a lower-case env or command is its own fold.
        # Only a head the fold changed is
        # asked about those three again, so a lower-case command pays no extra regex pass here
        # (each one walks the whole text in macOS awk). The assignment and the redirection are
        # no names either.
        } else if ((h = cmd_head_fold(s)) != s && match(h, /^(env|command|exec)([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(h, /^(nohup|setsid)([ \t]+|$)/)) {
          # A WRAPPER, NOT JUST AN OPENER (D8, REQ-6). Stripped the same way env/exec are —
          # setsid NOW JOINS nohup so `setsid bash tests/run.sh` reaches the bash/sh arm
          # instead of falling through to none with argv[0]=setsid — but the strip also
          # SETS A FLAG, because cmd_backgrounded (below) needs to know a wrapper was here
          # even though classify_argv never sees the word again. One reading, two answers.
          SAW_WRAPPER = 1
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(h, /^time([ \t]+-p)?([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(h, /^nice([ \t]+(-n[ \t]*[0-9]+|-[0-9]+|--adjustment[= \t][ \t]*[0-9]+))?([ \t]+|$)/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(h, /^(sudo|doas)([ \t]+|$)/)) {
          s = skip_opts(trim(substr(s, RLENGTH + 1)), " -u -g -p -U -C -r -t -h -D -R ")
        } else if (match(h, /^xargs([ \t]+|$)/)) {
          s = skip_opts(trim(substr(s, RLENGTH + 1)), " -I -i -n -L -P -s -E -a -d --replace --max-args --max-procs --max-lines --arg-file --delimiter --eof ")
        } else if (match(h, /^ssh([ \t]+|$)/)) {
          s = drop_word(skip_opts(trim(substr(s, RLENGTH + 1)), " -o -p -i -l -F -L -R -D -b -c -e -m -O -Q -S -W -w -J -E -B -I "))
        } else if (match(h, /^(find|[^ \t]*\/find)([ \t]+|$)/)) {
          s = after_exec(s)
        } else if (match(h, /^g?timeout[ \t]+(-[^ \t]+[ \t]+)*[0-9]+[smhd]?[ \t]+/)) {
          s = trim(substr(s, RLENGTH + 1))
        } else if (match(s, /^[0-9]*(&>>|&>|>>|>[|]|>&|<&|<>|<|>)/)) {
          # A LEADING REDIRECTION IS PLUMBING, glued (`<tests/a.test.sh wc -l`) or detached
          # (`2> log bash tests/a.test.sh`): the operator and its one target word come off,
          # quoted target included, so argv[0] never begins with `<` or `>` (wave-24 T5,
          # D12, AC-7.6). Without it the glued READ put a suite path at argv[0] and read as
          # a run of it, and a redirect in FRONT of a real run hid the run behind argv[0].
          s = trim(substr(s, RLENGTH + 1))
          if (s != "") s = trim(consume_value(s, 1))
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
    # The runner and the reader are names, matched on the folded head (CMD_WORD_FOLD_AWK); the
    # string, the flags and the file come off s as typed.
    function unwrap_runner(s,   inner, j, h) {
      h = cmd_head_fold(s)
      if (match(h, /^(ba|z|k|da)?sh[ \t]+-[a-z]*c[ \t]+/))
        return dequote_whole(substr(s, RLENGTH + 1))
      if (match(h, /^eval[ \t]+/))
        return dequote_whole(substr(s, RLENGTH + 1))
      # `bash <(cat FILE)` is `bash FILE` with a reader in the way; collapse to the script
      # that actually runs, or the workaround walks straight past the suite arm.
      if (match(h, /^(ba)?sh[ \t]+<\(/)) {
        inner = substr(s, RLENGTH + 1)
        j = index(inner, ")")
        if (j > 0) inner = substr(inner, 1, j - 1)
        if (match(cmd_head_fold(inner), /^(cat|tac)[ \t]+/)) inner = substr(inner, RLENGTH + 1)
        return "bash " trim(inner)
      }
      return s
    }

    # ---------- 4. argv ----------
    # A token quoted around whitespace is prose: it becomes \001, which matches nothing.
    function argv_tok(s, a,   i, L, c, e, t, cur, k, spaced, started) {
      L = length(s); cur = ""; k = 0; spaced = 0; started = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        # No escape inside quotes here: this reader never honoured one, and still does not.
        if (c == "'"'"'" || c == "\"") {
          e = cmdnorm_qend(s, i, c, 0); t = substr(s, i + 1, e - i - 1)
          if (t ~ /[ \t]/) spaced = 1
          cur = cur t; started = 1; i = e; continue
        }
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
    function classify_argv_read(s,   a, n, i, a1, a2, b0, b1, npxshift, n0) {
      LAST_TARGET = ""; LAST_PATH = ""; LAST_DRY = 0
      n = argv_tok(s, a)
      if (n == 0) return "none"
      # `--dry-run` IS A MODE THAT RUNS NOTHING (the walk, A-36a; critic K-2). It is read
      # off the whole segment rather than off argv[1], because the runner takes it after
      # the script and a reader that insisted on a position would miss the one spelling
      # anybody types. The CLASS is untouched: the command still runs the runner.
      for (i = 1; i <= n; i++) if (a[i] == "--dry-run") LAST_DRY = 1
      # b0 is the word as typed, for the arms that read a SCRIPT FILE by its name; n0 is its fold
      # (CMD_WORD_FOLD_AWK), for every arm that reads a command NAME (wave-25 T12).
      b0 = base(a[1]); n0 = cmd_word_fold(b0)
      # A PACKAGE RUNNER IS A PREFIX, NOT A COMMAND (REQ-1 AC-1.5). `npx jest …` runs jest
      # and spends what a jest run spends; `npx create-react-app x` runs something else
      # entirely, and the tier-2 nudge is the wall that speaks for those. The prefix comes
      # off HERE, inside the argv reading, and deliberately not in `strip_leading`: that
      # function feeds `cmd_unwrap_head`, whose whole job is to hand the farm-out nudge the
      # `npx …` head it matches on (B-4a), and stripping it there would take the nudge s
      # subject away from it.
      npxshift = 0
      if (n0 == "npx" || n0 == "bunx" || n0 == "pnpx") npxshift = 1
      else if ((n0 == "npm" || n0 == "pnpm" || n0 == "yarn" || n0 == "bun") && n >= 2 && (a[2] == "dlx" || a[2] == "exec")) npxshift = 2
      if (npxshift > 0 && n > npxshift) {
        for (i = 1; i + npxshift <= n; i++) a[i] = a[i + npxshift]
        n = n - npxshift
        b0 = base(a[1]); n0 = cmd_word_fold(b0)
      }
      if (n0 == "bash" || n0 == "sh" || n0 == "zsh" || n0 == "dash" || n0 == "ksh") {
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
        if (b1 == "run.sh" && (is_runner(a1) || (a1 == "run.sh" && CD_SEEN))) {
          if (runsh_noop(a, i + 1, n)) return "none"
          LAST_TARGET = b1; LAST_PATH = a1; return "suite"
        }
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
      if (index(a[1], "/") > 0 && ((b0 == "run.sh" && is_runner(a[1])) || b0 == "test.sh" || b0 ~ /\.test\.sh$/)) {
        if (b0 == "run.sh" && runsh_noop(a, 2, n)) return "none"
        LAST_TARGET = b0
        LAST_PATH = a[1]
        return "suite"
      }
      if (n0 == "pytest") return "suite"
      # `jest` NAMED, the runner the seed and D1 are about. Bare, or behind the `npx`
      # prefix dropped above — both are one run of one project s tests.
      if (n0 == "jest") return "suite"
      if (n0 == "npm" || n0 == "pnpm" || n0 == "yarn") {
        if (a1 == "test") return "suite"
        if (a1 == "install" || a1 == "add" || a1 == "ci") return "install"
        if (a1 == "run" && a2 == "build") return "build"
        return "none"
      }
      if (n0 == "go" || n0 == "cargo") {
        if (a1 == "test") return "suite"
        if (a1 == "build") return "build"
        return "none"
      }
      # `make clean` is trivial and stays silent; `make test`/`make check` are the suite;
      # bare `make` and every other target is a build.
      if (n0 == "make") {
        if (a1 == "test" || a1 == "check") return "suite"
        if (a1 == "clean") return "none"
        return "build"
      }
      if (n0 == "pip" || n0 == "pip3") return (a1 == "install" ? "install" : "none")
      if (n0 == "uv")   return ((a1 == "sync" || a1 == "pip") ? "install" : "none")
      if (n0 == "brew") return (a1 == "install" ? "install" : "none")
      if (n0 == "docker") return (a1 == "build" ? "build" : "none")
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
    #
    # THE RUN IS NORMALISED, NOT MERELY COLLAPSED (wave-20 T4; REQ-7, D7). `cmdnorm_run`
    # takes the segment`s trailing redirections off, so `npx jest x 2>&1` and
    # `npx jest x > log 2>&1` claim the run `npx jest x` — the run the brief declared. The
    # class reading below still sees the whole segment: what a command IS was never a
    # question its redirections could change.
    function classify_argv(s,   c) {
      LAST_RUN = cmdnorm_run(s)
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

    # ---------- 5. compound structure (wave-24 T5, D9/D12) ----------
    # One pass over the top-level segments that gives each one an INSTANCE: the branch of
    # the compound commands it sits in. `if`/`while`/`until`/`for`/`select`/`case` open a
    # child instance; `then`/`else`/`elif`/`do` and each case arm start a SIBLING of the
    # current one; `fi`/`done`/`esac` close it. Instance A is an ancestor of B exactly when
    # every run of B also ran A first — which is the one question both readers below ask:
    # does this `wait` cover that job, does this assignment reach that use. CI[i] is the
    # instance, HEAD[i] the segment with its branch keywords taken off. A `for V in w…`
    # header also opens a FRAME (FVAR, FWORDS, FOK, FSTART, FEND) for the expansion pass.
    function kw_branch() {
      INST_N++; IPAR[INST_N] = IPAR[ISTK[ISP]]; ISTK[ISP] = INST_N
    }
    function inst_anc(a, b) {
      while (b != 0) { if (b == a) return 1; b = IPAR[b] }
      return 0
    }
    function grp_anc(a, b) {
      for (;;) { if (b == a) return 1; if (b == 0) return 0; b = GPAR[b] }
    }
    # A literal word, or "" — dequoted when wholly quoted. Only these characters, so a
    # value can never carry a glob, an expansion or a separator into the text it replaces.
    function litword(w) {
      w = dequote_whole(w)
      return (w ~ /^[A-Za-z0-9._\/-]+$/ ? w : "")
    }
    function compound_pass(k, sg,   i, t, h, hv, rest, nw, W, x, lw) {
      INST_N = 1; IPAR[1] = 0; ISP = 0; ISTK[0] = 1; NF = 0
      for (i = 1; i <= k; i++) {
        t = trim(sg[i])
        if (ARMSTART[i] && ISP > 0) kw_branch()
        if (match(t, /^(done|fi|esac)([ \t;&|<>)]|$)/) && ISP > 0) {
          if (ICK[ISP] > 0) FEND[ICK[ISP]] = i
          ISP--
        }
        h = t
        for (;;) {
          if (match(h, /^(then|else|elif|do)([ \t]+|$)/)) {
            if (ISP > 0) kw_branch()
            h = trim(substr(h, RLENGTH + 1))
          } else if (match(h, /^[{][ \t]*/)) {
            h = trim(substr(h, RLENGTH + 1))
          } else break
        }
        if (match(h, /^(if|while|until|for|select|case)([ \t]+|$)/)) {
          INST_N++; IPAR[INST_N] = ISTK[ISP]; ISP++; ISTK[ISP] = INST_N; ICK[ISP] = 0
          if (h ~ /^for[ \t]/) {
            NF++; ICK[ISP] = NF; FSTART[NF] = i; FEND[NF] = k + 1; FOK[NF] = 0; FWORDS[NF] = ""
            if (match(h, /^for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in([ \t]|$)/)) {
              rest = substr(h, RLENGTH + 1)
              hv = h; sub(/^for[ \t]+/, "", hv); match(hv, /^[A-Za-z_][A-Za-z0-9_]*/)
              FVAR[NF] = substr(hv, 1, RLENGTH)
              nw = split(trim(rest), W, /[ \t]+/)
              FOK[NF] = (nw >= 1)
              for (x = 1; x <= nw; x++) {
                lw = litword(W[x])
                if (lw == "") FOK[NF] = 0
                FWORDS[NF] = FWORDS[NF] (x > 1 ? " " : "") lw
              }
            }
          }
        }
        CI[i] = ISTK[ISP]; HEAD[i] = h
      }
    }

    # ---------- 6. literal expansion (wave-24 T5, D9, REQ-6 AC-6.3/6.4) ----------
    # The budget arm reads the command TEXT, so `for s in a b; do bash tests/$s.test.sh;
    # done` reached it as one unresolvable `$s.test.sh` and was refused — and
    # `X=a.test.sh; bash tests/$X` reached it as class none and was never budgeted at all.
    # A variable whose every value is visible in the text is resolved here, each segment
    # that names it read once per value, and anything less certain is left as `$` text for
    # the unexpanded-name refusal to speak about. RESOLVED, exactly when:
    #   * a `for V in w…` loop whose every word is literal, for the segments of its body,
    #     when no body segment ASSIGNS V (below);
    #   * one standalone `V=<literal>` segment closed by `;`, `&&` or a newline and not
    #     opened by `||` or a pipe, which is the ONLY assignment of V anywhere in the
    #     command, for the segments after it that it reaches (same subshell group or a
    #     child of it, same branch or a child of it). A prefix `V=x cmd $V` is never one:
    #     the shell expands `$V` before the prefix takes effect.
    # NEVER RESOLVED in a command that defines a function, runs eval/source/`.`, assigns
    # IFS, or declares a nameref — each can assign a variable no text here names.
    # Checking the resolved set is a SUPERSET of what runs (break/continue only shrink it),
    # so the budget guarantee holds (research R3 Q1).
    function assigns(t, V,   h, u, A, n, x, a0) {
      if (match(t, "(^|[ \t;&|(){}!])" V "[=+[]")) return 1
      if (index(t, "${" V "=") || index(t, "${" V ":=")) return 1
      h = trim(t)
      while (match(h, /^(then|else|elif|do|[{])([ \t]+|$)/)) h = trim(substr(h, RLENGTH + 1))
      if (match(h, "^(for|select)[ \t]+" V "([ \t;]|$)")) return 1
      u = strip_leading(h)
      n = argv_tok(u, A); a0 = A[1]
      if (a0 ~ /^(read|mapfile|readarray|unset|declare|typeset|local|export|readonly|printf|getopts)$/)
        for (x = 2; x <= n; x++) if (A[x] == V || A[x] == "-v" V) return 1
      return 0
    }
    function expand_unsafe(k, sg, all,   j, u, A, n, x) {
      if (all ~ /(^|[^A-Za-z0-9_])IFS=/) return 1
      if (all ~ /[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*\)/ || all ~ /(^|[ \t;&|])function[ \t]/) return 1
      for (j = 1; j <= k; j++) {
        u = strip_leading(HEAD[j])
        n = argv_tok(u, A)
        if (A[1] == "eval" || A[1] == "source" || A[1] == ".") return 1
        if (A[1] ~ /^(declare|typeset|local)$/)
          for (x = 2; x <= n; x++) if (A[x] ~ /^-[A-Za-z]*n/) return 1
      }
      return 0
    }
    # s with every unquoted-or-double-quoted `$V` / `${V}` replaced by w. Single quotes
    # and a backslash keep the shell from expanding, so they keep this from it too.
    function subst(s, V, w,   L, lv, i, c, q, out) {
      L = length(s); lv = length(V); q = ""; out = ""
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (q == "\047") { out = out c; if (c == q) q = ""; continue }
        if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
        if (c == "\"") { q = (q == "" ? c : ""); out = out c; continue }
        if (c == "\047" && q == "") { q = c; out = out c; continue }
        if (c == "$") {
          if (substr(s, i + 1, lv + 2) == "{" V "}") { out = out w; i += lv + 2; continue }
          if (substr(s, i + 1, lv) == V && substr(s, i + 1 + lv, 1) !~ /[A-Za-z0-9_]/) { out = out w; i += lv; continue }
        }
        out = out c
      }
      return out
    }
    # NX[i] texts XT[i, 1..NX[i]] per segment: the segment itself, or one per value.
    function expand_all(k, sg, all,   i, j, f, h, V, val, pv, nc, AV, AJ, AL, na, x, y, nx, nn, X, Y, W, nw, BV, BL, nb, over, b) {
      for (i = 1; i <= k; i++) { NX[i] = 1; XT[i, 1] = sg[i] }
      if (index(all, "$") == 0) return
      na = 0
      for (j = 1; j <= k; j++) {
        h = HEAD[j]
        if (!match(h, /^[A-Za-z_][A-Za-z0-9_]*=/)) continue
        V = substr(h, 1, RLENGTH - 1); val = litword(substr(h, RLENGTH + 1))
        if (val == "") continue
        if (SEPKIND[j] != ";" && SEPKIND[j] != "\n" && SEPKIND[j] != "&&") continue
        pv = (j > 1 ? SEPKIND[j - 1] : "")
        if (pv == "||" || pv == "|" || pv == "|&" || pv == ")") continue
        # mode=effects: after `cmd &&` the variable may keep a value from the environment.
        if (FX && pv == "&&") continue
        na++; AV[na] = V; AJ[na] = j; AL[na] = val
      }
      if (NF == 0 && na == 0) return
      if (expand_unsafe(k, sg, all)) return
      for (f = 1; f <= NF; f++)
        if (FOK[f]) for (j = FSTART[f] + 1; j < FEND[f] && j <= k; j++) if (assigns(sg[j], FVAR[f])) { FOK[f] = 0; break }
      for (x = 1; x <= na; x++) {
        nc = 0
        for (j = 1; j <= k; j++) if (assigns(sg[j], AV[x])) nc++
        if (nc != 1) AJ[x] = 0
      }
      for (i = 1; i <= k; i++) {
        split("", BV); nb = 0
        for (f = 1; f <= NF; f++)
          if (FOK[f] && FSTART[f] < i && i < FEND[f]) {
            if (!(FVAR[f] in BV)) BL[++nb] = FVAR[f]
            BV[FVAR[f]] = FWORDS[f]
          }
        for (x = 1; x <= na; x++) {
          j = AJ[x]; V = AV[x]
          if (j == 0 || j >= i || (V in BV)) continue
          if (!grp_anc(SEGGRP[j], SEGGRP[i]) || !inst_anc(CI[j], CI[i])) continue
          BL[++nb] = V; BV[V] = AL[x]
        }
        if (nb == 0) continue
        nx = 1; X[1] = sg[i]; over = 0
        for (b = 1; b <= nb; b++) {
          V = BL[b]
          if (!index(sg[i], "$" V) && !index(sg[i], "${" V "}")) continue
          nw = split(BV[V], W, " ")
          if (nx * nw > 64) { over = 1; break }
          nn = 0
          for (x = 1; x <= nx; x++) for (y = 1; y <= nw; y++) Y[++nn] = subst(X[x], V, W[y])
          nx = nn
          for (x = 1; x <= nx; x++) X[x] = Y[x]
        }
        if (over) continue
        NX[i] = nx
        for (x = 1; x <= nx; x++) XT[i, x] = X[x]
      }
    }

    # ---------- 7. the loop header as the lines to run (wave-24 T13, D10, AC-6.3) ----------
    # The unexpanded-name refusal prints what a loop WOULD have run, spelled literally, and
    # this is the one reading of the header it prints from: each segment inside a `for V in
    # w...` frame whose words are all literal is read once per word with V put in, and every
    # reading that names a suite FILE gives one `bash <path>` line, the path as the body
    # spelled it. A BODY THAT ASSIGNS V (`assigns`, section 6) runs something other than the
    # words of the header, so a segment naming V inside that frame gives no line at all (wave-24
    # T26): printing the words would hand the reader a fix the loop never ran. Called before
    # expand_all, so FOK still means "every word is literal".
    function loop_lines(k, sg,   i, j, f, V, W, nw, X, Y, nx, nn, x, y, hit, over, t, seen, RE) {
      for (f = 1; f <= NF; f++)
        for (j = FSTART[f] + 1; j < FEND[f] && j <= k; j++) if (assigns(sg[j], FVAR[f])) { RE[f] = 1; break }
      for (i = 1; i <= k; i++) {
        if (index(sg[i], "$") == 0) continue
        nx = 1; X[1] = sg[i]; hit = 0; over = 0
        for (f = 1; f <= NF; f++) {
          if (!FOK[f] || FSTART[f] >= i || i >= FEND[f]) continue
          V = FVAR[f]
          if (!index(X[1], "$" V) && !index(X[1], "${" V "}")) continue
          if (f in RE) { over = 1; break }
          nw = split(FWORDS[f], W, " ")
          if (nx * nw > 64) { over = 1; break }
          nn = 0
          for (x = 1; x <= nx; x++) for (y = 1; y <= nw; y++) Y[++nn] = subst(X[x], V, W[y])
          nx = nn
          for (x = 1; x <= nx; x++) X[x] = Y[x]
          hit = 1
        }
        if (over || !hit) continue
        for (x = 1; x <= nx; x++) {
          LAST_TARGET = ""; LAST_KIND = ""; LAST_PATH = ""
          if (class_seg(trim(X[x]), 0) != "suite" || LAST_KIND != "file") continue
          if (LAST_PATH == "" || index(LAST_PATH, "$") || index(LAST_PATH, "`")) continue
          t = "bash " LAST_PATH
          if (!(t in seen)) { seen[t] = 1; print t }
        }
      }
    }

    { line[++nl] = $0 }
    END {
      out = ""; intag = 0; tag = ""
      for (i = 1; i <= nl; i++) {
        if (intag) {
          if (trim(line[i]) == tag) intag = 0
          # mode=effects: a body under an UNQUOTED tag runs its command substitutions.
          else if (hdx && FX_HDSEG == "" && (index(line[i], "$(") || index(line[i], "`"))) FX_HDSEG = hdl
          continue
        }
        out = out line[i] "\n"
        tag = heredoc_tag(line[i])
        if (tag != "") {
          intag = 1; hdx = 0; hdl = line[i]
          # mode=effects: a delimiter that is more than the word read here (`<<"E F"`, `<<E-X`)
          # ends its body somewhere else, so the lines stripped below may be commands.
          # So does an opener a comment or an open quote holds, which the shell never opens.
          if (mode == "effects") {
            hdx = !match(line[i], "<<-?[ \t]*[\047\"\\\\]" tag)
            if (FX_HDODD == "" && (!match(line[i], "<<-?[ \t]*(" tag "|\047" tag "\047|\"" tag "\"|\\\\" tag ")([ \t;&|<>)]|$)") \
                || index(substr(line[i], 1, index(line[i], "<<")), "#") \
                || fx_open_quote(substr(out, 1, length(out) - length(line[i]) - 1)))) FX_HDODD = line[i]
          }
        }
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
        # Its command word folded (wave-25 T12), so the tier-2 matcher compares a name to a name.
        # An option left at the front (env -C keeps its own here) is a flag, and never folds.
        hd0 = strip_leading(unwrap_runner(hd1))
        printf "%s", (substr(hd0, 1, 1) == "-" ? hd0 : cmd_head_fold(hd0))
        exit
      }
      # mode=bg: cmd_backgrounded (D8, REQ-6) — "1" when the TEXT backgrounds the
      # command, "0" otherwise. TOP-LEVEL ONLY, no class_seg/unwrap_runner recursion:
      # every AC-6 form types the wrapper or the trailing `&` where segments() already
      # sees it, and going deeper (through an sh -c layer, say) would answer a question
      # nobody asked yet — this predicate reads backgrounding, not suite-ness, and
      # `cmd_class` already owns the "is this a suite at all" half.
      #
      # A JOB THAT IS WAITED FOR IS NOT BACKGROUNDED (wave-24 T5, D12, AC-7.3). A bare `&`
      # starts a job PENDING in its subshell group and branch; it stops pending at a bare
      # `wait` (no operand) in the SAME group whose branch is the job`s or an ancestor of
      # it, reached unconditionally (not after `&&`/`||`/a pipe) and not itself a pipeline
      # stage or `&`-closed. A job still pending when the command ends backgrounds it. So
      # `a & b & wait` and `(a & b & wait)` are foreground, while `(a &); wait`,
      # `a & false && wait`, `a & wait | cat`, `a & p=$!; wait $p` and a wait inside an
      # `if` the job is not in all still read backgrounded. `wait $p` is not trusted to
      # clear: the text cannot prove `$p` names every job (research R4 §2, Q2).
      if (mode == "bg") {
        k = segments(out, bgseg)
        compound_pass(k, bgseg)
        bg = 0; np = 0
        for (i = 1; i <= k; i++) {
          t = trim(bgseg[i])
          if (t != "") {
            SAW_WRAPPER = 0
            strip_leading(t)
            if (SAW_WRAPPER) bg = 1
          }
          if (SEPKIND[i] == "&") { np++; PG[np] = SEGGRP[i]; PI[np] = CI[i]; PL[np] = 1; continue }
          if (HEAD[i] != "wait" || SEPKIND[i] == "|" || SEPKIND[i] == "|&") continue
          pv = (i > 1 ? SEPKIND[i - 1] : "")
          if (pv == "&&" || pv == "||" || pv == "|" || pv == "|&") continue
          for (p = 1; p <= np; p++)
            if (PL[p] && PG[p] == SEGGRP[i] && inst_anc(CI[i], PI[p])) PL[p] = 0
        }
        for (p = 1; p <= np; p++) if (PL[p]) bg = 1
        printf "%s", (bg ? "1" : "0")
        exit
      }
      # mode=writes: cmd_write_targets (wave-24 T12, D16) — the paths the command writes,
      # one per line, read by the functions in _CMD_WRITES_AWK above.
      if (mode == "writes") {
        WT_BASE = ENVIRON["_CMD_WT_CWD"]; split("", WT_SEEN)
        wt_run(out, "", 0)
        exit
      }
      # mode=effects: cmd_effects (wave-25 T2, D5) — the W, D and ? lines of _CMD_EFFECTS_AWK,
      # read by the writes walk with FX set, which routes each segment to fx_seg.
      if (mode == "effects") {
        FX = 1; fx_init(); FXR = (ENVIRON["_CMD_FX_READS"] == "reads")
        WT_BASE = ENVIRON["_CMD_WT_CWD"]; split("", WT_SEEN); split("", FX_SEEN)
        if (FX_HDSEG != "") fx_unk("a heredoc body runs a command substitution", FX_HDSEG)
        if (FX_HDODD != "") fx_unk("a heredoc the reader does not place", FX_HDODD)
        wt_run(out, "", 0)
        exit
      }
      k = segments(out, seg)
      compound_pass(k, seg)
      # mode=looplines: cmd_suite_loop_lines (wave-24 T13) — section 7, ahead of expand_all.
      if (mode == "looplines") { loop_lines(k, seg); exit }
      expand_all(k, seg, out)
      CD_SEEN = 0
      for (i = 1; i <= k; i++) {
        t0 = trim(seg[i])
        if (t0 == "") continue
        # ONE READING PER RESOLVED VALUE (section 6): the segment itself when it names no
        # variable this command pins, else once for each value it can take.
        for (x = 1; x <= NX[i]; x++) {
          t = trim(XT[i, x])
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
        }
        # Left-to-right, so a cd only licenses the basename form in the
        # segments that FOLLOW it.
        if (is_cd(t0)) CD_SEEN = 1
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

cmd_run_norm() {  # <command> -> the run it makes: trailing redirections, tee and || true off
  # THE ONE RULE, as a shell function, for a caller holding a whole command rather than an
  # awk program — the tests' spelling table, and the remedy text walls.sh builds. See
  # CMD_RUN_NORM_AWK above for what comes off and why only at the end.
  printf '%s' "${1-}" | awk "$CMD_RUN_NORM_AWK"'
    { a[++n] = $0 }
    END { s = ""; for (i = 1; i <= n; i++) s = s (i > 1 ? "\n" : "") a[i]; printf "%s", cmdnorm_run(s) }'
}

cmd_runs_norm() {  # <re_executes field, decoded> -> the same field, each marked run normalised
  # THE DECLARED SIDE OF THE COMPARE (wave-20 T4; REQ-7, D7). walls.sh decodes the row`s
  # `re_executes=` once per hook call and hands the result here, so the rule that built the
  # claim is the rule that reads the declaration. The field keeps the author`s backtick
  # marks, space-joined (A-T1.4), and that is what comes back: each run normalised INSIDE its
  # own marks, marks kept, one space between. A mark that never closes is not a run, the
  # same reading `_run_is_declared` gives it.
  #
  # THE FORK IS SKIPPED WHEN THE RULE HAS NOTHING TO DO. Every character the rule can act on
  # is one of `>`, `|` or `&`, or a run of whitespace a collapse would shorten; a field with
  # none of them is already normal, and the lift writes every field collapsed. The test is
  # the crude one on purpose, in the posture `cmd_strip_heredocs` takes: when in doubt, ask awk.
  case "${1-}" in
    *'>'*|*'|'*|*'&'*|*'  '*|*$'\t'*|*$'\n'*|*$'\r'*) : ;;
    *) printf '%s' "${1-}"; return 0 ;;
  esac
  printf '%s' "$1" | awk "$CMD_RUN_NORM_AWK"'
    { a[++n] = $0 }
    END {
      s = ""; for (i = 1; i <= n; i++) s = s (i > 1 ? "\n" : "") a[i]
      out = ""
      for (;;) {
        j = index(s, "`"); if (j == 0) break
        s = substr(s, j + 1)
        j = index(s, "`"); if (j == 0) break
        r = "`" cmdnorm_run(substr(s, 1, j - 1)) "`"
        s = substr(s, j + 1)
        out = (out == "" ? r : out " " r)
      }
      printf "%s", out
    }'
}

# ---------- WHAT A COMMAND WRITES (wave-24 T12; REQ-3, D16) ----------
#
# WHY A READING AND NOT A MATCH. The memory wall (payload/scripts/lib/walls.sh
# `wall_memory_store`) must refuse a write into the auto-memory store and admit every READ of
# it — and the run's own audit reads it with a redirect: `{ find <store> -newer m; } >
# record/x.txt` names the store and writes, but writes elsewhere. The incident it exists for
# named the store only in a `cd` and wrote bare basenames after it. So the answer is the
# PATHS a command writes, resolved, read with this file's own segmentation, heredoc removal,
# unwrapping and literal expansion.
#
# WHAT COUNTS AS A WRITE: the target of every redirect that opens a file for writing (`>`,
# `>>`, `>|`, `&>`, `&>>`, `<>`, `>&word`, a numbered stream); and the file arguments of
# `tee`, `sed -i`/`--in-place`, `touch`, `mkdir`, `ln` (the link), and the destination of `cp`
# and `mv` (the last operand, or `-t`/`--target-directory`). `rm` is not a write: removing a
# file stores nothing. A duplication (`2>&1`, `>&-`) names no file.
#
# RESOLUTION. `~`, `$HOME`, `${HOME}`, `$BIONIC_CLAUDE_HOME` and `$CLAUDE_CONFIG_DIR` (bare or
# braced) at the front of a word expand from the environment; one that is unset stays literal.
# A relative target joins the directory the last `cd`/`pushd` in its own subshell group named
# (`cd` alone is `~`; `cd -` and `popd` are a directory the text cannot name), and failing
# that the payload cwd the caller passes. `.` and `..` fold lexically, as
# hooks/canonical-sdlc-governing-skill.sh `fold_dots` folds them.
#
# DECLARED LIMITS. A target reached through a glob, a variable the text does not pin, `$'…'`,
# an interpreter (`python3 -c`, a heredoc fed to one) or a symlink is not seen; neither are
# `dd of=`, `install` or `perl -i`. Over-inclusion is the safe side of every guess here: a
# BSD `sed -i <suffix>` reads its suffix as the script and the script as a file.
#
# NO APOSTROPHE MAY APPEAR IN THIS TEXT, for the reason CMD_RUN_NORM_AWK gives.
_CMD_WRITES_AWK='
    # A double-quoted run without its escapes: a backslash hides the character after it and
    # is dropped, and one with nothing after it (the command ended inside the quote) stays.
    # One split, and the pieces joined in halves: appending them in turn would copy the
    # growing word once per backslash. The separator is a REGEX on purpose: macOS awk splits
    # on newline as well as on a one-character string separator, which loses every line
    # break of a multi-line body.
    function wt_unesc(r,   P, np, x, Q, m) {
      np = split(r, P, /\\/); m = 1; Q[1] = P[1]
      for (x = 2; x <= np; x++) {
        if (P[x] == "" && x < np) { Q[++m] = "\\"; x++; Q[++m] = P[x] }
        else if (P[x] == "") Q[++m] = "\\"
        else Q[++m] = P[x]
      }
      return wt_join(Q, 1, m)
    }
    function wt_join(Q, lo, hi,   h) {
      if (lo == hi) return Q[lo]
      h = int((lo + hi) / 2)
      return wt_join(Q, lo, h) wt_join(Q, h + 1, hi)
    }
    # Words of one segment, dequoted, beside a kind: W a word, R a write redirect (the next
    # word is its file), I an input redirect (the next word is consumed), D a duplication.
    #
    # A QUOTED RUN IS FOUND, NEVER WALKED (wave-24 T28), as T22 made it in segments() and
    # cmdnorm_run: cmdnorm_qend finds the close and one substr copies the run. Walking it a
    # character at a time cost a whole-string substr per character and a whole-word copy per
    # append, so a 207 KB quoted command took 12.5 s here, past the hook timeout of 10 s.
    function wt_tok(s, W, K,   L, i, c, cur, n, st, nx, j, w, e, r) {
      L = length(s); cur = ""; n = 0; st = 0
      for (i = 1; i <= L; i++) {
        c = substr(s, i, 1)
        if (c == "\047" || c == "\"") {
          e = cmdnorm_qend(s, i, c, 1); r = substr(s, i + 1, e - i - 1)
          if (c == "\"" && index(r, "\\") > 0) r = wt_unesc(r)
          cur = cur r; st = 1; i = e; continue
        }
        if (c == "\\") { i++; cur = cur substr(s, i, 1); continue }
        if (c == " " || c == "\t" || c == "\r" || c == "\n") {
          if (cur != "" || st) { W[++n] = cur; K[n] = "W" }
          cur = ""; st = 0; continue
        }
        if (c == ">" || (c == "&" && substr(s, i + 1, 1) == ">") || c == "<") {
          if (c != "&" && cur ~ /^[0-9]+$/ && !st) cur = ""
          if (cur != "" || st) { W[++n] = cur; K[n] = "W" }
          cur = ""; st = 0
          nx = substr(s, i + 1, 1)
          if (c == "<") {
            if (nx == ">") { W[++n] = "<>"; K[n] = "R"; i++; continue }
            if (nx == "&") { i++; while (substr(s, i + 1, 1) ~ /[0-9-]/) i++; W[++n] = "<&"; K[n] = "D"; continue }
            if (nx == "<") { i++; if (substr(s, i + 1, 1) == "<" || substr(s, i + 1, 1) == "-") i++; W[++n] = "<<"; K[n] = "I"; continue }
            W[++n] = "<"; K[n] = "I"; continue
          }
          if (c == "&") i++
          nx = substr(s, i + 1, 1)
          if (nx == ">" || nx == "|") { i++; nx = substr(s, i + 1, 1) }
          if (nx == "(") { W[++n] = ">("; K[n] = "I"; continue }
          if (nx == "&" && c != "&") {
            j = i + 2; w = ""
            while (j <= L && substr(s, j, 1) ~ /[0-9]/) { w = w substr(s, j, 1); j++ }
            if (w == "" && substr(s, j, 1) == "-") { w = "-"; j++ }
            if (w != "") { i = j - 1; W[++n] = ">&"; K[n] = "D"; continue }
            i++
          }
          W[++n] = ">"; K[n] = "R"; continue
        }
        cur = cur c
      }
      if (cur != "" || st) { W[++n] = cur; K[n] = "W" }
      return n
    }
    # The front of a word expanded the way the shell would expand it, from the environment.
    function wt_expand(w,   h, x, V, v, lv) {
      h = ENVIRON["HOME"]
      if (h != "" && (w == "~" || substr(w, 1, 2) == "~/")) return h substr(w, 2)
      split("HOME BIONIC_CLAUDE_HOME CLAUDE_CONFIG_DIR", WT_VARS, " ")
      for (x = 1; x <= 3; x++) {
        V = WT_VARS[x]; v = ENVIRON[V]; lv = length(V)
        if (v == "") continue
        if (w == "$" V || substr(w, 1, lv + 2) == "$" V "/") return v substr(w, lv + 2)
        if (w == "${" V "}" || substr(w, 1, lv + 4) == "${" V "}/") return v substr(w, lv + 4)
      }
      return w
    }
    function wt_norm(p,   abs, n, P, i, m, O, out) {
      abs = (substr(p, 1, 1) == "/"); n = split(p, P, "/"); m = 0
      for (i = 1; i <= n; i++) {
        if (P[i] == "" || P[i] == ".") continue
        if (P[i] == ".." && m > 0 && O[m] != "..") { m--; continue }
        if (P[i] == ".." && abs) continue
        O[++m] = P[i]
      }
      out = ""
      for (i = 1; i <= m; i++) out = out (i > 1 ? "/" : "") O[i]
      return (abs ? "/" out : (out == "" ? "." : out))
    }
    # A word is rooted when the shell would not join it to the cwd, or when its front is a
    # variable nothing here could expand.
    function wt_rooted(p,   c) { c = substr(p, 1, 1); return (c == "/" || c == "~" || c == "$") }
    function wt_emit(w, cwd,   p, c) {
      if (w == "") return
      # mode=effects reads the same writer table and prints through its own resolver.
      if (FX) { fx_emit("W", w, cwd); return }
      p = wt_expand(w)
      if (!wt_rooted(p)) {
        c = wt_expand(cwd)
        if (c != "") p = c "/" p
        if (!wt_rooted(p) && WT_BASE != "") p = WT_BASE "/" p
      }
      if (substr(p, 1, 1) == "/") p = wt_norm(p)
      else if (substr(p, 1, 1) != "$" && substr(p, 1, 1) != "~") p = wt_norm(p)
      if (!(p in WT_SEEN)) { WT_SEEN[p] = 1; print p }
    }
    # The directory a cd segment moves to, or cwd unchanged for any other segment.
    function wt_cd(A, m, cwd,   j, d) {
      if (m == 0 || (A[1] != "cd" && A[1] != "pushd" && A[1] != "popd")) return cwd
      if (A[1] == "popd") return ""
      for (j = 2; j <= m && A[j] ~ /^-[LPe@]+$/; j++) ;
      if (j <= m && A[j] == "--") j++
      d = (j <= m ? A[j] : "~")
      if (d == "-") return ""
      if (wt_rooted(d) || cwd == "") return d
      return cwd "/" d
    }
    function wt_argv(A, m, cwd,   b, j, w, opt, inp, hasE, np, P, tdir) {
      b = cmd_word_fold(base(A[1])); opt = 1; np = 0
      if (b == "tee" || b == "touch" || b == "mkdir") {
        for (j = 2; j <= m; j++) {
          w = A[j]
          if (opt && w == "--") { opt = 0; continue }
          if (opt && w ~ /^-./) {
            if ((b == "touch" && (w == "-d" || w == "-t" || w == "-r" || w == "-A" || w == "--date" || w == "--reference")) \
                || (b == "mkdir" && (w == "-m" || w == "--mode")))
              j++
            continue
          }
          wt_emit(w, cwd)
        }
        return
      }
      if (b == "sed") {
        inp = 0; hasE = 0
        for (j = 2; j <= m; j++) {
          w = A[j]
          if (opt && w == "--") { opt = 0; continue }
          if (opt && (w == "-e" || w == "-f" || w == "--expression" || w == "--file")) { j++; hasE = 1; continue }
          if (opt && w ~ /^--in-place/) { inp = 1; continue }
          if (opt && w ~ /^--(expression|file)=/) { hasE = 1; continue }
          if (opt && w == "-i") { inp = 1; if (j < m && A[j + 1] == "") j++; continue }
          if (opt && w ~ /^-[nrsuzE]*i/) { inp = 1; continue }
          if (opt && w ~ /^-[ef]/) { hasE = 1; continue }
          if (opt && w ~ /^-./) continue
          P[++np] = w
        }
        if (!inp) return
        for (j = (hasE ? 1 : 2); j <= np; j++) wt_emit(P[j], cwd)
        return
      }
      if (b == "cp" || b == "mv" || b == "ln") {
        tdir = ""
        for (j = 2; j <= m; j++) {
          w = A[j]
          if (opt && w == "--") { opt = 0; continue }
          if (opt && (w == "-t" || w == "--target-directory")) { j++; if (j <= m) tdir = A[j]; continue }
          if (opt && w ~ /^--target-directory=/) { tdir = substr(w, 20); continue }
          if (opt && w ~ /^-t./) { tdir = substr(w, 3); continue }
          if (opt && (w == "-S" || w == "--suffix")) { j++; continue }
          if (opt && w ~ /^-./) continue
          P[++np] = w
        }
        if (tdir != "") wt_emit(tdir, cwd)
        else if (np >= 2) wt_emit(P[np], cwd)
        else if (np == 1 && b == "ln") wt_emit(base(P[1]), cwd)
      }
    }
    # One segment: its redirect targets read off the whole text, then its argv after the
    # leading strip, or the command an `sh -c`/`eval` layer runs.
    function wt_seg(t, cwd, depth,   W, K, n, j, u0, u, A, m) {
      n = wt_tok(t, W, K)
      for (j = 1; j < n; j++) if (K[j] == "R" && K[j + 1] == "W") wt_emit(W[j + 1], cwd)
      u0 = strip_leading(t)
      u = unwrap_runner(u0)
      if (u != u0 && depth < 2) { wt_run(u, cwd, depth + 1); return cwd }
      split("", W); split("", K)
      n = wt_tok(u, W, K); m = 0
      for (j = 1; j <= n; j++) {
        if (K[j] == "R" || K[j] == "I") { j++; continue }
        if (K[j] == "W") A[++m] = W[j]
      }
      if (m > 0) wt_argv(A, m, cwd)
      return wt_cd(A, m, cwd)
    }
    # The cwd of subshell group g at depth d: its own once a cd set it, else its parent s.
    function wt_gcwd(d, g) {
      if ((d, g) in WGS) return WGC[d, g]
      WGS[d, g] = 1; WGC[d, g] = wt_gcwd(d, WGP[d, g])
      return WGC[d, g]
    }
    # Every segment of s. The segmentation globals are copied first, because an `sh -c` layer
    # re-enters segments() and overwrites them.
    #
    # `>|` IS ONE OPERATOR that segments() reads as `>` closed by a pipe. A segment ending in
    # `>` that a `|` closed can only be that (`> |` does not parse), so it is read joined to
    # the next one, whose first word is the file.
    function wt_run(s, cwd, depth,   k, sg, i, j, x, g, ng, c) {
      k = segments(s, sg); ng = GID_N
      if (depth == 0) { compound_pass(k, sg); expand_all(k, sg, s) }
      j = 0
      for (i = 1; i <= k; i++) {
        j++; WG[depth, j] = SEGGRP[i]; WSK[depth, j] = SEPKIND[i]; WRAW[depth, j] = sg[i]
        if (i < k && SEPKIND[i] == "|" && substr(sg[i], length(sg[i]), 1) == ">") {
          WNX[depth, j] = 1; WX[depth, j, 1] = sg[i] sg[i + 1]; WSK[depth, j] = SEPKIND[i + 1]; WRAW[depth, j] = sg[i] sg[i + 1]; i++; continue
        }
        WNX[depth, j] = (depth == 0 ? NX[i] : 1)
        for (x = 1; x <= WNX[depth, j]; x++) WX[depth, j, x] = (depth == 0 ? XT[i, x] : sg[i])
      }
      k = j
      for (g = 0; g <= ng; g++) { delete WGS[depth, g]; WGP[depth, g] = GPAR[g]; FXN[depth, g] = 1; FXX[depth, g] = "" }
      WGS[depth, 0] = 1; WGC[depth, 0] = cwd
      if (FX) { if (fx_text(s, depth, k)) return; FXLP[depth] = (s ~ /(^|[^A-Za-z0-9_])(for|while|until|select)[ \t]/) }
      for (i = 1; i <= k; i++) {
        g = WG[depth, i]; cwd = wt_gcwd(depth, g)
        if (FX) { WGC[depth, g] = fx_step(depth, i, k, g, cwd); continue }
        for (x = 1; x <= WNX[depth, i]; x++) c = wt_seg(trim(WX[depth, i, x]), cwd, depth)
        WGC[depth, g] = c
      }
    }
'

cmd_write_targets() {  # <command> [<cwd>] -> one resolved write target per line (D16, REQ-3)
  # The cwd rides the environment rather than `-v`, so `_cmd_class_awk` keeps its one
  # parameter: `-v` would also turn every backslash in a path into an escape.
  printf '%s' "${1-}" | _CMD_WT_CWD="${2-}" _cmd_class_awk writes
}

# ---------- WHAT A COMMAND WRITES AND DELETES, OR THAT IT CANNOT TELL (wave-25 T2; REQ-2, D5) ----------
#
# WHY A SECOND MODE AND NOT A CHANGE TO THE FIRST. `cmd_write_targets` answers the memory wall,
# for which an unread target is acceptable: it lists what it saw and is silent on the rest. A
# permission answer may allow only what was read in full, so silence there is a hole. This mode
# reads with the same segmentation, heredoc removal, literal expansion, tokeniser, writer table
# and resolution, and adds what the other cannot say: deletes, and `?` for everything it did
# not read. When in doubt it prints `?`. A false `?` costs a denial; a missed effect is a hole.
#
# OUTPUT, one line per effect, deduplicated, rc 0:
#   W<TAB><absolute path>   a write: everything mode=writes finds
#   D<TAB><absolute path>   a delete: the operands of rm, rmdir (and its parents under -p) and
#                           unlink, the sources of mv, the roots of `find ... -delete`
#   ?<TAB><reason><TAB><segment>   anything else that may act; the segment is flattened to one
#                           line and cut at 300 characters
# and, only when the third argument is the word `reads` (T16; review B3c, S4):
#   R<TAB><absolute path>   a file or directory read: each operand of cat, head, tail, wc, ls
#                           and grep (ls with none reads its directory), each `<` input, each
#                           source of cp, each file of sed, each operand of `git diff --no-index`
#   RR<TAB><absolute path>  a directory read and descended: grep -r/-R/--recursive/-d recurse
#                           (or a GREP_OPTIONS the text assigns), ls -R, every root of find, a
#                           cp -R/-a source, and the repository a git reader reads (-C or cwd)
# Without the word the output is byte for byte what it was before T16 added it.
#
# A PATH KEEPS ITS `..` (T16, review B1): it is joined to the directory it is read against and
# printed absolute, with only `.` and empty components taken out, because the kernel resolves
# `..` after following a link and only the hook (grant_resolve) can see the link. A cd target is
# the one place the shell folds `..` as text; after a cd through `..` a path is printed against
# both the folded and the unfolded directory (fx_emit), and a second such cd is `?`.
#
# A LINK MADE IN THE SAME COMMAND (T16, review B2). The hook resolves every path at question
# time, before the command runs. So `ln` is `?`, and so is any path at or beneath a cp or mv
# destination written earlier in the command (a delete AT it only when spelled with a trailing
# slash), since what was copied or moved there may be a link. `mkdir` makes no link.
#
# READ, NOT GUESSED. Argv[0] after the transparent prefixes (assignments, openers, `env`,
# `command`, `exec`, `nohup`, `setsid`, `time`, `nice`, `timeout`) must be in the writer
# table, the delete table or THE PURE-READER TABLE (fx_init); a pure reader with a write
# redirect still gives the redirect W line. Anything else is `?`, and so is: a `$`, backtick,
# glob, brace or leading `~` left in a path after expansion; a relative path with no cwd; a
# command substitution or process substitution anywhere in a segment; a heredoc body that runs
# one; an interpreter; a shell that reads a script or stdin; a third nested `sh -c`; `cd -`,
# `popd` and a `cd` to a variable, after which relative paths are `?` too; `xargs`, `eval`,
# `source`/`.`; a `git` subcommand that is not a known reader, `git -c`, `--output`; `find`
# with `-exec` or a file-printing primary; a sed script that writes or runs (`w`, `e`, `-f`).
#
# READS (orchestrator additions 2026-10-03). Without `reads` a read prints no line, so a read whose file the
# text does not name is `?`: an operand of cat, ls, head, tail, grep, wc, a git reader or find,
# or an input redirect `<`, that still holds a variable, substitution, glob, brace or leading
# `~` after expansion, or that came from a substituted literal (`d=.ssh; cat ~/$d/id`).
# Options and grep s pattern are not operands. `find -L`, `-H` and `-follow` are `?`: they walk
# through symlinks to places the roots do not name.
#
# WHERE A PATH IS READ AGAINST. A cd counts only where the text proves it ran (fx_step): a
# relative path after a cd whose list ended on `;`, a newline or `||` is `?`, because a failed
# cd leaves the shell where it was. The same holds for a cd in a loop, `! cd`, and readings of a
# loop variable that end in different directories.
#
# TEXT THE SEGMENTER MAY MISPLACE, read before any segment (fx_text and the heredoc pass): a
# heredoc whose delimiter, comment or open quote the reader does not place, `$'...'`, a quote
# inside `${...}`, a carriage return, a `#` comment in a segment that spans lines, a heredoc
# inside `sh -c`, a function definition (it may shadow any command here, cd included), and an
# assignment to PATH, CDPATH, IFS, ENV, BASH_ENV, SHELLOPTS, BASHOPTS, LD_*, DYLD_*, GIT_* or a
# variable the resolver expands. Each is `?`. A function definition, `$'...'`, a quote inside
# `${...}`, a carriage return and a heredoc inside `sh -c` also stop the walk at that depth.
#
# NO APOSTROPHE MAY APPEAR IN THIS TEXT, for the reason CMD_RUN_NORM_AWK gives.
_CMD_EFFECTS_AWK='
    # THE PURE-READER TABLE, the one list of commands whose argv writes and deletes nothing.
    # Short on purpose: a reader missing from it costs a denial, a writer in it is a hole.
    # A git subcommand is listed as git:<sub>.
    function fx_init(   R, n, x) {
      n = split("cat ls head tail grep wc echo printf test [ true pwd date find git:status git:log git:diff git:show git:rev-parse", R, " ")
      for (x = 1; x <= n; x++) FX_READ[R[x]] = 1
      FX_LOST = "\001"
    }
    # wt_expand, until the text assigns a variable it reads from the environment; after that a
    # `~` or `$` word stays as typed, and fx_emit reads it as unknown.
    function fx_expand(w) { return (FX_NOEXP ? w : wt_expand(w)) }
    # 1 when s ends inside a quote. Jumps from one quote or backslash to the next by index(),
    # and across each quoted run by cmdnorm_qend, the way segments() reads it.
    function fx_open_quote(s,   L, i, t, a, b, d, j, c) {
      L = length(s); i = 1
      while (i <= L) {
        t = substr(s, i); a = index(t, "\047"); b = index(t, "\""); d = index(t, "\\")
        j = 0
        if (a && (!j || a < j)) j = a
        if (b && (!j || b < j)) j = b
        if (d && (!j || d < j)) j = d
        if (!j) return 0
        i += j - 1; c = substr(s, i, 1)
        if (c == "\\") { i += 2; continue }
        i = cmdnorm_qend(s, i, c, 1)
        if (i > L) return 1
        i++
      }
      return 0
    }
    # Text the segmenter may split where the shell does not, which can carry a command into a
    # quote or a comment, or text that makes a listed command something else. Read once per
    # walk, at every depth; when it answers, nothing at that depth is read, because no path
    # read from it could be trusted.
    function fx_text(s, depth, k,   r, j) {
      r = ""
      # `name()` or `function name`: segments() leaves the bare name closed by `(`, then an
      # empty segment closed by `)`.
      for (j = 1; j <= k && r == ""; j++)
        if (trim(WX[depth, j, 1]) ~ /^function[ \t]/ \
            || (j < k && WSK[depth, j] == "(" && trim(WX[depth, j, 1]) ~ /^[A-Za-z_][A-Za-z0-9_]*$/ && trim(WX[depth, j + 1, 1]) == "" && WSK[depth, j + 1] == ")"))
          r = "defines a function, which may shadow a command"
      if (r == "" && index(s, "$\047")) r = "ANSI-C quoting the segmenter does not read"
      if (r == "" && s ~ /\$\{[^}]*[\047"]/) r = "a quote inside a parameter expansion the segmenter does not read"
      if (r == "" && index(s, "\r")) r = "a carriage return, which the shell keeps inside a word"
      if (r == "" && depth > 0 && index(s, "<<")) r = "a heredoc inside sh -c, whose body the reader does not strip"
      if (r != "") fx_unk(r, s)
      return (r != "")
    }
    # A READ OPERAND THE TEXT DOES NOT NAME (orchestrator addition 2026-10-03). A read prints
    # no line, so `cat ~/.ss?/id_ed25519` would read as no effect at all, and the reserved table
    # matches literal paths only. 1 when w, expanded, still holds a variable, substitution,
    # glob, brace or leading ~.
    function fx_rop(w,   p) { p = fx_expand(w); return (p ~ /[[$`*?{]/ || substr(p, 1, 1) == "~") }
    # Any unresolved operand of a file reader from argv[from]. Options are not operands, and
    # neither is grep s pattern (its first operand unless -e or -f gave one); the file an option
    # names (-f, --file=, --exclude-from=, --files0-from=) is.
    function fx_rargs(B, m, from,   j, w, pat, opt) {
      pat = (B[1] == "grep"); opt = 1
      for (j = from; j <= m; j++) {
        w = B[j]
        if (opt && w == "--") { opt = 0; continue }
        if (opt && B[1] == "grep" && (w == "-e" || w == "--regexp")) { j++; pat = 0; continue }
        if (opt && B[1] == "grep" && (w == "-f" || w == "--file")) { pat = 0; j++; if (j <= m && fx_rop(B[j])) return 1; continue }
        if (opt && w ~ /^--(file|exclude-from|files0-from)=/) { if (B[1] == "grep" && w ~ /^--file=/) pat = 0; if (fx_rop(substr(w, index(w, "=") + 1))) return 1; continue }
        if (opt && B[1] == "grep" && w ~ /^(-e.|--regexp=)/) { pat = 0; continue }
        if (opt && w ~ /^-./) continue
        if (pat) { pat = 0; continue }
        if (fx_rop(w)) return 1
      }
      return 0
    }
    function fx_flat(s) {
      if (length(s) > 300) s = substr(s, 1, 300) "..."
      gsub(/[\t\r\n]+/, " ", s)
      return trim(s)
    }
    function fx_unk(r, s,   k) {
      r = fx_flat(r); s = fx_flat(s); k = r "\t" s
      if (k in FX_SEEN) return
      FX_SEEN[k] = 1
      print "?\t" r "\t" s
    }
    # AN EFFECT PATH KEEPS ITS `..` (T16, review B1). The kernel resolves `a/link/..` AFTER it
    # follows the link, so a `..` folded as text names a place the command never touches, and
    # the hook, which resolves each path physically (grant_resolve), never saw the link. Only `.`
    # and empty components come out, each naming the directory it stands in. p is absolute.
    function fx_abs(p,   n, P, i, out) {
      n = split(p, P, "/"); out = ""
      for (i = 1; i <= n; i++) if (P[i] != "" && P[i] != ".") out = out "/" P[i]
      return (out == "" ? "/" : out)
    }
    function fx_under(p, d) { return (d == "/" || index(p, d "/") == 1) }
    # A PATH THROUGH WHAT THIS COMMAND COPIED OR MOVED (T16, review B2). The hook resolves every
    # path at question time, before a cp or mv destination holds what the command puts there, and
    # that may be a link. So a path strictly beneath a destination written earlier is unknown; so
    # is a write or read AT it, which goes through such a link, and a delete at it spelled with a
    # trailing slash, which follows one. A plain delete at it removes the link itself. Each path
    # is compared both as printed and folded, so a `c/../b/x` spelling is beneath b too.
    # Returns 1 when the line was printed (or already had been).
    function fx_put(tag, p, w,   x, d, q) {
      if (FX_ND) {
        q = wt_norm(p)
        for (x = 1; x <= FX_ND; x++) {
          d = FX_DEST[x]
          if (fx_under(p, d) || fx_under(q, d) || ((p == d || q == d) && (tag != "D" || w ~ /\/\.?$/))) {
            fx_unk("a path through " d ", which cp or mv wrote earlier in this command and may now be a link: " w, FX_SEG)
            return 0
          }
        }
      }
      p = tag "\t" p
      if (!(p in FX_SEEN)) { FX_SEEN[p] = 1; print p }
      return 1
    }
    function fx_dest(p) { FX_DEST[++FX_ND] = p; FX_DEST[++FX_ND] = wt_norm(p) }
    # A W or D line for w, joined to the directory it is read against, or a ? when the shell
    # still has something to decide about the path. With FX_REG set (a cp or mv destination),
    # each path printed is remembered for fx_put.
    #
    # THE ONE PLACE `..` IS FOLDED AS TEXT IS A CD TARGET, because there the shell folds it too:
    # bash and zsh `cd a/link/..` move to a, not to the parent of the link. But bash falls back to
    # the unfolded path when the folded one does not exist, so when the directory came from a cd
    # through `..`, the path is printed twice, against the folded directory and against the
    # unfolded one. Either can be the place, and the hook requires both inside: printing both can
    # only refuse. A second cd through `..` multiplies the places, and fx_cd calls it unknown.
    function fx_emit(tag, w, cwd,   p, o, c, b, k) {
      if (w == "") return
      p = fx_expand(w); o = p; b = ""
      if (substr(p, 1, 1) != "/" && !wt_rooted(p)) {
        if (cwd == FX_LOST) { fx_unk("a relative target after a directory the text cannot name: " w, FX_SEG); return }
        c = fx_expand(cwd)
        b = c
        if (!wt_rooted(b) && WT_BASE != "") b = (b == "" ? WT_BASE : WT_BASE "/" b)
        if (b != "") p = b "/" p
      }
      if (p ~ /[[$`*?{]/ || substr(p, 1, 1) == "~") { fx_unk("a variable, substitution or pattern in the target: " w, FX_SEG); return }
      if (p ~ /[\001-\037]/) { fx_unk("a control character in the target", FX_SEG); return }
      if (substr(p, 1, 1) != "/") { fx_unk("a relative target and no cwd: " w, FX_SEG); return }
      p = fx_abs(p)
      k = fx_put(tag, p, w)
      if (k && FX_REG) fx_dest(p)
      if (b == "" || !index("/" b "/", "/../")) return
      p = fx_abs(wt_norm(b) "/" o)
      k = fx_put(tag, p, w)
      if (k && FX_REG) fx_dest(p)
    }
    # The directory a cd, pushd or popd moves to. One the text cannot name is FX_LOST, and
    # every relative path after it is unknown rather than read against the wrong directory.
    function fx_cd(B, m, cwd, t,   j, d) {
      if (B[1] == "popd") { fx_unk("popd: a directory the text cannot name", t); return FX_LOST }
      for (j = 2; j <= m && B[j] ~ /^-[LPe@]+$/; j++) ;
      if (j <= m && B[j] == "--") j++
      if (j > m && B[1] == "pushd") { fx_unk("pushd: a directory the text cannot name", t); return FX_LOST }
      d = (j <= m ? B[j] : "~")
      if (d == "-" || d ~ /^[+-][0-9]+$/) { fx_unk(B[1] " " d ": a directory the text cannot name", t); return FX_LOST }
      d = fx_expand(d)
      if (d ~ /[[$`*?{]/ || substr(d, 1, 1) == "~") { fx_unk("a cd to a variable or pattern: " d, t); return FX_LOST }
      if (substr(d, 1, 1) == "/") return d
      if (cwd == FX_LOST) return FX_LOST
      # Each cd through `..` may be folded or not (fx_emit), so two of them name four places.
      if (index("/" d "/", "/../") && index("/" cwd "/", "/../")) { fx_unk("a second cd through ..: the shell may fold each one either way", t); return FX_LOST }
      return (cwd == "" ? d : cwd "/" d)
    }
    function fx_shell(B, m, cwd, depth, t,   j, c) {
      c = 0
      for (j = 2; j <= m && B[j] ~ /^[-+]./ && B[j] != "--"; j++) {
        if (B[j] ~ /^-[A-Za-z]*c[A-Za-z]*$/) c = 1
        else if (B[j] ~ /^[-+][oO]$/ || B[j] == "--rcfile" || B[j] == "--init-file") j++
      }
      if (j <= m && B[j] == "--") j++
      if (!c) { fx_unk("a shell reading a script, stdin or a heredoc: " B[1], t); return }
      if (j > m) return
      if (depth >= 2) { fx_unk("a third nested shell: the reader stops at two", t); return }
      wt_run(B[j], cwd, depth + 1)
    }
    # WHAT A COMMAND READS (T16; review B3c, S4), printed only when the caller passes the word
    # `reads`: `R<TAB>path` for each file or directory read, `RR<TAB>path` for one the reader
    # descends. The path rule is fx_emit s, so `..` stays in and a cp or mv destination is
    # honoured; an operand the text does not name is the `?` fx_rop already gives.
    function fx_read(tag, w, cwd) {
      if (fx_rop(w)) { FX_ROPA = 1; return }
      fx_emit(tag, w, cwd)
    }
    # The operands of a pure reader. Options are not operands, and neither is grep s pattern. An
    # option value is consumed only where the reader always takes one: a value read as an operand
    # adds a harmless line, an operand read as a value hides a read. RR for grep -r, -R,
    # --recursive, -d recurse or a GREP_OPTIONS the text assigns, and for ls -R. ls with no
    # operand reads the directory it runs in, and so does a recursive grep.
    function fx_reads(B, m, cwd,   j, w, b, opt, pat, rec, n, O) {
      b = B[1]; opt = 1; pat = (b == "grep"); rec = (b == "grep" && FX_GREPR); n = 0
      for (j = 2; j <= m; j++) {
        w = B[j]
        if (opt && w == "--") { opt = 0; continue }
        if (opt && w ~ /^-./) {
          if (w ~ /^--(file|exclude-from|files0-from)=/) fx_read("R", substr(w, index(w, "=") + 1), cwd)
          if (b == "grep") {
            if (w == "-e" || w == "--regexp") { pat = 0; j++ }
            else if (w ~ /^(-e.|--regexp=)/ || w ~ /^--file=/) pat = 0
            else if (w == "-f" || w == "--file") { pat = 0; j++; if (j <= m) fx_read("R", B[j], cwd) }
            else if (w == "-d" || w == "--directories") { j++; if (B[j] == "recurse") rec = 1 }
            else if (w == "-drecurse" || w == "--directories=recurse" || w == "--recursive" || w == "--dereference-recursive") rec = 1
            else if (w ~ /^(-m|-A|-B|-D|--max-count|--after-context|--before-context|--devices|--include|--exclude|--exclude-dir|--include-dir|--label|--binary-files)$/) j++
            else if (w ~ /^-[^-]/ && w ~ /[rR]/) rec = 1
          }
          else if (b == "ls") { if (w == "--recursive" || (w ~ /^-[^-]/ && index(w, "R"))) rec = 1 }
          else if (b == "head" || b == "tail") { if (w == "-n" || w == "-c" || w == "-b" || w == "--lines" || w == "--bytes") j++ }
          continue
        }
        if (pat) { pat = 0; continue }
        O[++n] = w
      }
      if (n == 0 && (b == "ls" || rec)) O[++n] = "."
      for (j = 1; j <= n; j++) fx_read((rec ? "RR" : "R"), O[j], cwd)
    }
    # git reads the repository its directory holds (-C, or the cwd), and --git-dir and
    # --work-tree name; with --no-index, diff reads each operand, wherever it is.
    function fx_gitreads(B, m, cwd,   j, d, s, ni, w) {
      d = ""
      for (j = 2; j <= m && B[j] ~ /^-/; j++) {
        if (B[j] == "-C") { j++; d = (d == "" || substr(fx_expand(B[j]), 1, 1) == "/" ? B[j] : d "/" B[j]); continue }
        if (B[j] == "--git-dir" || B[j] == "--work-tree") { j++; fx_read("RR", B[j], cwd); continue }
        if (B[j] ~ /^--(git-dir|work-tree)=/) { fx_read("RR", substr(B[j], index(B[j], "=") + 1), cwd); continue }
        if (B[j] == "--namespace") j++
      }
      fx_read("RR", (d == "" ? "." : d), cwd)
      ni = 0
      for (s = j + 1; s <= m; s++) if (B[s] == "--no-index") ni = 1
      if (!ni) return
      for (s = j + 1; s <= m; s++) {
        w = B[s]
        if (w ~ /^-./) continue
        fx_read("R", (d == "" || substr(fx_expand(w), 1, 1) == "/" || fx_rop(w) ? w : d "/" w), cwd)
      }
    }
    # sed reads every file operand, with -i or without: the script is the first operand unless
    # -e or --expression gave one. (-f is unknown before this is reached.)
    function fx_sedreads(B, m, cwd,   j, w, opt, hasE, np, P) {
      opt = 1; hasE = 0; np = 0
      for (j = 2; j <= m; j++) {
        w = B[j]
        if (opt && w == "--") { opt = 0; continue }
        if (opt && (w == "--expression" || w ~ /^-[nrsuzE]*e$/)) { j++; hasE = 1; continue }
        if (opt && (w ~ /^--expression=/ || w ~ /^-[nrsuzE]*e./)) { hasE = 1; continue }
        if (opt && w == "-i") { if (j < m && B[j + 1] == "") j++; continue }
        if (opt && w ~ /^-./) continue
        P[++np] = w
      }
      for (j = (hasE ? 1 : 2); j <= np; j++) fx_read("R", P[j], cwd)
    }
    # cp reads its sources, descending with -R, -r, -a, --recursive or --archive.
    function fx_cpreads(B, m, cwd,   j, w, opt, np, P, tdir, rec) {
      opt = 1; np = 0; tdir = 0; rec = 0
      for (j = 2; j <= m; j++) {
        w = B[j]
        if (opt && w == "--") { opt = 0; continue }
        if (opt && (w == "-t" || w == "--target-directory")) { j++; tdir = 1; continue }
        if (opt && w ~ /^(--target-directory=|-t.)/) { tdir = 1; continue }
        if (opt && (w == "-S" || w == "--suffix")) { j++; continue }
        if (opt && (w == "--recursive" || w == "--archive")) { rec = 1; continue }
        if (opt && w ~ /^-[^-]/) { if (w ~ /[rRa]/) rec = 1; continue }
        if (opt && w ~ /^-./) continue
        P[++np] = w
      }
      if (!tdir) np--
      for (j = 1; j <= np; j++) fx_read((rec ? "RR" : "R"), P[j], cwd)
    }
    function fx_git(B, m, t, cwd,   j, s) {
      for (j = 2; j <= m && B[j] ~ /^-/; j++) {
        if (B[j] == "-c" || B[j] ~ /^--config-env/) { fx_unk("git -c sets config that can run a command", t); return }
        if (B[j] ~ /^--exec-path=/) { fx_unk("git --exec-path runs git programs from elsewhere", t); return }
        if (B[j] == "-C" || B[j] == "--git-dir" || B[j] == "--work-tree" || B[j] == "--namespace") j++
      }
      s = (j <= m ? B[j] : "")
      if (!(("git:" s) in FX_READ)) { fx_unk("git " s " is not a known reader", t); return }
      if (FX_EXP || fx_rargs(B, m, 2)) FX_ROPA = 1
      for (j++; j <= m; j++) if (B[j] ~ /^--output(=|$)/) { fx_unk("git " s " --output writes a file", t); return }
      if (FXR) fx_gitreads(B, m, cwd)
    }
    # find: its roots are read operands, and -delete deletes each. -L, -H and -follow walk
    # through symlinks to places the roots do not name (orchestrator addition 2026-10-03:
    # every worktree holds a .bionic link into shared state), so they are unknown.
    function fx_find(B, m, cwd, t,   j, nr, RT, del, fl) {
      fl = 0
      for (j = 2; j <= m && B[j] ~ /^-[HLPEXdsx]+$/; j++) if (B[j] ~ /[HL]/) fl = 1
      nr = 0
      for (; j <= m; j++) {
        if (B[j] == "-f" && j < m) { RT[++nr] = B[++j]; continue }
        if (B[j] ~ /^-/ || B[j] == "(" || B[j] == "!" || B[j] == ")") break
        RT[++nr] = B[j]
      }
      del = 0
      for (; j <= m; j++) {
        if (B[j] ~ /^-(exec|execdir|ok|okdir)$/) { fx_unk("find runs a command", t); return }
        if (B[j] ~ /^-(fprint|fprint0|fprintf|fls)$/) { fx_unk("find writes a file", t); return }
        if (B[j] == "-delete") del = 1
        if (B[j] == "-follow") fl = 1
      }
      if (fl) { fx_unk("find follows symlinks", t); return }
      for (j = 1; j <= nr; j++) if (fx_rop(RT[j])) FX_ROPA = 1
      if (FX_EXP) FX_ROPA = 1
      # A find descends every root it names, or the directory it runs in when it names none.
      if (FXR) { if (nr == 0) fx_read("RR", ".", cwd); for (j = 1; j <= nr; j++) fx_read("RR", RT[j], cwd) }
      if (!del) return
      if (nr == 0) RT[++nr] = "."
      for (j = 1; j <= nr; j++) fx_emit("D", RT[j], cwd)
    }
    # rm, rmdir, unlink and the mv sources; rmdir -p removes each parent the operand names.
    function fx_del(B, m, cwd,   j, w, opt, par, np, P, tdir) {
      opt = 1; par = 0; np = 0; tdir = ""
      for (j = 2; j <= m; j++) {
        w = B[j]
        if (opt && w == "--") { opt = 0; continue }
        if (opt && B[1] == "mv" && (w == "-t" || w == "--target-directory" || w == "-S" || w == "--suffix")) { j++; if (w == "-t" || w == "--target-directory") tdir = B[j]; continue }
        if (opt && B[1] == "mv" && w ~ /^(--target-directory=|-t.)/) { tdir = w; continue }
        if (opt && w ~ /^-./) { if (B[1] == "rmdir" && (w ~ /^-[a-z]*p/ || w == "--parents")) par = 1; continue }
        P[++np] = w
      }
      if (B[1] == "mv" && tdir == "") np--
      for (j = 1; j <= np; j++) {
        w = P[j]; fx_emit("D", w, cwd)
        if (par) while (sub(/\/+[^\/]*\/*$/, "", w) && w != "") fx_emit("D", w, cwd)
      }
    }
    # SEGMENT i OF GROUP g AT depth, and the cwd the next segment of g inherits. A cd moves the
    # shell only where the text proves it ran: for the rest of its `&&` chain, and after the
    # list `cd X || exit`. A list it ends any other way leaves the shell in one of
    # two directories, which is FX_LOST. A cd in a pipeline stage moves only that stage; a
    # list sent to the background with `&` runs in a subshell and moves nothing; a cd in a
    # loop moves the segments before it on the next pass, which is unknown; and readings of
    # one segment through different literal values that end in different directories are lost.
    function fx_step(depth, i, k, g, before,   x, c, c1, s, pv, nx) {
      if (FXN[depth, g]) { FXS[depth, g] = before; FXC[depth, g] = 0; FXI[depth, g] = i; FXN[depth, g] = 0 }
      for (x = 1; x <= WNX[depth, i]; x++) {
        FX_EXP = (WX[depth, i, x] != WRAW[depth, i])
        c1 = fx_seg(trim(WX[depth, i, x]), before, depth)
        if (x == 1) c = c1
        else if (c1 != c) c = FX_LOST
      }
      s = WSK[depth, i]; pv = (i > 1 ? WSK[depth, i - 1] : "")
      if (c != before) {
        if (s == "|" || s == "|&" || pv == "|" || pv == "|&") c = before
        else {
          FXC[depth, g] = 1
          if (FXLP[depth]) { fx_unk("a cd inside a loop moves the segments before it on the next pass", WX[depth, i, 1]); c = FX_LOST }
        }
      }
      if (FXX[depth, g] != "") { c = FXX[depth, g]; FXX[depth, g] = ""; FXC[depth, g] = 0; FXN[depth, g] = 1; return c }
      if (s == "&&" || s == "(" || s == "|" || s == "|&") return c
      if (s == "||") {
        if (!FXC[depth, g]) return c
        nx = (i < k && WG[depth, i + 1] == g ? WSK[depth, i + 1] : "-")
        if (c != before && FXI[depth, g] == i && trim(WX[depth, i + 1, 1]) ~ /^exit([ \t]|$)/ && (nx == ";" || nx == "\n" || nx == "")) {
          FXX[depth, g] = c; return before
        }
        return FX_LOST
      }
      FXN[depth, g] = 1
      if (s == "&") return FXS[depth, g]
      return (FXC[depth, g] ? FX_LOST : c)
    }
    # One segment: its write redirects, then its argv after the transparent prefixes. Returns
    # the cwd the segments after it inherit. A segment holding a command or process
    # substitution is not read further: its words are not the words the shell will see, so
    # neither is any path in it, nor the directory a cd in it names.
    function fx_seg(t, cwd, depth,   W, K, n, j, A, m, i, w, B, sv, neg) {
      if (index(t, "$(") || index(t, "`") || index(t, "<(") || index(t, ">(")) {
        fx_unk("a command substitution runs a command the reader does not read", t)
        return FX_LOST
      }
      # A comment line runs nothing. One holding a quote or an escape is not read as one: the
      # segmenter may have carried the next line into it.
      if (substr(t, 1, 1) == "#" && t !~ /[\047"\\\n]/) return cwd
      if (index(t, "\n") && t ~ /(^|[ \t\n])#/) { fx_unk("a comment inside a segment that spans lines", t); return FX_LOST }
      sv = FX_SEG; FX_SEG = t; neg = 0; FX_ROPA = 0
      n = wt_tok(t, W, K); m = 0
      for (j = 1; j <= n; j++) {
        if (K[j] == "I" && W[j] == "<" && j < n && K[j + 1] == "W" && fx_rop(W[j + 1])) FX_ROPA = 1
        if (FXR && K[j] == "I" && W[j] == "<" && j < n && K[j + 1] == "W") fx_read("R", W[j + 1], cwd)
        if (K[j] == "R" || K[j] == "I") { if (K[j] == "R" && j < n && K[j + 1] == "W") fx_emit("W", W[j + 1], cwd); j++; continue }
        if (K[j] == "W") A[++m] = W[j]
      }
      for (i = 1; i <= m; i++) {
        w = A[i]
        if (w ~ /^(HOME|BIONIC_CLAUDE_HOME|CLAUDE_CONFIG_DIR)[+]?=/) FX_NOEXP = 1
        if (w ~ /^GREP_OPTIONS[+]?=/) FX_GREPR = 1
        if (w ~ /^(HOME|BIONIC_CLAUDE_HOME|CLAUDE_CONFIG_DIR|PATH|CDPATH|IFS|ENV|BASH_ENV|SHELLOPTS|BASHOPTS|LD_[A-Z0-9_]*|DYLD_[A-Z0-9_]*|GIT_[A-Z0-9_]*)[+]?=/)
          fx_unk("assigns a variable that moves what runs or where: " w, t)
        if (w == "!") neg = 1
        if (w ~ /^[A-Za-z_][A-Za-z0-9_]*[+]?=/ || w ~ /^([{}()!]|then|else|elif|do|done|fi|if|while|until|esac)$/) continue
        # The prefixes are names, read through the fold (CMD_WORD_FOLD_AWK); the reserved words
        # and the assignments above are not.
        w = cmd_word_fold(w)
        if (w ~ /^(env|command|exec|nohup|setsid)$/) {
          if (i < m && A[i + 1] ~ /^-/) { fx_unk("an option of " w " the reader does not parse", t); FX_SEG = sv; return cwd }
          continue
        }
        if (w == "time") { if (A[i + 1] == "-p") i++; continue }
        if (w == "nice") {
          if (A[i + 1] == "-n" || A[i + 1] == "--adjustment") i += 2
          else if (A[i + 1] ~ /^(-n?-?[0-9]+|--adjustment=.*)$/) i++
          continue
        }
        if (w == "timeout" || w == "gtimeout") {
          for (i++; i <= m && A[i] ~ /^-/; i++) if (A[i] ~ /^(-s|-k|--signal|--kill-after)$/) i++
          if (A[i] ~ /^[0-9.]+[smhd]?$/) continue
          fx_unk("a timeout the reader does not parse", t); FX_SEG = sv; return cwd
        }
        break
      }
      m = m - i + 1
      for (j = 1; j <= m; j++) B[j] = A[i + j - 1]
      if (neg && m > 0 && base(B[1]) ~ /^(cd|pushd|popd)$/) { fx_unk("a negated cd: what follows runs where it failed", t); FX_SEG = sv; return FX_LOST }
      if (m > 0) cwd = fx_argv(B, m, cwd, depth, t)
      if (FX_ROPA) fx_unk("unresolved read operand", t)
      FX_ROPA = 0
      FX_SEG = sv
      return cwd
    }
    function fx_argv(B, m, cwd, depth, t,   b, d, j, bt) {
      b = B[1]
      if (index(b, "/")) {
        d = b; sub(/\/[^\/]*$/, "", d)
        if (d !~ /^(\/usr(\/local)?|\/opt\/homebrew)?\/s?bin$/) { fx_unk("runs a script: " b, t); return cwd }
        b = base(b); B[1] = b
      }
      if (b == "cd" || b == "pushd" || b == "popd") return fx_cd(B, m, cwd, t)
      # A loop or case header names words, and exit or return ends the shell: none acts on a file.
      if (b == "for" || b == "select" || b == "case" || b == "exit" || b == "return") return cwd
      # EVERY TABLE BELOW HOLDS NAMES, compared to the word folded (CMD_WORD_FOLD_AWK, wave-25
      # T12), and B[1] carries the fold to the readers that ask it again (fx_rargs, fx_del).
      # The two lines above read as typed: the cd family, exit and return are not folded, and
      # neither is a reserved word.
      bt = b; b = cmd_word_fold(b); B[1] = b
      if (b ~ /^(ba|z|k|da)?sh$/) { fx_shell(B, m, cwd, depth, t); return cwd }
      if (b == "git") { fx_git(B, m, t, cwd); return cwd }
      if (b == "find") { fx_find(B, m, cwd, t); return cwd }
      if (b in FX_READ) {
        if (b ~ /^(cat|ls|head|tail|grep|wc)$/ && (FX_EXP || fx_rargs(B, m, 2))) FX_ROPA = 1
        if (FXR && b ~ /^(cat|ls|head|tail|grep|wc)$/) fx_reads(B, m, cwd)
        if (b == "date") for (j = 2; j <= m; j++) if (B[j] ~ /^(-s|--set)/ || B[j] !~ /^[-+]/) fx_unk("date may set the clock", t)
        return cwd
      }
      if (b == "rm" || b == "rmdir" || b == "unlink") { fx_del(B, m, cwd); return cwd }
      if (b == "mv") { fx_del(B, m, cwd); FX_REG = 1; wt_argv(B, m, cwd); FX_REG = 0; return cwd }
      if (b == "cp") { if (FXR) fx_cpreads(B, m, cwd); FX_REG = 1; wt_argv(B, m, cwd); FX_REG = 0; return cwd }
      # A link, symbolic or hard, redirects every later path through it, and the hook resolves
      # each path at question time, before the link exists (T16, review B2).
      if (b == "ln") { fx_unk("a link redirects every later path, and it does not exist yet when they are resolved", t); return cwd }
      if (b == "sed") {
        for (j = 2; j <= m; j++) {
          if (B[j] == "-f" || B[j] ~ /^--file/ || B[j] ~ /^-[nrsuzE]*f/) { fx_unk("sed reads its script from a file", t); return cwd }
          if (B[j] ~ /(^|[^A-Za-z])[wW][ \t]+[^ \t]/ || B[j] ~ /(^|[^A-Za-z])e([ \t;}]|$)/) { fx_unk("a sed script that writes or runs", t); return cwd }
        }
        wt_argv(B, m, cwd)
        if (FXR) fx_sedreads(B, m, cwd)
        return cwd
      }
      if (b == "tee" || b == "touch" || b == "mkdir") { wt_argv(B, m, cwd); return cwd }
      if (b == "eval") { fx_unk("eval runs text the reader does not read", t); return cwd }
      if (b == "source" || b == ".") { fx_unk("source runs a file the reader does not read", t); return cwd }
      if (b == "xargs") { fx_unk("xargs takes its targets from stdin", t); return cwd }
      if (b ~ /^(python[0-9.]*|perl[0-9.]*|ruby|node|nodejs|deno|bun|php|lua|rscript|osascript|tclsh|pwsh|awk|gawk|mawk|nawk)$/) {
        fx_unk("an interpreter body or a heredoc fed to one: " bt, t); return cwd
      }
      fx_unk("not a known reader or writer: " bt, t)
      return cwd
    }
'

# The names the shared walk calls when FX is set, for every mode that never sets it.
_CMD_EFFECTS_STUBS='
    function fx_init() { }
    function fx_open_quote(s) { return 0 }
    function fx_unk(r, s) { }
    function fx_emit(tag, w, cwd) { }
    function fx_text(s, depth, k) { return 0 }
    function fx_step(depth, i, k, g, before) { return before }
'

cmd_effects() {  # <command> [<cwd>] [reads] -> W/D<TAB><absolute path> or ?<TAB><reason><TAB><segment> per line (D5, REQ-2); with `reads`, R/RR<TAB><absolute path> too (T16)
  printf '%s' "${1-}" | _CMD_WT_CWD="${2-}" _CMD_FX_READS="${3-}" _cmd_class_awk effects
  return 0
}

cmd_backgrounded() {  # <command> -> 0 when the TEXT backgrounds it, 1 otherwise (D8, REQ-6)
  # A BARE `&` control operator outside quotes and not folded into `&&` or a redirect
  # (`2>&1`, `&>log`) that no bare `wait` collects (see mode=bg for the rule), OR a
  # `nohup`/`setsid` wrapper — READ, never string-matched, by the
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
  #     guard has a refusal written for exactly that state. A variable whose values the
  #     text states (a literal `for` list, one literal assignment) is resolved BEFORE this
  #     point by the awk reading (section 6, wave-24 D9), so what still arrives with a `$`
  #     is a name nothing here can vouch for.
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

cmd_suite_loop_lines() {  # <command> -> one `bash <path>` line per suite a literal loop header names
  # THE FIX THE UNEXPANDED-NAME REFUSAL PRINTS (wave-24 T13, D10, AC-6.3). A loop the claims
  # will not resolve (an `eval` or a function elsewhere in the command) still has a header of
  # literal words, and those words put into the path the body runs are the lines the reader
  # meant: one `bash <path>` per distinct suite, in header order. Nothing for a `$` no literal
  # loop pins, nor for a body that reassigns the variable, whose header is not what runs
  # (wave-24 T26). payload/scripts/lib/walls.sh prints this and never reads the loop itself.
  printf '%s' "${1-}" | _cmd_class_awk looplines
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
  # position — but the class column is now matched by `case`, where it was one
  # `awk -F'\t'` plus one `grep -qx` PER CLASS NAME over a handful of lines. Four greps
  # to ask four questions of one small string is four process spawns on the hottest
  # path in the tree.
  #
  # EXACT-FIELD SEMANTICS, WHICH IS WHAT `grep -qx` GAVE. The lines are wrapped in a
  # newline on both ends, and each pattern carries a newline before the word it looks
  # for and a tab or a newline after it, so `suite` matches the whole field `suite`
  # and never a field that merely contains it. A `case` pattern would otherwise be a
  # substring test, which is exactly the direction `-x` existed to refuse: without
  # the anchors a class column reading `not-suite` would answer `suite`, and the
  # farm-out wall would deny a command it has no business denying.
  #
  # THE FIELD SPLIT MATCHES awk's. A line's first field is the class word exactly when the
  # line is the word followed by a tab, or the word alone — what `awk -F'\t' '{print $1}'`
  # printed for a line carrying no tab.
  #
  # NO WALK OVER THE LINES (wave-24 T22). Each line echoes its segment whole, so a quoted
  # body of N lines is N lines here, and the walk that peeled them off one at a time with
  # `${rest%%…}`/`${rest#*…}` cost N passes over the whole text: 4.9 s under 3.2 on a 52 KB
  # `python3 -c` body of 1 350 lines. Two anchored `case` tests per class word read the
  # same lines in a fixed number of passes.
  local lines c
  lines=$'\n'"$(cmd_class_lines "${1-}")"$'\n'
  for c in suite bootstrap install build; do
    case "$lines" in
      *$'\n'"$c"$'\t'*|*$'\n'"$c"$'\n'*) printf '%s' "$c"; return 0 ;;
    esac
  done
  printf 'none'
}
