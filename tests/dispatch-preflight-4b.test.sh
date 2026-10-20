#!/bin/bash
# Tests for hooks/dispatch-preflight.sh — THE START GATE. One shard of four, in two parts: part 2 of 2, §T72 … §FILES.
#
# The suite's header (what it governs, how it stays hermetic) is in tests/dispatch-preflight.test.sh; the
# fixtures and their fidelity notes are in tests/dispatch-preflight.prelude.sh; what the two parts of this shard
# share, and why it is two, is in tests/dispatch-preflight-4.prelude.sh.
#
# THIS SHARD IS TWO PARTS (wave-39 T37; D1, D13, REQ-3 AC-3.3). One dispatch-preflight-4.test.sh promised more
# than a landing window holds, so it runs as two suites cut at a section boundary:
#
#   dispatch-preflight-4a.test.sh   S10h … §LR
#   dispatch-preflight-4b.test.sh   §T72 … §FILES
#
# Each is a gating suite by location and each passes alone.
#
# Usage: bash tests/run.sh --only dispatch-preflight-4b.test.sh


set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/bound-marker.sh"
. "$(dirname "$0")/lib/roster-row.sh"
. "$(dirname "$0")/lib/live-answer.sh"
. "$(dirname "$0")/lib/swept-marker.sh"
. "$(dirname "$0")/dispatch-preflight.prelude.sh"

. "$(dirname "$0")/dispatch-preflight-4.prelude.sh"

# ============================================================================

section "§T72 — a reader's suites are its Suites: tokens, and a record is a regular file (wave-27 T72; review pass 49 B1, S1, S2)"
# THE ROLE DECIDES (B1). T49 and T57 each closed the states of a reader's `Suites:` line they
# listed, and review pass 49 found the one neither listed: a line that is all comment. The
# shipped scaffold's line with `none` removed and its comment kept IS that line, and the reader
# was given the writer's derivation (eight suites beside its run) or refused for the missing
# impact command. Each reader below is driven at the real wall WITH a stale impact-command: line
# whose stub would answer eight suites and WITHOUT one (wave-31 T2: nothing reads the line now);
# a writer with the same lines is the control.
T72_REC=.bionic/docs/record/w
T72_SCAF="$(scaffold_raw_line "$DISPATCH_FILE" Suites)"
T72_CMT="Suites:${T72_SCAF#Suites: none}"
T72_HASH="Suites: #"
T72_RUN="Re-executes: ${RL_BT}pytest tests/unit${RL_BT}"
expect_eq "T72 …and with none removed it is a label, a comment and no token" "Suites:  # " "${T72_CMT:0:11}"
t72_impact() {  # <repo> -> an impact command that answers eight suites for any path
  mkdir -p "$1/.bionic"
  printf 'for s in a b c d e f g h; do printf "%%s.test.sh\\t%%s\\n" "$s" "$1"; done\n' > "$1/t72-impact.sh"
  printf 'impact-command: bash %s/t72-impact.sh\n' "$1" > "$1/.bionic/config.yaml"
}
t72_repo() {  # <role key: aud|crit|rev|wr> <on|off> -> the repo that role is dispatched in
  local repo
  case "$1" in
    rev) repo=$(q_unbound "rt72-$1-$2") ;;
    *)   repo=$(make_repo "rt72-$1-$2" yes); write_attestation "$repo" "$SID_A"
         [ "$1" = crit ] && q_rigor "$repo" single ;;
  esac
  [ "$2" = on ] && t72_impact "$repo"
  printf '%s' "$repo"
}
t72_brief() {  # <role key> <tag> <suites line> [<runs line>] -> that role's brief
  local q f
  case "$1" in
    crit) q='evidence, adversarial, structure'; f="$T72_REC/$2-e.md, $T72_REC/$2-a.md, $T72_REC/$2-s.md" ;;
    wr)   q=''; f='lib/a.sh' ;;
    *)    q=evidence; f="$T72_REC/$2-e.md" ;;
  esac
  printf 'Your task: re-run the evidence.\nExpected artifact: %s/%s-e.md\nExpected duration: ~30 minutes.\n' "$T72_REC" "$2"
  [ -n "$q" ] && printf 'Questions: %s\n' "$q"
  printf 'Files: %s\n%s' "$f" "$3"
  [ -n "${4:-}" ] && printf '\n%s' "$4"
  return 0
}
t72_gate() {  # <repo> <tag> <role> <brief> -> R: allow:<suites_allowed>|<suites_source>|<re_executes>, or deny:<first line>
  local row
  q_gate "$1" "t72-$2" "$3" "$4"
  if [ "$GATE_VERDICT" = allow ]; then
    row=$(/usr/bin/grep -F "|name=wq-t72-$2|" "$(roster_path "$1" "$SID_A")" | head -1)
    R="allow:$(roster_field "$row" suites_allowed)|$(roster_field "$row" suites_source)|$(roster_field "$row" re_executes)"
  else R="deny:$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')"; fi
}
T72_N=0
for T72_IMP in on off; do
  for T72_K in "aud bionic:auditor auditor" "crit bionic:critic critic"; do
    set -- $T72_K; T72_KEY=$1; T72_ROLE=$2; T72_WORD=$3
    T72_R=$(t72_repo "$T72_KEY" "$T72_IMP")
    for T72_L in cmt hash; do
      case "$T72_L" in cmt) T72_LINE="$T72_CMT"; T72_SAY="the scaffold line with none removed" ;;
                       *)   T72_LINE="$T72_HASH"; T72_SAY="Suites: #" ;; esac
      T72_N=$((T72_N + 1))
      t72_gate "$T72_R" "$T72_N" "$T72_ROLE" "$(t72_brief "$T72_KEY" "r$T72_N" "$T72_LINE" "$T72_RUN")"
      expect_eq "T72-B1 $T72_ROLE, impact command $T72_IMP, $T72_SAY and one run: admitted, Suites: none, the one run" \
        "allow:none|declared|${RL_BT}pytest tests/unit${RL_BT}" "$R"
      T72_N=$((T72_N + 1))
      t72_gate "$T72_R" "$T72_N" "$T72_ROLE" "$(t72_brief "$T72_KEY" "r$T72_N" "$T72_LINE")"
      expect_contains "T72-B1 $T72_ROLE, impact command $T72_IMP, $T72_SAY and no run: refused, nothing to re-execute" \
        "the $T72_WORD declares nothing to re-execute" "$R"
      expect_contains "T72-B1 …the reason the wall hands back names it" "declares nothing to re-execute" "$GATE_REASON"
      expect_absent "T72-B1 …and no second fault: never the Files-alone refusal" "names no suite" "$GATE_REASON"
      # the lines a brief may hold beside it, through the same library the wall reads
      BV=$(brief_verdict "$T72_ROLE" "$T72_R" "$(t72_brief "$T72_KEY" "v$T72_N" "$T72_LINE" 'Re-executes: none')")
      expect_contains "T72-B1 …and its set is the waiver, nothing derived" "suites=none" "$BV"
      BV=$(brief_verdict "$T72_ROLE" "$T72_R" "$(t72_brief "$T72_KEY" "v$T72_N" "$T72_LINE" \
        "Re-executes: ${RL_BT}pytest a${RL_BT}, ${RL_BT}pytest b${RL_BT}, ${RL_BT}pytest c${RL_BT}, ${RL_BT}pytest d${RL_BT}")")
    done
    BV=$(brief_verdict "$T72_ROLE" "$T72_R" "$(t72_brief "$T72_KEY" "v$T72_N" 'Suites: a.test.sh  # note' \
      "Re-executes: ${RL_BT}pytest a${RL_BT}, ${RL_BT}pytest b${RL_BT}, ${RL_BT}pytest c${RL_BT}")")
  done
  # a writer is untouched: its Files: alone is refused, a stale impact-command: line or not
  T72_R=$(t72_repo wr "$T72_IMP")
  for T72_L in cmt hash; do
    case "$T72_L" in cmt) T72_LINE="$T72_CMT"; T72_SAY="the scaffold line with none removed" ;;
                     *)   T72_LINE="$T72_HASH"; T72_SAY="Suites: #" ;; esac
    T72_N=$((T72_N + 1))
    t72_gate "$T72_R" "$T72_N" bionic:implementor "$(t72_brief wr "r$T72_N" "$T72_LINE" "$T72_RUN")"
    expect_contains "T72-B1 a writer, impact command $T72_IMP, $T72_SAY: refused for Files: alone, as the base does" \
      "Files: alone names no suite" "$R"
  done
done

