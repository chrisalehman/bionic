#!/bin/bash
# tests/time.test.sh — payload/scripts/lib/time.sh `iso_epoch`, the one reader of an instant.
#
# WHAT THIS SUITE OWNS. An instant is `YYYY-MM-DDTHH:MM:SSZ`, twenty characters, UTC, and nothing else. Three
# readers of it stood: hooks/session-poker.sh `iso_epoch` (BSD `date -j -f`, which reads `…Zx` with a warning,
# then GNU `date -d`, which reads anything), lib/patrol.sh's awk `iso2epoch` (which read a no-Z instant and a
# fractional `.5Z`), and lib/gate.sh's own days-from-civil awk in `_gate_row_done` (which range-checked nothing, so
# month 13 converted). D18 rules strict `…Z`: lib/time.sh owns the grammar and the arithmetic (the patrol's), and
# the three former callers read through it.
#
#   §AGREE   one table of instants, read three ways on each: lib/time.sh `iso_epoch`, the poker's `iso_epoch` (its
#            own definition, lifted from the hook and run over the library the hook loads), and the gate
#            (`_gate_row_done`, over a landing record written by line.sh's `line_event`: the epoch is the last
#            asked= the record's `published` line still finishes after, found by bisection). Each valid instant
#            reads one epoch on all three; each refused one reads nothing on all three.
#   §STAMP   `iso_now`, the clock's instant: one instant, the clock's second, and the clock even with a pin set.
#   §EPOCH   `epoch_iso`, an epoch as an instant: three epochs rendered and read back; a word, a sign, a blank
#            and the empty argument print nothing and exit 1, the word with a file of its name beside it.
#   §PIN     `time_now`, the pinned clock: a numeric pin is read; no pin, an empty one and one that is not a
#            number read the machine's clock.
#   §MTIME   `file_mtime`, a path's modified time: a file and a directory read their epoch, a missing or empty
#            path prints nothing and exits 1, and under a stand-in GNU stat the time comes from `stat -c`.
#
# FIXTURE FIDELITY. The instants are SYNTHESIZED, each valid one's epoch measured with macOS `date -u -j -f
# '%Y-%m-%dT%H:%M:%SZ'` (the poker's former reader). The poker's reader is its own text in the hook, not a copy. The
# gate's record is written by line.sh's real `line_event`, only its clock (`_line_now`) pinned to the instant under
# test. The transcript lines have the shape Claude Code writes (`"timestamp":"…724Z"`, measured on this machine's
# own session transcripts), cut to the fields the patrol's jq reads.
#
# ANTI-VACUITY. Every refused row (an empty reading) sits in the same table as valid rows read through the same
# three extractors, and §AGREE first proves each extractor returns a number on a valid instant. In the four sections
# after it each answer of nothing sits beside an answer of a number read through the same door, `lib_call`, which
# joins the exit code to the output so an absent function reads `|127`, never a pass. The epochs and modified times
# are SYNTHESIZED from §AGREE's measured rows; the stand-in GNU stat answers `-f` with filesystem text, the shape
# GNU's `stat -f` prints.
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
# The gate's record is written by line.sh's own writer, its clock pinned in its text: a variable is shadowed by its locals.
git init -q "$TMP/p" 2>/dev/null
PLAN="$TMP/p/.bionic/docs/plans/epic-x/wave-x.plan.md"
mkdir -p "${PLAN%/*}" && printf '# plan\n' > "$PLAN"
REC="$(bash -c '. "$1/line.sh" 2>/dev/null; line_record "$2"' _ "$LIB" "$PLAN" 2>/dev/null)"
expect_regex "AG.0b line.sh names the plan's landing record, the run's log" '/record/[^/]+/run\.log$' "$REC"
via_gate() {
  rm -f "$REC"
  bash -c '. "$1/line.sh" 2>/dev/null; eval "_line_now() { printf \"%s\\n\" $(printf %q "$3"); }"; line_event "$2" published row=T1 commit=c1 kind=queue by=- why=-' \
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
three() { printf '%s|%s|%s' "$(via_lib "$1")" "$(via_poker "$1")" "$(via_gate "$1")"; }

section "§AGREE — one instant, one epoch, on the library and two of its former callers (D18; AC-12.1)"
# Valid instants, each with the epoch `date -u -j -f` gives it on macOS (and :60, Feb 30 normalised as it does).
while IFS='|' read -r id s want why; do
  [ -n "$id" ] || continue
  expect_eq "$id $why: $s reads $want on lib|poker|gate" "$want|$want|$want" "$(three "$s")"
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
  expect_eq "$id $why: '$s' reads nothing on lib|poker|gate" "||" "$(three "$s")"
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
expect_eq "AG.14 the empty string reads nothing on lib|poker|gate" "||" "$(three "")"

# The four answers below are read through one door each: the library sourced in a fresh shell, the function's
# stdout and its exit code joined by a bar, so an answer of nothing is told from an answer that failed. The clock
# readings are bracketed by `date -u +%s` before and after the call, so a clock answer is a number in that span.
lib_call() { bash -c '. "$1/time.sh" 2>/dev/null; shift; o="$("$@")"; r=$?; printf "%s|%s" "$o" "$r"' _ "$LIB" "$@" 2>/dev/null; }
in_span() {  # <before> <reading> <after> -> "clock" when the reading is a number in the span, else the reading
  case "$2" in ''|*[!0-9]*) printf '%s' "$2"; return ;; esac
  if [ "$1" -le "$2" ] && [ "$2" -le "$3" ]; then printf clock; else printf '%s' "$2"; fi
}

