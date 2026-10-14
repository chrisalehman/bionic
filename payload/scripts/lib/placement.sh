# payload/scripts/lib/placement.sh — ONE READER FOR "where does this command run" (wave-36 T3;
# spec D11, ruled at D6; REQ-5).
#
# WHY IT EXISTS. Four readers answered this with four grammars (research-landing-and-walls.md §Q2,
# cause A): the shim's stamp walk (walls.sh `_bsg_cd_walk`), the gate's tree (booked.sh
# `booked_cd_dir`), the commit's cwd (walls.sh `_eg_commit_cwd`/`_eg_cd_targets`) and its separator
# test (`_eg_placed`). The stamp walk asked the RAW TEXT ahead of the suite for `( ) | & \``, and
# asked that the suite's segment occur verbatim in the command, so a parenthesis in a quoted note,
# a heredoc, a `$(date)` in an echo or a `> "$LOG"` redirect unplaced a run that plainly ran where
# it cd'd; eighteen of wave-35's runs went uncounted for it (§Q5). This reader is built on
# cmd-class.sh's segment parse, so quoted text and heredoc bodies are invisible to it by
# construction. It adds no grammar of its own: the reading is cmd-class's awk program in
# `mode=place` (its section 8), over the segments, compound branches and pinned variables that
# program already reads.
#
# THE CONTRACT (stated in full, with an example per form, in
# .bionic/docs/record/wave-36-zero-machine-errors/T3-placement.md, which the callers read):
#
#   cmd_place <command> <cwd> [<target>]
#
#   <command>  the Bash tool call's text, as the hook receives it.
#   <cwd>      the absolute directory the call stands in (the payload's cwd).
#   <target>   which segment's place is asked: `suite` for the first segment cmd-class calls
#              suite-class; any other word for the first segment whose command word (after
#              cmd-class's leading strip: assignments, openers, env/command/exec, sudo, time …)
#              is that word, folded as the machine resolves it (`GIT` is git); omitted for the
#              end of the command, where the shell stands after its last segment.
#
#   stdout and exit:
#     0  one line: the absolute directory the target runs in, `.` and `..` folded lexically,
#        no trailing slash. With no move ahead of the target it is <cwd>, folded the same way.
#     1  one line: `moving <segment>`: a move ahead of the target the reader cannot be sure of,
#        and no absolute literal cd after it; <segment> is that move's segment as typed, blanks
#        between words collapsed. A target whose own text moves (`bash -c 'cd x && …'`) names
#        itself.
#     2  nothing on stdout: <cwd> is missing or not absolute (one line on stderr says so).
#     3  nothing on stdout: a <target> was named and no segment carries it.
#
#   A READABLE MOVE is a segment whose command word is `cd` (a `{` opener in front at most) with
#   at most one operand, `--` allowed before it, redirections ignored, and that operand a
#   LITERAL: a bare word, or one quoted with nothing to expand, `~` or `~/…` from HOME, or no
#   operand (HOME); no option, no `$`, backquote or backslash left after pinned variables are
#   put in, no glob character. A PINNED VARIABLE is cmd-class's: one standalone `V=<literal>`
#   segment closed by `;`, `&&` or a newline, not opened by `||` or a pipe, the only assignment
#   of V in the command, reaching the cd (same subshell group or a child, same branch or a
#   child), in a command that defines no function and runs no eval or source; or a literal
#   `for` list, which gives a cd more than one value and so is never read.
#   ITS REACH IS SURE when the cd sits in the target's subshell group or an enclosing one and
#   in the target's compound branch or an enclosing one; is not behind `||` or a pipe; is not
#   piped on or backgrounded; is behind `&&` only when `&&` carries on unbroken to the target;
#   and the target is not on the cd's own `||` failure branch. For THE END OF THE COMMAND, which
#   is reached whether or not a step fails, a cd behind `&&` is sure only when every link ahead
#   of it on its `&&` run is a cd with a literal operand (wave-36 T43): `cd /a && cd /b` ends in
#   /b, `true && cd /b` is moving.
#   EVERY OTHER MOVE LOSES THE PLACE: pushd, popd, a cd it cannot read, a cd whose reach is
#   unsure, and a cd behind anything in front of the command word or inside a string the
#   segment runs (`X=1 cd`, `if cd`, `then cd`, `! cd`, `command cd`, `builtin cd`, `eval cd`,
#   `sh -c 'cd …'`). An absolute literal cd after a lost place anchors it again; a relative one
#   stays lost. A cd the shell would fail (a directory that is not there) is read as written:
#   the reader touches no filesystem.
#   INVISIBLE: anything inside quotes, every heredoc body, the inside of `$(…)` and backquotes,
#   and every segment that moves nothing, whatever it holds.
#
# COST. One awk reading, whatever the command's length: the shell side is a fixed handful of
# commands (tests/hook-latency.test.sh §PLACE counts a 2 KB and a 200 KB quoted body equal).
#
# LOADING. Sources cmd-class.sh from its own directory unless it is already loaded. A library
# that cannot load leaves cmd_place undefined and the source returns 1, so a caller can fail
# closed on it.
#
# BASH 3.2. [WALL: tests/placement.test.sh]

if ! declare -F _cmd_class_awk >/dev/null 2>&1; then
  case "${BASH_SOURCE[0]}" in
    */*) _PLACEMENT_LIB_DIR="${BASH_SOURCE[0]%/*}" ;;
    *)   _PLACEMENT_LIB_DIR="." ;;
  esac
  # shellcheck source=cmd-class.sh
  . "$_PLACEMENT_LIB_DIR/cmd-class.sh" || return 1
fi

cmd_place() {  # <command> <cwd> [<target>] -> the tree (rc 0), `moving <segment>` (rc 1); rc 2 bad cwd, rc 3 no such target
  case "${2-}" in
    /*) : ;;
    *) printf 'cmd_place: the cwd must be an absolute path, got: %s\n' "${2-}" >&2; return 2 ;;
  esac
  printf '%s' "${1-}" | _CMD_PLACE_CWD="$2" _CMD_PLACE_TARGET="${3-}" _CMD_SCRIPT_CWD="$2" _cmd_class_awk place
}
