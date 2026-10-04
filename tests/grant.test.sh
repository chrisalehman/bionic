#!/bin/bash
# tests/grant.test.sh — payload/scripts/lib/grant.sh: THE GRANT (epic-23 wave-25-never-paused,
# REQ-2, REQ-3, REQ-4, REQ-7; spec D2, D4, D6; ADR-042).
#
# WHAT IT OWNS. The verdict the permission answer gives and the words it gives it in. Four
# functions, one question each:
#
#   grant_roots <class> <key=value>...   which roots a class gets from the facts it is handed
#   grant_decide <class> <w> <d> <fx> [<category>] [<main root>]
#                                        allow, deny-fix or deny-reserved, and why
#   grant_reserved <tool> <command|path> which reserved category an action falls in, if any
#   grant_resolve <path>                 the real location of a path, or a mark that it has none
#
# One section per Eval-design row of the spec that names this suite, §G1 to §G10, each built
# to go red on the planted defect its matrix block names under `fails-when:`. §G11 holds AC-2.2
# and AC-2.7 where the run works in the main checkout itself: the project's shared directories
# under the main root are no checkout's, and the main root is no one's to delete. §G12 holds
# the device sinks: a write to /dev/null and its kin is no effect, a delete of one is judged.
# §G13–§G15 are T11's and T13's (who a fix sends the asker to; which program a word runs).
# §G16–§G21 are T17's, the review's place-not-spelling findings: every common credential store
# by every spelling (§G16), read lines and the reserved reading of them (§G17), a reader's
# report bounded by what the lead holds (§G18), the state classes agreeing with patrol.sh's
# (§G19), no delete of a root itself (§G20), and the one-process resolver (§G21). §G0 is the
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
grant_decide "$cls" "$GRANT_WRITE_ROOTS" "$GRANT_DELETE_ROOTS" "$eff" "$res" "${GRANT_MAIN_ROOT-}"'

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
G0_RESOLVER="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; declare -f _grant_resolve_set' _ "$LIB")"
expect_regex "G0.9 the extractor sees the resolver's reach (readlink, pwd -P)" 'readlink' "$G0_RESOLVER"
expect_regex "G0.10 the lib defines the four public functions" '^grant_decide$' "$G0_FNS"
G0_REACH=""
while IFS= read -r fn; do
  case "$fn" in grant_resolve|grant_resolve_lines|_grant_resolve*|'') continue ;; esac
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

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G11 the project's shared directories are no checkout's, and the main root is no one's to delete"

