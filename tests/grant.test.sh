#!/bin/bash
# tests/grant.test.sh — payload/scripts/lib/grant.sh: THE GRANT (epic-23 wave-25-never-paused,
# REQ-2, REQ-3, REQ-4, REQ-7; spec D2, D4, D6; ADR-042).
#
# WHAT IT OWNS. The verdict the permission answer gives and the words it gives it in. Four
# functions, one question each:
#
#   grant_roots <class> <key=value>...   which roots a class gets from the facts it is handed
#   grant_decide <class> <w> <d> <fx> [<category>]
#                                        allow, deny-fix or deny-reserved, and why
#   grant_reserved <tool> <command|path> which reserved category an action falls in, if any
#   grant_resolve <path>                 the real location of a path, or a mark that it has none
#
# One section per Eval-design row of the spec that names this suite, §G1 to §G10, each built
# to go red on the planted defect its matrix block names under `fails-when:`. §G0 is the
# purity rule the decision rests on (the freeze): the decision and the reserved table read no
# file, no environment and run no git, so the same facts give the same verdict anywhere.
#
# THE FACTS ARE STRINGS. §G1–§G4 and §G6–§G10 hand the lib invented absolute paths; nothing on
# disk is consulted, because nothing the decision does may consult it. §G5 alone builds a
# real directory with real symlinks under one mktemp sandbox, because resolving is the one
# thing that must touch the disk.
#
# HERMETIC. Every call sources the lib in a CHILD shell, so no row is answered by state an
# earlier row left behind, and a missing or broken lib yields empty output and a red row
# rather than a dead suite.
#
# FIXTURE FIDELITY (declared, per .claude/rules/test-harness.md, "Fixture fidelity"):
#   * The project paths are SYNTHESIZED in the shape of this run's own: `.worktrees/<wave>-T<n>`
#     trees beside the main checkout, `.bionic/docs/record/<wave>/`, a plan under
#     `.bionic/docs/plans/<epic>/`, and the session scratch as the harness spells it
#     (`/private/tmp/claude-<uid>/<project slug>/<sid>/scratchpad`, research-R2 §3).
#   * The effect lines are SYNTHESIZED in the reader's interface shape (`W|D<TAB>path`,
#     `?<TAB>reason<TAB>segment`, plan Interfaces "effects"); the reader itself is T2's and
#     is not called here, so §G8's table miss hands the decision the line the reader prints
#     for a command off its pure-reader list.
#   * The state-file names are the prefixes `.bionic/tmp` holds today (roster-, engaged-,
#     patrol-) and the two this wave adds (workspaces-, gate-).
#   * The answer log's path is read from `lib/root.sh` (`answers_path` when present, else
#     `audit_path`'s directory, where D9 places it), never retyped.
#   * Every class is handed MORE facts than D4 gives it (`ALL_FACTS`), so a class that took a
#     fact meant for another would allow a row that must deny.
#
# ANTI-VACUITY (per .claude/rules/test-harness.md, "Anti-vacuity"): every deny row sits in a
# section with an allow row on the same facts (G1.1, G2.1, G3.1, G4.1, G5.11, G6.<class>.0,
# G10.<class>.0), so a lib that denied everything is red too; §G0's absence checks are each
# preceded by a proof that their probe reads non-empty.
#
# Usage: bash tests/grant.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# GRANT_TEST_LIB and GRANT_TEST_ROOT_LIB let a mutation run point the suite at a planted
# copy; unset, each is the shipped lib.
LIB="${GRANT_TEST_LIB:-$REPO_ROOT/payload/scripts/lib/grant.sh}"
ROOT_LIB="${GRANT_TEST_ROOT_LIB:-$REPO_ROOT/payload/scripts/lib/root.sh}"

SANDBOX="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/grant-test.XXXXXX")" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

TAB=$'\t'
NL=$'\n'

# call <fn> <args...> — one lib function in a child shell; its status is left in CALL_RC.
CALL_RC=0
call() {
  local fn="$1" out; shift
  out="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; fn="$2"; shift 2; "$fn" "$@"' \
         _ "$LIB" "$fn" "$@" 2>"$SANDBOX/.err" </dev/null)"
  CALL_RC=$?
  printf '%s' "$out"
}

# THE DRIVER is what the hook does in order: compose the roots from facts, then decide.
# Facts travel as one newline-separated string of key=value words.
DRIVER='. "$1" >/dev/null 2>&1 || exit 127
cls="$2"; facts="$3"; eff="$4"; res="${5-}"
set --
while IFS= read -r f; do
  [ -n "$f" ] && set -- "$@" "$f"
done <<GRANT_FACTS
$facts
GRANT_FACTS
grant_roots "$cls" "$@" || exit $?
grant_decide "$cls" "$GRANT_WRITE_ROOTS" "$GRANT_DELETE_ROOTS" "$eff" "$res"'

# dec <class> <facts> <effects> [<category>] — the verdict line.
dec() {
  local out
  out="$(bash -c "$DRIVER" _ "$LIB" "$@" 2>"$SANDBOX/.err" </dev/null)"
  CALL_RC=$?
  printf '%s' "$out"
}

