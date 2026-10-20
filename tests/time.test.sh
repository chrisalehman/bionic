#!/bin/bash
# tests/time.test.sh — payload/scripts/lib/time.sh `iso_epoch`, the one reader of an instant (wave-39 T17; D18,
# REQ-12 AC-12.1; burns debt iso-to-epoch).
#
# WHAT THIS SUITE OWNS. An instant is `YYYY-MM-DDTHH:MM:SSZ`, twenty characters, UTC, and nothing else. Three
# readers of it stood: hooks/session-poker.sh `iso_epoch` (BSD `date -j -f`, which reads `…Zx` with a warning,
# then GNU `date -d`, which reads anything), lib/patrol.sh's awk `iso2epoch` (which read a no-Z instant and a
# fractional `.5Z`), and lib/gate.sh's own days-from-civil awk in `_gate_row_done` (which range-checked nothing, so
# month 13 converted). D18 rules strict `…Z`: lib/time.sh owns the grammar and the arithmetic (the patrol's), and
# the three former callers read through it.
#
#   §AGREE   one table of instants, read four ways on each: lib/time.sh `iso_epoch`, the poker's `iso_epoch` (its
#            own definition, lifted from the hook and run over the library the hook loads), the patrol's ledger
#            report (`fill_ledger_report`: the epoch is <now> less the seconds it charges the line), and the gate
#            (`_gate_row_done`, over a landing record written by line.sh's `line_event`: the epoch is the last
#            asked= the record's `published` line still finishes after, found by bisection). Each valid instant
#            reads one epoch on all four; each refused one reads nothing on all four.
#   §TRANSCRIPT  the patrol's verdict reads Claude Code's transcript, whose instants carry milliseconds: a
#            fractional `…33.724Z` there is read to the whole second (the transcript's edge, not the grammar), and
#            a no-Z one is still unreadable.
#
# FIXTURE FIDELITY. The instants are SYNTHESIZED, each valid one's epoch measured with macOS `date -u -j -f
# '%Y-%m-%dT%H:%M:%SZ'` (the poker's former reader). The poker's reader is its own text in the hook, not a copy. The
# gate's record is written by line.sh's real `line_event`, only its clock (`_line_now`) pinned to the instant under
# test. The transcript lines have the shape Claude Code writes (`"timestamp":"…724Z"`, measured on this machine's
# own session transcripts), cut to the fields the patrol's jq reads.
#
# ANTI-VACUITY. Every refused row (an empty reading) sits in the same table as valid rows read through the same
# four extractors, and §AGREE first proves each extractor returns a number on a valid instant.
#
# Usage: bash tests/time.test.sh

set -uo pipefail

. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"

LIB="$BIONIC_SCRIPTS_DIR/payload/scripts/lib"
POKER="$BIONIC_HOOKS_DIR/session-poker.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unset BIONIC_NOW_EPOCH

for f in time.sh patrol.sh gate.sh line.sh; do
  if [ -r "$LIB/$f" ] && bash -n "$LIB/$f" 2>/dev/null; then ok "subject present and parses: lib/$f"
  else no "subject present and parses: lib/$f" "missing or unparseable"; fi
done