# A RECORD IS A REGULAR FILE, OR A PATH NOT THERE YET (S1). ONE row: for every shape the wall's
# count of the path beside the fact verb's answer for it once it exists, red on any disagreement.
# The shapes are review pass 49's (its d5 and d6 tables) and the four of the plan's S1 that a
# test can make: a directory named without its slash, a symlink, a FIFO, a path under a directory
# of mode 000. A device needs root to make under record/, and a name holding a comma is two
# Files: entries before the wall sees it, so neither is a row here.
T72_D=$(walk_repo rt72-diff double)
T72_OUT="$SANDBOX/t72-outside"; mkdir -p "$T72_OUT/sub"
T72_LNK="$SANDBOX/t72-link"; ln -s "$SANDBOX" "$T72_LNK"
T72_DR="$T72_D/$T72_REC"
mkdir -p "$T72_DR/dirx" "$T72_DR/locked" "$T72_D/.bionic/tmp/scr"
ln -s "$T72_OUT" "$T72_DR/out"; ln -s "$T72_DR" "$T72_D/.bionic/tmp/scr/in"; ln -s "$T72_OUT/sub" "$T72_DR/lout"
t72_record() {  # <file> -> a reading record the verb takes, for the differential repo
  printf 'reviewed: %s..%s\nquestion: evidence\nresult: pass\nscope: piece\n\nfound\n' \
    "$(git -C "$T72_D" rev-list --max-parents=0 HEAD)" "$(git -C "$T72_D" rev-parse HEAD)" > "$1"
}
t72_record "$T72_DR/sl-target.md"; ln -s "$T72_DR/sl-target.md" "$T72_DR/sl.md"
t72_record "$T72_DR/hard-src.md"; ln "$T72_DR/hard-src.md" "$T72_DR/hard.md"
mkfifo "$T72_DR/ff"
t72_record "$T72_DR/locked/p-locked.md"; chmod 000 "$T72_DR/locked"
T72_AB="$T72_D"; T72_AL="$T72_LNK${T72_D#"$SANDBOX"}"
T72_DIFF=""; T72_SEEN=0; T72_TOOK=0
while IFS='|' read -r T72_TAG T72_P; do
  [ -n "$T72_TAG" ] || continue
  T72_P="${T72_P//@R@/$T72_AB}"; T72_P="${T72_P//@L@/$T72_AL}"
  T72_BR="Your task: read.