# kind <verdict line> — allow, deny-fix or deny-reserved. fld <n> <line> — the nth TAB field.
kind() { printf '%s' "${1%%"$TAB"*}"; }
fld() { printf '%s\n' "$2" | cut -f"$1"; }

# Effect lines, as the reader prints them.
W() { printf 'W\t%s' "$1"; }
D() { printf 'D\t%s' "$1"; }
U() { printf '?\t%s\t%s' "$1" "$2"; }

# THE FIXTURE PROJECT. Invented paths; the shape is a real run's.
P=/w/proj                                        # the main checkout
WAVE=$P/.worktrees/25-never-paused               # the wave checkout
T1=$P/.worktrees/25-T1                           # a writer's recorded tree
T10=$P/.worktrees/25-T10                         # its sibling, one digit longer
T1OLD=$P/.worktrees/25-T1-old                    # a sibling sharing its prefix
OTHER=$P/.worktrees/24-T27                       # a tree another session recorded
S=/private/tmp/claude-501/-w-proj/sid-1/scratchpad
REC=$P/.bionic/docs/record/wave-25-never-paused
PLAN=$P/.bionic/docs/plans/epic-23/wave-25-never-paused.plan.md
REPORT=$REC/R1-report.md

# Every fact the hook could know, handed to every class: a class takes only what D4 gives it.
ALL_FACTS="checkout=$WAVE${NL}tree=$T1${NL}tree=$T10${NL}own=$T1${NL}scratch=$S${NL}record=$REC${NL}plan=$PLAN${NL}report=$REPORT"
LEAD_FACTS="checkout=$WAVE${NL}tree=$T1${NL}tree=$T10${NL}scratch=$S${NL}record=$REC${NL}plan=$PLAN"
WRITER_FACTS="$ALL_FACTS"
READER_FACTS="checkout=$WAVE${NL}tree=$T1${NL}scratch=$S${NL}record=$REC${NL}plan=$PLAN${NL}report=$REPORT"
UNBOUND_FACTS="$ALL_FACTS"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G0 purity: the decision and the reserved table read no file, no environment, no git"

# The same facts under two different homes, two working directories and a scrubbed
# environment give byte-identical verdicts. A decision that expanded `~` from HOME, or read
# a file relative to where it stands, would differ between the runs.
G0_CASES="lead|$(W "$WAVE/a")|
writer|$(W "$T10/f")|
reader|$(U 'command is not on the pure-reader list' 'make build')|
writer||leaves-the-machine"
g0_run() {  # <scrub|keep> <home> <cwd> → every case's verdict, one per line
  local mode="$1" home="$2" cwd="$3" cls eff res
  while IFS='|' read -r cls eff res; do
    if [ "$mode" = scrub ]; then
      (cd "$cwd" && env -i PATH="$PATH" HOME="$home" bash -c "$DRIVER" _ "$LIB" "$cls" "$ALL_FACTS" "$eff" "$res" </dev/null)
    else
      (cd "$cwd" && HOME="$home" BIONIC_ROOT=/elsewhere CLAUDE_PROJECT_DIR=/elsewhere \
        bash -c "$DRIVER" _ "$LIB" "$cls" "$ALL_FACTS" "$eff" "$res" </dev/null)
    fi
    echo
  done <<< "$G0_CASES"
}
mkdir -p "$SANDBOX/g0a" "$SANDBOX/g0b"
G0A="$(g0_run scrub /nowhere-a "$SANDBOX/g0a")"
G0B="$(g0_run keep "$SANDBOX/g0b" /)"
expect_contains "G0.1 the purity fixture yields verdicts (non-empty readback)" "allow" "$G0A"
expect_contains "G0.2 …and a denial among them" "deny-fix" "$G0A"
expect_eq "G0.3 two homes, two directories, one environment scrubbed: identical verdicts" "$G0A" "$G0B"

R0A="$(cd "$SANDBOX/g0a" && env -i PATH="$PATH" HOME=/Users/alice bash -c '. "$1" >/dev/null 2>&1 || exit 127; grant_reserved Bash "cat /Users/alice/.ssh/id_ed25519"' _ "$LIB")"
R0B="$(cd / && env -i PATH="$PATH" HOME=/nowhere bash -c '. "$1" >/dev/null 2>&1 || exit 127; grant_reserved Bash "cat /Users/alice/.ssh/id_ed25519"' _ "$LIB")"
expect_eq "G0.4 a credential path is reserved by its shape, not by the reader's HOME" "credentials" "$R0A"
expect_eq "G0.5 …the same verdict under another HOME" "$R0A" "$R0B"

# No git runs: a `git` first on PATH leaves a mark when invoked. The mark is proved to work
# before its absence is read.
mkdir -p "$SANDBOX/fakebin"
printf '#!/bin/sh\necho ran >> "%s/git-ran"\n' "$SANDBOX" > "$SANDBOX/fakebin/git"
chmod +x "$SANDBOX/fakebin/git"
PATH="$SANDBOX/fakebin:$PATH" git status >/dev/null 2>&1
expect_eq "G0.6 the trap git leaves its mark when it runs (the probe works)" "ran" "$(cat "$SANDBOX/git-ran" 2>/dev/null)"
: > "$SANDBOX/git-ran"
G0R="$(PATH="$SANDBOX/fakebin:$PATH" bash -c '. "$1" >/dev/null 2>&1 || exit 127; grant_reserved Bash "git push origin wave/25-never-paused"; grant_decide lead "/w" "/w" "$(printf "W\t/w/x")"' _ "$LIB")"
expect_eq "G0.7 a push is read and decided with the trap git on PATH" "leaves-the-machine${NL}allow" "$G0R"
expect_eq "G0.8 …and git never ran" "" "$(cat "$SANDBOX/git-ran" 2>/dev/null)"

