# payload/scripts/lib/binding.sh — THE ONE WRITER OF THE SESSION MARKER.
#
# WHAT IT OWNS (wave-session-bound-run, 2026-09-04, spec §Design "Session binding";
# AC-7/AC-8/AC-9). Exactly one writer function, and it is the only code in this tree permitted to
# create or rewrite `<root>/.bionic/tmp/engaged-<sid>.state`:
#   bind_plan <root> <sid> <plan|none> -> 0 written · 1 refused-invalid · 2 write failure,
#                                          and BIND_REFUSAL naming WHICH of the five
#
# WHY A FILE OF ITS OWN, for one function. Three callers write this marker —
# `hooks/engage.sh` at invocation, `hooks/session-poker.sh bind` when the operator names a
# run, `hooks/canonical-sdlc-governing-skill.sh` when a run's plan file is first written —
# and before this wave the invariants lived inline in engage.sh, where the other two could
# not reach them. A marker is what points every wall in the fleet at a PARTICULAR plan, so
# three spellings of the write is three chances to produce a marker that reads wrong. The
# invariants are asserted once, here: the two-line shape, mode 600, the symlink refusal on
# the marker path AND its two directories, the CANONICAL spelling of the plan, and membership
# in `open_runs` at the instant of the write.
#
# IT REFUSES RATHER THAN GUESSES. A bound plan must be an absolute path that `open_runs`
# lists for THIS root, checked with both sides resolved. Not "a file that exists", not "a
# path under the docs root" — the same set membership `session_run` will later rule on, so
# a binding cannot be written that the reader would then have to reject. `none` is always
# accepted and never validated: it is what engagement writes when the root holds zero or
# several open runs, and it is the marker's way of saying "unbound", not a path.
#
# ENGAGED_AT IS PRESERVED, NEVER REFRESHED. The stamp answers "since when has this session
# been inside bionic", and a session engages once however many times it invokes the skill.
# It is minted only when the existing marker has no stamp to carry forward.
#
# FAIL DIRECTION. This is the write behind the one artifact whose PRESENCE opens walls, so
# every doubt resolves to NOT writing: a misshapen sid, a symlink anywhere on the marker's
# own path, a plan that is not an open run. Refusal is silent and returns 1; the caller
# decides what to say. A
# tree that cannot take the write is a different answer — 2 — because a refusal is the
# caller's fault and a broken tree is not.
#
# PRINTS NOTHING, EVER. Callers print; `bind_plan` reports by exit status and by
# `BIND_REFUSAL` alone, and `bind_holders` (below) by exit status and `BIND_HOLDERS`.
#
# ONE READER BESIDE THE WRITER (wave-23-fixit-1810 T13, critic C-3; spec D1 Δ4).
# `bind_holders` answers the one question engagement asks before it GUESSES a binding:
# which other sessions' markers already name this plan. It lives here, not in run.sh,
# because the answer is a plan compare and `_bind_resolve` is this file's: a marker stores
# the canonical spelling `bind_plan` wrote, and the candidate comes off `open_runs`' walk,
# so both sides go through the one resolver or a symlinked root reads as two plans.
# Liveness is NOT asked here — that is the sweeper's predicate (lib/patrol.sh), and this
# file depends on run.sh alone; the caller intersects.
#
# WHICH REFUSAL IS A VARIABLE, NOT A WIDER SET OF EXIT CODES (epic-23 wave-18-fixit-185,
# REQ-2 AC-2.2; A-T3.1). Five causes shared one status, so every caller that wanted to say
# why had to re-derive it from the filesystem afterwards — hooks/session-poker.sh:3203 does
# exactly that, in a comment calling the re-derivation "POSITIONAL", and the PostToolUse
# bind arm cannot re-derive anything: by the time it runs the tool has already written the
# file. The five names below are therefore set on the way out, beside the status rather
# than inside it. WIDENING THE STATUS WAS THE FIRST DESIGN AND IT INVERTS TWO READERS
# OUTSIDE THIS FILE: tests/engage.test.sh §E8 (f)(g)(g2)(h) pins `exit 1` for four of the
# five, and hooks/session-poker.sh:3199 reads `BIND_RC -ge 2` as "the marker write failed",
# so a sixth code would report a valid refusal as a broken tree. The status contract is
# unchanged and the distinction rides beside it. [WALL: tests/binding.test.sh]
#
#   BIND_REFUSAL — empty on success, and CLEARED ON ENTRY so a reader can never attribute
#   the previous call's decline to this one:
#
#     1 sid                 the sid is empty, `unknown`, or outside [A-Za-z0-9_-]
#     2 marker-dir-symlink  `.bionic` or `.bionic/tmp` on the marker's own path is a link
#     3 marker-symlink      the marker file itself is a link
#     4 unresolvable        the plan is not an absolute path whose directory resolves, or
#                           the open-run set could not be read
#     5 not-an-open-run     the plan resolves and is not a member of `open_runs "$root"`
#     6 write-failed        the write itself failed — status 2, a broken tree and not a
#                           refusal, which is why it is numbered with them and not among them
#
# THE RUN'S SESSIONS (wave-36 T9; spec D10, design ledger Δ3 "D5 1"; AC-4.2). A `/clear`
# re-keys the session, so a reader keyed by the live session id loses what the session before
# it did. The run owns its session history instead: the act that binds a plan writes the
# binding INTO THE PLAN, one line per session, under `## SDLC State`:
#
#     - session: <sid> bound <ISO-8601 UTC> by <act>        act: engage | bind | write
#
# `bind_plan`'s fourth operand names the act (engage.sh, `session-poker.sh bind`, and the
# governing skill's bind on the Write that creates a plan). The line is written once per
# session — a later binding by the same session leaves it — never for `none` and never when
# no act is named, so a library caller of the three-operand form changes no plan. It is
# placed after the section's last `- session:` line, else after the section's last non-blank
# line, fences skipped. `bind_sessions <plan>` is its one reader. Neither the marker's
# status contract nor its shape changes: the record reports beside it, in `BIND_SESSION`:
#
#     recorded  the line was written     present  the plan already had this session's line
#     act       the act is not one of the three, nothing written
#     failed    the plan could not take the write (a symlink, not a regular file, no
#               `## SDLC State`, or the plan changed while the line was being placed); the
#               marker stands, and the session's next binding act writes it
#
# DEPENDS ON run.sh, which must be sourced first: `engaged_marker_path` owns the sid shape
# rule and the marker path, `open_runs` owns the set, `_run_lines` owns the line-ending
# translation. Every consumer names both files in its `BIONIC_LIB_WANT` line.
#
# BASH 3.2. No associative arrays, no `${var^^}`, no `mapfile`.
#
# FUNCTIONS ONLY — sourcing this file executes no top-level command and prints nothing.
#
# [WALL: tests/engage.test.sh]

