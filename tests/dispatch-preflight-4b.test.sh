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
# THE NARROWING (wave-39 T44; D6, AC-2.4, A-orch-22). The verbs of hooks/session-poker.sh this suite reaches,
# directly or through the hooks and scripts it runs: adopt, debt, interval, interval-default, proof-add, row-
# landed, window. Each line below is that closure: the library (every run executes it), the arm of each verb,
# the sections defining the globals they read, and each helper outside those.
reads hooks/session-poker.sh section "the library"
reads hooks/session-poker.sh section "whose run is this?"
reads hooks/session-poker.sh section "the runs (wave-30 T12; D6, D7d)"
reads hooks/session-poker.sh section "is this row too quiet?"
reads hooks/session-poker.sh section "the contract grammar"
reads hooks/session-poker.sh section "the plan transaction"
reads hooks/session-poker.sh section "the call a refusal names"
reads hooks/session-poker.sh section "the launch sync"
reads hooks/session-poker.sh verb adopt
reads hooks/session-poker.sh verb debt
reads hooks/session-poker.sh verb interval
reads hooks/session-poker.sh verb interval-default
reads hooks/session-poker.sh verb proof-add
reads hooks/session-poker.sh verb row-landed
reads hooks/session-poker.sh verb window
reads hooks/session-poker.sh fn clean
reads hooks/session-poker.sh fn clean_whole
reads hooks/session-poker.sh fn count_main_thread_dispatches
reads hooks/session-poker.sh fn count_refused_dispatches
reads hooks/session-poker.sh fn deliver_check
reads hooks/session-poker.sh fn epoch_iso
reads hooks/session-poker.sh fn file_birth
reads hooks/session-poker.sh fn file_mtime
reads hooks/session-poker.sh fn iso_epoch
reads hooks/session-poker.sh fn iso_now
reads hooks/session-poker.sh fn line_field
reads hooks/session-poker.sh fn note
reads hooks/session-poker.sh fn now_epoch
reads hooks/session-poker.sh fn pair
reads hooks/session-poker.sh fn parse_seconds
reads hooks/session-poker.sh fn patrol_stamp_file
reads hooks/session-poker.sh fn poker_interval_seconds
reads hooks/session-poker.sh fn roster_window
reads hooks/session-poker.sh fn row_has_key
reads hooks/session-poker.sh fn row_writer
reads hooks/session-poker.sh fn session_transcript
reads hooks/session-poker.sh fn tmp_dir_ok
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
expect_contains "T72 precondition: the shipped scaffold's Suites: line is the waiver and a comment" "Suites: none  # " "$T72_SCAF"
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
      expect_contains "T72-B1 $T72_ROLE, impact command $T72_IMP, $T72_SAY and Re-executes: none: nothing to re-execute" \
        "finding: the $T72_WORD declares nothing to re-execute" "$BV"
      expect_contains "T72-B1 …and its set is the waiver, nothing derived" "suites=none" "$BV"
      BV=$(brief_verdict "$T72_ROLE" "$T72_R" "$(t72_brief "$T72_KEY" "v$T72_N" "$T72_LINE" \
        "Re-executes: ${RL_BT}pytest a${RL_BT}, ${RL_BT}pytest b${RL_BT}, ${RL_BT}pytest c${RL_BT}, ${RL_BT}pytest d${RL_BT}")")
      expect_contains "T72-B1 $T72_ROLE, impact command $T72_IMP, $T72_SAY and four runs: refused on the total" \
        "finding: the total of 4 runs exceeds the 3-run cap" "$BV"
    done
    BV=$(brief_verdict "$T72_ROLE" "$T72_R" "$(t72_brief "$T72_KEY" "v$T72_N" 'Suites: a.test.sh  # note' \
      "Re-executes: ${RL_BT}pytest a${RL_BT}, ${RL_BT}pytest b${RL_BT}, ${RL_BT}pytest c${RL_BT}")")
    expect_contains "T72-B1 $T72_ROLE, impact command $T72_IMP: a named token beside its comment still counts, four in total" \
      "finding: the total of 4 runs exceeds the 3-run cap" "$BV"
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
expect_contains "T72-S4 the over-cap detail is printed for four suites" "finding: the total of 4 runs exceeds the 3-run cap" "$BV"
expect_contains "T72-S4 …and names the characters that make housekeeping a run, as the cap's comment does" \
  'counts nothing unless it holds one of ; & | ` $( <( >( or a' "$BV"
expect_absent "T72-S4 …never \"a shell operator\", which a redirection is and a quoted ; is not" "a shell operator" "$BV"
T72_S3=$(/usr/bin/grep -n "AN ABSOLUTE PATH IS PLACED AS THE FACT VERB PLACES IT" -A3 "$GATE")
expect_contains "T72-S3 the placing's comment is found in the wall" "PLACES IT" "$T72_S3"
expect_contains "T72-S3 …and says the verb reads with a logical cd, so .. is folded in the text first" \
  'a logical `cd` and then `pwd -P`, so `..` is folded in the text before' "$T72_S3"
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
expect_contains "LO1b …the line says the brief names none" "the brief has no Lands-on: line" "$(t7_first)"
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
expect_contains "LO3c …and its fix" "(name a suite the row runs)" "$(t7_first)"
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
expect_contains "LO8b …the line says the brief names none" "the brief has no Lands-on: line" "$(t7_first)"

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
expect_contains "RL1n2 …for the missing line" "the brief has no Lands-on: line" "$(t7_first)"
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
expect_contains "OR3c …and so is the Row:/name mismatch, one line beside it on the several-fault wire" "Row: T9 is not the name's row T1 (rename or drop Row:)" "$GATE_VERR"
expect_eq "OR3d …and no row is written" "" "$T7_ROW"

t55_gate or4 w-T1 'Row: T2
Lands-on: widget'
expect_eq "OR4 a name that matches T1 briefed Row: T2 (a row waiting on nothing) is refused" "deny" "$GATE_VERDICT"
expect_contains "OR4b …the line says the label is not the name's row (the fix named)" \
  "Row: T2 is not the name's row T1 (rename or drop Row:)" "$(t7_first)"