Expected artifact: .bionic/tmp/scr/out.md
Expected duration: 30 minutes.
Files: %s
Suites: tests/a.test.sh
Questions: evidence"
  t72_gate "$T72_D" "d-$T72_TAG" bionic:auditor "$(printf "$T72_BR" "$T72_P")"
  case "$R" in
    allow:*) T72_WALL=1; T72_READER="wq-t72-d-$T72_TAG" ;;
    *'dealt 1 question, names 0 records'*) T72_WALL=0
      t72_gate "$T72_D" "v-$T72_TAG" bionic:auditor "$(printf "$T72_BR" "$T72_REC/zz-$T72_TAG.md, $T72_P")"
      T72_READER="wq-t72-v-$T72_TAG" ;;
    *) T72_WALL="?"; T72_READER="" ;;
  esac
  T72_VERB="?"
  if [ -n "$T72_READER" ] && [ "${R%%:*}" = allow ]; then
    walk_start "$T72_D" "$T72_READER"
    case "$T72_P" in /*) T72_K="$T72_P" ;; *) T72_K="$T72_D/$T72_P" ;; esac
    # the path exists when the verb reads it: a missing file is written where the kernel puts
    # it, and also where a logical cd places it, so the answer is the placing's and not the content's
    if [ ! -e "$T72_K" ] && [ ! -L "$T72_K" ] && [ "${T72_K%/}" = "$T72_K" ]; then
      mkdir -p "$(dirname "$T72_K")" 2>/dev/null && t72_record "$T72_K" 2>/dev/null
      T72_LOG="$(cd "$(dirname "$T72_K")" 2>/dev/null && pwd -P)" && [ -d "$T72_LOG" ] \
        && [ ! -e "$T72_LOG/$(basename "$T72_K")" ] && t72_record "$T72_LOG/$(basename "$T72_K")" 2>/dev/null
    fi
    if (cd "$T72_D" && env -u CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID="$SID_A" bash "${BIONIC_HOOKS_DIR}/session-poker.sh" \
          proof-add review "$T72_K" --question evidence --reader "$T72_READER" >/dev/null 2>&1); then T72_VERB=1; else T72_VERB=0; fi
  fi
  T72_SEEN=$((T72_SEEN + 1)); [ "$T72_VERB" = 1 ] && T72_TOOK=$((T72_TOOK + 1))
  printf '  T72-S1 shape %-10s wall=%s verb=%s  %s\n' "$T72_TAG" "$T72_WALL" "$T72_VERB" "$T72_P"
  [ "$T72_WALL" = "$T72_VERB" ] || T72_DIFF="$T72_DIFF $T72_TAG(wall=$T72_WALL,verb=$T72_VERB)"
done <<T72_SHAPES
plain|$T72_REC/p-plain.md
abs|@R@/$T72_REC/p-abs.md
abslink|@L@/$T72_REC/p-abslink.md
outlink|$T72_REC/out/p-out.md
outlinkA|@R@/$T72_REC/out/p-outA.md
inlink|.bionic/tmp/scr/in/p-in.md
inlinkL|@L@/.bionic/tmp/scr/in/p-inL.md
dotdotin|$T72_REC/../w/p-dd.md
dotdotout|$T72_REC/../../plans/p-ddo.md
newpar|$T72_REC/newdir/p-new.md
newparL|@L@/$T72_REC/newdir2/deeper/p-newL.md
slash|$T72_REC/dirx/
dirnoslash|$T72_REC/dirx
quote|$T72_REC/it's.md
dotslash|./$T72_REC/p-ds.md
dblslash|@R@/.bionic//docs/./record/w/p-dbl.md
nopedotdot|$T72_REC/nope/../p-nope.md
loutdotdot|$T72_REC/lout/../p-lout.md
symfile|$T72_REC/sl.md
hardlink|$T72_REC/hard.md
case|.bionic/docs/RECORD/w/p-case.md
docsrel|record/w/p-docsrel.md
locked|$T72_REC/locked/p-locked.md
tilde|~/p-tilde.md
fifo|$T72_REC/ff
T72_SHAPES
chmod 755 "$T72_DR/locked"
expect_eq "T72-S1 the differential ran every shape" "25" "$T72_SEEN"
expect_eq "T72-S1 …the verb took fourteen of them, so both answers are in the table" "14" "$T72_TOOK"
expect_eq "T72-S1 for every shape the wall counts a record exactly when the fact verb takes it" "" "$T72_DIFF"

# THE COST OF PLACING (S2): linear in a path's length, and a path over 1,024 bytes is no record.
t72_len() {  # <bytes> -> a path under the record root of exactly that many bytes, its directories missing
  local p="$T72_REC/n" n
  while [ "$(( ${#p} + 5 ))" -le "$1" ]; do p="$p/a"; done
  p="$p.md"; n=$(( $1 - ${#p} )); while [ "$n" -gt 0 ]; do p="${p%.md}x.md"; n=$((n - 1)); done
  printf '%s' "$p"
}
T72_R=$(make_repo rt72-len yes); write_attestation "$T72_R" "$SID_A"
T72_P1024=$(t72_len 1024); T72_P1025=$(t72_len 1025)
expect_eq "T72-S2 precondition: the two paths are 1,024 and 1,025 bytes" "1024 1025" \
  "$(printf '%s' "$T72_P1024" | wc -c | tr -d ' ') $(printf '%s' "$T72_P1025" | wc -c | tr -d ' ')"
t72_gate "$T72_R" len1024 bionic:auditor "$(t72_brief aud x 'Suites: tests/a.test.sh' | sed "s|^Files: .*|Files: $T72_P1024|; s|^Expected artifact: .*|Expected artifact: .bionic/tmp/scr/out.md|")"
expect_contains "T72-S2 a record path of 1,024 bytes is a record" "allow:" "$R"
t72_gate "$T72_R" len1025 bionic:auditor "$(t72_brief aud x 'Suites: tests/a.test.sh' | sed "s|^Files: .*|Files: $T72_P1025|; s|^Expected artifact: .*|Expected artifact: .bionic/tmp/scr/out.md|")"
expect_contains "T72-S2 a record path of 1,025 bytes is no record" "dealt 1 question, names 0 records" "$R"
# twenty paths of 2,500 missing segments: a reader's dispatch within one second of a writer's
# same line, under /bin/bash 3.2 (the best of two each, so one busy moment is not the verdict)
T72_DEEP=""; for T72_I in $(seq 1 2500); do T72_DEEP="${T72_DEEP}a/"; done
T72_F20=""; for T72_I in $(seq 1 20); do T72_F20="${T72_F20:+$T72_F20, }$T72_REC/c$T72_I/${T72_DEEP}x.md"; done
T72_BEST_W=999999; T72_BEST_A=999999
for T72_I in 1 2; do
  for T72_K in "w bionic:implementor" "a bionic:auditor"; do
    set -- $T72_K
    PATH="/bin:$PATH" GATE_HIRES=1 q_gate "$T72_R" "t72-cost$1$T72_I" "$2" "Your task: read.
Expected artifact: .bionic/tmp/scr/out.md
Expected duration: 30 minutes.
Files: $T72_F20
Suites: tests/a.test.sh
Questions: evidence"
    [ "$1" = w ] && T72_WV="$GATE_VERDICT"
    if [ "$1" = w ]; then [ "${GATE_TIME_CS:-999999}" -lt "$T72_BEST_W" ] && T72_BEST_W="$GATE_TIME_CS"
    else [ "${GATE_TIME_CS:-999999}" -lt "$T72_BEST_A" ] && T72_BEST_A="$GATE_TIME_CS"; fi
  done
done
expect_eq "T72-S2 the writer's dispatch with twenty deep paths is admitted (the control runs)" "allow" "$T72_WV"
printf '  T72-S2 best of two: writer %s cs, reader %s cs\n' "$T72_BEST_W" "$T72_BEST_A"
expect_eq "T72-S2 twenty paths of 2,500 missing segments cost a reader at most one second over a writer" "ok" \
  "$([ "$T72_BEST_A" -le $((T72_BEST_W + 100)) ] && echo ok || echo "reader ${T72_BEST_A} cs, writer ${T72_BEST_W} cs")"
# the placing alone, under /bin/bash 3.2: twenty paths of 1,000 bytes cost what twenty short ones do
T72_PLACE=$(/usr/bin/sed -n '/^    _dp_rec_place() {/,/^    }/p' "$GATE")
expect_contains "T72-S2 precondition: the placing is lifted out of the wall" "_dp_rec_place() {" "$T72_PLACE"
T72_COST=$(/bin/bash -c '
  eval "$1"; BIONIC_ROOT="$2"
  cs() { python3 -c "import time; print(int(time.time()*100))"; }
  long="'"$T72_REC"'/n"; while [ "${#long}" -lt 990 ]; do long="$long/a"; done
  t0=$(cs); for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do _dp_rec_place "$long/x$i.md" >/dev/null; done; t1=$(cs)
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do _dp_rec_place "'"$T72_REC"'/s$i/x.md" >/dev/null; done; t2=$(cs)
  printf "%s %s %s" "$(_dp_rec_place "'"$T72_REC"'/s1/x.md")" "$((t1 - t0))" "$((t2 - t1))"
' _ "$T72_PLACE" "$T72_R" 2>&1)
expect_contains "T72-S2 the lifted placing runs and places a short path" "$T72_REC/s1/x.md" "$T72_COST"
set -- $T72_COST
expect_eq "T72-S2 placing twenty 1,000-byte paths costs at most half a second over twenty short ones" "ok" \
  "$([ "${2:-999999}" -le $(( ${3:-0} + 50 )) ] && echo ok || echo "long ${2:-?} cs, short ${3:-?} cs")"

# TWO SENTENCES (S3, S4) say what the code does.
BV=$(brief_detail bionic:auditor "$BRIEF_NOCONF" "Questions: evidence
Suites: tests/a.test.sh, tests/b.test.sh, tests/c.test.sh, tests/d.test.sh")
expect_absent "T72-S4 …never \"a shell operator\", which a redirection is and a quoted ; is not" "a shell operator" "$BV"
T72_S3=$(/usr/bin/grep -n "AN ABSOLUTE PATH IS PLACED AS THE FACT VERB PLACES IT" -A3 "$GATE")
expect_contains "T72-S3 the placing's comment is found in the wall" "PLACES IT" "$T72_S3"
expect_absent "T72-S3 …never that the verb reads with cd -P" 'with `cd -P`' "$T72_S3"

# ============================================================================

section "§LANDS-ON — a writer binding a row names the suites it lands on (wave-28 T7; REQ-1 AC-1.4, D4)"
# =====================================================================
# ============================================================================
#
# A brief carries `Lands-on: <suite>[, <suite>]` or `Lands-on: none <reason>` on a line of its own.
# The wall writes it on the launch row as `lands_on=`, a bare suite as `<name>.test.sh` and a path-qualified
# one at its declared path (wave-34 T27; the spelling lib/line.sh `_line_suites` decodes, so ready runs
# that file), and refuses: a writer brief that binds a
# row of the bound plan and carries no line (ruling A-orch-73: a dispatch binding no row is owed
# none; A-orch-71: whatever version wrote the plan); `none` with no reason; a suite outside the set
# the checks derived. FIXTURES: adv_brief's writer contract (Suites: tests/widget.test.sh), on
# make_repo's approved, bound plan with a `## Tasks` table holding T23 and A2. SYNTHESIZED.
# fails-when: a bound writer with no line, a reasonless none, or an outside suite is admitted; a
# well-formed line is refused or not written in the one spelling; an unbound writer is refused.
t7_gate() {  # <repo tag> <body lines> [<name>] [<subagent_type>] [<brief>] -> GATE_*, T7_ROW
  REPO=$(make_repo "$1" yes); write_attestation "$REPO" "$SID_A"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T23 | 4 | build | the widget | implementor | — | 30 | REQ-1 | a.sh | — | — | pending | — |\n| A2 | 4 | build | another | implementor | — | 30 | REQ-1 | b.sh | — | — | pending | — |\n' \
    >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "${5:-$(adv_brief "$2")}" "${3:-w99-T23}" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" "${4:-implementor}")"
  T7_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
}
t7_first() { printf '%s\n' "$GATE_ERR" | grep -m1 'bionic: dispatch refused'; }
t7_cols_ok() { [ "$(bionic_cols "$(t7_first)")" -le 100 ] && echo ok || echo "wide:$(bionic_cols "$(t7_first)")"; }

t7_gate lo1 'Scope constraint: touch only payload/scripts/lib/widget.sh.'
expect_eq "LO1 a writer named w99-T23 (row T23's by the name match) with no Lands-on: line is refused" "deny" "$GATE_VERDICT"
expect_contains "LO1c …the detail gives the line to add" "    Lands-on: <suite>[, <suite>]" "$GATE_VERR"
expect_contains "LO1d …and the none form with its reason" "    Lands-on: none <reason>" "$GATE_VERR"
expect_eq "LO1e …its first line is at most 100 columns" "ok" "$(t7_cols_ok)"
expect_eq "LO1f …and no row is written" "" "$T7_ROW"

t7_gate lo2 'Lands-on: widget'
expect_eq "LO2 Lands-on: widget, a suite of the row's set named bare, is admitted" "allow" "$GATE_VERDICT"
expect_eq "LO2b …the row carries lands_on=widget.test.sh, the one spelling" "widget.test.sh" "$(roster_field "$T7_ROW" lands_on)"
t7_gate lo2t 'Lands-on: tests/widget.test.sh  # the suite this row lands on'
expect_eq "LO2t Lands-on: tests/widget.test.sh with a trailing comment is admitted, written at its declared path" \
  "allow|tests/widget.test.sh" "$GATE_VERDICT|$(roster_field "$T7_ROW" lands_on)"
# A path-qualified suite is in the row's set by its file name (Suites: records suites so), and the row keeps
# the path, so ready runs that file and no other of its name. fails-when: the path is refused as outside
# Suites:, or the row carries the file name alone.
t7_gate lo2p 'Lands-on: scripts/deploy/__tests__/widget.test.sh'
expect_eq "LO2p Lands-on: scripts/deploy/__tests__/widget.test.sh, in Suites: by its file name, is admitted, written at its path" \
  "allow|scripts/deploy/__tests__/widget.test.sh" "$GATE_VERDICT|$(roster_field "$T7_ROW" lands_on)"
t7_gate lo2x 'Lands-on: ../widget.test.sh'
expect_eq "LO2x Lands-on: ../widget.test.sh, a path out of the tree, is refused" "deny" "$GATE_VERDICT"
expect_contains "LO2x2 …naming it" "Lands-on: ../widget" "$(t7_first)"
expect_contains "LO2x3 …as no suite of the set" "is outside Suites:" "$(t7_first)"

LO3_S="a-suite-name-of-sixty-characters-long-enough-to-wrap.test.sh"
t7_gate lo3 "Lands-on: widget.test.sh, ${LO3_S}"
expect_eq "LO3 a Lands-on: naming a suite outside the row's set is refused" "deny" "$GATE_VERDICT"
expect_contains "LO3b …the line names the suite, cut to fit" "Lands-on: a-suite-name" "$(t7_first)"
expect_eq "LO3d …its first line at most 100 columns with a sixty-character name" "ok" "$(t7_cols_ok)"
expect_contains "LO3e …the detail names the set it may name from" "Suites: widget.test.sh" "$GATE_VERR"
expect_eq "LO3f …and no row is written" "" "$T7_ROW"
t7_gate lo3r 'Lands-on: run.sh'
expect_contains "LO3r the full-suite runner is no suite of the line: refused as outside the set" "Lands-on: run.sh is outside Suites:" "$(t7_first)"

t7_gate lo4 'Lands-on: none'
expect_eq "LO4 Lands-on: none with no reason is refused" "deny" "$GATE_VERDICT"
expect_contains "LO4b …the line says it gives no reason" "Lands-on: none gives no reason" "$(t7_first)"
expect_eq "LO4c …its first line at most 100 columns" "ok" "$(t7_cols_ok)"
t7_gate lo5 'Lands-on: none — the row edits only prose no suite reads'
expect_eq "LO5 Lands-on: none with a reason is admitted, the row carrying lands_on=none" \
  "allow|none" "$GATE_VERDICT|$(roster_field "$T7_ROW" lands_on)"

t7_gate lo6 'Scope constraint: touch only payload/scripts/lib/widget.sh.' w99-misc
expect_eq "LO6 an unbound writer (w99-misc is no row's name, no Row: label) with no Lands-on: is admitted" "allow" "$GATE_VERDICT"
expect_contains "LO6b …its row is written (the extractor reads a real row)" "status=intended" "$T7_ROW"
expect_absent "LO6c …with no lands_on= on it" "lands_on=" "$T7_ROW"
t7_gate lo7 'Scope constraint: read only.' w99-T23 bionic:researcher \
  "$(adv_brief 'Scope constraint: read only.' | sed '/^Files:/d; s#^Suites: .*#Suites: none#')"
expect_eq "LO7 a read-only role bound to T23 by its name, with no Lands-on:, is admitted" "allow" "$GATE_VERDICT"
expect_contains "LO7b …its row is written" "subagent_type=bionic:researcher" "$T7_ROW"
t7_gate lo8 'Lands-on: <suite>[, <suite>]'
expect_eq "LO8 the scaffold slot pasted unfilled declares nothing: the bound writer is refused for no line" \
  "deny" "$GATE_VERDICT"

# §LANDS-ON, THE READS INDEX (wave-36 T27; REQ-6 AC-6.1; D12, ADR-056). A writer binding a row lands on every suite
# that reads its Files: lib/anchors.sh `reads_index`, read once per dispatch at the plan's working head (the tree
# here, the plan naming no working branch), routes a file to each suite whose text names it, and the wall refuses a
# Lands-on: that omits one, printing the missing suites and a whole Lands-on: line the author can paste. A declared
# `none <reason>` is refused the same way: a reason does not unread a file. FIXTURES: t7_gate's plan, with the
# tree holding payload/scripts/lib/widget.sh, read by widget.test.sh and by reader.test.sh's grep; other.test.sh
# reads neither. fails-when: a Lands-on: omitting reader.test.sh is admitted, or one naming both is refused.
li_gate() {  # <repo tag> <brief> -> GATE_*, T7_ROW: t7_gate's plan, its tree holding the reading suites
  REPO=$(make_repo "$1" yes); write_attestation "$REPO" "$SID_A"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T23 | 4 | build | the widget | implementor | — | 30 | REQ-1 | a.sh | — | — | pending | — |\n' \
    >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  mkdir -p "$REPO/payload/scripts/lib" "$REPO/tests"
  printf 'the widget\n' > "$REPO/payload/scripts/lib/widget.sh"; printf 'the gadget\n' > "$REPO/payload/scripts/lib/gadget.sh"
  printf '#!/bin/bash\nbash "$REPO/payload/scripts/lib/widget.sh"\n' > "$REPO/tests/widget.test.sh"
  printf '#!/bin/bash\ngrep -c widget "$REPO/payload/scripts/lib/widget.sh"\n' > "$REPO/tests/reader.test.sh"
  printf '#!/bin/bash\necho other\n' > "$REPO/tests/other.test.sh"
  git -C "$REPO" add payload tests >/dev/null 2>&1 && git -C "$REPO" commit -qm "suites that read the widget" >/dev/null 2>&1
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$2" w99-T23 claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" implementor)"
  T7_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
}
li_brief() {  # <Lands-on line> [<Suites line>] [<Files line>] -> adv_brief's contract with those lines
  adv_brief "$1" | sed "s#^Suites: .*#${2:-Suites: tests/widget.test.sh}#; s#^Files: .*#${3:-Files: payload/scripts/lib/widget.sh}#"
}
li_gate li0 "$(li_brief 'Lands-on: widget')"
expect_eq "LI-0 precondition: the reads index of the fixture names widget.test.sh and reader.test.sh for the widget, not other.test.sh" \
  "payload/scripts/lib/widget.sh	tests/reader.test.sh,tests/widget.test.sh" \
  "$(bash "${BIONIC_HOOKS_DIR}/../payload/scripts/lib/anchors.sh" reads_index "$REPO" 2>/dev/null | awk -F'\t' '$1 == "payload/scripts/lib/widget.sh"')"
expect_eq "LI-1 AC-6.1 a Lands-on: omitting reader.test.sh, which greps the brief's Files, is refused" "deny" "$GATE_VERDICT"
expect_contains "LI-1b …the line says Lands-on: omits a suite that reads the Files" "Lands-on: omits reader.test.sh" "$(t7_first)"
expect_eq "LI-1c …its first line is at most 100 columns" "ok" "$(t7_cols_ok)"
expect_contains "LI-1d …the detail prints the missing suites on one line" "    Missing:  reader.test.sh" "$GATE_VERR"
expect_contains "LI-1e …and the whole line to paste" "    Lands-on: widget.test.sh, reader.test.sh" "$GATE_VERR"
expect_absent "LI-1f …never a suite that reads none of the Files (positive: LI-1d read reader.test.sh from the same detail)" \
  "other.test.sh" "$GATE_VERR"
expect_eq "LI-1g …and no row is written" "" "$T7_ROW"
li_gate li2 "$(li_brief 'Lands-on: widget, reader' 'Suites: tests/widget.test.sh, tests/reader.test.sh')"
expect_eq "LI-2 AC-6.1 a Lands-on: naming every suite the index names for the Files is admitted, written whole" \
  "allow|widget.test.sh,reader.test.sh" "$GATE_VERDICT|$(roster_field "$T7_ROW" lands_on)"
li_gate li3 "$(li_brief 'Lands-on: none — the row edits only prose no suite reads')"
expect_eq "LI-3 Lands-on: none with a reason, on Files the index routes to suites, is refused the same way" "deny" "$GATE_VERDICT"
expect_contains "LI-3b …naming the suites it omits" "    Missing:  reader.test.sh, widget.test.sh" "$GATE_VERR"
expect_contains "LI-3c …and the line to paste in place of none" "    Lands-on: reader.test.sh, widget.test.sh" "$GATE_VERR"
li_gate li4 "$(li_brief 'Lands-on: none — the gadget is read by no suite' '' 'Files: payload/scripts/lib/gadget.sh')"
expect_eq "LI-4 control: Files no suite reads, Lands-on: none with its reason, is admitted (positive: LI-3 refused on the same tree)" \
  "allow|none" "$GATE_VERDICT|$(roster_field "$T7_ROW" lands_on)"

# ============================================================================

section "§ROW-LABEL — Row: binds the dispatch to a row of the plan, and a Row: the name contradicts is refused (wave-28 T7, T55; REQ-3 AC-3.4, D17)"
# ============================================================================
# `Row: <id>` on a line of its own is written on the launch row as `row=<id>`; the launch record,
# the fill and the stop wall read it before the name match (tests/session-poker.test.sh §ROW-LABEL,
# tests/stop.test.sh §LAUNCHED). A Row: naming no row of the bound plan is refused.
# fails-when: the label is not written, a row the plan lacks is admitted, or a fenced example binds.
t7_gate rl1 'Row: T23
Lands-on: widget' w-misc
expect_eq "RL1 an agent named w-misc (no row's name) briefed Row: T23 with its Lands-on: is admitted" "allow" "$GATE_VERDICT"
expect_eq "RL1b …the row carries row=T23" "T23" "$(roster_field "$T7_ROW" row)"
expect_eq "RL1c …and lands_on=widget.test.sh" "widget.test.sh" "$(roster_field "$T7_ROW" lands_on)"
t7_gate rl1n 'Row: T23' w-misc
expect_eq "RL1n Row: T23 binds an agent no name match would: with no Lands-on: it is refused" "deny" "$GATE_VERDICT"
t7_gate rl2 'Row: T99
Lands-on: widget' w-A2
expect_eq "RL2 Row: T99, no row of the bound plan, is refused" "deny" "$GATE_VERDICT"
expect_contains "RL2b …the line names the label" "Row: T99 names no plan row" "$(t7_first)"
expect_eq "RL2c …its first line at most 100 columns" "ok" "$(t7_cols_ok)"
expect_contains "RL2d …the detail names the plan" "wave-01-test.plan.md" "$GATE_VERR"
t7_gate rl3 'Lands-on: widget'
expect_contains "RL3 a brief with no Row: is admitted and its row written" "status=intended" "$T7_ROW"
expect_absent "RL3b …with no row= on it" "|row=" "$T7_ROW"
t7_gate rl4 'An example of the label, never read:
```
Row: T23
```' w-misc
expect_eq "RL4 a Row: inside a fenced block is an example: the unbound writer is admitted" "allow" "$GATE_VERDICT"
expect_contains "RL4b …its row is written" "status=intended" "$T7_ROW"
expect_absent "RL4c …with no row= on it" "|row=" "$T7_ROW"

# ============================================================================

section "§ONE-ROW — a dispatch is bound to ONE row, whichever arm asks (wave-28 T55; REQ-1 AC-1.1, AC-1.3, D4)"
# ============================================================================
# T7 made `Row:` bind the launch record, the fill, the stop wall and the landing; the approval arm and
# the full-run floor still found the row by the agent's NAME. The wall now answers "whose dispatch is
# this" in one place (`dp_row_reader`): the brief's `Row:` when it carries one, else the row the name
# matches, and every arm reads that id. A `Row:` naming a row other than the one the name matches is
# refused; a name that matches no row with a `Row:` that names one is T7's design and stays admitted.
# FIXTURES: make_repo's approved plan with T1, T2 and T9 (T9 reads approval:release, never recorded).
# P1-P3 are the reader's probe (w28-T24-r26 probe-dp.log). SYNTHESIZED.
# fails-when: a Row:-bound dispatch under a name that matches no row, or another row, passes the
# approval arm; the full-run floor reads the name when the brief carries Row:; the mismatch is
# admitted or its line is over 100 columns; a name that matches nothing is refused for its Row:.
t55_gate() {  # <tag> <name> <body lines> [<extra row ids, space-separated>] -> GATE_*, T7_ROW
  local _x _ids=""
  REPO=$(make_repo "$1" yes); write_attestation "$REPO" "$SID_A"
  local _r
  for _x in ${4:-}; do
    _r="—"; case "$_x" in *=*) _r="${_x#*=}"; _x="${_x%%=*}" ;; esac   # `<id>=<reads>` gives the row a reads cell
    _ids="${_ids}| ${_x} | 4 | build | long | implementor | — | 30 | REQ-1 | c.sh | — | — | pending | ${_r} |
"; done
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | the widget | implementor | — | 30 | REQ-1 | a.sh | — | — | pending | — |\n| T2 | 4 | build | another | implementor | — | 30 | REQ-1 | b.sh | — | — | pending | — |\n| T9 | 7 | doc | the release | implementor | — | 20 | REQ-1 | CHANGELOG.md | — | — | pending | approval:release |\n%s' "$_ids" \
    >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief "$3")" "$2" claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" implementor)"
  T7_ROW=$(roster_nth_row "$(roster_path "$REPO" "$SID_A")" 1)
}
OR_WAIT="row T9 waits for approval:release"

t55_gate or1 w-T9 'Lands-on: widget'
expect_eq "OR1 (P1) an agent named w-T9, no Row:, is refused: its row waits for the release's approval" "deny" "$GATE_VERDICT"
expect_contains "OR1b …the line names the row and the approval" "$OR_WAIT" "$(t7_first)"
t55_gate or2 w-release 'Row: T9
Lands-on: widget'
expect_eq "OR2 (P2) an agent named w-release (no row's name) briefed Row: T9 is refused by the approval arm" "deny" "$GATE_VERDICT"
expect_contains "OR2b …the line names the row the label bound and the approval" "$OR_WAIT" "$(t7_first)"
expect_eq "OR2c …and no row is written" "" "$T7_ROW"
t55_gate or3 w-T1 'Row: T9
Lands-on: widget'
expect_eq "OR3 (P3) an agent named w-T1 briefed Row: T9 is refused" "deny" "$GATE_VERDICT"
expect_contains "OR3b …the approval wait is on the wire" "$OR_WAIT" "$GATE_ERR"
expect_eq "OR3d …and no row is written" "" "$T7_ROW"

t55_gate or4 w-T1 'Row: T2
Lands-on: widget'
expect_eq "OR4 a name that matches T1 briefed Row: T2 (a row waiting on nothing) is refused" "deny" "$GATE_VERDICT"
expect_eq "OR4c …its first line at most 100 columns" "ok" "$(t7_cols_ok)"
expect_contains "OR4d …the detail names both rows and the plan" "wave-01-test.plan.md" "$GATE_VERR"
expect_eq "OR4e …and no row is written" "" "$T7_ROW"
OR_LA="a-row-id-of-forty-characters-long-000001"; OR_LB="b-row-id-of-forty-characters-long-000002"
t55_gate or4w "w-${OR_LB}" "Row: ${OR_LA}
Lands-on: widget" "$OR_LA $OR_LB"
expect_eq "OR4f the widest case, two forty-character row ids, is refused for the mismatch" "deny" "$GATE_VERDICT"
expect_eq "OR4h …and that line is at most 100 columns" "ok" "$(t7_cols_ok)"

t55_gate or5 w-misc 'Row: T2
Lands-on: widget'
expect_eq "OR5 a name that matches no row briefed Row: T2 is admitted (T7's design)" "allow" "$GATE_VERDICT"
expect_eq "OR5b …the row carries row=T2" "T2" "$(roster_field "$T7_ROW" row)"
t55_gate or6 w-T2 'Row: T2
Lands-on: widget'
expect_eq "OR6 a name that matches T2 briefed Row: T2 is admitted" "allow" "$GATE_VERDICT"
expect_eq "OR6b …the row carries row=T2" "T2" "$(roster_field "$T7_ROW" row)"
t55_gate or7 w-T9 'Row: T9
Lands-on: widget'
expect_eq "OR7 a name and a Row: that agree on T9 are held by T9's approval alike" "deny" "$GATE_VERDICT"
expect_contains "OR7b …naming the wait" "$OR_WAIT" "$(t7_first)"
t55_gate or8 w-release 'Row: T99
Lands-on: widget'
expect_contains "OR8 a Row: naming no plan row is still the one refusal, never a mismatch beside it" \
  "Row: T99 names no plan row" "$(t7_first)"
expect_absent "OR8b …and no mismatch line rides with it" "is not the name's row" "$GATE_ERR"

# THE FULL-RUN FLOOR finds its row by the same reader. T12 waits on T2 only; T13 (another verify row)
# waits on T5. A dispatch that names no row is held by both; one briefed Row: T12 under a name that
# matches nothing is held by T2 alone.
OR_FLOOR="$(pf_repo orfloor)"
write_attestation "$OR_FLOOR" "$SID_A"
pf_plan "$OR_FLOOR" "" \
  "$(pf_row T1 4 landed lib/one.sh)" \
  "$(pf_row T2 4 active 'lib/two.sh, tests/two.test.sh')" \
  "$(pf_row T5 4 active 'lib/five.sh, tests/five.test.sh')" \
  "$(pf_row T12 5 pending .bionic/docs/record/w99-floor.txt verify 'T1, T2')" \
  "$(pf_row T13 5 pending .bionic/docs/record/w99-other.txt verify 'T1, T5')"
run_gate "$(mk_agent_payload "$SID_A" "$OR_FLOOR" "$PF_FULL_BRIEF" "w99-orx")"
expect_eq "OR9 precondition: a full run naming no row is refused" "deny" "$GATE_VERDICT"
expect_eq "OR9b …held by both open writers (the open verify rows' waits), so the reader is told apart" \
  "T2 T5" "$(pf_line | /usr/bin/grep -o 'T2\|T5' | sort -u | tr '\n' ' ' | sed 's/ $//')"
run_gate "$(mk_agent_payload "$SID_A" "$OR_FLOOR" "$PF_FULL_BRIEF
Row: T12" "w99-orx")"
expect_eq "OR9c the same full run briefed Row: T12 is refused, held by T12's wait" "deny" "$GATE_VERDICT"
expect_contains "OR9d …naming T2, the writer T12 waits on" "T2" "$(pf_line)"
expect_absent "OR9e …and not T5, which only T13 waits on: the floor row is the label's, not the name's" "T5" "$(pf_line)"

# THE MUTATION ARM: the reader returning the name's row alone. The shipped reader denies P2; a doctored
# copy of the hook whose reader ignores Row: admits it, so the row above can fail.
OR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t55-reader.XXXXXX")
OR_HOOKS=$(s21_plant "$OR_ROOT")
sed 's/^  DP_BOUND_ROW="${DP_ROW:-$DP_NAME_ROW}"$/  DP_BOUND_ROW="$DP_NAME_ROW"/' "$GATE" > "$OR_HOOKS/dispatch-preflight.sh"
OR_SAVED_GATE="$GATE"; GATE="$OR_HOOKS/dispatch-preflight.sh"
t55_gate or10 w-release 'Row: T9
Lands-on: widget'
expect_eq "OR10b with the reader returning the name's row alone, P2 is ADMITTED (the row above is red on it)" \
  "allow" "$GATE_VERDICT"
GATE="$OR_SAVED_GATE"; rm -rf "$OR_ROOT"

# AN NAME THAT MATCHES MORE THAN ONE ROW, WITH NO Row:, IS REFUSED (wave-28 T58; REQ-5, D8). The reader
# bound the first match and the approval arm judged only it, so a second match that waits for approval
# was carried past (the pass-31 probe: `x-A-T1` against rows T1 and A-T1). The launch record already
# records nothing for such a name; the wall now says the same. A `Row:` resolves it (T55's mismatch arm
# still judges a label outside the matches); a name that matches one row or none is as T55 built it.
# FIXTURES: rows T1, T2, T9 and A-T1 (A-T1 reads approval:release); `x-A-T1` matches T1 and A-T1, in
# plan order. SYNTHESIZED from the probe. fails-when: the ambiguous name is admitted, its line names
# no row or is over 100 columns, or a Row: on it is not bound and judged.
AN_ROWS="A-T1=approval:release"
t55_gate an1 x-A-T1 'Lands-on: widget' "$AN_ROWS"
expect_eq "AN1 (the probe) a name that matches T1 and A-T1, no Row:, is refused" "deny" "$GATE_VERDICT"
expect_eq "AN1c …its first line at most 100 columns" "ok" "$(t7_cols_ok)"
expect_contains "AN1d …the detail names the dispatch's name and the plan" "x-A-T1" "$GATE_VERR"
expect_eq "AN1e …and no row is written" "" "$T7_ROW"
expect_absent "AN1f …and no approval wait rides with it: the first match is judged by nothing" "waits for approval" "$GATE_VERR"
t55_gate an2 x-A-T1 'Row: A-T1
Lands-on: widget' "$AN_ROWS"
expect_eq "AN2 the same name briefed Row: A-T1 is bound to A-T1 and refused by the approval arm" "deny" "$GATE_VERDICT"
expect_contains "AN2b …the line names A-T1's wait" "row A-T1 waits for approval:release" "$(t7_first)"
expect_contains "AN2c …the detail names the row" "row A-T1 of" "$GATE_VERR"
expect_absent "AN2d …and no ambiguity line rides with it" "matches rows" "$GATE_ERR$GATE_VERR"
t55_gate an3 x-A-T1 'Row: T1
Lands-on: widget' "$AN_ROWS"
expect_eq "AN3 the same name briefed Row: T1 is admitted" "allow" "$GATE_VERDICT"
expect_eq "AN3b …the row carries row=T1" "T1" "$(roster_field "$T7_ROW" row)"
t55_gate an4 w-T9 'Lands-on: widget' "$AN_ROWS"
expect_eq "AN4 a name that matches exactly one row (T9) is bound to it, as before: refused for its wait" "deny" "$GATE_VERDICT"
expect_contains "AN4b …by T9's wait" "$OR_WAIT" "$(t7_first)"
expect_contains "AN4c …the detail names the row" "row T9 of" "$GATE_VERR"
expect_absent "AN4d …with no ambiguity line" "matches rows" "$GATE_ERR$GATE_VERR"
t55_gate an5 w-misc 'Row: T2
Lands-on: widget' "$AN_ROWS"
expect_eq "AN5 a name that matches no row briefed Row: T2 is still admitted (OR5 stands)" "allow" "$GATE_VERDICT"
t55_gate an6 w-T2 'Lands-on: widget' "$AN_ROWS"
expect_eq "AN6 a name that matches exactly one row (T2), no Row:, is admitted" "allow" "$GATE_VERDICT"
expect_eq "AN6b …and its row is written" "intended" "$(roster_field "$T7_ROW" status)"
AN_LX="a-row-id-of-forty-characters-long-0001"; AN_LY="b-row-${AN_LX}"
t55_gate an7 "w-${AN_LY}" 'Lands-on: widget' "$AN_LX $AN_LY"
expect_eq "AN7 the widest case, two long row ids one behind the other's name, is refused" "deny" "$GATE_VERDICT"
expect_eq "AN7c …and that line is at most 100 columns" "ok" "$(t7_cols_ok)"

# THE MUTATION ARM: the ambiguity check removed, so the first match is bound as before. The shipped
# reader refuses AN1; a doctored copy of the hook admits it, so the row above can fail.
AN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t58-reader.XXXXXX")
AN_HOOKS=$(s21_plant "$AN_ROOT")
sed 's/^  if \[ -z "\$DP_ROW" \] \&\& \[ -n "\$DP_NAME_AMBIG" \]; then$/  if false; then/' "$GATE" > "$AN_HOOKS/dispatch-preflight.sh"
AN_SAVED_GATE="$GATE"; GATE="$AN_HOOKS/dispatch-preflight.sh"
t55_gate an8 x-A-T1 'Lands-on: widget' "$AN_ROWS"
expect_eq "AN8b with the check removed, the ambiguous name is ADMITTED on its first match (AN1 is red on it)" \
  "allow" "$GATE_VERDICT"
expect_eq "AN8c …and its row is written, bound to the first match" "intended" "$(roster_field "$T7_ROW" status)"
GATE="$AN_SAVED_GATE"; rm -rf "$AN_ROOT"

# ============================================================================

section "§BARE — a bare file name with an extension is a deliverable (wave-28 T7; REQ-15 AC-15.1, D32)"
# ============================================================================
# The deliverable span takes a name `files_entry` calls a path, as a Files: item is read: a name with
# an extension on a stem holding a letter. A word of prose is not one. The writer here binds no row.
# fails-when: `Expected artifact: notes.md` is refused, or a span of prose names a deliverable.
t7_bare() { adv_brief 'Scope constraint: touch only payload/scripts/lib/widget.sh.' | sed "s#^Expected artifact: .*#Expected artifact: $1#"; }
t7_gate bare1 '' w99-bare implementor "$(t7_bare 'notes.md')"
expect_eq "BARE1 Expected artifact: notes.md is admitted" "allow" "$GATE_VERDICT"
expect_eq "BARE1b …the row's deliverable is notes.md" "notes.md" "$(roster_field "$T7_ROW" deliverable)"
t7_gate bare2 '' w99-bare implementor "$(t7_bare 'a written report of the findings.')"
expect_eq "BARE2 a span of prose with no file name is refused" "deny" "$GATE_VERDICT"
expect_contains "BARE2b …it still names no deliverable" "this brief names no deliverable" "$(t7_first)"
t7_gate bare3 '' w99-bare implementor "$(t7_bare 'version 1.12.0 of the notes')"
expect_contains "BARE3 a version number is no file name: still no deliverable" "this brief names no deliverable" "$(t7_first)"

section "§RIGOR — the dealing is single or double, the same at either scale, and a refusal prints the level by its word (wave-28 T44; wave-30 T11: REQ-1 AC-1.4, D1)"
# ============================================================================
# The wall asks lib/proof.sh `facts_owed`, which reads the plan's word through lib/run.sh
# `rigor_level`: `single` deals the critic every question, `double` the auditor evidence and the
# critic the rest, at task scale as at wave scale, and a refusal names the level as `rigor_print`
# prints it. §Q's fixtures and helpers, the plan's rigor line (and scale line) set per case.
RV_N=0
rv_gate() {  # <tag> <rigor> <role> <questions line or empty> [<scale>] -> GATE_* for that dispatch
  # The repository is named by a counter, never by the rigor word, so no path in a refusal carries it.
  RV_N=$((RV_N + 1))
  REPO=$(make_repo "rv-$1-$RV_N" yes); write_attestation "$REPO" "$SID_A"; q_rigor "$REPO" "$2"
  if [ -n "${5:-}" ]; then
    local p="$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
    sed "s/^scale: .*/scale: $5/" "$p" > "$p.tmp" && mv "$p.tmp" "$p"
  fi
  q_gate "$REPO" "rv-$1" "$3" "$(q_brief "rv-$1" "$4")"
}
# The reviewer row is the retired role (wave-30 T20): still refused, now as retired (§RET reads the line).
for rv_case in "single|bionic:auditor|Questions: evidence|deny" \
               "single|bionic:critic|Questions: evidence, adversarial, structure|allow" \
               "double|bionic:auditor|Questions: evidence|allow" \
               "double|bionic:critic|Questions: adversarial, structure|allow" \
               "double|bionic:reviewer|Questions: structure|deny" \
               "double|bionic:critic|Questions: adversarial|deny" \
               "double|bionic:auditor|Questions: evidence, structure|deny"; do
  IFS='|' read -r rv_l rv_role rv_q rv_want <<< "$rv_case"
  rv_gate w "$rv_l" "$rv_role" "$rv_q"; rv_wv="$GATE_VERDICT"; rv_wq="$(roster_field "$(q_row "$REPO")" questions)"
  rv_gate t "$rv_l" "$rv_role" "$rv_q" task
  expect_eq "RV1 $rv_l, $rv_role, '$rv_q': $rv_want" "$rv_want" "$rv_wv"
  expect_eq "RV1 …and a task-scale plan gives the same verdict" "$rv_wv" "$GATE_VERDICT"
  [ "$rv_want" = allow ] && expect_eq "RV1 …and records the same set" "$rv_wq" "$(roster_field "$(q_row "$REPO")" questions)"