# _bind_resolve <abs-path> -> the path with its DIRECTORY resolved (symlinks and `..`
# collapsed by `pwd -P`) and its final component left alone; exit 1 on a relative path or a
# directory that does not resolve.
#
# THE FINAL COMPONENT IS DELIBERATELY NOT RESOLVED. Both sides of the membership compare go
# through this, and `open_runs` reports what `find` walked — so resolving the leaf here
# would make a plan reachable through a symlink compare unequal to itself. Resolving the
# directory is what makes `/a/./b/../plans/x.md` and `/a/plans/x.md` the same binding.
_bind_resolve() {
  local p="$1" d b
  case "$p" in /*) ;; *) return 1 ;; esac
  d=$(dirname "$p")
  b=$(basename "$p")
  d=$(cd "$d" 2>/dev/null && pwd -P) || return 1
  case "$d" in
    /) printf '/%s\n' "$b" ;;
    *) printf '%s/%s\n' "$d" "$b" ;;
  esac
}

# bind_delivered <root> <resolved plan> -> 0 when the plan is one of the root's run candidates (the walk `open_runs`
# reads, lib/run.sh `_run_candidates`) whose run closed by delivery: `run_open` calls it closed, its frontmatter
# carries no `abandoned:`, and a `Step 9:` line carries `delivered:` (run_open's own test). 1 otherwise, silent.
bind_delivered() {
  local root="$1" want="$2" droot f c lines
  droot=$(docs_root "$root") || return 1
  while IFS= read -r -d '' f; do
    c=$(_bind_resolve "$f") || continue
    [ "$c" = "$want" ] || continue
    run_open "$f" && return 1
    lines=$(_run_lines "$f")
    awk 'NR == 1 && $0 == "---" { f = 1; next } f && $0 == "---" { exit } f && /^abandoned:/ { a = 1 } END { exit !a }' \
      <<< "$lines" && return 1
    grep -qE '^[[:space:]]*-?[[:space:]]*Step 9:.*delivered:' <<< "$lines"
    return
  done < <(_run_candidates "$droot")
  return 1
}

# bind_plan <root> <sid> <plan|none> [<act>] -> write the session's binding; with an act and a
# plan, the session's line in that plan too (THE RUN'S SESSIONS, above; never changes the status).
#
#   0  written: the marker is exactly `plan=<value>\nengaged_at=<iso>\n`, mode 600, and
#      <value> is the plan's CANONICAL spelling (`_bind_resolve`'s) or the literal `none`
#   1  refused: the sid is misshapen, the marker path or either of its two directories is a
#      symlink, or the plan is not an absolute path that `open_runs "$root"` lists (with the act
#      `bind`, or that `bind_delivered` admits)
#   2  the write itself failed (unwritable tree, a directory in the way, no clock)
#
# THE BIND VERB MAY NAME A DELIVERED RUN (wave-36 T14; D13, AC-7.7; ruling r1791955629-34788). With the act `bind`
# (session-poker.sh's verb, and only it), a delivered plan of this root is admitted too, and BIND_DELIVERED reads
# `yes`: the session then reads it `bound-closed`, which opens nothing but `task-set --reason`. Engagement
# (`engage`), the governing skill's Write (`write`) and an act-less call keep the open-run set, unchanged.
bind_plan() {
  local root="$1" sid="$2" plan="$3" act="${4:-}"
  local path
  # CLEARED FIRST, ABOVE EVERY ARM THAT COULD REFUSE.
  BIND_REFUSAL=""; BIND_SESSION=""; BIND_DELIVERED=""
  path=$(engaged_marker_path "$root" "$sid") || { BIND_REFUSAL="sid"; return 1; }

  # THE WHOLE MARKER PATH, NOT JUST ITS LEAF (S10a, review SEC F1). A leaf-only `-L` test
  # answers "is the marker a link" and leaves "is the marker's DIRECTORY a link" unasked, so
  # a tree shipping `.bionic/tmp` — or `.bionic` — as a symlink had this function create a
  # file outside the root while every check passed. Both ancestors are derived from `$path`
  # rather than rebuilt from `$root`, because `engaged_marker_path` owns that spelling and a
  # second copy of it here is a second place for the layout to drift.
  local mtmp mbio
  mtmp=$(dirname "$path")
  mbio=$(dirname "$mtmp")
  if [ -L "$mtmp" ] || [ -L "$mbio" ]; then BIND_REFUSAL="marker-dir-symlink"; return 1; fi

  # Refused BEFORE it is followed, and before anything is read out of it: a planted link
  # would otherwise have this function read a stamp out of, and then clobber, a file outside
  # the tree on the one write bionic performs at the invocation the user just typed. It is
  # tested AGAIN immediately before the write — see there for why once is not enough.
  [ -L "$path" ] && { BIND_REFUSAL="marker-symlink"; return 1; }

  # MEMBERSHIP, not existence. `open_runs` is the same set `session_run` rules on, so a
  # binding this accepts is one the reader will honour.
  #
  # `want` IS WHAT GETS STORED (S10a, review SEC "one correctness note"). This validated a
  # RESOLVED spelling and then wrote the RAW argument, so a caller passing
  # `<docs>/plans/../plans/p.md` — or reaching the root through a symlinked alias — left a
  # marker whose text does not share the docs-root prefix it was checked against. Nothing
  # compares on that prefix today; the point is that the next thing to try would be wrong,
  # and the one site that already compares two spellings (`adopt_plan_key`) has to normalize
  # at compare time to work around it. Storing the canonical spelling costs nothing.
  local value="$plan"
  if [ "$plan" != "none" ]; then
    local want runs cand c found=0
    want=$(_bind_resolve "$plan") || { BIND_REFUSAL="unresolvable"; return 1; }
    runs=$(open_runs "$root" 2>/dev/null) || runs=""
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      c=$(_bind_resolve "$cand") || continue
      if [ "$c" = "$want" ]; then found=1; break; fi
    done <<< "$runs"
    if [ "$found" -eq 0 ] && [ "$act" = bind ] && bind_delivered "$root" "$want"; then
      found=1; BIND_DELIVERED=yes
    fi
    if [ "$found" -eq 0 ]; then
      # An open-run set that could not be read stays `unresolvable`, as it was before the delivered arm.
      [ -n "$runs" ] || { BIND_REFUSAL="unresolvable"; return 1; }
      BIND_REFUSAL="not-an-open-run"; return 1
    fi
    value="$want"
  fi

  # ENGAGED_AT: carried forward from whatever is on disk, minted only when there is
  # nothing to carry. Read through `_run_lines` so a marker that went through a
  # CRLF-normalising tool does not bake a trailing CR into the value forever — every
  # consumer reads that stamp as text.
  local stamp=""
  if [ -f "$path" ]; then
    local lines
    lines=$(_run_lines "$path")
    stamp=$(grep -m1 -E '^engaged_at=' <<< "$lines" | sed -E 's/^engaged_at=//')
  fi
  if [ -z "$stamp" ]; then
    stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || stamp=""
    [ -n "$stamp" ] || { BIND_REFUSAL="write-failed"; return 2; }
  fi

  # THE LEAF IS TESTED AGAIN, HERE, AND THAT IS THE ONE THAT MATTERS (S10a, review SEC F2).
  # Between the first `-L` above and this write sit `_bind_resolve`, the WHOLE `open_runs`
  # walk — seconds, not microseconds, at a few hundred open plans — and the `engaged_at`
  # read. A `>` redirect follows a link planted inside that window, and `umask`/`chmod`
  # govern the MODE of whatever the write lands on, not what it lands on. Re-testing
  # immediately before the redirect shrinks the window to the gap between two adjacent
  # commands, at the cost of one `test`. The earlier check is not redundant: it is what keeps
  # the `engaged_at` read above from following a link out of the tree in the first place.
  [ -L "$path" ] && { BIND_REFUSAL="marker-symlink"; return 1; }

  # `umask` is shell-global, so the write runs in a subshell rather than leaking a
  # tightened mask back to a hook that has other files to create. The explicit chmod is
  # NOT redundant with it: `>` onto an existing file keeps that file's mode, so a marker
  # first written under a looser umask would stay loose forever without this.
  ( umask 077; printf 'plan=%s\nengaged_at=%s\n' "$value" "$stamp" > "$path" ) 2>/dev/null \
    || { BIND_REFUSAL="write-failed"; return 2; }
  chmod 600 "$path" 2>/dev/null || :
  # THE RUN'S SESSIONS: after the marker, so a plan line never exists for a binding that was
  # not written. Its outcome rides in BIND_SESSION; the binding's status is the marker's.
  if [ -n "$act" ] && [ "$value" != "none" ]; then
    bind_record_session "$value" "$sid" "$act" || :
  fi
  return 0
}

# BIND_SESSION_ACTS — the acts that bind, and so the only words a session line's `by` carries.
BIND_SESSION_ACTS="engage bind write"

# bind_sessions <plan> -> the sessions the run recorded, one id per line, in the order they
# bound (each once); exit 1 when the plan is not a readable file. The lines are read under the
# FIRST flush-left `## SDLC State`, fences skipped, as every reader of that section reads it,
# and an id outside the marker's own shape rule ([A-Za-z0-9_-], not `unknown`) is skipped: a
# reader turns an id into a transcript path, so a hand-typed `../x` must never reach one.
bind_sessions() {  # <plan>
  local plan="${1:-}"
  [ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || return 1
  awk '
    /^[ \t]*```/ { fence = !fence; next }
    fence { next }
    /^##[ \t]/ { if (sdlc == 1) sdlc = 2; if (!seen && $0 ~ /^##[ \t]+SDLC State([ \t].*)?\r?$/) { sdlc = 1; seen = 1 }; next }
    sdlc == 1 && /^- session:[ \t]/ {
      sub(/\r$/, ""); split($0, f, /[ \t]+/); s = f[3]
      if (s ~ /^[A-Za-z0-9_-]+$/ && s != "unknown" && !(s in got)) { got[s] = 1; print s }
    }' "$plan"
}

# bind_record_session <plan> <sid> <act> -> the session's line written into <plan>, once.
#   0 recorded · 1 present · 2 act (not one of BIND_SESSION_ACTS) · 3 failed; BIND_SESSION
#   names which. Prints nothing.
#
# THE PLAN IS REPLACED, NOT EDITED IN PLACE, as every plan verb replaces it
# (hooks/session-poker.sh `plan_verb_swap`): the new text goes to a sibling file, the plan's
# checksum is compared with the one read before, and the sibling is moved over the plan. A plan
# that changed in between is left alone — a verb's write wins, and the session's next binding
# act writes the line. The sibling takes the plan's own mode and mtime before the move.
bind_record_session() {  # <plan> <sid> <act>
  local plan="${1:-}" sid="${2:-}" act="${3:-}" iso sum tmp mode line
  BIND_SESSION=""
  case "$act" in ''|*[!a-z]*) BIND_SESSION="act"; return 2 ;; esac
  case " $BIND_SESSION_ACTS " in *" $act "*) ;; *) BIND_SESSION="act"; return 2 ;; esac
  case "$sid" in ''|unknown|*[!A-Za-z0-9_-]*) BIND_SESSION="failed"; return 3 ;; esac
  { [ -f "$plan" ] && [ ! -L "$plan" ]; } || { BIND_SESSION="failed"; return 3; }
  if bind_sessions "$plan" | grep -qxF -- "$sid"; then BIND_SESSION="present"; return 1; fi
  iso=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) && [ -n "$iso" ] || { BIND_SESSION="failed"; return 3; }
  line="- session: $sid bound $iso by $act"
  sum=$(cksum < "$plan" 2>/dev/null) || { BIND_SESSION="failed"; return 3; }
  tmp="$(dirname "$plan")/.$(basename "$plan").session-$$"
  { [ ! -e "$tmp" ] && [ ! -L "$tmp" ]; } || { BIND_SESSION="failed"; return 3; }
  if ! BS_LINE="$line" awk '
    BEGIN { line = ENVIRON["BS_LINE"] }
    { L[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        l = L[i]
        if (l ~ /^[ \t]*```/) { fence = !fence; continue }
        if (fence) continue
        if (l ~ /^##[ \t]/) {
          if (sdlc == 1) sdlc = 2
          if (!seen && l ~ /^##[ \t]+SDLC State([ \t].*)?\r?$/) { sdlc = 1; seen = 1; last = i }
          continue
        }
        if (sdlc != 1) continue
        if (l ~ /[^ \t\r]/) last = i
        if (l ~ /^- session:[ \t]/) sess = i
      }
      if (!seen) exit 1
      at = sess ? sess : last
      for (i = 1; i <= n; i++) { print L[i]; if (i == at) print line }
    }' "$plan" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; BIND_SESSION="failed"; return 3
  fi
  mode=$(stat -f %Lp "$plan" 2>/dev/null || stat -c %a "$plan" 2>/dev/null) && chmod "$mode" "$tmp" 2>/dev/null
  # THE PLAN'S MTIME IS KEPT. Recording a session is bookkeeping, not work on the run, and the fleet
  # reads mtime as activity: `live_runs`' window and the newest-plan fallback (lib/run.sh) would
  # otherwise rank a plan by when a session last bound it.
  touch -r "$plan" "$tmp" 2>/dev/null || :
  if [ "$(cksum < "$plan" 2>/dev/null)" != "$sum" ] || ! mv -f "$tmp" "$plan" 2>/dev/null; then
    rm -f "$tmp"; BIND_SESSION="failed"; return 3
  fi
  BIND_SESSION="recorded"
  return 0
}

# bind_holders <root> <sid> <plan> -> 0 and BIND_HOLDERS = the OTHER sessions whose marker
# names <plan>, one id per line; 1 and BIND_HOLDERS empty when none does.
#
# THE MARKERS ARE READ THROUGH `session_plan`, so every guard the readers apply applies
# here too: the sid shape rule (a file whose id `engaged_marker_path` refuses is skipped,
# never read), a symlinked marker skipped before it is followed, CRLF translated, and the
# four "no binding" shapes — absent, empty, no `plan=`, `plan=none` — naming nothing.
# The caller's own marker is skipped by id: a session never holds a run against itself.
bind_holders() {  # <root> <sid> <plan>
  local root="$1" self="$2" plan="$3"
  local mine dir want f base osid op
  BIND_HOLDERS=""
  mine=$(engaged_marker_path "$root" "$self") || return 1
  want=$(_bind_resolve "$plan") || return 1
  dir=$(dirname "$mine")
  for f in "$dir"/engaged-*.state; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    base="${f##*/}"; osid="${base#engaged-}"; osid="${osid%.state}"
    [ "$osid" != "$self" ] || continue
    [ "$(engaged_marker_path "$root" "$osid" 2>/dev/null)" = "$f" ] || continue
    op=$(session_plan "$root" "$osid") || continue
    op=$(_bind_resolve "$op") || continue
    [ "$op" = "$want" ] || continue
    BIND_HOLDERS="${BIND_HOLDERS}${BIND_HOLDERS:+
}${osid}"
  done
  [ -n "$BIND_HOLDERS" ]
}
