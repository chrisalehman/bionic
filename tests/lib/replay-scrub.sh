#!/bin/bash
# tests/lib/replay-scrub.sh <docs root> <epic> <wave> <out docs root> [<cut instant> <step>] — one closed run's
# record as a tracked fixture, in a docs tree of its own (plans/<epic>/<wave>.plan.md, record/<wave>/…).
#
# Kept: the plan, the three logs the reader folds, the review files the findings read, each card's Replay
# table, and the test-ratio line of each release check. Dropped: everything no question reads.
# Scrubbed, in one pass so a session id keeps one stand-in across files: the machine's paths, session and turn
# ids (numbered by first appearance), the names of the people who approve, the repository owner and the
# scratchpad. Shas, instants and finding sentences stay, because the answers are built from them.
# A cut instant gives the run as it stood then, at <step>: later log lines go, an ask closed after the cut is
# open again, and so are the plan's later steps, landings and proofs. Only a cut before the first proof is
# valid, because every proof, move, deferral and waiver line is dropped.
# The repository ignores *.log, so a refreshed fixture is added with `git add -f`.
# With BIONIC_NAME_LIST naming the private list, a fixture that holds an entry refuses the refresh.
set -euo pipefail
src=$1 epic=$2 wave=$3 out=$4 cut=${5:-} step=${6:-}
rec=$src/record/$wave plan=$epic/$wave.plan.md o=$out/record/$wave
mkdir -p "$o" "$out/plans/$epic"
# A line with no at= field (the landed:, debt: and void: forms) is timed by the first instant it holds.
at() { awk -v cut="$cut" '{ t = ""; n = split($0, a, "|"); for (i = 1; i <= n; i++) if (a[i] ~ /^at=/) t = substr(a[i], 4)
  if (t == "" && match($0, /20[0-9][0-9]-[0-9-]+T[0-9:]+Z/)) t = substr($0, RSTART, RLENGTH)
  if (cut == "" || t == "" || t <= cut) print }' "$1"; }
for f in landing-proofs.log fill-ledger.log; do at "$rec/$f" > "$o/$f"; done
awk -F'|' -v cut="$cut" '{ delete v; for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = substr($i, length(kv[1]) + 2) }
  if (cut != "" && v["opened"] > cut) next
  if (cut != "" && v["at"] > cut) $0 = "owed/v1|key=" v["key"] "|state=open|at=" v["opened"] "|opened=" v["opened"]
  print }' "$rec/asks.state" > "$o/asks.state"
if [ -z "$cut" ]; then
  for f in "$rec"/critic-*.md "$rec"/auditor-evidence*.md; do [ -f "$f" ] && cp "$f" "$o/"; done
  for f in "$rec"/release-approval-*.md; do sed -n '/^## Replay/,$p' "$f" > "$o/${f##*/}"; done
  for f in "$rec"/release-check-*.log; do grep '^test-ratio:' "$f" > "$o/${f##*/}" || rm -f "$o/${f##*/}"; done
  cp "$src/plans/$plan" "$out/plans/$plan"
else
  # rows landed after the cut, and rows born after it
  late=$(awk -v cut="$cut" 'function t(s) { return match(s, /20[0-9][0-9]-[0-9-]+T[0-9:]+Z/) ? substr(s, RSTART, RLENGTH) : "" }
    /^- T[0-9]+: landed/ { id = $2; sub(/:$/, "", id); if (t($0) > cut) print "L" id
      if (match($0, /added by task-add at /) && t(substr($0, RSTART)) > cut) print "B" id }' "$src/plans/$plan" | tr '\n' ' ')
  awk -v cut="$cut" -v step="$step" -v late=" $late" '
    function t(s) { return match(s, /20[0-9][0-9]-[0-9-]+T[0-9:]+Z/) ? substr(s, RSTART, RLENGTH) : "" }
    /^## SDLC State/ { st = 1 }
    /^## Verification Matrix/ { mx = 1 } /^## (Assumptions|Handoff|SDLC State)/ { mx = 0 }
    /^\| T[0-9]+ \|/ { id = $2; if (index(late, " B" id " ")) next
      if (index(late, " L" id " ")) { n = split($0, c, "|"); c[n - 5] = " pending "; $0 = c[1]; for (i = 2; i <= n; i++) $0 = $0 "|" c[i] } }
    mx && /^(stack-health|walk-artifact):/ { next }
    mx && /^\| AC-/ { n = split($0, c, "|"); c[4] = " pending "; c[5] = c[6] = " — "; $0 = c[1]; for (i = 2; i <= n; i++) $0 = $0 "|" c[i] }
    st && /^current:/ { $0 = "current: " step }
    st && /^- Step [0-9]+:/ { skip = ($3 + 0 > step) }
    st && /^- / && !/^- Step/ { skip = 0 }
    st && /^(proved|moved|deferred|waived):/ { next }
    st && !/^  / && !/^- Step/ && t($0) > cut { skip = 1 }
    st && skip { next }
    { print }' "$src/plans/$plan" > "$out/plans/$plan"
fi
find "$out" -type f | LC_ALL=C sort | ROOT=$(cd "$src/../.." && pwd) xargs perl -e '
  my $who = qr/(?:(?<=by=)|(?<=by )|(?<=via )|(?<=approved-by: ))([A-Z][a-z]+ [A-Z][a-z]+)|\b([A-Z][a-z]+ [A-Z][a-z]+)(?= 20\d\d-)/;
  for my $f (@ARGV) { open my $h, "<", $f or die; local $/; $t{$f} = <$h> }
  for my $f (@ARGV) { while ($t{$f} =~ /$who/g) { $n{$1 // $2} ||= "Person " . chr(64 + keys %n) } }
  for my $f (@ARGV) { local $_ = $t{$f};
    for my $name (sort { length $b <=> length $a } keys %n) {
      my ($first) = split " ", $name; s{\b\Q$name\E\b}{$n{$name}}g; s{\b\Q$first\E\b}{$n{$name}}g }
    s{\Q$ENV{ROOT}\E}{/fixture/project}g; s{/Users/[^/\s"]+}{/fixture/home}g;
    s{/private/tmp/claude-\d+}{/fixture/scratch}g; s{github\.com/[\w.-]+}{github.com/fixture}g;
    s{\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b}{$u{$1} ||= sprintf("00000000-0000-4000-8000-%012d", scalar keys %u)}ge;
    open my $o, ">", $f or die; print $o $_ }'
if [ -n "${BIONIC_NAME_LIST:-}" ] && grep -rqiFf <(grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' "$BIONIC_NAME_LIST") "$out"; then
  echo "replay-scrub: refused — a fixture holds an entry of the private list" >&2; exit 1
fi