done

# THE PRINTED FORM: the role dealt nothing, and the set the rigor deals, each with its level.
for rv_s in wave task; do
  rv_gate p single bionic:auditor 'Questions: evidence' "$rv_s"
  expect_eq "RV2 single ($rv_s): an auditor is dealt nothing and refused" "deny" "$GATE_VERDICT"
  for rv_old in "independent reader)" "independent readers)" "three independent"; do
    expect_absent "RV2 …and never the printed form before 1.14.0 ('$rv_old')" "$rv_old" "$GATE_VERR"
  done
done
for rv_s in wave task; do
  rv_gate s double bionic:auditor 'Questions: evidence, structure' "$rv_s"
  expect_eq "RV3 double ($rv_s): an auditor naming more than it is dealt is refused" "deny" "$GATE_VERDICT"
  for rv_old in "independent reader)" "independent readers)" "three independent"; do
    expect_absent "RV3 …and never the printed form before 1.14.0 ('$rv_old')" "$rv_old" "$GATE_VERR"
  done
done
for rv_s in wave task; do
  rv_gate m double bionic:critic '' "$rv_s"
  expect_eq "RV4 double ($rv_s): a critic with no Questions: line is refused" "deny" "$GATE_VERDICT"
  expect_absent "RV4 …and never the printed form before 1.14.0" "independent readers" "$GATE_VERR"