expect_eq "OR4c …its first line at most 100 columns" "ok" "$(t7_cols_ok)"
expect_contains "OR4d …the detail names both rows and the plan" "wave-01-test.plan.md" "$GATE_VERR"
expect_eq "OR4e …and no row is written" "" "$T7_ROW"
OR_LA="a-row-id-of-forty-characters-long-000001"; OR_LB="b-row-id-of-forty-characters-long-000002"
t55_gate or4w "w-${OR_LB}" "Row: ${OR_LA}
Lands-on: widget" "$OR_LA $OR_LB"
expect_eq "OR4f the widest case, two forty-character row ids, is refused for the mismatch" "deny" "$GATE_VERDICT"
expect_contains "OR4g …each id cut to eleven columns on the one line" "Row: a-row-id-o… is not the name's row b-row-id-o…" "$(t7_first)"
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
expect_eq "OR10 meta: the doctored reader landed (the sed anchor still matches)" "1" \
  "$(/usr/bin/grep -c '^  DP_BOUND_ROW="\$DP_NAME_ROW"$' "$OR_HOOKS/dispatch-preflight.sh")"
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
expect_contains "AN1b …the one line names both rows and the fix (no row named as the remedy: A-orch-230 a)" \
  "the name matches rows T1, A-T1 (add Row: <id>)" "$(t7_first)"
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
expect_contains "AN7b …each id cut to eleven columns on the one line" \
  "the name matches rows a-row-id-o…, b-row-a-ro… (add Row: <id>)" "$(t7_first)"
expect_eq "AN7c …and that line is at most 100 columns" "ok" "$(t7_cols_ok)"

# THE MUTATION ARM: the ambiguity check removed, so the first match is bound as before. The shipped
# reader refuses AN1; a doctored copy of the hook admits it, so the row above can fail.
AN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t58-reader.XXXXXX")
AN_HOOKS=$(s21_plant "$AN_ROOT")
sed 's/^  if \[ -z "\$DP_ROW" \] \&\& \[ -n "\$DP_NAME_AMBIG" \]; then$/  if false; then/' "$GATE" > "$AN_HOOKS/dispatch-preflight.sh"
expect_eq "AN8 meta: the doctored reader landed (the sed anchor still matches)" "1" \
  "$(/usr/bin/grep -c '^  if false; then$' "$AN_HOOKS/dispatch-preflight.sh")"
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
  expect_contains "RV2 …the detail names the level, with its meaning" \
    "Dealt: nothing at review rigor: single (one independent mind), scale $rv_s" "$GATE_VERR"
  for rv_old in "independent reader)" "independent readers)" "three independent"; do
    expect_absent "RV2 …and never the printed form before 1.14.0 ('$rv_old')" "$rv_old" "$GATE_VERR"
  done
done
for rv_s in wave task; do
  rv_gate s double bionic:auditor 'Questions: evidence, structure' "$rv_s"
  expect_eq "RV3 double ($rv_s): an auditor naming more than it is dealt is refused" "deny" "$GATE_VERDICT"
  expect_contains "RV3 …the detail names the dealt set and the level, with its meaning" \
    "Dealt: evidence (review rigor: double (two independent minds), scale $rv_s)" "$GATE_VERR"
  for rv_old in "independent reader)" "independent readers)" "three independent"; do
    expect_absent "RV3 …and never the printed form before 1.14.0 ('$rv_old')" "$rv_old" "$GATE_VERR"
  done
done
for rv_s in wave task; do
  rv_gate m double bionic:critic '' "$rv_s"
  expect_eq "RV4 double ($rv_s): a critic with no Questions: line is refused" "deny" "$GATE_VERDICT"
  expect_contains "RV4 …the detail names the level the set is dealt at, with its meaning" \
    "review rigor: double (two independent minds)" "$GATE_VERR"
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
expect_contains "RV5 …on its own line, the whole set kept" "$RV5_LINE" "$GATE_ERR"
# MEASURED IN COLUMNS (wave-30 T20, A-T20.2): A-T11.9 read this line as 101 columns, one over the budget,
# from an awk `length` that counts the em dash as three bytes under macOS awk; the line is 99 columns, and
# `bionic_cols` (lib/width.sh, the measure the refusal library and §T49 use) says so. rv_cols is that measure.
expect_eq "RV5 …which is 99 columns, inside the 100 budget" "99" "$(rv_cols "$RV5_LINE")"
expect_eq "RV5 …and the line the wall printed is no wider than 100" "ok" \
  "$([ "$(rv_cols "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 'bionic: dispatch refused')")" -le 100 ] && echo ok || echo wide)"
expect_contains "RV5 …the detail names the role as typed" "Role:  bionic:critic" "$GATE_VERR"
expect_contains "RV5 …and the level in the printed form" "review rigor: single (one independent mind)" "$GATE_VERR"
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
  expect_contains "RET …on its own line, naming the retirement and the role to dispatch" "$RET_LINE" "$GATE_ERR"
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
expect_contains "RET …on the same line" "$RET_LINE" "$GATE_ERR"
REPO=$(q_unbound rret-nq)
q_gate "$REPO" ret-nq bionic:reviewer "$(q_brief ret-nq '')"
expect_contains "RET a reviewer brief with no Questions: line is refused as retired as well" "$RET_LINE" "$GATE_ERR"
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
expect_eq "RC2 the refusal's first line is the one the inventory prints" "$RC2_LINE" \
  "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 '^bionic: ')"
expect_eq "RC2 …and it is 74 columns, inside the 100" "74" "$(bionic_cols "$RC2_LINE")"
expect_contains "RC2 …the detail says no row was written and the launch was not admitted" \
  "No row was written, so the launch is not admitted" "$GATE_VERR"

# --- RC3: a row that does not build is refused, not appended blank and not warned about.
RC3_GATE="$(rc_plant "$RC_ROOT/unbuilt" unbuilt)"
rc_repo c3
GATE="$RC3_GATE"
run_gate "$(mk_agent_payload "$SID_A" "$REPO")"
GATE="$RC_SAVED_GATE"
expect_eq "RC3 a launch row that does not build REFUSES the dispatch" "deny" "$GATE_VERDICT"
RC3_LINE="bionic: dispatch refused — the launch row did not build (run /bionic:doctor)"
expect_eq "RC3 …on its own line" "$RC3_LINE" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 '^bionic: ')"
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
expect_eq "RC4 …saying so on one line (A-orch-231 2), on a roster path a main-thread dispatch would be refused for" \
  "$RC4_LINE" "$GATE_ERR"
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
expect_eq "RC5 …on its own line" "$RC5_LINE" "$(printf '%s\n' "$GATE_ERR" | /usr/bin/grep -m1 '^bionic: ')"
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