# Static: no function the lib defines, other than the resolver, carries a filesystem reach.
# The extractor is proved on the resolver first, where the reach is meant to be.
G0_FNS="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; declare -F | awk "{print \$3}" | grep -E "^_?grant_"' _ "$LIB")"
G0_RESOLVER="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; declare -f grant_resolve' _ "$LIB")"
expect_regex "G0.9 the extractor sees the resolver's reach (readlink, pwd -P)" 'readlink' "$G0_RESOLVER"
expect_regex "G0.10 the lib defines the four public functions" '^grant_decide$' "$G0_FNS"
G0_REACH=""
while IFS= read -r fn; do
  case "$fn" in grant_resolve|_grant_resolve*|'') continue ;; esac
  body="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; declare -f "$2"' _ "$LIB" "$fn")"
  if printf '%s' "$body" | grep -Eq 'readlink|pwd|(^|[^-_[:alnum:]])cd |\[ -[edfLrs] |\$\{?HOME|(^|[^<])< *[/"$]|(^|[^-_[:alnum:]])cat '; then
    G0_REACH="$G0_REACH $fn"
  fi
done <<< "$G0_FNS"
expect_eq "G0.11 no function but the resolver reads a file, a home or a directory" "" "$G0_REACH"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G1 a writer inside its recorded tree is allowed; a sibling or the main checkout is not"

expect_eq "G1.1 a write in the writer's own tree allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W "$T1/payload/x.sh")")"
expect_eq "G1.2 a delete in the writer's own tree allows" "allow" "$(dec writer "$WRITER_FACTS" "$(D "$T1/a/b")")"
expect_eq "G1.3 the tree root itself is inside the tree" "allow" "$(dec writer "$WRITER_FACTS" "$(W "$T1")")"
expect_eq "G1.4 a write to the sibling tree 25-T10 is deny-fix (path components, not a prefix)" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W "$T10/f")")")"
expect_eq "G1.5 a write to 25-T1-old is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W "$T1OLD/f")")")"
expect_eq "G1.6 a write in the main checkout is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W "$P/payload/x.sh")")")"
expect_eq "G1.7 a write in the wave checkout is deny-fix for a writer" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W "$WAVE/x")")")"
expect_eq "G1.8 a write in the scratch allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W "$S/run.sh")")"
expect_eq "G1.9 one effect inside and one outside is deny-fix: every effect must be inside" "deny-fix" \
  "$(kind "$(dec writer "$WRITER_FACTS" "$(W "$T1/a")${NL}$(D "$T10/b")")")"
expect_eq "G1.10 no effects at all (a pure reader) allows" "allow" "$(dec writer "$WRITER_FACTS" "")"
# The containment rule on bare roots, without the composer in between.
expect_eq "G1.11 root /x/25-T1 contains /x/25-T1/a/b" "allow" "$(call grant_decide writer "/x/25-T1" "/x/25-T1" "$(W /x/25-T1/a/b)")"
expect_eq "G1.12 root /x/25-T1 does not contain /x/25-T10/f" "deny-fix" "$(kind "$(call grant_decide writer "/x/25-T1" "/x/25-T1" "$(W /x/25-T10/f)")")"
expect_eq "G1.13 root /x/25-T1 does not contain /x/25-T1-old/f" "deny-fix" "$(kind "$(call grant_decide writer "/x/25-T1" "/x/25-T1" "$(D /x/25-T1-old/f)")")"
expect_eq "G1.14 a root written with a trailing slash contains its tree" "allow" "$(call grant_decide writer "/x/25-T1/" "/x/25-T1/" "$(W /x/25-T1/f)")"
expect_eq "G1.15 a root of / grants nothing" "deny-fix" "$(kind "$(call grant_decide lead "/" "/" "$(W /etc/hosts)")")"
expect_eq "G1.16 an unknown class is malformed input, rc 2" "2" "$(call grant_decide admin "/x" "/x" "$(W /x/f)" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G1.17 an unknown effect kind is malformed input, rc 2" "2" "$(call grant_decide writer "/x" "/x" "X${TAB}/x/f" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G1.18 a W line with no path is malformed input, rc 2" "2" "$(call grant_decide writer "/x" "/x" "W${TAB}" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G1.19 a ? line with no segment field is malformed input, rc 2" "2" "$(call grant_decide writer "/x" "/x" "?${TAB}reason" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G1.20 a verdict is rc 0" "0" "$(call grant_decide writer "/x" "/x" "$(W /y/f)" >/dev/null; printf '%s' "$CALL_RC")"
G1_ONE="$(call grant_decide writer "/x" "/x" "$(W /y/f)${NL}$(W /z/f)")"
expect_nonempty "G1.21 a two-effect denial prints a verdict" "$G1_ONE"
expect_eq "G1.22 …exactly one line of it" "1" "$(printf '%s\n' "$G1_ONE" | wc -l | tr -d ' ')"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G2 the lead is allowed inside what the run created, and nowhere else"