done

# THE LONGEST VALUES, UNDER THE STRICT WIDTH (A-orch-17). Each refusal is driven at the widest value
# it can carry: single deals the critic all three questions, and the retired reviewer is refused as retired.
# Under BIONIC_REFUSE_STRICT=1 an over-wide line refuses its own call, so a whole line here is the
# proof it fits.
rv_cols() { bionic_cols "$1"; }
expect_eq "RV5 precondition: this suite runs with the strict refusal width" "1" "${BIONIC_REFUSE_STRICT:-}"
rv_gate w single bionic:critic 'Questions: evidence'
expect_eq "RV5 single: a critic naming one of its three questions is refused" "deny" "$GATE_VERDICT"
RV5_LINE="bionic: dispatch refused — single rigor deals critic: evidence,adversarial,structure (use that set)"
# MEASURED IN COLUMNS (wave-30 T20, A-T20.2): A-T11.9 read this line as 101 columns, one over the budget,
# from an awk `length` that counts the em dash as three bytes under macOS awk; the line is 99 columns, and
# `bionic_cols` (lib/width.sh, the measure the refusal library and §T49 use) says so. rv_cols is that measure.
expect_eq "RV5 …which is 99 columns, inside the 100 budget" "99" "$(rv_cols "$RV5_LINE")"
expect_eq "RV5 …and the line the wall printed is no wider than 100" "ok" \
  "$([ "$(rv_cols "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')")" -le 100 ] && echo ok || echo wide)"