# A run that works in the main checkout itself hands the lead `checkout=<main>`, and that root
# physically holds .bionic (every run's docs and state), .worktrees (every run's trees) and
# .git. The main root arrives as a fact (`main=`), so the decision still looks nothing up.
# Every deny row here sits beside an allow row on the same facts.
G11_T9=$P/.worktrees/25-T9
G11_LEAD="checkout=$P${NL}main=$P${NL}scratch=$S${NL}record=$REC${NL}plan=$PLAN${NL}tree=$G11_T9"
expect_eq "G11.1 lead in the main checkout: a write under src allows" "allow" "$(dec lead "$G11_LEAD" "$(W "$P/src/app.ts")")"
expect_eq "G11.2 …and a delete under src allows" "allow" "$(dec lead "$G11_LEAD" "$(D "$P/src/old.ts")")"
expect_eq "G11.3 a delete of .bionic/docs/x is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P/.bionic/docs/x")")")"
expect_eq "G11.4 a delete of .bionic itself is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P/.bionic")")")"
expect_eq "G11.5 a delete of another run's tree under .worktrees is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P/.worktrees/other")")")"
expect_eq "G11.6 a delete under .git is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P/.git/config")")")"
expect_eq "G11.7 a delete of the main root itself is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P")")")"
expect_eq "G11.8 a delete of the main root's parent is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "${P%/*}")")")"
expect_eq "G11.9 a write under .bionic outside the run's record and plan is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(W "$P/.bionic/docs/specs/other.md")")")"
expect_eq "G11.10 a write into another run's tree is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(W "$P/.worktrees/other/f")")")"
expect_eq "G11.11 a write under .git is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(W "$P/.git/HEAD")")")"
expect_eq "G11.12 a write under the lead's own record root (inside .bionic) allows" "allow" "$(dec lead "$G11_LEAD" "$(W "$REC/T11-carve-outs.md")")"
expect_eq "G11.13 …and the lead's delete there allows" "allow" "$(dec lead "$G11_LEAD" "$(D "$REC/T11-carve-outs.md")")"
expect_eq "G11.14 a write to the run's plan file allows" "allow" "$(dec lead "$G11_LEAD" "$(W "$PLAN")")"
expect_eq "G11.15 a delete inside a recorded tree under .worktrees allows" "allow" "$(dec lead "$G11_LEAD" "$(D "$G11_T9/build")")"
expect_eq "G11.16 …but a delete of that recorded tree itself is deny-fix: a root is deleted by no one (§G20)" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$G11_T9")")")"
expect_eq "G11.17 .bionic spelled in another case is still shared (case-blind filesystems)" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P/.Bionic/docs")")")"
expect_eq "G11.18 .git spelled in another case is still shared" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(W "$P/.GIT/config")")")"
expect_eq "G11.19 the main root written with a trailing slash is still the main root" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D "$P/")")")"
expect_eq "G11.20 a delete of / is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LEAD" "$(D /)")")"
expect_eq "G11.21 one effect allowed and one shared is deny-fix" "deny-fix" \
  "$(kind "$(dec lead "$G11_LEAD" "$(W "$P/src/a")${NL}$(D "$P/.bionic/docs")")")"
expect_eq "G11.22 a state file under .bionic/tmp is still named as state first" "deny-fix|state" \
  "$(v="$(dec lead "$G11_LEAD" "$(W "$P/.bionic/tmp/roster-sid-1.state")")"; printf '%s|' "$(kind "$v")"; case "$v" in (*"bionic's own state"*) printf state ;; esac)"

# The writer: its own tree under .worktrees grants inside it; a sibling under .worktrees does not.
G11_WRITER="own=$G11_T9${NL}main=$P${NL}scratch=$S${NL}record=$REC"
expect_eq "G11.w1 a writer's write in its own tree under .worktrees allows" "allow" "$(dec writer "$G11_WRITER" "$(W "$G11_T9/payload/x.sh")")"
expect_eq "G11.w2 …and its delete there allows" "allow" "$(dec writer "$G11_WRITER" "$(D "$G11_T9/payload/x.sh")")"
expect_eq "G11.w3 a write in a sibling tree is deny-fix" "deny-fix" "$(kind "$(dec writer "$G11_WRITER" "$(W "$P/.worktrees/25-T10/f")")")"
expect_eq "G11.w4 a delete in a sibling tree is deny-fix" "deny-fix" "$(kind "$(dec writer "$G11_WRITER" "$(D "$P/.worktrees/25-T10/f")")")"
expect_eq "G11.w5 a writer's write under the record dir (inside .bionic) allows" "allow" "$(dec writer "$G11_WRITER" "$(W "$REC/T9.md")")"
G11_WREC="$(dec writer "$G11_WRITER" "$(D "$REC/T9.md")")"
# The add-only wording is matched by a `case` OUTSIDE a command substitution: a one-line
# `case` inside one is the shape tests/cross-gate-agreement.test.sh §BP forbids.
G11_WREC_HOW=""
case "$G11_WREC" in *"not delete"*) G11_WREC_HOW="not delete" ;; esac
expect_eq "G11.w6 …its delete there is still the add-only deny-fix" "deny-fix|not delete" \
  "$(kind "$G11_WREC")|$G11_WREC_HOW"

# A writer whose own tree IS the main root, as §G6 hands it: the shared directories stay out.
G11_WMAIN="own=$P${NL}main=$P${NL}scratch=$S"
expect_eq "G11.w7 own=<main>: a write under src allows" "allow" "$(dec writer "$G11_WMAIN" "$(W "$P/src/x")")"
expect_eq "G11.w8 own=<main>: a write under .bionic is deny-fix" "deny-fix" "$(kind "$(dec writer "$G11_WMAIN" "$(W "$P/.bionic/docs/x")")")"
expect_eq "G11.w9 own=<main>: a delete under .worktrees is deny-fix" "deny-fix" "$(kind "$(dec writer "$G11_WMAIN" "$(D "$P/.worktrees/25-T1/x")")")"

# A linked-worktree checkout: the wave checkout is under .worktrees, so it grants inside itself.
G11_LINKED="checkout=$P/.worktrees/25-wave${NL}main=$P${NL}scratch=$S"
expect_eq "G11.l1 linked checkout: a write inside it allows" "allow" "$(dec lead "$G11_LINKED" "$(W "$P/.worktrees/25-wave/src/x")")"
expect_eq "G11.l2 linked checkout: a delete inside it allows" "allow" "$(dec lead "$G11_LINKED" "$(D "$P/.worktrees/25-wave/src/x")")"
expect_eq "G11.l3 linked checkout: the main checkout's src is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LINKED" "$(W "$P/src/x")")")"
expect_eq "G11.l4 linked checkout: a sibling tree is deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_LINKED" "$(D "$P/.worktrees/25-T1/x")")")"

# Every class handed a root that IS the main root: the root is live, and rule 4 and the shared
# directories hold for each.
G11_CLASSES="lead|checkout=$P
writer|own=$P
reader|scratch=$P
unbound|scratch=$P"
while IFS='|' read -r cls fact; do
  f="$fact${NL}main=$P"
  expect_eq "G11.$cls.0 $cls: a write under src allows (the root is live)" "allow" "$(dec "$cls" "$f" "$(W "$P/src/x")")"
  expect_eq "G11.$cls.1 $cls: a delete of the main root is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(D "$P")")")"
  expect_eq "G11.$cls.2 $cls: a delete under .bionic is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(D "$P/.bionic/docs")")")"
  expect_eq "G11.$cls.3 $cls: a delete under .worktrees is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(D "$P/.worktrees/x")")")"
  expect_eq "G11.$cls.4 $cls: a write under .git is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(W "$P/.git/HEAD")")")"
done <<< "$G11_CLASSES"
# A root ABOVE the main root does not reach a delete of it either.
expect_eq "G11.above a root above the main root: a write beside the project allows" "allow" "$(dec lead "checkout=${P%/*}${NL}main=$P" "$(W "${P%/*}/notes")")"
expect_eq "G11.above2 …and a delete of the main root is deny-fix" "deny-fix" "$(kind "$(dec lead "checkout=${P%/*}${NL}main=$P" "$(D "$P")")")"

# The differential: the same facts with no main root decide exactly as before (rule 5).
G11_NOMAIN="checkout=$P${NL}scratch=$S${NL}record=$REC"
expect_eq "G11.diff1 no main root: a delete of .bionic/docs/x allows, as before" "allow" "$(dec lead "$G11_NOMAIN" "$(D "$P/.bionic/docs/x")")"
expect_eq "G11.diff2 …with the main root: deny-fix" "deny-fix" "$(kind "$(dec lead "$G11_NOMAIN${NL}main=$P" "$(D "$P/.bionic/docs/x")")")"
expect_eq "G11.diff3 no main root: a delete of the main root through a root above it allows, as before (G11.above2 is the pair)" "allow" "$(dec lead "checkout=${P%/*}" "$(D "$P")")"
expect_eq "G11.diff4 an empty main= is no main root" "allow" "$(dec lead "$G11_NOMAIN${NL}main=" "$(D "$P/.git/x")")"
expect_eq "G11.diff5 grant_decide with five arguments decides as before" "allow" "$(call grant_decide lead "$P" "$P" "$(D "$P/.git/x")" "")"
expect_eq "G11.diff6 …and with the main root as the sixth argument, deny-fix" "deny-fix" "$(kind "$(call grant_decide lead "$P" "$P" "$(D "$P/.git/x")" "" "$P")")"
expect_eq "G11.diff7 grant_roots hands the main root back in GRANT_MAIN_ROOT, trailing slash removed" "$P" \
  "$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; grant_roots lead "main=$2/" && printf "%s" "$GRANT_MAIN_ROOT"' _ "$LIB" "$P")"

# Malformed: a main root that cannot be one, or given twice, is rc 2 rather than ignored.
expect_eq "G11.bad1 a relative main root is malformed input, rc 2" "2" "$(dec lead "checkout=$P${NL}main=w/proj" "$(W "$P/x")" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G11.bad2 main given twice is malformed input, rc 2" "2" "$(dec lead "checkout=$P${NL}main=$P${NL}main=/w" "$(W "$P/x")" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G11.bad3 a sixth argument that is not an absolute root is malformed input, rc 2" "2" \
  "$(call grant_decide lead "$P" "$P" "$(W "$P/x")" "" "w/proj" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G11.bad4 a main root of / is malformed input, rc 2" "2" "$(call grant_decide lead "$P" "$P" "$(W "$P/x")" "" "/" >/dev/null; printf '%s' "$CALL_RC")"

# The message keeps its three parts and says the shared directories are not a run's checkout.
G11_MSG="$(dec lead "$G11_LEAD" "$(D "$P/.bionic/docs/x")")"
G11_R="$(fld 2 "$G11_MSG")"; G11_F="$(fld 3 "$G11_MSG")"
expect_contains "G11.msg1 the reason names the path" "$P/.bionic/docs/x" "$G11_R"
expect_contains "G11.msg2 …says the shared directories are not part of a run's checkout" "shared directories are not part of a run's checkout" "$G11_R"
for r in "$S" "$P" "$REC"; do
  expect_contains "G11.msg3 …and names the root $r" "$r" "$G11_R"
done
expect_nonempty "G11.msg4 there is a next step" "$G11_F"
expect_eq "G11.msg5 the next step is one sentence" "1" "$(printf '%s' "$G11_F" | grep -o '\. ' | wc -l | awk '{print $1 + 1}')"
G11_UP="$(fld 2 "$(dec lead "$G11_LEAD" "$(D "${P%/*}")")")"
expect_contains "G11.msg6 an ancestor delete's reason names the target" "${P%/*}" "$G11_UP"
expect_contains "G11.msg7 …and says it holds the project" "project" "$G11_UP"
expect_ne "G11.msg8 a shared-directory denial does not read as a plain outside-the-workspace one" \
  "$(fld 2 "$(dec lead "$G11_LEAD" "$(W "/elsewhere/x")")" | sed 's#/elsewhere/x#X#')" "$(printf '%s' "$G11_R" | sed "s#$P/.bionic/docs/x#X#")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G12 a write to a device sink is no effect; a delete of one, or any other device, is judged"

# The reader prints `W<TAB>/dev/null` for every `2>/dev/null`. A write to /dev/null, /dev/stdout,
# /dev/stderr, /dev/tty or /dev/fd/<digits> changes no file, so it is skipped for every class.
# Every class is handed its usual facts: its scratch is a delete root, /dev is in none.
G12_CLASSES="lead|$LEAD_FACTS
writer|$WRITER_FACTS
reader|$READER_FACTS
unbound|$UNBOUND_FACTS"
G12_ROWS="$(printf '%s\n' "$G12_CLASSES" | sed -n 's/^\([a-z]*\)|.*/\1/p')"
expect_eq "G12.0 the class list reads four classes (non-empty readback)" "lead writer reader unbound" "$(printf '%s' "$G12_ROWS" | tr '\n' ' ' | sed 's/ $//')"
for cls in $G12_ROWS; do
  case "$cls" in
    lead) f="$LEAD_FACTS" ;; writer) f="$WRITER_FACTS" ;; reader) f="$READER_FACTS" ;; unbound) f="$UNBOUND_FACTS" ;;
  esac
  expect_eq "G12.$cls.1 $cls: W /dev/null alone allows" "allow" "$(dec "$cls" "$f" "$(W /dev/null)")"
  expect_eq "G12.$cls.2 $cls: W /dev/null plus a delete inside its delete roots allows" "allow" "$(dec "$cls" "$f" "$(W /dev/null)${NL}$(D "$S/tmp.txt")")"
  expect_eq "G12.$cls.3 $cls: W /dev/null plus a write outside is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(W /dev/null)${NL}$(W /elsewhere/x)")")"
  expect_eq "G12.$cls.4 $cls: D /dev/null is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(D /dev/null)")")"
  expect_eq "G12.$cls.5 $cls: W /dev/sda is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(W /dev/sda)")")"
  expect_eq "G12.$cls.6 $cls: W /dev/fd/3 allows" "allow" "$(dec "$cls" "$f" "$(W /dev/fd/3)")"
  expect_eq "G12.$cls.7 $cls: W /dev/fd/x is deny-fix" "deny-fix" "$(kind "$(dec "$cls" "$f" "$(W /dev/fd/x)")")"