section "§STAMP — iso_now is the clock's instant, and never the pinned clock"
b="$(date -u +%s)"; st="$(lib_call iso_now)"; a="$(date -u +%s)"
expect_regex "ST.1 iso_now prints one instant and exits 0" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\|0$' "$st"
expect_eq "ST.2 iso_now's instant is the clock's second" "clock" "$(in_span "$b" "$(via_lib "${st%|*}")" "$a")"
b="$(date -u +%s)"; st="$(BIONIC_NOW_EPOCH=1008 lib_call iso_now)"; a="$(date -u +%s)"
expect_eq "ST.3 with the clock pinned to 1008, iso_now still reads the machine's clock" "clock" "$(in_span "$b" "$(via_lib "${st%|*}")" "$a")"

section "§EPOCH — epoch_iso renders an epoch as an instant, and nothing for what is not a number"
while IFS='|' read -r id e want why; do
  [ -n "$id" ] || continue
  expect_eq "$id $why: epoch_iso $e prints $want" "$want|0" "$(lib_call epoch_iso "$e")"
  expect_eq "$id.r $why: iso_epoch reads $want back as $e" "$e" "$(via_lib "$want")"
done <<'ROWS'
EP.1|1792336053|2026-10-18T15:07:33Z|the research fixture
EP.2|0|1970-01-01T00:00:00Z|the epoch itself
EP.3|951868799|2000-02-29T23:59:59Z|a leap day's last second
ROWS
# BSD `date -r` reads a word as a file's name and prints that file's time, so a word refused must be refused with a
# file of that name in the working directory, where `date` would find it.
mkdir -p "$TMP/cwd" && : > "$TMP/cwd/abc"
while IFS='|' read -r id e why; do
  [ -n "$id" ] || continue
  expect_eq "$id $why: epoch_iso '$e' prints nothing and exits 1" "|1" "$(cd "$TMP/cwd" && lib_call epoch_iso "$e")"
done <<'ROWS'
EP.4||the empty argument
EP.5|abc|a word that names a file in the working directory
EP.6|12x|digits with a letter after them
EP.7|-5|a negative number
EP.8| 12|a leading blank
ROWS
expect_eq "EP.9 epoch_iso with no argument prints nothing and exits 1" "|1" "$(lib_call epoch_iso)"

section "§PIN — time_now is the pinned clock when the pin is a number, else the machine's clock"
expect_eq "PN.1 BIONIC_NOW_EPOCH=1008 reads 1008" "1008|0" "$(BIONIC_NOW_EPOCH=1008 lib_call time_now)"
expect_eq "PN.2 BIONIC_NOW_EPOCH=0 reads 0" "0|0" "$(BIONIC_NOW_EPOCH=0 lib_call time_now)"
b="$(date -u +%s)"; pn="$(lib_call time_now)"; a="$(date -u +%s)"
expect_eq "PN.3 with no pin it reads the machine's clock" "clock|0" "$(in_span "$b" "${pn%|*}" "$a")|${pn##*|}"
while IFS='|' read -r id pin why; do
  [ -n "$id" ] || continue
  b="$(date -u +%s)"; pn="$(BIONIC_NOW_EPOCH="$pin" lib_call time_now)"; a="$(date -u +%s)"
  expect_eq "$id $why: a pin of '$pin' is not read, the machine's clock is" "clock|0" "$(in_span "$b" "${pn%|*}" "$a")|${pn##*|}"
done <<'ROWS'
PN.4||an empty pin
PN.5|abc|a word
PN.6|12x|digits with a letter after them
PN.7|-5|a negative number
ROWS

section "§MTIME — file_mtime is a path's modified time, GNU stat asked first, and nothing for a path it cannot stat"
mkdir -p "$TMP/mt/dir" && : > "$TMP/mt/f"
touch -d 2026-10-18T15:07:33Z "$TMP/mt/f" 2>/dev/null
touch -d 2000-02-29T23:59:59Z "$TMP/mt/dir" 2>/dev/null
expect_eq "MT.1 a file's modified time is its epoch seconds" "1792336053|0" "$(lib_call file_mtime "$TMP/mt/f")"
expect_eq "MT.2 a directory's modified time is its epoch seconds" "951868799|0" "$(lib_call file_mtime "$TMP/mt/dir")"
expect_eq "MT.3 a path that is not there prints nothing and exits 1" "|1" "$(lib_call file_mtime "$TMP/mt/gone")"
expect_eq "MT.4 the empty path prints nothing and exits 1" "|1" "$(lib_call file_mtime "")"
# GNU `stat -f` is the filesystem's status, and prints it with exit 0 whatever the format word, so asking BSD's form
# first on GNU reads filesystem text as a time. A stand-in stat on PATH answers each form as GNU stat does.
mkdir -p "$TMP/gnu"
cat > "$TMP/gnu/stat" <<'GNU'
#!/bin/bash
case "$1" in
  -c) printf '%s\n' 1792336053 ;;
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: apfs\n' "$3" ;;
  *) exit 1 ;;
esac
GNU
chmod +x "$TMP/gnu/stat"
expect_eq "MT.5 under GNU stat the time is read from stat -c, never the filesystem text of stat -f" "1792336053|0" \
  "$(PATH="$TMP/gnu:$PATH" lib_call file_mtime "$TMP/mt/f")"

finish