expect_eq "G2.1 the wave checkout allows" "allow" "$(dec lead "$LEAD_FACTS" "$(W "$WAVE/payload/x.sh")")"
expect_eq "G2.2 a tree this session recorded allows, write and delete" "allow" "$(dec lead "$LEAD_FACTS" "$(W "$T1/f")${NL}$(D "$T10/g")")"
expect_eq "G2.3 the scratch allows" "allow" "$(dec lead "$LEAD_FACTS" "$(D "$S/tmp.txt")")"
expect_eq "G2.4 the record dir allows" "allow" "$(dec lead "$LEAD_FACTS" "$(W "$REC/T3-grant.md")")"
expect_eq "G2.5 the plan file allows" "allow" "$(dec lead "$LEAD_FACTS" "$(W "$PLAN")")"
expect_eq "G2.6 a tree another session recorded is deny-fix" "deny-fix" "$(kind "$(dec lead "$LEAD_FACTS" "$(W "$OTHER/f")")")"
expect_eq "G2.7 the main checkout is deny-fix" "deny-fix" "$(kind "$(dec lead "$LEAD_FACTS" "$(W "$P/README.md")")")"
expect_eq "G2.8 another plan beside the run's is deny-fix" "deny-fix" "$(kind "$(dec lead "$LEAD_FACTS" "$(W "$P/.bionic/docs/plans/epic-23/wave-24.plan.md")")")"
expect_eq "G2.9 a lead with no facts at all has no grant" "deny-fix" "$(kind "$(dec lead "" "$(W "$WAVE/x")")")"
expect_eq "G2.10 a missing fact contributes no root: no scratch known, the scratch is outside" "deny-fix" \
  "$(kind "$(dec lead "checkout=$WAVE" "$(W "$S/x")")")"
expect_eq "G2.11 an unknown fact key is malformed input, rc 2" "2" "$(dec lead "project=$P" "$(W "$P/x")" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G2.12 a fact carrying a newline cannot smuggle a root in" "deny-fix" \
  "$(kind "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; grant_roots writer "own=/x/a
/etc" ; grant_decide writer "$GRANT_WRITE_ROOTS" "$GRANT_DELETE_ROOTS" "$(printf "W\t/etc/hosts")"' _ "$LIB")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G3 a read-only agent has the scratch and its declared report"

expect_eq "G3.1 the scratch allows a write" "allow" "$(dec reader "$READER_FACTS" "$(W "$S/notes.md")")"
expect_eq "G3.2 the scratch allows a delete" "allow" "$(dec reader "$READER_FACTS" "$(D "$S/notes.md")")"
expect_eq "G3.3 the declared report allows a write" "allow" "$(dec reader "$READER_FACTS" "$(W "$REPORT")")"
expect_eq "G3.4 a tracked file is deny-fix" "deny-fix" "$(kind "$(dec reader "$READER_FACTS" "$(W "$P/payload/scripts/lib/grant.sh")")")"
expect_eq "G3.5 the wave checkout is deny-fix (no inherited lead grant)" "deny-fix" "$(kind "$(dec reader "$READER_FACTS" "$(W "$WAVE/x")")")"
expect_eq "G3.6 a recorded tree is deny-fix" "deny-fix" "$(kind "$(dec reader "$READER_FACTS" "$(W "$T1/x")")")"
expect_eq "G3.7 another file in the record dir is deny-fix" "deny-fix" "$(kind "$(dec reader "$READER_FACTS" "$(W "$REC/other.md")")")"
expect_eq "G3.8 deleting its own report is deny-fix (write only)" "deny-fix" "$(kind "$(dec reader "$READER_FACTS" "$(D "$REPORT")")")"
expect_eq "G3.9 the report path grants only itself, not files beside or under it" "deny-fix" "$(kind "$(dec reader "$READER_FACTS" "$(W "$REPORT.bak")")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G4 the record is add-only for agents; the lead may delete there"

expect_eq "G4.1 a writer's write under the record dir allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W "$REC/T3-grant.md")")"
expect_eq "G4.2 a writer's delete under the record dir is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(D "$REC/T3-grant.md")")")"
expect_eq "G4.3 the lead's delete under the record dir allows" "allow" "$(dec lead "$LEAD_FACTS" "$(D "$REC/T3-grant.md")")"
G4_MSG="$(dec writer "$WRITER_FACTS" "$(D "$REC/T3-grant.md")")"
expect_contains "G4.4 the writer's denial names the record file" "$REC/T3-grant.md" "$G4_MSG"
expect_contains "G4.5 …and says it may add there but not delete" "not delete" "$G4_MSG"
expect_eq "G4.6 a writer's move out of the record (a delete of its source) is deny-fix" "deny-fix" \
  "$(kind "$(dec writer "$WRITER_FACTS" "$(D "$REC/a.md")${NL}$(W "$T1/a.md")")")"