done
expect_eq "G12.8 W /dev/stdout allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W /dev/stdout)")"
expect_eq "G12.9 W /dev/stderr allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W /dev/stderr)")"
expect_eq "G12.10 W /dev/tty allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W /dev/tty)")"
expect_eq "G12.11 W /dev/fd/12 allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W /dev/fd/12)")"
expect_eq "G12.12 W /dev/fd/ (no digits) is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W /dev/fd/)")")"
expect_eq "G12.13 W /dev/fd/3x is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W /dev/fd/3x)")")"
expect_eq "G12.14 W /dev/nullx is deny-fix (exact names only)" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W /dev/nullx)")")"
expect_eq "G12.15 W /dev/null/x is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(W /dev/null/x)")")"
expect_eq "G12.16 D /dev/fd/3 is deny-fix" "deny-fix" "$(kind "$(dec writer "$WRITER_FACTS" "$(D /dev/fd/3)")")"
expect_eq "G12.17 a reserved action with only a sink write is still deny-reserved" "deny-reserved" \
  "$(kind "$(dec writer "$WRITER_FACTS" "$(W /dev/null)" leaves-the-machine)")"
expect_eq "G12.18 with a main root, W /dev/null still allows" "allow" "$(dec lead "checkout=$P${NL}main=$P${NL}scratch=$S" "$(W /dev/null)")"
G12_MSG="$(dec writer "$WRITER_FACTS" "$(W /dev/null)${NL}$(W /elsewhere/x)${NL}$(W /dev/stderr)")"
expect_contains "G12.19 a denial beside sink writes names the real target" "/elsewhere/x" "$(fld 2 "$G12_MSG")"
expect_no_regex "G12.20 …and counts no sink among the failing effects" 'more of its effects|/dev/' "$(fld 2 "$G12_MSG")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G13 a delete outside the delete roots: an agent is sent to the lead, the lead to the human"

