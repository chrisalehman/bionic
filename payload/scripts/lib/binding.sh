# payload/scripts/lib/binding.sh — THE ONE WRITER OF THE SESSION MARKER.
#
# WHAT IT OWNS (wave-session-bound-run, 2026-09-04, spec §Design "Session binding";
# AC-7/AC-8/AC-9). Exactly one function, and it is the only code in this tree permitted to
# create or rewrite `<root>/.bionic/tmp/engaged-<sid>.state`:
#   bind_plan <root> <sid> <plan|none> -> 0 written · 1 refused-invalid · 2 write failure
#
# WHY A FILE OF ITS OWN, for one function. Three callers write this marker —
# `hooks/engage.sh` at invocation, `hooks/session-poker.sh bind` when the operator names a
# run, `hooks/canonical-sdlc-governing-skill.sh` when a run's plan file is first written —
# and before this wave the invariants lived inline in engage.sh, where the other two could
# not reach them. A marker is what points every wall in the fleet at a PARTICULAR plan, so
# three spellings of the write is three chances to produce a marker that reads wrong. The
# invariants are asserted once, here: the two-line shape, mode 600, the symlink refusal,
# and membership in `open_runs` at the instant of the write.
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
# every doubt resolves to NOT writing: a misshapen sid, a symlink on the path, a plan that
# is not an open run. Refusal is silent and returns 1; the caller decides what to say. A
# tree that cannot take the write is a different answer — 2 — because a refusal is the
# caller's fault and a broken tree is not.
#
# PRINTS NOTHING, EVER. Callers print; `bind_plan` reports by exit status alone.
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

# bind_plan <root> <sid> <plan|none> -> write the session's binding.
#
#   0  written: the marker is exactly `plan=<value>\nengaged_at=<iso>\n`, mode 600
#   1  refused: the sid is misshapen, the marker path is a symlink, or the plan is not an
#      absolute path that `open_runs "$root"` lists
#   2  the write itself failed (unwritable tree, a directory in the way, no clock)
bind_plan() {
  local root="$1" sid="$2" plan="$3"
  local path
  path=$(engaged_marker_path "$root" "$sid") || return 1

  # Refused BEFORE it is followed, and before anything is read out of it: a planted link
  # would otherwise have this function clobber a file outside the tree on the one write
  # bionic performs at the invocation the user just typed.
  [ -L "$path" ] && return 1

  # MEMBERSHIP, not existence. `open_runs` is the same set `session_run` rules on, so a
  # binding this accepts is one the reader will honour.
  if [ "$plan" != "none" ]; then
    local want runs cand c found=0
    want=$(_bind_resolve "$plan") || return 1
    runs=$(open_runs "$root" 2>/dev/null) || return 1
    while IFS= read -r cand; do
      [ -n "$cand" ] || continue
      c=$(_bind_resolve "$cand") || continue
      if [ "$c" = "$want" ]; then found=1; break; fi
    done <<< "$runs"
    [ "$found" -eq 1 ] || return 1
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
    [ -n "$stamp" ] || return 2
  fi

  # `umask` is shell-global, so the write runs in a subshell rather than leaking a
  # tightened mask back to a hook that has other files to create. The explicit chmod is
  # NOT redundant with it: `>` onto an existing file keeps that file's mode, so a marker
  # first written under a looser umask would stay loose forever without this.
  ( umask 077; printf 'plan=%s\nengaged_at=%s\n' "$plan" "$stamp" > "$path" ) 2>/dev/null || return 2
  chmod 600 "$path" 2>/dev/null || :
  return 0
}