section "§REMARK — a dispatch into a tree its row already recorded re-marks it for the new name (wave-34 T28; D24, REQ-1 AC-1.1)"
# ============================================================================
# The gate names a writer that carries no name by its tree's `bionic-agent` marker (lib/gate.sh THE
# PLACE), and `spawn-worktree.sh create --for` writes it. A row re-dispatched into the tree its earlier
# launch recorded (the plan row's `worktree` cell) used to keep the predecessor's marker, so the new
# writer asked the gate as the old one; `spawn-worktree.sh mark` existed and nothing called it. The
# wall now calls it for the bound row's recorded tree once the launch is on the roster. FIXTURES: a
# real linked tree of the fixture repo, marked w-T1 by the real `mark`; row T1 active under w-T1 with
# that tree in its cell. The gate ask runs the real gate_ask from the tree, no name carried, against
# a scratch store and a planted machine. SYNTHESIZED.
# fails-when: the dispatch leaves the predecessor's name on the tree (the call removed), the request
# is filed under w-T1, the main checkout or a missing tree gets a marker, or a dispatch is refused.
RMK_SPAWN="${BIONIC_SCRIPTS_DIR}/payload/scripts/spawn-worktree.sh"
RMK_GATE_LIB="${BIONIC_SCRIPTS_DIR}/payload/scripts/lib/gate.sh"
rmk_marker() {  # <tree> -> its own git directory's bionic-agent, or `none`
  local gd; gd="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)"
  [ -n "$gd" ] && [ -f "$gd/bionic-agent" ] && cat "$gd/bionic-agent" || echo none
}
rmk_repo() {  # <tag> <worktree cell> -> REPO, RMK_TREE (.worktrees/34-T1, marked w-T1), row T1 active under w-T1
  REPO=$(make_repo "$1" yes); write_attestation "$REPO" "$SID_A"
  RMK_TREE="$REPO/.worktrees/34-T1"
  git -C "$REPO" worktree add -q --detach "$RMK_TREE" 2>/dev/null
  bash "$RMK_SPAWN" mark "$RMK_TREE" --for w-T1 >/dev/null 2>&1
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | the widget | w-T1 | — | 30 | REQ-1 | a.sh | %s | %s | active | — |\n' \
    "$2" "$(git -C "$REPO" rev-parse HEAD)" >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
}
rmk_who() {  # <dir> <key> -> the who= of the request one gate_ask work <key> from <dir> files, no name carried
  local g; g="$(mktemp -d "$SANDBOX/rmk-gate.XXXXXX")"; mkdir -p "$g/config"
  ( cd "$1" && env -u BIONIC_GATE_AGENT -u BIONIC_GATE_ADMIT BIONIC_GATE_DIR="$g/store" CLAUDE_CONFIG_DIR="$g/config" \
      CLAUDE_CODE_SESSION_ID="$SID_A" BIONIC_PROBE_CORES=8 BIONIC_PROBE_TOTAL_MB=8192 BIONIC_PROBE_USED_PCT=20 \
      BIONIC_PROBE_FREE_PCT=80 BIONIC_PROBE_FREE_MB=6553 BIONIC_PROBE_BUSY_CORES=0.5 BIONIC_PROBE_BUSY_CORES_5M=0.5 \
      BIONIC_PROBE_LOAD_1M=0.5 BIONIC_PROBE_SWAP_PCT=0 \
      bash -c '. "$1" 2>/dev/null; gate_ask work "$2" --within 2 >/dev/null 2>&1' _ "$RMK_GATE_LIB" "$2" )
  sed -n 's/^who=//p' "$g/store/requests/"[0-9]* 2>/dev/null | head -n 1
}

rmk_repo rmk1 .worktrees/34-T1
expect_eq "RMK.0 control: the recorded tree is marked for the predecessor, the main checkout is not" "w-T1|none" \
  "$(rmk_marker "$RMK_TREE")|$(rmk_marker "$REPO")"
expect_eq "RMK.0b control: before any dispatch a no-name ask from the tree is filed under w-T1" "$SID_A:w-T1" \
  "$(rmk_who "$RMK_TREE" widget.test.sh)"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.1 the row's re-run, w-T1-r1 (bound by its name), is admitted" "allow" "$GATE_VERDICT"
expect_eq "RMK.1b AC-1.1 …and the tree its row recorded now names it, not w-T1" "w-T1-r1" "$(rmk_marker "$RMK_TREE")"
expect_eq "RMK.1c …and the main checkout still has none (RMK.1b is the positive, same reader)" "none" "$(rmk_marker "$REPO")"
expect_empty "RMK.1d …and the allow path says nothing" "$GATE_ERR"
# w-T1-r1 is closed before its successor goes in: a live writer keeps its tree (wave-35 T7, RMK.9 below).
s22_ack "$REPO" "$SID_A" w-T1-r1 2099-01-01T00:00:00Z
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Row: T1
Lands-on: widget')" w-T2)"
expect_eq "RMK.2 a successor named w-T2, bound by Row: T1, is admitted" "allow" "$GATE_VERDICT"
expect_eq "RMK.2b AC-1.1 …and the tree now names w-T2" "w-T2" "$(rmk_marker "$RMK_TREE")"
expect_eq "RMK.2c AC-1.1 …so a no-name ask from the tree files who=…:w-T2, the successor, never w-T1" "$SID_A:w-T2" \
  "$(rmk_who "$RMK_TREE" widget.test.sh)"
expect_eq "RMK.2d …while the same ask from the main checkout files who=…:main (RMK.2c is the positive)" "$SID_A:main" \
  "$(rmk_who "$REPO" widget.test.sh)"

# A ROW WITH NO TREE OF ITS OWN TOUCHES NOTHING: a cell naming the main checkout, a cell naming a tree
# that is gone, and a dispatch that binds no row each leave every marker as it was and are admitted.
rmk_repo rmk3 .
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.3 a row whose cell names the main checkout is admitted" "allow" "$GATE_VERDICT"
expect_eq "RMK.3b …and the main checkout gets no marker" "none" "$(rmk_marker "$REPO")"
expect_eq "RMK.3c …and the linked tree the row does not record keeps w-T1" "w-T1" "$(rmk_marker "$RMK_TREE")"
rmk_repo rmk4 .worktrees/34-gone
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.4 a row whose recorded tree is gone is admitted" "allow" "$GATE_VERDICT"
expect_false "RMK.4b …and nothing is made at the recorded path" test -e "$REPO/.worktrees/34-gone"
expect_eq "RMK.4c …and the tree it does not record keeps w-T1" "w-T1" "$(rmk_marker "$RMK_TREE")"
rmk_repo rmk5 .worktrees/34-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief '')" w-misc)"
expect_eq "RMK.5 a dispatch that binds no row is admitted" "allow" "$GATE_VERDICT"
expect_eq "RMK.5b …and marks nothing (RMK.1b is the positive)" "w-T1" "$(rmk_marker "$RMK_TREE")"
rmk_repo rmk8 .worktrees/34-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" \
  "$(adv_brief 'Scope constraint: read only.' | sed '/^Files:/d; s#^Suites: .*#Suites: none#')" \
  w-T1-r1 claude-sonnet-5 "$S5_LIVE_TRANSCRIPT" bionic:researcher)"