# Rule 6's delete fix used to tell every class to ask the lead, the lead included (T11's
# concern 1). The lead and an unbound session ARE the lead session: there is no lead above
# them to ask, so their next step is the human. An agent's is still the lead. Same target,
# same rule, four classes.
G13_T="/elsewhere/old.txt"
for cls in lead unbound; do
  case "$cls" in lead) f="$LEAD_FACTS" ;; unbound) f="$UNBOUND_FACTS" ;; esac
  v="$(dec "$cls" "$f" "$(D "$G13_T")")"
  expect_eq "G13.$cls.0 $cls: a delete outside its roots is deny-fix" "deny-fix" "$(kind "$v")"
  expect_contains "G13.$cls.1 …the reason is rule 6's (outside where it may delete)" "outside where" "$(fld 2 "$v")"
  expect_contains "G13.$cls.2 …and the fix sends it to the human" "report it to the human" "$(fld 3 "$v")"
  expect_absent "G13.$cls.3 …never to ask the lead (it is the lead)" "ask the lead" "$(fld 3 "$v")"
done
for cls in writer reader; do
  case "$cls" in writer) f="$WRITER_FACTS" ;; reader) f="$READER_FACTS" ;; esac
  v="$(dec "$cls" "$f" "$(D "$G13_T")")"
  expect_eq "G13.$cls.0 $cls: a delete outside its roots is deny-fix" "deny-fix" "$(kind "$v")"
  expect_contains "G13.$cls.1 …the reason is rule 6's (outside where it may delete)" "outside where" "$(fld 2 "$v")"
  expect_contains "G13.$cls.2 …and the fix sends the agent to the lead" "ask the lead to remove it" "$(fld 3 "$v")"
  expect_absent "G13.$cls.3 …not past it to the human" "human" "$(fld 3 "$v")"
done
# The other rule-6 delete wording is unchanged: an agent deleting in the add-only record.
expect_eq "G13.addonly the add-only record fix is untouched" "Leave it in place and write a new file beside it instead." \
  "$(fld 3 "$(dec writer "$WRITER_FACTS" "$(D "$REC/a.md")")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G14 which program a word runs is the shared reader's; a match made to refuse stays case-blind"

# Two questions, two rules (wave-25 T13; Chris's Step-4 ruling and A-orch-29). WHICH PROGRAM
# a word runs is git-argv.sh's `cmd_word_fold`, the one rule every reader asks: an external
# program word folds, so `GH` runs gh. A path or an argument matched in order to REFUSE
# (a credential store, a reserved subcommand) is matched without regard to case, looser
# than the fold: refusing something harmless is the only error a refusing guard may make.
#
# Every program word of the table, capitalised: each is still its category.
G14_PROG="GIT push origin wave/x|leaves-the-machine
Git push origin wave/x|leaves-the-machine
GH pr create --fill|leaves-the-machine
Gh auth token|credentials
NPM publish|leaves-the-machine
PNPM publish|leaves-the-machine
YARN npm publish|leaves-the-machine
CARGO publish|leaves-the-machine
GEM push x.gem|leaves-the-machine
TWINE upload dist/x|leaves-the-machine
SECURITY find-generic-password -s x -w|credentials
TERRAFORM apply|production-infrastructure
KUBECTL apply -f deploy.yaml|production-infrastructure
VERCEL --prod|production-infrastructure
AWS s3 cp f s3://b/f|production-infrastructure
GCLOUD billing accounts list|billing
AZ group delete -n rg|production-infrastructure
/usr/local/bin/TERRAFORM destroy|production-infrastructure
SUDO gh pr create --fill|leaves-the-machine
Sudo pnpm publish --access public|leaves-the-machine
COMMAND npm publish|leaves-the-machine
NOHUP cargo publish|leaves-the-machine
ENV X=1 gh pr create --fill|leaves-the-machine"
while IFS='|' read -r what cat; do
  expect_eq "G14.prog '$what' is $cat" "$cat" "$(call grant_reserved Bash "$what")"
done <<< "$G14_PROG"
# Every subcommand and option word the table refuses on, capitalised: still refused.
G14_SUB="git PUSH origin wave/x|leaves-the-machine
gh PR create --fill|leaves-the-machine
gh -R o/r RELEASE create v1|leaves-the-machine
gh --REPO o/r ISSUE create|leaves-the-machine
gh API repos/o/r/issues|leaves-the-machine
gh AUTH token|credentials
npm PUBLISH|leaves-the-machine
npm LOGIN|credentials
pnpm -C d publish|leaves-the-machine
yarn NPM publish|leaves-the-machine
cargo YANK --version 1.0.0|leaves-the-machine
gem PUSH x.gem|leaves-the-machine
gem SIGNIN|credentials
twine UPLOAD dist/x|leaves-the-machine
aws CE get-cost-and-usage|billing
az CONSUMPTION usage list|billing"
while IFS='|' read -r what cat; do
  expect_eq "G14.sub '$what' is $cat" "$cat" "$(call grant_reserved Bash "$what")"
done <<< "$G14_SUB"
# Every credential store, capitalised, in a command and as a tool's path.
G14_CRED="Bash|cat ~/.SSH/id_ed25519
Bash|cp \$HOME/.AWS/credentials /tmp/x
Bash|ssh-add --key=~/.Ssh/id_rsa
Bash|cat /w/proj/.ENV
Bash|SOURCE .Env.Local
Read|/Users/alice/.AWS/credentials
Write|/Users/alice/.Config/GH/hosts.yml
Edit|/Users/alice/.NETRC
Write|/w/proj/.ENV
Read|/w/proj/.Env.Production"
while IFS='|' read -r tool what; do
  expect_eq "G14.cred $tool '$what' is credentials" "credentials" "$(call grant_reserved "$tool" "$what")"
done <<< "$G14_CRED"
# A capitalised word the shared reader does NOT fold: a shell builtin or keyword exists only
# in the shell, which matches it case-exactly, so `EXEC gh …` is "command not found" and runs
# no gh (git-argv.sh, `cmd_word_fold`'s never list). The grant reads it as the reader does:
# no category. The lower-case spelling, on the same extractor, is the category.
G14_NEVER="exec gh pr create --fill|EXEC gh pr create --fill
exec terraform apply|Exec terraform apply
if gh pr create; then :; fi|IF gh pr create; then :; fi
then gh pr create|THEN gh pr create
do npm publish|DO npm publish"
while IFS='|' read -r runs never; do
  expect_eq "G14.never.0 '$runs' runs the program: a category" "nonempty" \
    "$([ -n "$(call grant_reserved Bash "$runs")" ] && echo nonempty || echo empty)"
  expect_eq "G14.never.1 '$never' runs nothing (the reader does not fold it): no category" "" \
    "$(call grant_reserved Bash "$never")"