expect_contains "RV5 …the detail names the role as typed" "Role:  bionic:critic" "$GATE_VERR"
# ============================================================================
section "§RET — the structure reader is retired: a brief naming bionic:reviewer is refused, and says where structure went (wave-30 T20; REQ-1 AC-1.6, D2)"
# ============================================================================
# fails-when: the wall admits `subagent_type: bionic:reviewer` at either level or with no bound plan,
# the refusal does not name the retirement and the role that holds `structure`, or its first line is
# wider than 100 columns. Each refusal is read beside the critic admitted on the same plan, so a wall
# that refuses everything cannot pass.
RET_LINE="bionic: dispatch refused — bionic:reviewer is retired (1.14.0) (dispatch bionic:critic)"
for ret_l in single double; do
  rv_gate ret-$ret_l "$ret_l" bionic:reviewer 'Questions: structure'
  expect_eq "RET $ret_l: bionic:reviewer is refused" "deny" "$GATE_VERDICT"
  expect_contains "RET …the detail says structure is the critic's question" "structure is the critic's question" "$GATE_VERR"
  expect_contains "RET …and names the role as typed" "bionic:reviewer" "$GATE_VERR"
  expect_absent "RET …and is not the old 'rigor deals reviewer' refusal" "deals reviewer" "$GATE_ERR"
  rv_gate ret-c-$ret_l "$ret_l" bionic:critic "$([ "$ret_l" = single ] && echo 'Questions: evidence, adversarial, structure' || echo 'Questions: adversarial, structure')"
  expect_eq "RET $ret_l: …while bionic:critic is admitted on the same plan (the positive beside it)" "allow" "$GATE_VERDICT"