expect_eq "RMK.8 a read-only role bound to T1 by its name is admitted" "allow" "$GATE_VERDICT"
expect_eq "RMK.8b …and is not the tree's writer: the tree keeps w-T1 (RMK.1b is the positive)" "w-T1" "$(rmk_marker "$RMK_TREE")"

# A MARK THAT FAILS IS SAID, NEVER REFUSED: the launch is on the roster already. The tree's git
# directory is made unwritable, so `mark` cannot write the marker.
rmk_repo rmk7 .worktrees/34-T1
RMK_GD="$(git -C "$RMK_TREE" rev-parse --absolute-git-dir)"
chmod 555 "$RMK_GD"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
chmod 755 "$RMK_GD"
expect_eq "RMK.7 a re-dispatch whose tree cannot be re-marked is still admitted" "allow" "$GATE_VERDICT"
expect_contains "RMK.7b …and the wall says the tree still names its last writer" \
  "still names its last writer: spawn-worktree.sh mark --for w-T1-r1 failed" "$GATE_ERR"
expect_eq "RMK.7c …which it does" "w-T1" "$(rmk_marker "$RMK_TREE")"

# A LIVE WRITER KEEPS ITS TREE (wave-35 T7; REQ-5 AC-5.4, D14). Before the launch is written, the wall asks
# who writes the row now (lib/line.sh `line_row_writer`, the landing's own answer) and who the tree's marker
# names; when either is open on this session's roster (`roster_open_names`, acks applied) and is not the
# dispatch's own name, the dispatch is refused naming that writer and its tree, and nothing moves. The tree
# is the one the roster's open writer recorded (`workspace_for_name`) when it has one, else the plan cell.
# FIXTURES: rmk_repo's tree marked w-T1, w-T1 given an open roster row (named by the plan row's agent cell);
# the closed case adds an ack taken after that launch. SYNTHESIZED.
# fails-when: with w-T1 open the dispatch of w-T1-r1 is admitted or the marker reads w-T1-r1; with w-T1
# acked the re-mark does not happen.
rmk_repo rmk9 .worktrees/34-T1
s22_roster_row "$REPO" "$SID_A" w-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.9 AC-5.4 with w-T1 open on the roster, w-T1-r1's dispatch to row T1 is refused" "deny" "$GATE_VERDICT"
expect_contains "RMK.9b …naming the live writer" "row T1 has a live writer w-T1" "$GATE_REASON"
expect_contains "RMK.9c …and the tree it holds" "$RMK_TREE" "$GATE_REASON"
expect_eq "RMK.9d AC-5.4 …and the marker still names w-T1 (RMK.1b is the positive)" "w-T1" "$(rmk_marker "$RMK_TREE")"
expect_eq "RMK.9e …and no launch row of w-T1-r1 was written" "0" \
  "$(/usr/bin/grep -c '|name=w-T1-r1|' "$(roster_path "$REPO" "$SID_A")")"
rmk_repo rmk10 .worktrees/34-T1
s22_roster_row "$REPO" "$SID_A" w-T1
s22_ack "$REPO" "$SID_A" w-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.10 AC-5.4 with w-T1 acked (its row closed), w-T1-r1's dispatch is admitted" "allow" "$GATE_VERDICT"
expect_eq "RMK.10b …and the re-mark proceeds: the tree names w-T1-r1" "w-T1-r1" "$(rmk_marker "$RMK_TREE")"
# THE TREE FROM THE ROSTER: the plan cell names no tree, the open writer's workspace record does. The marker is
# planted as someone else, so the refusal can only have come from the roster's writer, through its record.
rmk_repo rmk11 —
bash "$RMK_SPAWN" mark "$RMK_TREE" --for w-other >/dev/null 2>&1
s22_roster_row "$REPO" "$SID_A" w-T1
RMK_PTREE="$(cd "$RMK_TREE" && pwd -P)"
printf 'workspace/v1|session=%s|name=w-T1|path=%s|branch=HEAD|base=%s|plan=none|at=2026-09-02T00:00:00Z\n' \
  "$SID_A" "$RMK_PTREE" "$(git -C "$REPO" rev-parse HEAD)" >> "$REPO/.bionic/tmp/workspaces-${SID_A}.state"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.11 AC-5.4 a row whose plan cell names no tree is still refused while its writer is open" "deny" "$GATE_VERDICT"
expect_contains "RMK.11b …naming the tree the roster's open writer recorded" "$RMK_PTREE" "$GATE_REASON"
expect_eq "RMK.11c …and that tree keeps its marker" "w-other" "$(rmk_marker "$RMK_TREE")"

# THE MUTATION ARM: the wall's call to `mark` made a no-op. The shipped wall moves the marker (RMK.1b);
# the doctored copy leaves w-T1, so RMK.1b goes red on it.
RMK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/t28-remark.XXXXXX")
RMK_HOOKS=$(s21_plant "$RMK_ROOT")
sed '/spawn-worktree\.sh" mark /s/bash .* 2>&1/true/' "$GATE" > "$RMK_HOOKS/dispatch-preflight.sh"
expect_eq "RMK.6 meta: the shipped wall has the one call, the doctored copy none, and the copy parses" "1|0|parses" \
  "$(/usr/bin/grep -c 'spawn-worktree.sh" mark ' "$GATE")|$(/usr/bin/grep -c 'spawn-worktree.sh" mark ' "$RMK_HOOKS/dispatch-preflight.sh")|$(bash -n "$RMK_HOOKS/dispatch-preflight.sh" && echo parses)"
RMK_SAVED_GATE="$GATE"; GATE="$RMK_HOOKS/dispatch-preflight.sh"
rmk_repo rmk6 .worktrees/34-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(adv_brief 'Lands-on: widget')" w-T1-r1)"
expect_eq "RMK.6b the mutant still runs and admits the dispatch" "allow" "$GATE_VERDICT"
expect_eq "RMK.6c …and with the call made a no-op the tree still names w-T1 (RMK.1b is red on it)" "w-T1" "$(rmk_marker "$RMK_TREE")"
GATE="$RMK_SAVED_GATE"; rm -rf "$RMK_ROOT"