done <<< "$G14_NEVER"
# …and it is still denied, never allowed: the real effects reader (cmd-class.sh, T2's) marks
# the unknown word `?`, and the decision denies it with a fix.
CMD_LIB="$REPO_ROOT/payload/scripts/lib/cmd-class.sh"
while IFS='|' read -r runs never; do
  fx="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; cmd_effects "$2" /w/proj' _ "$CMD_LIB" "$never" 2>/dev/null)"
  expect_regex "G14.never.2 the reader marks '$never' unknown" "^\\?${TAB}" "$fx"
  expect_eq "G14.never.3 …and '$never' is decided deny-fix" "deny-fix" \
    "$(kind "$(dec lead "$LEAD_FACTS" "$fx" "$(call grant_reserved Bash "$never")")")"
done <<< "$G14_NEVER"
# The grant keeps no lower-casing of its own: the program word is the reader's fold, and a
# refusal's match is case-blind by matching, not by a second copy of the words.
G14_SRC="$(cat "$LIB" 2>/dev/null)"
expect_regex "G14.src the lib asks the shared reader's fold" 'cmd_word_fold' "$G14_SRC"
expect_no_regex "G14.src2 …and lower-cases no word itself" "tr '\\[:upper:\\]'|tr A-Z|tr '\\[A-Z\\]'" "$G14_SRC"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G15 every fix line sends the asker to the one above its own class"

# A fix line never tells an asker to ask itself (T4's concern 2, wave-25 T13). A writer or a
# read-only agent is sent to the lead. The lead and an unbound session have no lead above
# them: they are sent to the human. Three fix lines, every class, each row keeping §G7's rule
# (three fields, one next step).
g15_check() {  # <label> <verdict> <reason needle> <want in fix> <never in fix>
  expect_eq "$1.0 deny-fix with three fields" "deny-fix|3" "$(kind "$2")|$(printf '%s\n' "$2" | awk -F'\t' '{print NF}')"
  expect_contains "$1.1 the reason names what failed" "$3" "$(fld 2 "$2")"
  expect_contains "$1.2 the fix sends it to the $4" "$4" "$(fld 3 "$2")"
  expect_absent "$1.3 …never to the $5" "$5" "$(fld 3 "$2")"
  expect_eq "$1.4 the next step is one sentence" "1" "$(fld 3 "$2" | grep -o '\. ' | wc -l | awk '{print $1 + 1}')"
}
for cls in lead unbound writer reader; do
  case "$cls" in
    lead) f="$LEAD_FACTS"; up=human; not=lead ;;
    unbound) f="$UNBOUND_FACTS"; up=human; not=lead ;;
    writer) f="$WRITER_FACTS"; up=lead; not=human ;;
    reader) f="$READER_FACTS"; up=lead; not=human ;;
  esac
  # The no-workspace fix: no facts, so no root to work in.
  g15_check "G15.none.$cls" "$(dec "$cls" "" "$(W "$P/x")")" "no workspace" "$up" "$not"
  # Rule 2: one of bionic's own state files.
  g15_check "G15.state.$cls" "$(dec "$cls" "$f" "$(W "$P/.bionic/tmp/gate-sid-1.state")")" "bionic's own state" "$up" "$not"
  # Rule 5, a delete: the main checkout's .git, which no root grants.
  g15_check "G15.git.$cls" "$(dec "$cls" "$f${NL}main=$P" "$(D "$P/.git/index")")" "$P/.git" "$up" "$not"
done

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G16 every common credential store is refused by any spelling of its path"

# The stores a common tool keeps a secret in by default, at home spelled three ways and
# capitalised (wave-25 T17, review B3b). The clean rows beside them are the same names one
# component or one suffix off, so a table that refused every dotted word is red there.
G16_STORES=".npmrc
.pypirc
.git-credentials
.kube/config
.docker/config.json
.gnupg/pubring.kbx
.config/gcloud/credentials.db
.cargo/credentials.toml
.azure/msal_token_cache.json
.ssh/id_rsa
.aws/credentials
.config/gh/hosts.yml
.netrc"
while IFS= read -r st; do
  for spell in "/Users/alice/$st" "~/$st" "\$HOME/$st"; do
    expect_eq "G16.bash 'cat $spell' is credentials" "credentials" "$(call grant_reserved Bash "cat $spell")"
  done
  expect_eq "G16.read Read /Users/alice/$st is credentials" "credentials" "$(call grant_reserved Read "/Users/alice/$st")"
  G16_UP="$(printf '%s' "$st" | tr '[:lower:]' '[:upper:]')"
  expect_eq "G16.case Read /Users/alice/$G16_UP is credentials" "credentials" "$(call grant_reserved Read "/Users/alice/$G16_UP")"
done <<< "$G16_STORES"
G16_CLEAN="Bash|cat /w/proj/docs/npmrc-guide.md
Bash|cat /w/proj/.npmrc.md
Bash|ls /Users/alice/.kube
Bash|/Users/alice/.cargo/bin/cargo build
Bash|ls /Users/alice/.docker/contexts
Read|/Users/alice/.kube/cache/discovery.json
Read|/w/proj/config.json
Read|/w/proj/docs/.git-credentials-helper.md
Bash|cat /w/proj/.gitconfig"
while IFS='|' read -r tool what; do
  expect_eq "G16.clean $tool '$what' is not reserved" "" "$(call grant_reserved "$tool" "$what")"
done <<< "$G16_CLEAN"
# One list: the lib names its stores once, and every name on it is refused under a home.
G16_LIST="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; printf "%s" "${GRANT_CREDENTIAL_STORES-}"' _ "$LIB")"
expect_nonempty "G16.list the lib names its credential stores in one list" "$G16_LIST"
set -f
for st in $G16_LIST; do
  probe="${st%/}"
  case "$st" in */) probe="$probe/x" ;; esac
  probe="${probe//\*/local}"
  expect_eq "G16.list '$st' (Read ~/$probe) is credentials" "credentials" "$(call grant_reserved Read "~/$probe")"
done
set +f
for st in .npmrc .pypirc .git-credentials .kube/config .docker/config.json .gnupg/ .config/gcloud/ .cargo/credentials.toml .azure/; do
  case " $G16_LIST " in
    *" $st "*) ok "G16.named the list names $st" ;;
    *) no "G16.named the list names $st" "$G16_LIST" ;;
  esac