done
expect_eq "RET the retirement line is 87 columns, inside the 100 budget" "87" "$(rv_cols "$RET_LINE")"
REPO=$(q_unbound rret-unbound)
q_gate "$REPO" ret-unbound bionic:reviewer "$(q_brief ret-unbound 'Questions: structure')"
expect_eq "RET with no bound plan: bionic:reviewer is refused too" "deny" "$GATE_VERDICT"
REPO=$(q_unbound rret-nq)
q_gate "$REPO" ret-nq bionic:reviewer "$(q_brief ret-nq '')"
# A bare `reviewer` is not the plugin's role (a consumer's own agent of that name may exist): untouched.
REPO=$(make_repo rret-bare yes); write_attestation "$REPO" "$SID_A"
q_gate "$REPO" ret-bare reviewer "$(q_brief ret-bare '')"
expect_absent "RET a bare 'reviewer' is not the retired plugin role" "is retired" "$GATE_ERR"

# ============================================================================

section "§RECORDER — a dispatch the roster cannot carry is refused, and a slow wall refuses too (wave-28 T70; REQ-5, REQ-6, D8)"
# ============================================================================
# THE FINDING (A-orch-205 to 212). Two dispatches of one row were ADMITTED and journalled nothing; the
# harness transcript shows why: both `PreToolUse:Agent` hooks are `hook_cancelled` at 15012 and 15016 ms,
# the registration's own 15 s. A cancelled hook is an admitted dispatch, and the roster append is the
# hook's last step, so a wall that overran left a writer running with no row for any later wall to judge.
# The three paths the plan listed (a symlinked roster, an unwritable one, a row that did not build) were
# warnings or silent exits; none was what happened, and all three are refusals now. The fourth is the
# overrun: the wall carries a deadline of its own, strictly under the registration (the rule for every
# inner bound, pinned by cross-gate-agreement §L.4c), and refuses when the deadline passes before the row is journalled.
#
# fails-when: an unwritable, symlinked or unbuilt roster ADMITS the dispatch; a wall that has not finished by
# the deadline lets the dispatch through; the deadline sits at or over the registration's timeout; or the
# read-only role launched from inside an agent (S20's legitimate case) is refused or journalled.
RC_N=0
rc_repo() {  # <tag> -> REPO, attested, bound to the fixture wave
  RC_N=$((RC_N + 1)); REPO=$(make_repo "rc-$1-$RC_N" yes); write_attestation "$REPO" "$SID_A"
}
rc_rows() { roster_rows "$(roster_path "$REPO" "$SID_A")"; }
# rc_plant <root> <plain|unbuilt|slow> -> the path of a copy of the hook beside a library whose roster.sh
# is the shipped one with `roster_row` replaced: unbuilt returns 2 (the row does not build); slow waits
# two seconds past the copy's DP_DEADLINE_S (RC_DEADLINE, below) and then builds the
# real row, so a wall with no deadline admits it with a row and a wall with one refuses it with none.
# The slow copy's deadline is shortened to RC_DEADLINE (wave-34 T12, D20): RC5 waits that, not the shipped
# one, so one drive costs RC_DEADLINE + 2 s instead of the shipped deadline + 2. Only the scratch copy is
# edited; RC6 reads the shipped file, so the shipped constant is still the one held under the registration.
RC_SHIPPED_DEADLINE="$(sed -n 's/^DP_DEADLINE_S=\([0-9][0-9]*\).*/\1/p' "$GATE" | head -1)"
RC_DEADLINE=8
rc_plant() {
  local root="$1" mode="$2" lib f
  lib="$(cd "${BIONIC_HOOKS_DIR}/../payload/scripts/lib" && pwd -P)"
  mkdir -p "$root/hooks" "$root/scripts/lib"
  for f in "$lib"/*; do
    [ "${f##*/}" = roster.sh ] && continue
    ln -s "$f" "$root/scripts/lib/${f##*/}"
  done
  cp "$lib/roster.sh" "$root/scripts/lib/roster.sh"
  case "$mode" in
    unbuilt) printf '%s\n' 'roster_row() { return 2; }' >> "$root/scripts/lib/roster.sh" ;;
    # the slow roster_row sleeps past the copy's DP_DEADLINE_S (RC_DEADLINE, set in the copy below); the deadline is a constant in the hook (no environment knob pins it), and no wait can observe a deadline sooner than it fires
    slow)    printf '%s\n' '_rc_f="$(declare -f roster_row)"; eval "_rc_orig_${_rc_f}"' \
                           "roster_row() { sleep $(( ${RC_DEADLINE:-12} + 2 )); _rc_orig_roster_row \"\$@\"; }" >> "$root/scripts/lib/roster.sh" ;;
  esac
  if [ "$mode" = slow ]; then
    sed "s/^DP_DEADLINE_S=[0-9][0-9]*/DP_DEADLINE_S=${RC_DEADLINE}/" "$GATE" > "$root/hooks/dispatch-preflight.sh"
  else
    cp "$GATE" "$root/hooks/dispatch-preflight.sh"
  fi
  printf '%s' "$root/hooks/dispatch-preflight.sh"
}
RC_SAVED_GATE="$GATE"
RC_ROOT=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/rc-t70.XXXXXX")" && pwd -P)