# The poker's own definition, lifted as text: from its `iso_epoch()` line to the line that closes it (the same line
# for a one-line body). The hook cannot be sourced, so its definition is run over the library the hook loads first
# (lib/patrol.sh, which brings lib/time.sh).
POKER_ISO="$(awk '
  !f && index($0, "iso_epoch()") == 1 { f = 1; print; l = $0; sub(/[ \t]*#.*$/, "", l); if (l ~ /\}[ \t]*$/) exit; next }
  f { print; if ($0 == "}") exit }' "$POKER")"
expect_regex "AG.0 the poker's iso_epoch definition is lifted from the hook" '^iso_epoch\(\)' "$POKER_ISO"

via_lib() { bash -c '. "$1/time.sh" 2>/dev/null; iso_epoch "$2"' _ "$LIB" "$1" 2>/dev/null; }
via_poker() { bash -c '. "$1/patrol.sh" 2>/dev/null; eval "$2"; iso_epoch "$3"' _ "$LIB" "$POKER_ISO" "$1" 2>/dev/null; }
NOW_FAR=4000000000
via_patrol() {
  printf 'fill-ledger/v1|at=%s|state=ok|ready=T1|missed=1|turn=t1\n' "$1" > "$TMP/fill.log"
  bash -c '. "$1/patrol.sh" 2>/dev/null; fill_ledger_report "$2" s yes "$3"' _ "$LIB" "$TMP/fill.log" "$NOW_FAR" 2>/dev/null \
    | awk -F'|' -v now="$NOW_FAR" 'index($0, "fill-report/v1|") == 1 {
        for (i = 2; i <= NF; i++) { if (index($i, "turns=") == 1) t = substr($i, 7); if (index($i, "missed_s=") == 1) m = substr($i, 10) }
        if (t == 1) printf "%d\n", now - m }'
}
# The gate's record is written by line.sh's own writer, its clock pinned to the instant under test.
git init -q "$TMP/p" 2>/dev/null
PLAN="$TMP/p/.bionic/docs/plans/epic-x/wave-x.plan.md"
mkdir -p "${PLAN%/*}" && printf '# plan\n' > "$PLAN"
REC="$(bash -c '. "$1/line.sh" 2>/dev/null; line_record "$2"' _ "$LIB" "$PLAN" 2>/dev/null)"
expect_regex "AG.0b line.sh names the plan's landing record" '/landing-proofs\.log$' "$REC"
via_gate() {
  rm -f "$REC"
  bash -c '. "$1/line.sh" 2>/dev/null; at="$3"; _line_now() { printf "%s\n" "$at"; }; line_event "$2" published row=T1 commit=c1 kind=queue by=- why=-' \
    _ "$LIB" "$PLAN" "$1" >/dev/null 2>&1
  bash -c '
    . "$1/gate.sh" 2>/dev/null
    done_after() { _G_DONE_FOR=""; _gate_row_done "$2" T1 "$1"; }
    done_after -1 "$2" || exit 0
    lo=-1 hi=$3
    while [ $((hi - lo)) -gt 1 ]; do
      mid=$(( (lo + hi) / 2 ))
      if done_after "$mid" "$2"; then lo=$mid; else hi=$mid; fi
    done
    echo "$hi"' _ "$LIB" "$REC" "$NOW_FAR" 2>/dev/null
}
four() { printf '%s|%s|%s|%s' "$(via_lib "$1")" "$(via_poker "$1")" "$(via_patrol "$1")" "$(via_gate "$1")"; }

section "§AGREE — one instant, one epoch, on the library and its three former callers (D18; AC-12.1)"
# Valid instants, each with the epoch `date -u -j -f` gives it on macOS (and :60, Feb 30 normalised as it does).
while IFS='|' read -r id s want why; do
  [ -n "$id" ] || continue
  expect_eq "$id $why: $s reads $want on lib|poker|patrol|gate" "$want|$want|$want|$want" "$(four "$s")"
done <<'ROWS'
AG.1|2026-10-18T15:07:33Z|1792336053|the research fixture
AG.2|1970-01-01T00:16:48Z|1008|near the epoch, as gate.test.sh's landings are
AG.3|2000-02-29T23:59:59Z|951868799|a leap day's last second
AG.4|2026-10-18T15:07:60Z|1792336080|a leap second, carried into the next minute
AG.5|2026-02-30T00:00:00Z|1772409600|February 30, carried into March as date carries it
ROWS
# Refused instants: nothing on every reader.
while IFS='|' read -r id s why; do
  [ -n "$id" ] || continue
  expect_eq "$id $why: '$s' reads nothing on lib|poker|patrol|gate" "|||" "$(four "$s")"
done <<'ROWS'
AG.6|2026-10-18T15:07:33.5Z|a fractional second
AG.7|2026-10-18T15:07:33|no Z
AG.8|2026-10-18T15:07:33Zx|a character after the Z (BSD date read it with a warning)
AG.9|2026-13-01T00:00:00Z|month 13 (the gate converted it)
AG.10|2026-10-18T24:00:00Z|hour 24
AG.11|2026-10-18 15:07:33Z|a blank for the T
AG.12|2026-10-18T15:07:33+00:00|an offset for the Z
AG.13| 2026-10-18T15:07:33Z|a leading blank
ROWS
expect_eq "AG.14 the empty string reads nothing on lib|poker|patrol|gate" "|||" "$(four "")"

section "§TRANSCRIPT — the patrol reads the transcript's milliseconds to the whole second; the grammar stays strict"
STAMP="$TMP/patrol.stamp"; : > "$STAMP"
TZ=UTC touch -t 202610181506.40 "$STAMP"   # 1792336000
tr_line() { printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n' "$1"; }
verdict() { bash -c '. "$1/patrol.sh" 2>/dev/null; patrol_verdict "$2" "$3" 60' _ "$LIB" "$STAMP" "$1" 2>/dev/null; }
{ tr_line 2026-10-18T15:07:33.724Z; tr_line 2026-10-18T15:17:33.5Z; } > "$TMP/frac.jsonl"
expect_regex "TR.1 two turns at …33.724Z and ten minutes on at …33.5Z: dead, gap 600 s, the stamp the reference" \
  '^verdict=dead\|ref=1792336000\|gap=600\|window=66\|' "$(verdict "$TMP/frac.jsonl")"
{ tr_line 2026-10-18T15:07:33Z; tr_line 2026-10-18T15:17:33Z; } > "$TMP/whole.jsonl"
expect_regex "TR.2 the same turns at whole seconds read alike (gap 600)" \
  '^verdict=dead\|ref=1792336000\|gap=600\|' "$(verdict "$TMP/whole.jsonl")"
{ tr_line 2026-10-18T15:07:33.724Z; tr_line 2026-10-18T15:17:33; } > "$TMP/noz.jsonl"
expect_regex "TR.3 a turn stamped with no Z leaves the window unreadable" \
  '^verdict=unreadable\|.*no readable timestamp' "$(verdict "$TMP/noz.jsonl")"

finish