done

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G17 a read changes nothing about the roots; a read that reaches a credential store is reserved"

# The reader's read lines (wave-25 T16's frozen interface): `R<TAB>path` for each file or
# directory a pure reader reads, `RR<TAB>path` for a read that descends beneath it. The
# decision accepts them and confines nothing by them; the reserved table reads them, every
# spelling the hook hands it, with the home directory as a fact (T17, review B3c and S4).
R() { printf 'R\t%s' "$1"; }
RR() { printf 'RR\t%s' "$1"; }
expect_eq "G17.1 a read alone allows" "allow" "$(dec writer "$WRITER_FACTS" "$(R /elsewhere/a.txt)")"
expect_eq "G17.2 a recursive read alone allows" "allow" "$(dec writer "$WRITER_FACTS" "$(RR /elsewhere)")"
expect_eq "G17.3 a read outside beside a write inside allows: a read is not confined by a write root" "allow" \
  "$(dec writer "$WRITER_FACTS" "$(R /elsewhere/a)${NL}$(RR /elsewhere/d)${NL}$(W "$T1/b")")"
G17_4="$(dec writer "$WRITER_FACTS" "$(R /elsewhere/a)${NL}$(W /elsewhere/b)")"
expect_eq "G17.4 a read beside a write outside is deny-fix" "deny-fix" "$(kind "$G17_4")"
expect_contains "G17.4b …naming the write" "/elsewhere/b is outside" "$(fld 2 "$G17_4")"
expect_absent "G17.4c …and counting no read among its failing effects" "more of its effects" "$(fld 2 "$G17_4")"
expect_eq "G17.5 an R line with no path is malformed input, rc 2" "2" "$(call grant_decide writer "/x" "/x" "R${TAB}" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G17.6 an RX line is malformed input, rc 2" "2" "$(call grant_decide writer "/x" "/x" "RX${TAB}/x/f" >/dev/null; printf '%s' "$CALL_RC")"
expect_eq "G17.7 a read the resolver marked unresolved is accepted, and allows" "allow" \
  "$(call grant_decide writer "/x" "/x" "R${TAB}?${TAB}k/id")"
expect_eq "G17.8 a read with a reserved category is deny-reserved" "deny-reserved" \
  "$(kind "$(dec writer "$WRITER_FACTS" "$(R /Users/alice/.ssh/id_rsa)" credentials)")"

H=/Users/alice
expect_eq "G17.r1 a read of a store file is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(R "$H/.ssh/id_rsa")")"
expect_eq "G17.r2 …a read of an ordinary file is no category" "" "$(call grant_reserved_effects "$H" "$(R "$H/src/a.txt")")"
expect_eq "G17.r3 a read of the home directory itself, not recursive, is no category" "" "$(call grant_reserved_effects "$H" "$(R "$H")")"
expect_eq "G17.r4 a recursive read of the home directory reaches every store: credentials" "credentials" "$(call grant_reserved_effects "$H" "$(RR "$H")")"
expect_eq "G17.r5 a recursive read of / is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(RR /)")"
expect_eq "G17.r6 a recursive read above home is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(RR /Users)")"
expect_eq "G17.r7 a recursive read of ~/.config (above two stores) is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(RR "$H/.config")")"
expect_eq "G17.r8 a recursive read of ~/.kube (above its config) is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(RR "$H/.kube")")"
expect_eq "G17.r9 a recursive read of a project tree is no category" "" "$(call grant_reserved_effects "$H" "$(RR /w/proj/src)")"
expect_eq "G17.r10 a recursive read of a sibling sharing home's prefix is no category" "" "$(call grant_reserved_effects "$H" "$(RR /Users/alice2)")"
expect_eq "G17.r11 a recursive read of home spelled in another case is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(RR /users/ALICE/)")"
expect_eq "G17.r12 with no home fact, a recursive read is credentials (it may reach any store)" "credentials" "$(call grant_reserved_effects "" "$(RR /w/proj/src)")"
expect_eq "G17.r13 …while a plain read is still judged by its shape" "" "$(call grant_reserved_effects "" "$(R /w/proj/src/a)")"
expect_eq "G17.r14 a write that lands on a store is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(W /w/proj/.env)")"
expect_eq "G17.r15 a delete that lands on a store is credentials" "credentials" "$(call grant_reserved_effects "$H" "$(D "$H/.aws/config")")"
expect_eq "G17.r16 a store path behind the resolver's mark is still read" "credentials" \
  "$(call grant_reserved_effects "$H" "R${TAB}?${TAB}$H/.ssh/id_rsa")"
expect_eq "G17.r17 an unknown line is no category" "" "$(call grant_reserved_effects "$H" "$(U 'a reason' 'make')")"
expect_eq "G17.r18 one store among many lines is credentials" "credentials" \
  "$(call grant_reserved_effects "$H" "$(R /w/a)${NL}$(W /w/b)${NL}$(R "$H/.npmrc")${NL}$(D /w/c)")"
expect_eq "G17.r19 a recursive read inside a store is credentials by its shape" "credentials" "$(call grant_reserved_effects "/nowhere" "$(RR /Users/bob/.gnupg)")"
G17_NCM="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
grant_reserved_effects /Users/alice "$(printf "RR\t/Users/ALICE")" >/dev/null
shopt -q nocasematch && printf on || printf off
shopt -s nocasematch
grant_reserved_effects /Users/alice "$(printf "R\t/w/a")" >/dev/null
shopt -q nocasematch && printf on || printf off' _ "$LIB")"
expect_eq "G17.ncm the caller's nocasematch is left as it was, off and on" "offon" "$G17_NCM"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G18 a read-only agent's report is a root only inside what the lead holds"