# ============================================================================
section "§OWED-REG2 — the whole-run wall reads an owed floor on the regression-2 road (wave-35 T10; REQ-1 AC-1.3, AC-1.8; T9 concern 1)"
# ============================================================================
# The floor judge (lib/proof.sh, T9) answers `owed<TAB><suites>` when the floor's whole run left suites red and no
# later landing has run them green. The whole-run wall knew `covered` and `uncovered` alone, so an owed floor fell to
# `not checked` and a second whole run was admitted with no approval. An owed floor means the first whole run has
# been run: a second is the user's word (`approve regression-2`), as on the uncovered road, and the refusal names
# the suites still owed, which a fix row runs instead.
# FIXTURE FIDELITY: S28's pf_repo (a real repository on wave/99-test, five suites), its plan carrying one floor proof
# at the working head in proof-add regression's shape with `owed=a.test.sh`; every earlier run the wall counts is one this
# gate journalled.
# fails-when: a second whole run is admitted over an owed floor with no approval; the refusal names no owed suite.
REPO=$(pf_repo rowed)
write_attestation "$REPO" "$SID_A"
OW_H="$(git -C "$REPO" rev-parse HEAD)"
PF_STATE_EXTRA="proved: kind=regression head=$OW_H at=2026-10-12T04:00:00Z evidence=record/w99-floor.txt owed=a.test.sh"
pf_plan "$REPO" "" \
  "$(pf_row T1 4 landed lib/one.sh)" \
  "$(pf_row T12 5 pending .bionic/docs/record/w99-floor.txt verify 'T1')"
PF_STATE_EXTRA=""
expect_eq "OW.0 precondition: proof_state reads the floor owed, naming a.test.sh" "$(printf 'owed\ta.test.sh')" "$(pf_state "$REPO")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w99-T12")"
expect_eq "OW.1 the plan's first whole-run dispatch is ADMITTED on an owed floor (rule 4)" "allow" "$GATE_VERDICT"
expect_status "OW.1b …and journalled" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w-ow-again")"
expect_eq "OW.2 T9 concern 1 a second whole run over an owed floor is REFUSED with no approval (rule 5)" "deny" "$GATE_VERDICT"
expect_contains "OW.2b …the one line says it is a second whole run, naming the approval" "a second whole run on this plan" "$(pf_line)"
expect_contains "OW.2c …the detail names the suite the floor still owes" "a.test.sh" "$GATE_VERR"
expect_absent "OW.2d …and the arm is not left unchecked" "not checked: full-run" "$GATE_ERR$GATE_VERR"
expect_status "OW.2e …and journalled nothing" "1" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
# THE WALL HOLDS THE FLOOR AS THE JUDGE HOLDS IT (wave-35 T31; D20, critic-adversarial finding 8), pinned by what it
# does, never by its sentence (wave-36 T6; D12, AC-6.3; C53): the floor is one whole run, green or red, so over an
# owed floor the fix row the refusal names is admitted, and a second whole run is admitted on the user's word alone.
# fails-when: the owed suite's fix row is refused; the approved second whole run over an owed floor is refused.
OW_FIX_BRIEF='Your task: run the suite the floor still owes green, with its fix.
Expected artifact: .bionic/docs/record/w99-fix.txt
Expected duration: ~20 minutes.
Files: tests/a.test.sh
Suites: tests/a.test.sh
Lands-on: a.test.sh'
PF_STATE_EXTRA="proved: kind=regression head=$OW_H at=2026-10-12T04:00:00Z evidence=record/w99-floor.txt owed=a.test.sh"
pf_plan "$REPO" "" \
  "$(pf_row T1 4 landed lib/one.sh)" \
  "$(pf_row T12 5 active .bionic/docs/record/w99-floor.txt verify 'T1')" \
  "$(pf_row T14 5 pending tests/a.test.sh build 'T12')"
expect_eq "OW.2f precondition: the floor is still read owed, naming a.test.sh" "$(printf 'owed\ta.test.sh')" "$(pf_state "$REPO")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$OW_FIX_BRIEF" "w99-T14")"
expect_eq "OW.2f D20 the fix row the refusal names, the owed suite's, is ADMITTED over the owed floor" "allow" "$GATE_VERDICT"
expect_status "OW.2f …and journalled" "2" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"
PF_STATE_EXTRA="proved: kind=regression head=$OW_H at=2026-10-12T04:00:00Z evidence=record/w99-floor.txt owed=a.test.sh
approved: regression-2 by dana 2026-10-12T05:00:00Z \"yes, run it again\""
pf_plan "$REPO" ""
PF_STATE_EXTRA=""
# The approval is read from the row's reads column, which pf_plan's table does not carry.
{
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | reads | status |\n'
  printf -- '|---|---|---|---|---|---|---|---|---|---|---|\n'
  printf '%s\n' '| T1 | 4 | build | a | implementor | — | 30 | REQ-1 | lib/one.sh |  | landed |' \
    '| T12 | 5 | verify | the regression | test-runner | T1 | 30 | REQ-1 | .bionic/docs/record/w99-floor.txt |  | active |' \
    '| T13 | 5 | verify | the second regression | test-runner | T1 | 30 | REQ-1 | .bionic/docs/record/w99-floor2.txt | approval:regression-2, head | pending |'
} >> "$(pf_plan_path "$REPO")"
expect_eq "OW.2g precondition: the floor is still read owed with the approval written" "$(printf 'owed\ta.test.sh')" "$(pf_state "$REPO")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$PF_FULL_BRIEF" "w99-T13")"
expect_eq "OW.2g D20 …and a second whole run on the user's word is ADMITTED over it: a red floor is the whole run, not a demand for a green one" "allow" "$GATE_VERDICT"
expect_status "OW.2g …and journalled" "3" "$(roster_rows "$(roster_path "$REPO" "$SID_A")")"

# ============================================================================
section "§REMEDY — the full-tree refusal names regression-run, and the line, run as printed, is admitted (wave-35 T10; REQ-1 AC-1.8; D10)"
# ============================================================================
# The budget arm refuses `tests/run.sh` to an agent whose row does not carry run.sh. The whole run has one path a
# runner is given, `session-poker.sh regression-run`, held to the full-run rules; the refusal prints that path as a line of
# its own, never `amend --reexec+ '<cmd>'` (an amend would widen a writer's budget to the whole tree, the run the
# rules hold). A refused suite FILE keeps `--suites+ <suite>`. The printed line, put back through the same wall as
# the same agent, is admitted as typed.
# FIXTURE FIDELITY: a real dispatch through this gate (Suites: tests/a.test.sh), the agent identified by the real
# execution recorder, and every command judged by the real hooks/bash-walls.sh for that agent, in a repository whose
# tests/run.sh takes --only (the door).
# fails-when: the full-tree refusal names --reexec+, or its printed remedy is refused again.
REPO=$(make_repo rremedy yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/tests"
printf '#!/bin/bash\n# takes --only\nexit 0\n' > "$REPO/tests/run.sh"
for s in a b; do printf '#!/bin/bash\nexit 0\n' > "$REPO/tests/$s.test.sh"; done
git -C "$REPO" add tests >/dev/null 2>&1 && git -C "$REPO" commit -qm suites >/dev/null 2>&1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" 'Your task: build it.
Expected artifact: .bionic/docs/record/wrm.md
Expected duration: ~15 minutes.
Files: lib/x.sh
Suites: tests/a.test.sh' "wrm-T1")"
expect_eq "RM.0 precondition: the writer is admitted with a.test.sh as its budget" "allow|a.test.sh" \
  "$GATE_VERDICT|$(roster_field "$(grep -F '|name=wrm-T1|' "$(roster_path "$REPO" "$SID_A")" | tail -1)" suites_allowed)"
RM_ID="awrm-4000000000000001"
printf '{}\n' > "$REPO/rm-transcript.jsonl"
jq -n --arg s "$SID_A" --arg c "$REPO" --arg a "$RM_ID" \
  '{session_id:$s, transcript_path:($c+"/rm-transcript.jsonl"), cwd:$c, agent_id:$a,
    agent_type:"wrm-T1", hook_event_name:"SubagentStart"}' \
  | env CLAUDE_CODE_SESSION_ID="$SID_A" bash "${BIONIC_HOOKS_DIR}/execution-recorder.sh" >/dev/null 2>&1