# --- RC1: the control. A writable roster journals one row and the dispatch passes, silent.
rc_repo c1
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_eq "RC1 a writable roster admits the dispatch" "allow" "$GATE_VERDICT"
expect_eq "RC1 …and journals exactly one row" "1" "$(rc_rows)"
expect_empty "RC1 …and says nothing on the allow path" "$GATE_ERR"

# --- RC2: S10g and S10h above are the unwritable and the symlinked path. Here the wording is held to
# the width the driver sweeps, and the unwritable path's reason is named as the shell gave it.
rc_repo c2
chmod 555 "$REPO/.bionic/tmp"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
chmod 755 "$REPO/.bionic/tmp"
RC2_LINE="bionic: dispatch refused — the roster cannot be written (make it writable)"
expect_eq "RC2 …and it is 74 columns, inside the 100" "74" "$(bionic_cols "$RC2_LINE")"

# --- RC3: a row that does not build is refused, not appended blank and not warned about.
RC3_GATE="$(rc_plant "$RC_ROOT/unbuilt" unbuilt)"
rc_repo c3
GATE="$RC3_GATE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
GATE="$RC_SAVED_GATE"
expect_eq "RC3 a launch row that does not build REFUSES the dispatch" "deny" "$GATE_VERDICT"
RC3_LINE="bionic: dispatch refused — the launch row did not build (run /bionic:doctor)"
expect_eq "RC3 …which is 76 columns" "76" "$(bionic_cols "$RC3_LINE")"
expect_contains "RC3 …the detail names the roster path" "roster-${SID_A}.state" "$GATE_VERR"
expect_eq "RC3 …and no row, blank or otherwise, was appended" "0" "$(rc_rows)"
RC3P_GATE="$(rc_plant "$RC_ROOT/plain" plain)"
rc_repo c3p
GATE="$RC3P_GATE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
GATE="$RC_SAVED_GATE"
expect_eq "RC3 control: the same copy with the shipped roster.sh admits and journals" "1" "$(rc_rows)"

# --- RC4: the delegation arm's legitimate case is untouched. A read-only role launched from inside an
# agent is admitted, silent, and journals no row (S20, depth one), even on a roster path the other
# paths refuse: the delegation arm answers before any of them.
rc_repo c4
ln -s "$DECOY_ROSTER" "$(roster_path "$REPO" "$SID_A")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$BRIEF_FULL" "w99-impl" "claude-sonnet-5" \
             "$S5_LIVE_TRANSCRIPT" "bionic:researcher" | jq -c '. + {agent_id:"a70nested-0123456789ab"}')"
expect_eq "RC4 a read-only role launched from inside an agent is admitted" "allow" "$GATE_VERDICT"
RC4_LINE="bionic: dispatch admitted without a roster row — a read-only role launched from inside an agent; the ledger stays at depth one"
expect_eq "RC4 …which is 126 columns, a notice and not a refusal" "126" "$(bionic_cols "$RC4_LINE")"
expect_status "RC4 …and the decoy was not appended to" "untouched" "$(cat "$DECOY_ROSTER")"

# --- RC5: THE DEADLINE. The wall waits two seconds past its deadline inside the row's build.
RC5_GATE="$(rc_plant "$RC_ROOT/slow" slow)"
# the copy carries the short deadline and the shipped hook is not the one edited (the sed took, and only in the copy)
expect_eq "RC5 precondition: the slow copy's deadline is the short one" "$RC_DEADLINE" \
  "$(sed -n 's/^DP_DEADLINE_S=\([0-9][0-9]*\).*/\1/p' "$RC5_GATE" | head -1)"
expect_eq "RC5 …and the shipped hook still names its own" "$RC_SHIPPED_DEADLINE" \
  "$(sed -n 's/^DP_DEADLINE_S=\([0-9][0-9]*\).*/\1/p' "$RC_SAVED_GATE" | head -1)"
expect_true "RC5 …and the copy differs from the shipped hook in that line alone" \
  test "$(diff "$RC_SAVED_GATE" "$RC5_GATE" | /usr/bin/grep -c '^[<>]')" -eq 2
rc_repo c5
GATE="$RC5_GATE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
GATE="$RC_SAVED_GATE"
expect_eq "RC5 a wall still working at its deadline REFUSES the dispatch" "deny" "$GATE_VERDICT"
RC5_LINE="bionic: dispatch refused — the wall ran out of time (dispatch again)"
expect_eq "RC5 …which is 68 columns" "68" "$(bionic_cols "$RC5_LINE")"
expect_eq "RC5 …and no row was journalled for the refused launch" "0" "$(rc_rows)"
expect_true "RC5 …after the deadline, not before it (waited at least $(( ${RC_DEADLINE:-12} - 1 )) s)" test "$GATE_TIME" -ge $(( ${RC_DEADLINE:-12} - 1 ))
expect_true "RC5 …and sooner than the shipped deadline of ${RC_SHIPPED_DEADLINE:-?} s (took ${GATE_TIME} s)" test "$GATE_TIME" -lt "${RC_SHIPPED_DEADLINE:-0}"
expect_contains "RC5 …the detail names the roster the row would have gone to" "roster-${SID_A}.state" "$GATE_VERR"

# --- RC6: THE DEADLINE IS UNDER THE REGISTRATION. Both numbers are read, not transcribed.
RC6_DEADLINE="$(sed -n 's/^DP_DEADLINE_S=\([0-9][0-9]*\).*/\1/p' "$GATE" | head -1)"
RC6_TIMEOUT="$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Agent") | .hooks[] | select(.command | test("dispatch-preflight")) | .timeout' "${BIONIC_HOOKS_DIR}/hooks.json" 2>/dev/null)"
expect_nonempty "RC6 precondition: the hook names its deadline" "$RC6_DEADLINE"
expect_nonempty "RC6 precondition: hooks.json registers the hook with a timeout" "$RC6_TIMEOUT"
expect_true "RC6 the deadline sits at least 2 s under the registration's timeout (${RC6_DEADLINE:-?} under ${RC6_TIMEOUT:-?})" \
  test "${RC6_DEADLINE:-99}" -le "$(( ${RC6_TIMEOUT:-0} - 2 ))"
expect_true "RC6 …and above the slowest recorded healthy dispatch (3.8 s)" test "${RC6_DEADLINE:-0}" -ge 8

# --- RC7: THE WATCHDOG LEAVES NOTHING BEHIND. A passed dispatch's hook returns at once, not at the
# deadline, and its timer does not outlive it.
rc_repo c7
RC7_T0=$(date +%s)
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
expect_true "RC7 an allowed dispatch returns well inside the deadline (took ${GATE_TIME}s)" test "$GATE_TIME" -le 6
expect_eq "RC7 …and journalled its row" "1" "$(rc_rows)"
rm -rf "$RC_ROOT"
GATE="$RC_SAVED_GATE"



finish