expect_eq "G4.7 an unbound session's record write is deny-fix (the scratch only)" "deny-fix" "$(kind "$(dec unbound "$UNBOUND_FACTS" "$(W "$REC/x.md")")")"
expect_eq "G4.8 an unbound session's scratch write allows" "allow" "$(dec unbound "$UNBOUND_FACTS" "$(W "$S/x.md")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G5 a path that resolves outside is outside: symlinks and .. are resolved first"

# A real tree. `out` and `abs` point outside it, `dangling` names a file outside that does not
# exist yet, and `.bionic` points at a separate record tree, the way a worktree's own does.
G5=$SANDBOX/g5
mkdir -p "$G5/tree/sub" "$G5/outside" "$G5/docs/record"
: > "$G5/tree/real.txt"
ln -s ../outside "$G5/tree/out"
ln -s "$G5/outside" "$G5/tree/abs"
ln -s "$G5/outside/new.txt" "$G5/tree/dangling"
ln -s "$G5/docs" "$G5/tree/.bionic"
G5_FACTS="own=$G5/tree${NL}scratch=$SANDBOX/g5-scratch${NL}record=$G5/docs/record"

expect_eq "G5.1 a real file resolves to itself" "$G5/tree/real.txt" "$(call grant_resolve "$G5/tree/real.txt")"
expect_eq "G5.2 a file that does not exist yet resolves under its real parent" "$G5/tree/sub/new.txt" "$(call grant_resolve "$G5/tree/sub/new.txt")"
expect_eq "G5.3 a target through a relative symlink resolves outside" "$G5/outside/f" "$(call grant_resolve "$G5/tree/out/f")"
expect_eq "G5.4 a target through an absolute symlink resolves outside" "$G5/outside/f" "$(call grant_resolve "$G5/tree/abs/f")"
expect_eq "G5.5 a dangling symlink resolves to where it would write" "$G5/outside/new.txt" "$(call grant_resolve "$G5/tree/dangling")"
expect_eq "G5.6 tree/../x resolves beside the tree" "$G5/x" "$(call grant_resolve "$G5/tree/../x")"
expect_eq "G5.7 a resolved path is rc 0" "0" "$(call grant_resolve "$G5/tree/real.txt" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G5.8 a relative path is marked unresolved" "?${TAB}tree/real.txt" "$(call grant_resolve "tree/real.txt")"
expect_eq "G5.9 …rc 1" "1" "$(call grant_resolve "tree/real.txt" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G5.10 .. through a directory that does not exist is marked unresolved" "?${TAB}$G5/tree/nope/../x" "$(call grant_resolve "$G5/tree/nope/../x")"

# Resolved, then decided: what the hook does.
expect_eq "G5.11 a write to a real file in the tree allows" "allow" \
  "$(dec writer "$G5_FACTS" "$(W "$(call grant_resolve "$G5/tree/real.txt")")")"
expect_eq "G5.12 a write through the symlink that points out is deny-fix" "deny-fix" \
  "$(kind "$(dec writer "$G5_FACTS" "$(W "$(call grant_resolve "$G5/tree/out/f")")")")"
expect_eq "G5.13 a write through the dangling symlink is deny-fix" "deny-fix" \
  "$(kind "$(dec writer "$G5_FACTS" "$(W "$(call grant_resolve "$G5/tree/dangling")")")")"
expect_eq "G5.14 a write to tree/../x is deny-fix" "deny-fix" \
  "$(kind "$(dec writer "$G5_FACTS" "$(W "$(call grant_resolve "$G5/tree/../x")")")")"
expect_eq "G5.15 the record through the tree's own .bionic link: a write allows" "allow" \
  "$(dec writer "$G5_FACTS" "$(W "$(call grant_resolve "$G5/tree/.bionic/record/T3.md")")")"
expect_eq "G5.16 …and a delete there is deny-fix, though the path is spelled inside the tree" "deny-fix" \
  "$(kind "$(dec writer "$G5_FACTS" "$(D "$(call grant_resolve "$G5/tree/.bionic/record/T3.md")")")")"
# Unresolved paths handed straight to the decision are never inside.
expect_eq "G5.17 an unresolved tree/../x handed to the decision is deny-fix" "deny-fix" \
  "$(kind "$(call grant_decide writer "$G5/tree" "$G5/tree" "$(W "$G5/tree/../x")")")"
expect_eq "G5.18 a path ending in /.. is deny-fix" "deny-fix" \
  "$(kind "$(call grant_decide writer "$G5/tree" "$G5/tree" "$(D "$G5/tree/sub/..")")")"
expect_eq "G5.19 a relative path is deny-fix" "deny-fix" \
  "$(kind "$(call grant_decide writer "$G5/tree" "$G5/tree" "$(W "real.txt")")")"
expect_eq "G5.20 the resolver's unresolved mark, passed on as a path, is deny-fix" "deny-fix" \
  "$(kind "$(call grant_decide writer "$G5/tree" "$G5/tree" "W${TAB}$(call grant_resolve "tree/real.txt")")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G6 bionic's own state files are in no grant, the lead's included"