rm_wall() {  # <command> -> RM_RC, RM_ERR, RM_OUT: the real bash wall's answer for the identified agent
  jq -n --arg s "$SID_A" --arg c "$REPO" --arg m "$1" --arg a "$RM_ID" \
    '{session_id:$s, transcript_path:($c+"/rm-transcript.jsonl"), cwd:$c,
      permission_mode:"bypassPermissions", hook_event_name:"PreToolUse", tool_name:"Bash",
      tool_input:{command:$m}, tool_use_id:"toolu_rm", agent_id:$a, agent_type:"bionic:test-runner"}' \
    | env -u CLAUDE_PROJECT_DIR HOME="$REPO" CLAUDE_CODE_SESSION_ID="$SID_A" \
        bash "${BIONIC_HOOKS_DIR}/bash-walls.sh" > "$SANDBOX/rm.out" 2> "$SANDBOX/rm.err"
  RM_RC=$?; RM_ERR="$(cat "$SANDBOX/rm.err")"; RM_OUT="$(cat "$SANDBOX/rm.out")"
}
rm_wall 'tests/run.sh --only a.test.sh'
expect_eq "RM.1 precondition: the agent's budgeted suite through the door is admitted (the arm reads this agent's row)" "0" "$RM_RC"
rm_wall 'tests/run.sh'
expect_eq "RM.2 the full tree is refused to the writer (rc 2)" "2" "$RM_RC"
expect_contains "RM.2b …by the full-tree arm" "full tree refused" "$RM_ERR"
RM_LINE="$(printf '%s\n' "$RM_ERR" | /usr/bin/grep -E '^    bash .*session-poker\.sh.? regression-run$' | head -n 1 | sed 's/^    //')"
expect_nonempty "RM.3 AC-1.8 the refusal prints the whole run's path as a line of its own: session-poker.sh regression-run" "$RM_LINE"
RM_SCRIPT="$(eval "set -- $RM_LINE"; printf '%s' "${2:-}")"
expect_true "RM.3b …the plugin's own verb, by a path that is this tree's session-poker.sh" test "$RM_SCRIPT" -ef "${BIONIC_HOOKS_DIR}/session-poker.sh"
expect_absent "RM.3c …and never the amend flag for a run, --reexec+" "--reexec+" "$RM_ERR"
rm_wall "$RM_LINE"
expect_eq "RM.4 AC-1.8 the printed remedy, run as printed by the same agent, is admitted (rc 0)" "0" "$RM_RC"
expect_absent "RM.4b …as typed: the wall neither refuses nor rewrites it" "permissionDecision" "$RM_OUT"
expect_absent "RM.4c …and says nothing refused" "refused" "$RM_ERR"
rm_wall 'tests/run.sh --only b.test.sh'
expect_eq "RM.5 a suite FILE off the budget is still refused (rc 2)" "2" "$RM_RC"
expect_contains "RM.5b …and its remedy keeps --suites+ <suite>" "--suites+ b.test.sh" "$RM_ERR"
expect_absent "RM.5c …never the whole run's path" "regression-run" "$RM_ERR"


# ============================================================================
section "§HOLD — a dispatch onto a row a roster holds open is refused, whichever session's roster (wave-35 T28; REQ-5 AC-5.5, D14; A-orch-27)"
# ============================================================================
# T17 (record/wave-35-no-workarounds/two-writers.md, finding 2) drove session B's launch of row T1 while
# w01-T1 was open on session A's roster: the wall admitted it, because the live-writer arm (T7) reads this
# session's roster alone. The arm now reads the set the fill reads, lib/fill.sh `fill_roster_holds`: every
# roster's open names under .bionic/tmp, acks applied, the rows of this plan. A row-bound writer dispatch
# onto a row one of those names holds is refused naming the writer and its session, unless it is this
# session's own name. FIXTURES: make_repo's plan with one pending build row T1 (no agent, no tree); a
# launch row through the one writer (`roster_row_fixture`) on SID_B's or SID_A's roster, identified, row=T1,
# plan= this plan. SYNTHESIZED.
# fails-when: a dispatch onto T1 is admitted while another session's or this session's roster holds T1
# open under another name; the refusal names no writer or no session; an acked hold, or one of another
# plan, still refuses; an unreadable roster refuses or goes unsaid.
hdw_repo() {  # <tag> -> REPO, HDW_PLAN (physical); row T1 pending, no agent, no tree
  REPO=$(make_repo "$1" yes); write_attestation "$REPO" "$SID_A"; write_attestation "$REPO" "$SID_B"
  printf '\n## Tasks\n\n| id | step | kind | task | agent | deps | size | serves | Files | worktree | base | status | reads |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| T1 | 4 | build | the widget | — | — | 30 | REQ-1 | a.sh | — | — | pending | — |\n' \
    >> "$REPO/.bionic/docs/plans/epic-99-test/wave-01-test.plan.md"
  HDW_PLAN="$(cd "$REPO/.bionic/docs/plans/epic-99-test" && pwd -P)/wave-01-test.plan.md"
}
hdw_hold() {  # <repo> <sid> <name> [<plan= value>] — an open launch row of <name> on row T1
  local f; f="$(roster_path "$1" "$2")"; mkdir -p "${f%/*}"
  roster_row_fixture status=identified "session=$2" "name=$3" "agent_id=a-$3" launched_at=2026-09-02T00:00:00Z \
    subagent_type=implementor "plan=${4:-$HDW_PLAN}" row=T1 >> "$f"
}
HDW_BRIEF="$(adv_brief 'Row: T1
Lands-on: widget')"