# ADR-042 decision 1: a grant is never wider than its parent. A reader's report counts only
# when it is strictly inside the run's record directory or the session scratch, the two
# places the lead holds; anywhere else it contributes no root (T17, review S1).
G18_IN="scratch=$S${NL}record=$REC${NL}report=$REC/R2.md"
expect_eq "G18.1 a report in the record directory: a write to it allows" "allow" "$(dec reader "$G18_IN" "$(W "$REC/R2.md")")"
expect_eq "G18.2 a report in the scratch: a write to it allows" "allow" "$(dec reader "scratch=$S${NL}report=$S/r.md" "$(W "$S/r.md")")"
G18_3="$(dec reader "scratch=$S${NL}record=$REC${NL}report=$P/hooks" "$(W "$P/hooks/bash-walls.sh")")"
expect_eq "G18.3 a report naming the main checkout's hooks: a write there is deny-fix" "deny-fix" "$(kind "$G18_3")"
expect_contains "G18.3b …and the grant it names is the scratch alone" "This read-only agent may write and delete under $S." "$(fld 2 "$G18_3")"
expect_eq "G18.4 a report file in the main checkout: a write to it is deny-fix" "deny-fix" \
  "$(kind "$(dec reader "scratch=$S${NL}record=$REC${NL}report=$P/hooks/r.md" "$(W "$P/hooks/r.md")")")"
expect_eq "G18.5 a report in another writer's tree: deny-fix" "deny-fix" \
  "$(kind "$(dec reader "scratch=$S${NL}record=$REC${NL}report=$T1/r.md" "$(W "$T1/r.md")")")"
expect_eq "G18.6 a report that is the record directory itself grants nothing under it" "deny-fix" \
  "$(kind "$(dec reader "scratch=$S${NL}record=$REC${NL}report=$REC" "$(W "$REC/x.md")")")"
expect_eq "G18.7 a report in the record directory with no record fact (an unbound session): deny-fix" "deny-fix" \
  "$(kind "$(dec reader "scratch=$S${NL}report=$REC/R2.md" "$(W "$REC/R2.md")")")"
expect_eq "G18.8 a report beside the record directory sharing its prefix: deny-fix" "deny-fix" \
  "$(kind "$(dec reader "scratch=$S${NL}record=$REC${NL}report=$REC-old/x.md" "$(W "$REC-old/x.md")")")"
expect_eq "G18.9 the scratch itself as the report grants nothing more than the scratch" "deny-fix" \
  "$(kind "$(dec reader "scratch=$S${NL}report=$S" "$(D "$S")")")"
expect_eq "G18.10 with the main root, a report in the record under .bionic still allows" "allow" \
  "$(dec reader "scratch=$S${NL}record=$REC${NL}report=$REC/R2.md${NL}main=$P" "$(W "$REC/R2.md")")"
expect_eq "G18.11 a writer is not bounded by this: its record write still allows" "allow" \
  "$(dec writer "own=$T1${NL}scratch=$S${NL}record=$REC" "$(W "$REC/T1.md")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G19 bionic's own state is every session-state class patrol.sh owns"

# The grant keeps its own copy of the class list, because it must not source patrol.sh (the
# freeze: the decision reads nothing). This section is the agreement: the two lists are one
# set, and every class on patrol.sh's list is state for every asker (T17, review S2).
PATROL_LIB="${GRANT_TEST_PATROL_LIB:-$REPO_ROOT/payload/scripts/lib/patrol.sh}"
G19_PATROL="$(sed -n 's/^PATROL_STATE_CLASSES="\(.*\)"$/\1/p' "$PATROL_LIB")"
G19_GRANT="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127; printf "%s" "${GRANT_STATE_CLASSES-}"' _ "$LIB")"
expect_nonempty "G19.0 patrol.sh's class list reads" "$G19_PATROL"
expect_nonempty "G19.0b …and so does the grant's" "$G19_GRANT"
expect_eq "G19.1 the grant's state classes are patrol.sh's, as a set" \
  "$(printf '%s\n' $G19_PATROL | sort -u | tr '\n' ' ')" "$(printf '%s\n' $G19_GRANT | sort -u | tr '\n' ' ')"
g19_state() {  # <class> <facts> <effect> -> kind|state
  local v how=""
  v="$(dec "$1" "$2" "$3")"
  case "$v" in *"bionic's own state"*) how=state ;; esac
  printf '%s|%s' "$(kind "$v")" "$how"
}
for c in $G19_PATROL; do
  for cls in lead writer reader unbound; do
    case "$cls" in
      lead) f="checkout=$P" ;; writer) f="own=$P" ;; *) f="scratch=$P/.bionic/tmp" ;;
    esac
    expect_eq "G19.$c.$cls $cls: a write to $c-sid-1.state is state" "deny-fix|state" "$(g19_state "$cls" "$f" "$(W "$P/.bionic/tmp/$c-sid-1.state")")"
  done
  expect_eq "G19.$c.d a delete of $c-sid-1.state is state" "deny-fix|state" "$(g19_state lead "checkout=$P" "$(D "$P/.bionic/tmp/$c-sid-1.state")")"
  G19_UP="$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]')"
  expect_eq "G19.$c.case $G19_UP-sid-1.state is state (case-blind filesystems)" "deny-fix|state" "$(g19_state lead "checkout=$P" "$(W "$P/.bionic/tmp/$G19_UP-sid-1.state")")"
done
expect_eq "G19.armed the Patrol stamp's .armed sibling is state" "deny-fix|state" "$(g19_state lead "checkout=$P" "$(W "$P/.bionic/tmp/patrol-sid-1.state.armed")")"
expect_eq "G19.ctl an ordinary file beside them is not state" "allow|" "$(g19_state lead "checkout=$P" "$(W "$P/.bionic/tmp/notes.txt")")"
G19_SRC="$(cat "$LIB" 2>/dev/null)"
expect_regex "G19.src the source-line extractor sees the lib's one sibling (git-argv.sh)" '\. "\$_GRANT_LIB_DIR/git-argv\.sh"' "$G19_SRC"
expect_no_regex "G19.src2 …and the lib sources no patrol.sh" '(\.|source) +"?[^ ]*patrol\.sh' "$G19_SRC"
G19_NCM="$(bash -c '. "$1" >/dev/null 2>&1 || exit 127
grant_decide lead /w /w "$(printf "W\t/w/.bionic/tmp/Roster-x.state")" >/dev/null
shopt -q nocasematch && printf on || printf off
shopt -s nocasematch
grant_decide lead /w /w "$(printf "W\t/w/.bionic/tmp/notes")" >/dev/null
shopt -q nocasematch && printf on || printf off' _ "$LIB")"
expect_eq "G19.ncm the decision leaves the caller's nocasematch as it was, off and on" "offon" "$G19_NCM"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G20 a delete must be strictly beneath a delete root: a root itself is no one's to delete"