# Every class is handed a root that CONTAINS .bionic/tmp, so only the state rule can deny:
# the lead's checkout is the main checkout, the writer's tree is too, and the reader's and
# the unbound session's scratch is .bionic/tmp itself.
G6_TMP=$P/.bionic/tmp
G6_CASES="lead|checkout=$P|$P/README.md
writer|own=$P|$P/README.md
reader|scratch=$G6_TMP|$G6_TMP/notes.txt
unbound|scratch=$G6_TMP|$G6_TMP/notes.txt"
while IFS='|' read -r cls fact ok_path; do
  expect_eq "G6.$cls.0 $cls: an ordinary file under the same root allows (the root is live)" "allow" \
    "$(dec "$cls" "$fact" "$(W "$ok_path")")"
  for st in roster-sid-1.state engaged-sid-1.state patrol-sid-1.state workspaces-sid-1.state gate-sid-1.state; do
    expect_eq "G6.$cls.${st%%-*} $cls: a write to $st is deny-fix" "deny-fix" \
      "$(kind "$(dec "$cls" "$fact" "$(W "$G6_TMP/$st")")")"
  done
  expect_eq "G6.$cls.del $cls: a delete of a roster is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$fact" "$(D "$G6_TMP/roster-sid-1.state")")")"
done <<< "$G6_CASES"
expect_eq "G6.case a roster spelled in another case is deny-fix (case-blind filesystems)" "deny-fix" \
  "$(kind "$(dec lead "checkout=$P" "$(W "$P/.Bionic/TMP/Roster-sid-1.state")")")"
expect_eq "G6.dir deleting .bionic/tmp itself is deny-fix" "deny-fix" "$(kind "$(dec lead "checkout=$P" "$(D "$G6_TMP")")")"
expect_eq "G6.dir2 deleting .bionic is deny-fix" "deny-fix" "$(kind "$(dec lead "checkout=$P" "$(D "$P/.bionic")")")"
G6_MSG="$(dec lead "checkout=$P" "$(W "$G6_TMP/roster-sid-1.state")")"
expect_contains "G6.msg the denial names the state file" "$G6_TMP/roster-sid-1.state" "$G6_MSG"
expect_contains "G6.msg2 …and says it is bionic's own state" "bionic's own state" "$G6_MSG"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G7 every deny-fix carries the target or reason, the roots and one next step"

# One row per way to be denied, each through the full driver with the writer's facts. The
# roots every message must list are the writer's: its scratch, its tree, the record dir.
G7_ROWS="outside-write|$(W "$P/payload/x.sh")|$P/payload/x.sh
outside-delete|$(D "$T10/f")|$T10/f
record-delete|$(D "$REC/a.md")|$REC/a.md
unknown|$(U 'a variable in a target' 'rm -f $TR')|a variable in a target
unresolved|$(W "$T1/../x")|$T1/../x
state|$(W "$P/.bionic/tmp/gate-sid-1.state")|$P/.bionic/tmp/gate-sid-1.state"
G7_SEEN=""
while IFS='|' read -r name eff what; do
  v="$(dec writer "$WRITER_FACTS" "$eff")"
  reason="$(fld 2 "$v")"; fix="$(fld 3 "$v")"
  expect_eq "G7.$name.0 deny-fix with three fields" "deny-fix|3" "$(kind "$v")|$(printf '%s\n' "$v" | awk -F'\t' '{print NF}')"
  expect_contains "G7.$name.1 the reason names what could not be shown inside" "$what" "$reason"
  for r in "$S" "$T1" "$REC"; do
    expect_contains "G7.$name.2 the message names the root $r" "$r" "$reason $fix"
  done
  expect_nonempty "G7.$name.3 there is a next step" "$fix"
  expect_eq "G7.$name.4 the next step is one sentence" "1" "$(printf '%s' "$fix" | grep -o '\. ' | wc -l | awk '{print $1 + 1}')"
  G7_SEEN="$G7_SEEN${NL}$reason"
done <<< "$G7_ROWS"
expect_eq "G7.distinct the six reasons are six different texts (no fixed string)" "6" \
  "$(printf '%s\n' "$G7_SEEN" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
G7_U="$(dec writer "$WRITER_FACTS" "$(U 'a variable in a target' 'rm -f $TR')")"
expect_contains "G7.cmd an unread command's fix: put the script in a file in the workspace" "file" "$(fld 3 "$G7_U")"
expect_contains "G7.cmd2 …named by a real root" "$S" "$(fld 3 "$G7_U")"
expect_contains "G7.cmd3 …and run it from there" "run it from there" "$(fld 3 "$G7_U")"
expect_contains "G7.cmd4 the unread segment is named" 'rm -f $TR' "$(fld 2 "$G7_U")"
G7_LONG="$(dec writer "$WRITER_FACTS" "$(U 'an interpreter body' "python3 -c '$(printf 'x%.0s' $(seq 1 3000))'")")"
expect_contains "G7.long a long unread segment is quoted by its head" "python3 -c 'xxxx" "$(fld 2 "$G7_LONG")"
expect_eq "G7.long2 …and cut, so the reason stays readable" "short" "$([ "$(fld 2 "$G7_LONG" | wc -c)" -lt 800 ] && echo short || echo long)"
G7_W="$(dec writer "$WRITER_FACTS" "$(W "$P/payload/x.sh")")"
expect_contains "G7.path an outside write's fix names a root to write under" "under $S" "$(fld 3 "$G7_W")"
G7_NONE="$(dec reader "" "$(W "$P/x")")"
expect_contains "G7.none an asker with no roots is told it has none" "no workspace" "$(fld 2 "$G7_NONE")"
expect_contains "G7.none2 …and its one step is the lead" "lead" "$(fld 3 "$G7_NONE")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G8 a reserved action is never allowed; a table miss is denied with a fix"