hdw_repo hdw1
hdw_hold "$REPO" "$SID_B" w-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
expect_eq "HDW.1 AC-5.5 with w-T1 open on session B's roster, session A's dispatch onto row T1 is refused" "deny" "$GATE_VERDICT"
expect_contains "HDW.1b …naming the writer" "row T1 has a live writer w-T1" "$GATE_REASON"
expect_contains "HDW.1c …and its session" "session ${SID_B:0:8}" "$GATE_REASON"
expect_eq "HDW.1d …and no launch row of w-T1-r1 was written" "0" \
  "$(cat "$(roster_path "$REPO" "$SID_A")" 2>/dev/null | /usr/bin/grep -c '|name=w-T1-r1|')"

hdw_repo hdw2
hdw_hold "$REPO" "$SID_B" w-T1
s22_ack "$REPO" "$SID_B" w-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
expect_eq "HDW.2 with w-T1 acked on session B's ledger after its launch, the same dispatch is admitted" "allow" "$GATE_VERDICT"

hdw_repo hdw3
hdw_hold "$REPO" "$SID_B" w-T1 "$SANDBOX/elsewhere/.bionic/docs/plans/epic-98-x/wave-01-x.plan.md"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
expect_eq "HDW.3 a row open on session B's roster under ANOTHER plan holds nothing here: admitted" "allow" "$GATE_VERDICT"

# T17 FINDING 3, PINNED: the same session dispatching the row again under another name while its first
# writer is open. The plan row names no writer and no tree, so T7's reads (`line_row_writer`, the marker)
# have nothing to go on; the roster's row=T1 does.
hdw_repo hdw4
hdw_hold "$REPO" "$SID_A" w-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-again)"
expect_eq "HDW.4 AC-5.5 with w-T1 open on this session's roster, a second dispatch of row T1 as w-T1-again is refused" "deny" "$GATE_VERDICT"
expect_contains "HDW.4b …naming the writer" "row T1 has a live writer w-T1" "$GATE_REASON"
expect_contains "HDW.4c …and the session, its own" "session ${SID_A:0:8}" "$GATE_REASON"

# T17 case 2: session B launching the row under session A's own name. Names are per session; the
# writer is not B's.
hdw_repo hdw5
hdw_hold "$REPO" "$SID_A" w-T1
run_gate "$(mk_agent_payload "$SID_B" "$REPO" "$HDW_BRIEF" w-T1)"
expect_eq "HDW.5 AC-5.5 session B dispatching row T1 under A's open name w-T1 is refused" "deny" "$GATE_VERDICT"
expect_contains "HDW.5b …naming A's writer and A's session" "row T1 has a live writer w-T1 (session ${SID_A:0:8})" "$GATE_REASON"

# A ROSTER THE SESSION CANNOT READ HOLDS NOTHING, and is said; never fatal.
hdw_repo hdw6
hdw_hold "$REPO" "$SID_B" w-T1
chmod 000 "$(roster_path "$REPO" "$SID_B")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
chmod 644 "$(roster_path "$REPO" "$SID_B")"
expect_eq "HDW.6 an unreadable roster on session B holds nothing: the dispatch is admitted" "allow" "$GATE_VERDICT"
expect_contains "HDW.6b …and the wall says the roster cannot be read" "roster-${SID_B}.state cannot be read" "$GATE_ERR"

# ONE CLOSURE RULE (wave-36 T10; REQ-4 AC-4.4, D10). The hold applied acks but not adopt's closure, so a row
# held by a session that is gone and whose files the sweep already takes was refused with a remedy, "adopt, then
# acked", that loops: adopt counts that row closed and never offers it (research C15). Both now ask lib/fill.sh
# `roster_row_open`: a dead session's row whose files are sweepable is closed. A dead session is one the roster
# names whose pid is not live (patrol_live_session_ids reads <claude home>/sessions/*.json); sweepable is the
# sweep's own window, every state file of that session older than the poker interval. FIXTURES: hdw_repo's T1
# held on session B's roster; `hdw_age` dates every one of B's files under .bionic/tmp to 2026-01-01;
# `hdw_live` writes a sessions file naming B with this shell's pid, so B is live.
# fails-when: a dead sweepable session's row still refuses the dispatch; a live session's row, however old its
# files, is admitted; a dead session's young row is admitted, or refused with a remedy that names no sweep;
# adopt and the wall answer the same fixture differently.
hdw_age() {  # <repo> <sid> — every state file of <sid> under .bionic/tmp dated 2026-01-01
  find "$1/.bionic/tmp" -name "*$2*" -exec touch -t 202601010000 {} + 2>/dev/null
}
HDW_SESSIONS="$PROBE_ENV_HOME/.claude/sessions"
hdw_live() {  # <sid> <repo> — a sessions file naming <sid> with a live pid (this shell's)
  mkdir -p "$HDW_SESSIONS"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s"}\n' "$$" "$1" "$2" > "$HDW_SESSIONS/hdw-live.json"
}
hdw_unlive() { rm -f "$HDW_SESSIONS/hdw-live.json"; }

hdw_repo hdw7
hdw_hold "$REPO" "$SID_B" w-T1
hdw_age "$REPO" "$SID_B"
expect_eq "HDW.7-0 the fixture: every file of session B is dated 2026-01-01" "0" \
  "$(find "$REPO/.bionic/tmp" -name "*$SID_B*" -newermt 2026-01-02 2>/dev/null | /usr/bin/grep -c .)"
expect_true "HDW.7-0b …and session B's roster is one of them" test -f "$(roster_path "$REPO" "$SID_B")"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
expect_eq "HDW.7 AC-4.4 w-T1 open on session B's roster, B dead and its files sweepable: the dispatch onto T1 is admitted" \
  "allow" "$GATE_VERDICT"
expect_eq "HDW.7b …and the launch row of w-T1-r1 is written" "1" \
  "$(cat "$(roster_path "$REPO" "$SID_A")" 2>/dev/null | /usr/bin/grep -c '|name=w-T1-r1|')"
HDW7_ADOPT="$(cd "$REPO" && env CLAUDE_CODE_SESSION_ID="$SID_A" CLAUDE_CONFIG_DIR="$PROBE_ENV_HOME/.claude" HOME="$PROBE_ENV_HOME" \
  bash "$BIONIC_HOOKS_DIR/session-poker.sh" adopt --report-only 2>&1)"
expect_contains "HDW.7c the same fixture asked of adopt: the row is closed there too (one rule, two callers)" \
  "1 row(s) skipped" "$HDW7_ADOPT"

hdw_repo hdw8
hdw_hold "$REPO" "$SID_B" w-T1
hdw_age "$REPO" "$SID_B"
hdw_live "$SID_B" "$REPO"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
hdw_unlive
expect_eq "HDW.8 the same old files, session B live: the row is still B's, refused" "deny" "$GATE_VERDICT"
expect_contains "HDW.8b …naming the writer and B's session" "row T1 has a live writer w-T1 (session ${SID_B:0:8})" "$GATE_REASON"