# `rm -rf <own tree>`, `rm -rf <wave checkout>` and `rm -rf <scratch>` each deleted a whole
# workspace through a containment that matched the root itself (review N5). A write to a root
# path is unchanged; a delete is allowed only strictly beneath a delete root (T17).
g20_check() {  # <label> <verdict> <want in fix> <never in fix>
  expect_eq "$1.0 deny-fix" "deny-fix" "$(kind "$2")"
  expect_contains "$1.1 the reason says it is a root of the workspace" "a root of the workspace" "$(fld 2 "$2")"
  expect_contains "$1.2 the fix sends it to the $3" "$3" "$(fld 3 "$2")"
  expect_absent "$1.3 …never to the $4" "$4" "$(fld 3 "$2")"
}
g20_check "G20.w.tree writer: a delete of its own tree" "$(dec writer "$WRITER_FACTS" "$(D "$T1")")" "lead" "human"
g20_check "G20.w.slash writer: …spelled with a trailing slash" "$(dec writer "$WRITER_FACTS" "$(D "$T1/")")" "lead" "human"
g20_check "G20.w.dot writer: …spelled with a trailing /." "$(dec writer "$WRITER_FACTS" "$(D "$T1/.")")" "lead" "human"
g20_check "G20.w.scratch writer: a delete of the scratch" "$(dec writer "$WRITER_FACTS" "$(D "$S")")" "lead" "human"
g20_check "G20.r.scratch reader: a delete of the scratch" "$(dec reader "$READER_FACTS" "$(D "$S")")" "lead" "human"
g20_check "G20.l.wave lead: a delete of the wave checkout" "$(dec lead "$LEAD_FACTS" "$(D "$WAVE")")" "human" "ask the lead"
g20_check "G20.l.tree lead: a delete of a tree it recorded" "$(dec lead "$LEAD_FACTS" "$(D "$T1")")" "human" "ask the lead"
g20_check "G20.l.rec lead: a delete of the record directory" "$(dec lead "$LEAD_FACTS" "$(D "$REC")")" "human" "ask the lead"
g20_check "G20.l.plan lead: a delete of the plan file" "$(dec lead "$LEAD_FACTS" "$(D "$PLAN")")" "human" "ask the lead"
g20_check "G20.u.scratch unbound: a delete of the scratch" "$(dec unbound "$UNBOUND_FACTS" "$(D "$S")")" "human" "ask the lead"
expect_eq "G20.c1 control: the writer's delete beneath its tree allows" "allow" "$(dec writer "$WRITER_FACTS" "$(D "$T1/build")")"
expect_eq "G20.c2 control: a write to the tree root itself still allows" "allow" "$(dec writer "$WRITER_FACTS" "$(W "$T1")")"
expect_eq "G20.c3 control: the lead's delete beneath the wave checkout allows" "allow" "$(dec lead "$LEAD_FACTS" "$(D "$WAVE/build")")"
expect_eq "G20.c4 control: the scratch's contents may go" "allow" "$(dec unbound "$UNBOUND_FACTS" "$(D "$S/tmp")")"
expect_eq "G20.c5 a root strictly beneath another delete root may be deleted through the outer one" "allow" \
  "$(dec lead "checkout=$P${NL}tree=$P/.worktrees/25-T9" "$(D "$P/.worktrees/25-T9")")"
expect_eq "G20.c6 a sibling sharing the root's prefix is plain outside, not a root" "deny-fix|outside where" \
  "$(v="$(dec writer "$WRITER_FACTS" "$(D "$T1OLD")")"; printf '%s|' "$(kind "$v")"; case "$v" in (*"outside where"*) printf 'outside where' ;; esac)"
expect_contains "G20.msg the root denial names the root" "$T1" "$(fld 2 "$(dec writer "$WRITER_FACTS" "$(D "$T1")")")"

# ══════════════════════════════════════════════════════════════════════════════════════
section "§G21 one resolver for a whole effect list gives the answers one path at a time gives"

# The hook used to fork once per effect to resolve it, and a 2000-operand rm ran past its
# registration (review S3). grant_resolve_lines resolves a whole list in one process; this
# section holds it to grant_resolve's answers on §G5's real tree, line for line.
G21_IN="$(W "$G5/tree/real.txt")
$(D "$G5/tree/sub/new.txt")
$(R "$G5/tree/out/f")
$(RR "$G5/tree/abs")
$(W "$G5/tree/dangling")
$(D "$G5/tree/../x")
$(W "tree/real.txt")
$(U 'a reason' 'make build')
$(W /dev/null)
$(W /dev/fd/3)
$(W /dev/fd/x)
$(R "$G5/tree/nope/../x")
$(RR "$G5/tree/.bionic/record")"
G21_WANT=""
while IFS= read -r line; do
  k="${line%%"$TAB"*}"; p="${line#*"$TAB"}"
  case "$k:$p" in
    \?:*|W:/dev/null|W:/dev/fd/3) G21_WANT="$G21_WANT$line$NL" ;;
    *) G21_WANT="$G21_WANT$k$TAB$(call grant_resolve "$p")$NL" ;;
  esac
done <<< "$G21_IN"
G21_GOT="$(call grant_resolve_lines "$G21_IN")"
expect_contains "G21.0 the one-at-a-time answers read (a resolved path among them)" "$G5/outside/f" "$G21_WANT"
expect_eq "G21.1 the batch gives the same answers, line for line" "${G21_WANT%"$NL"}" "$G21_GOT"
expect_eq "G21.2 rc 0" "0" "$(call grant_resolve_lines "$G21_IN" >/dev/null; printf '%s' "$CALL_RC")"
G21_CWD="$(cd / && bash -c '. "$1" >/dev/null 2>&1 || exit 127; grant_resolve_lines "$(printf "W\t%s/tree/sub/a" "$2")" >/dev/null; pwd' _ "$LIB" "$G5")"
expect_eq "G21.3 the caller's directory is where it was" "/" "$G21_CWD"
G21_MANY="$(i=1; while [ "$i" -le 400 ]; do printf 'D\t%s/tree/f%s\n' "$G5" "$i"; i=$((i + 1)); done)"
G21_MOUT="$(call grant_resolve_lines "$G21_MANY")"
expect_eq "G21.4 four hundred effects, four hundred answers" "400" "$(printf '%s\n' "$G21_MOUT" | grep -c "^D${TAB}$G5/tree/f")"
expect_eq "G21.5 …the last of them resolved" "D${TAB}$G5/tree/f400" "$(printf '%s\n' "$G21_MOUT" | tail -1)"

finish