# tool | command or path | category. Each is decided with NO effects — the most an allow
# could want — so only the reserved category can deny it.
G8_ROWS="Bash|git push origin wave/25-never-paused|leaves-the-machine
Bash|git -C /w/proj push --force origin HEAD:refs/heads/main|leaves-the-machine
Bash|bash -c 'cd /w && git push'|leaves-the-machine
Bash|gh issue create --title x --body y|leaves-the-machine
Bash|gh pr create --fill|leaves-the-machine
Bash|gh -R owner/repo release create v1|leaves-the-machine
Bash|gh api repos/o/r/issues|leaves-the-machine
Bash|gh auth token|credentials
Bash|npm publish|leaves-the-machine
Bash|sudo pnpm publish --access public|leaves-the-machine
Bash|yarn npm publish|leaves-the-machine
Bash|cargo publish|leaves-the-machine
Bash|gem push x.gem|leaves-the-machine
Bash|twine upload dist/*|leaves-the-machine
Read|/Users/alice/.ssh/id_ed25519|credentials
Read|~/.ssh/id_ed25519|credentials
Bash|cat ~/.ssh/id_ed25519|credentials
Bash|cp \$HOME/.aws/credentials /tmp/x|credentials
Write|/Users/alice/.config/gh/hosts.yml|credentials
Edit|/Users/alice/.netrc|credentials
Write|/w/proj/.env|credentials
Read|/w/proj/.env.production|credentials
Bash|source .env.local|credentials
Bash|security find-generic-password -s x -w|credentials
Bash|terraform apply|production-infrastructure
Bash|kubectl apply -f deploy.yaml|production-infrastructure
Bash|vercel --prod|production-infrastructure
Bash|aws s3 cp f s3://b/f|production-infrastructure
Bash|gcloud run deploy svc|production-infrastructure
Bash|az group delete -n rg|production-infrastructure
Bash|gcloud billing accounts list|billing"
G8_ALLOWS=""
while IFS='|' read -r tool what cat; do
  got="$(call grant_reserved "$tool" "$what")"
  expect_eq "G8 $tool '$what' is $cat" "$cat" "$got"
  v="$(dec lead "$LEAD_FACTS" "" "$got")"
  expect_eq "G8 …and decided with no effects it is deny-reserved" "deny-reserved${TAB}$cat" "$(kind "$v")${TAB}$(fld 2 "$v")"
  [ "$(kind "$v")" = "allow" ] && G8_ALLOWS="$G8_ALLOWS $what;"
done <<< "$G8_ROWS"
# The table reads words, not text: quoting, escaping, a line continuation or a runner
# string around a reserved word does not hide it.
expect_eq "G8.obf1 a push spelled with quotes inside its words" "leaves-the-machine" "$(call grant_reserved Bash "g'i't p\"u\"sh origin wave/x")"
expect_eq "G8.obf2 a push spelled with backslash escapes" "leaves-the-machine" "$(call grant_reserved Bash 'gi\t pu\sh origin wave/x')"
expect_eq "G8.obf3 a push split by a line continuation" "leaves-the-machine" "$(call grant_reserved Bash "git pu\\${NL}sh origin wave/x")"
expect_eq "G8.obf4 a quoted tool name" "leaves-the-machine" "$(call grant_reserved Bash "'npm' publish")"
expect_eq "G8.obf5 a publish inside bash -c" "leaves-the-machine" "$(call grant_reserved Bash "bash -c \"npm publish\"")"
expect_eq "G8.obf6 a pr inside eval" "leaves-the-machine" "$(call grant_reserved Bash "eval 'gh pr create --fill'")"
expect_eq "G8.obf7 a reserved segment after a long run of ordinary ones" "production-infrastructure" \
  "$(call grant_reserved Bash "$(for i in 1 2 3 4 5 6 7 8 9 10; do printf 'echo %s > /tmp/f%s; ' "$i" "$i"; done)/usr/local/bin/terraform destroy")"
# Case-blind, as the filesystem is: `GH` runs gh, and `~/.SSH` opens ~/.ssh.
expect_eq "G8.case1 a tool name in capitals" "leaves-the-machine" "$(call grant_reserved Bash "GH pr create --fill")"
expect_eq "G8.case2 a credential directory in capitals, in a command" "credentials" "$(call grant_reserved Bash "cat ~/.SSH/id_ed25519")"
expect_eq "G8.case3 a credential directory in capitals, as a Read path" "credentials" "$(call grant_reserved Read "/Users/alice/.SSH/id_ed25519")"
# A caller under `set -euo pipefail` (a hook) survives a command whose text hits the
# screen while none of its words matches: the screen's filter finds nothing, which is
# not a failure.
G8_STRICT="$(bash -c 'set -euo pipefail; . "$1"; grant_reserved Bash "echo pu\\\\sh"; grant_reserved Bash "git push origin x"; echo survived' _ "$LIB" 2>&1 </dev/null)"
expect_eq "G8.strict a strict caller reads a near miss and a push, and lives" "leaves-the-machine${NL}survived" "$G8_STRICT"
# Reserved wins over effects that would otherwise allow.
expect_eq "G8.win a push whose effects are all inside is still deny-reserved" "deny-reserved" \
  "$(kind "$(dec lead "$LEAD_FACTS" "$(W "$WAVE/x")" leaves-the-machine)")"
# The table must not swallow ordinary work.
G8_CLEAN="Bash|git status
Bash|git log --grep push
Bash|echo 'git push origin main'
Bash|npm install
Bash|npm run publish-docs
Bash|gh --version
Bash|cat README.env.md
Bash|ls environments/
Read|/w/proj/src/app.ts
Write|/w/proj/.envrc.example.md
Bash|terraformer-docs --help"
while IFS='|' read -r tool what; do
  expect_eq "G8.clean $tool '$what' is not reserved" "" "$(call grant_reserved "$tool" "$what")"
done <<< "$G8_CLEAN"
# A publish tool the table lacks: no category, and the reader marks it unknown, so the
# decision denies it with a fix rather than allowing it.
expect_eq "G8.miss 'poetry publish' is not in the table" "" "$(call grant_reserved Bash "poetry publish")"
G8_MISS="$(dec lead "$LEAD_FACTS" "$(U 'command is not on the pure-reader list' 'poetry publish')" "")"
expect_eq "G8.miss2 …and is deny-fix, never allow" "deny-fix" "$(kind "$G8_MISS")"
[ "$(kind "$G8_MISS")" = "allow" ] && G8_ALLOWS="$G8_ALLOWS poetry publish;"
expect_eq "G8.none no reserved row and no table miss was allowed" "" "$G8_ALLOWS"
expect_eq "G8.badcat an unknown category is malformed input, rc 2" "2" \
  "$(dec lead "$LEAD_FACTS" "" "secrets" >/dev/null; printf '%s' "$CALL_RC")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G9 a reserved denial names the category and the human, and carries no file route"

for cat in leaves-the-machine credentials production-infrastructure billing; do
  v="$(dec writer "$WRITER_FACTS" "$(W "$T1/x")" "$cat")"
  reason="$(fld 3 "$v")"
  expect_eq "G9.$cat.0 deny-reserved, category in the second field" "deny-reserved${TAB}$cat" "$(kind "$v")${TAB}$(fld 2 "$v")"
  expect_nonempty "G9.$cat.1 there is a reason" "$reason"
  expect_contains "G9.$cat.2 the reason names the category in words" "$(printf '%s' "$cat" | tr '-' ' ')" "$reason"
  expect_contains "G9.$cat.3 …says it is the human's to act on" "human" "$reason"
  expect_contains "G9.$cat.4 …and tells the agent to report it to the lead" "report it to the lead" "$reason"
  expect_no_regex "G9.$cat.5 …and offers no file route or workaround" '[Ff]ile|[Ss]cript|/|[Ww]orkspace|[Ii]nstead|run it' "$reason"
done

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G10 the answer log is in no workspace"

# The log's path is the project's log directory under the user's home (D9). It is read from
# the lib that owns it: `answers_path` once the hook row has added it, else the directory of
# `audit_path` beside which D9 places it.
G10_HOME=$SANDBOX/home
G10_LOG="$(HOME="$G10_HOME" bash -c '. "$1" >/dev/null 2>&1 || exit 127
if declare -F answers_path >/dev/null; then answers_path "$2"; else a="$(audit_path "$2")" && printf "%s/permission-answers.log" "${a%/*}"; fi' _ "$ROOT_LIB" "$P")"
expect_regex "G10.0 the log path is read (non-empty, absolute, the answers log)" '^/.*/permission-answers\.log$' "$G10_LOG"
# Each class is handed every fact it could hold, and a HOME-wide fact it must not turn into a
# root: the log is outside all of them.
for cls in lead writer reader unbound; do
  case "$cls" in
    lead) f="$LEAD_FACTS" ;; writer) f="$WRITER_FACTS" ;; reader) f="$READER_FACTS" ;; unbound) f="$UNBOUND_FACTS" ;;
  esac
  expect_eq "G10.$cls.0 $cls: its scratch allows (the facts are live)" "allow" "$(dec "$cls" "$f" "$(W "$S/x")")"
  expect_eq "G10.$cls.1 $cls: a write to the answer log is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(W "$G10_LOG")")")"
  expect_eq "G10.$cls.2 $cls: a delete of the answer log is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(D "$G10_LOG")")")"
done
# Where the main checkout is the lead's checkout, a log under .bionic/ would sit inside it.
expect_eq "G10.main the lead whose checkout is the main checkout still cannot write the log" "deny-fix" \
  "$(kind "$(dec lead "checkout=$P${NL}scratch=$S" "$(W "$G10_LOG")")")"

finish