hdw_repo hdw9
hdw_hold "$REPO" "$SID_B" w-T1
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$HDW_BRIEF" w-T1-r1)"
expect_eq "HDW.9 session B dead, its files inside the poker interval: not yet sweepable, refused" "deny" "$GATE_VERDICT"
expect_contains "HDW.9b AC-4.4 …and the remedy names sweep" "session-poker.sh sweep" "$GATE_REASON"

# ============================================================================
section "§FILES — a template's rendered outputs join the row's Files, and the wall prints them (wave-36 T6; D12, AC-6.3; C68)"
# ============================================================================
# A row whose Files name a template under agents-src/ edits what render.sh rewrites: the template's own output
# and the checksum manifest. Nothing carried that relation, so a writer was refused at its stop for the file its
# own render wrote. The wall reads the unit table (RENDER_UNITS) and the manifest path (MANIFEST_REL) from the
# project's agents-src/render.sh, adds each named template's output and the manifest to the Files the row is
# recorded with, and prints each on the model's channel. A unit is matched by the template's own directory, so a
# steps template renders under skills/canonical-sdlc/steps, never one level up.
# FIXTURE FIDELITY: the shipped agents-src/render.sh, copied into a real fixture repository; the row read back from
# the roster this gate wrote; the advisory read from stdout as the harness reads it.
# fails-when: a template's output or the manifest is missing from files=; the wall prints neither; a steps
# template renders into the wrong unit; a twin already in Files is added twice; a Files line with no template
# gains anything.
tw_brief() {  # <Files value> -> adv_brief's contract with that Files: line
  adv_brief 'Scope constraint: the files below.' | sed "s|^Files: payload/scripts/lib/widget.sh\$|Files: $1|"
}
tw_files() {  # <repo> <n> -> files= of the roster's nth row
  roster_field "$(roster_nth_row "$(roster_path "$1" "$SID_A")" "$2")" files
}
tw_has() {  # <files value> <path> -> how many of the value's comma-joined items are exactly <path>
  printf '%s\n' "$1" | tr ',' '\n' | /usr/bin/grep -cxF -- "$2"
}
REPO=$(make_repo twins yes)
write_attestation "$REPO" "$SID_A"
mkdir -p "$REPO/agents-src"; cp "$BIONIC_SCRIPTS_DIR/agents-src/render.sh" "$REPO/agents-src/render.sh"
expect_contains "TW.0 precondition: the fixture carries the shipped render.sh and its unit table" \
  "agents-src/templates/skills/canonical-sdlc/steps|skills/canonical-sdlc/steps" "$(cat "$REPO/agents-src/render.sh")"
TW_B1="$(tw_brief 'agents-src/templates/implementor.md.tmpl, payload/scripts/lib/widget.sh')"
expect_contains "TW.0 precondition: the brief declares the template" \
  "Files: agents-src/templates/implementor.md.tmpl, payload/scripts/lib/widget.sh" "$TW_B1"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$TW_B1" "w99-tw1")"
expect_eq "TW.1 a brief naming a template is admitted" "allow" "$GATE_VERDICT"
TW_F1="$(tw_files "$REPO" 1)"
expect_eq "TW.1 the template stays in the row's Files" "1" "$(tw_has "$TW_F1" agents-src/templates/implementor.md.tmpl)"
expect_eq "TW.1 …and its rendered output joins them" "1" "$(tw_has "$TW_F1" agents/implementor.md)"
expect_eq "TW.1 …and so does the manifest render.sh rewrites" "1" "$(tw_has "$TW_F1" payload/integrity/rendered.sha256)"
expect_eq "TW.1 …and the declared file is kept" "1" "$(tw_has "$TW_F1" payload/scripts/lib/widget.sh)"
TW_CTX1="$(adv_ctx)"
expect_contains "TW.2 the wall prints the output it added, beside its template" \
  "agents-src/templates/implementor.md.tmpl renders agents/implementor.md" "$TW_CTX1"
expect_contains "TW.2 …and the manifest" "payload/integrity/rendered.sha256" "$TW_CTX1"
# A steps template is matched by its own directory, the deeper unit.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(tw_brief 'agents-src/templates/skills/canonical-sdlc/steps/4.md.tmpl')" "w99-tw3")"
expect_eq "TW.3 a brief naming a steps template is admitted" "allow" "$GATE_VERDICT"
TW_F3="$(tw_files "$REPO" 2)"
expect_eq "TW.3 its output is under skills/canonical-sdlc/steps" "1" "$(tw_has "$TW_F3" skills/canonical-sdlc/steps/4.md)"
expect_eq "TW.3 …and not one level up, in the skill's own unit (one rendered path, the manifest beside it)" \
  "agents-src/templates/skills/canonical-sdlc/steps/4.md.tmpl,skills/canonical-sdlc/steps/4.md,payload/integrity/rendered.sha256" "$TW_F3"
# A twin already declared is not added twice.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(tw_brief 'agents-src/templates/critic.md.tmpl, agents/critic.md')" "w99-tw4")"
expect_eq "TW.4 a brief naming a template and its output is admitted" "allow" "$GATE_VERDICT"
TW_F4="$(tw_files "$REPO" 3)"
expect_eq "TW.4 the declared output is in the row's Files once, not twice" "1" "$(tw_has "$TW_F4" agents/critic.md)"
expect_eq "TW.4 …and the manifest is still added" "1" "$(tw_has "$TW_F4" payload/integrity/rendered.sha256)"
# A Files line with no template gains nothing, in the same repository.
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(tw_brief 'payload/scripts/lib/widget.sh')" "w99-tw5")"
expect_eq "TW.5 a brief naming no template is admitted" "allow" "$GATE_VERDICT"
expect_eq "TW.5 …and its row's Files are what it declared" "payload/scripts/lib/widget.sh" "$(tw_files "$REPO" 4)"
expect_absent "TW.5 …and the wall prints no rendered output" " renders " "$(adv_ctx)"
# A project with no agents-src/render.sh has no units: a .md.tmpl there is a file like any other.
REPO=$(make_repo twnone yes)
write_attestation "$REPO" "$SID_A"
run_gate "$(mk_agent_payload "$SID_A" "$REPO" "$(tw_brief 'agents-src/templates/implementor.md.tmpl')" "w99-tw6")"
expect_eq "TW.6 with no render.sh the brief is admitted" "allow" "$GATE_VERDICT"
expect_eq "TW.6 …and its row's Files are what it declared" "agents-src/templates/implementor.md.tmpl" "$(tw_files "$REPO" 1)"

finish
