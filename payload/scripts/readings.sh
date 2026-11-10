#!/bin/bash
# readings.sh — the release's size readings, measured at one revision.
# usage: bash readings.sh <rev> [<record dir>]   run from inside the repository whose revision is read.
#
# Readings 1 to 5 read git objects only, never the working tree, so any two revisions are measured by
# the same lines. Readings 6 to 8 read a run's record: the record is named by the caller, never found
# by default, and the output says which one was read. The plan beside it is `<docs>/plans/*/<wave>.plan.md`
# for a record at `<docs>/record/<wave>`.
#   1  files that parse a plan or a log outside the reader: the one-reader check's own count, taken at
#      this checkout over the revision's hooks and scripts
#   7  born events the reader lists for the run (a run kept in older homes is answered through its translation)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[ -n "${1:-}" ] || { echo "usage: readings.sh <rev> [<record dir>]" >&2; exit 2; }
rev="$1"; rec="${2:-}"
git rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "readings: $rev is not a revision here" >&2; exit 2; }
obj() { git cat-file -p "$rev:$1"; }
paths() { git ls-tree -r "$rev" -- hooks payload tests | awk -F'\t' '$1 !~ /^120000/ {print $2}' | /usr/bin/grep -E "$1"; }
sum() { local n=0 f; while IFS= read -r f; do n=$((n + $(obj "$f" | wc -l))); done; echo "$n"; }
echo "rev=$(git rev-parse --short=9 "$rev")"
# 1. parsers of a run fact outside the reader
tree="$(mktemp -d)"; trap 'rm -rf "$tree"' EXIT
git archive "$rev" hooks payload/scripts | tar -x -C "$tree"
echo "r1_parsers=$(bash "$here/one-reader-check.sh" "$tree" | sed -n 's/^parsers=//p')"
# 2. session-poker top-level verbs: the last `case "$VERB" in` arms, the early-exit case arms, and anchors
v=$(obj hooks/session-poker.sh | awk '
  /^case "\$VERB" in/ { k++; inblk=1; next }
  inblk && /^esac/ { inblk=0 }
  inblk && /^  [a-z|-]+\)/ { s=$0; sub(/^  /,"",s); sub(/\).*/,"",s); n=split(s,a,"|"); for(i=1;i<=n;i++) print k"\t"a[i] }' \
  | awk -F'\t' '{ last[$1]=last[$1] "\n" $2; max=($1>max)?$1:max } END { printf "%s\n%s\nanchors\n", last[max], last[max-1] }' | /usr/bin/grep -v '^$' | sort -u | wc -l | tr -d ' ')
echo "r2_session_poker_verbs=$v"
# 3. registered hook scripts, and how many hold over 30% of their code in-file (code = not comment, not blank;
#    the pasted loader block counts as plumbing, not logic)
over=0; n=0
for f in $(obj hooks/hooks.json | jq -r '[.hooks[][] .hooks[] .command | split(" ")[0] | sub(".*/hooks/";"hooks/")] | unique[]'); do
  n=$((n+1))
  code=$(obj "$f" | awk '!/^[[:space:]]*#/ && !/^[[:space:]]*$/' | wc -l)
  lc=$(obj "$f" | awk '/^# --- bionic-loader\/v2 BEGIN/{p=1} p && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ {c++} /^# --- bionic-loader\/v2 END/{p=0} END{print c+0}')
  [ $(( (code - lc) * 100 )) -gt $(( code * 30 )) ] && over=$((over+1))
done
echo "r3_registered_hook_scripts=$n r3_over_30pct_in_file=$over"
echo "r3_loader_copies=$(git grep -l '^# --- bionic-loader/v2 BEGIN' "$rev" -- 'hooks/*.sh' | wc -l | tr -d ' ')"
# 4. shell outside tests: every .sh under hooks/ and payload/, symlinks not followed
echo "r4_shell_outside_tests_lines=$(paths '^(hooks|payload)/(.*/)?[^/]+\.sh$' | sum)"
# 5. tests: every .sh under tests/
echo "r5_tests_lines=$(paths '^tests/(.*/)?[^/]+\.sh$' | sum)"
if [ -z "$rec" ]; then echo "record=none"; exit 0; fi
rec="$(cd "$rec" 2>/dev/null && pwd -P)" || { echo "readings: $2 is not a record directory" >&2; exit 2; }
echo "record=$rec"
# 6. hand edits: `hand-edit: ` lines in the run's assumptions.md, and the card's hand-holds total
echo "r6_hand_edit_lines=$(/usr/bin/grep -c 'hand-edit: ' "$rec/assumptions.md" 2>/dev/null)"
echo "r6_hand_holds_total_at_close=$(/usr/bin/grep -h -o -E '^hand-holds: total=[0-9]+' "$rec/continuation.md" 2>/dev/null | tail -1 | sed 's/.*=//')"
# 7. born events the reader lists for the run
pl=$(ls "$(dirname "$(dirname "$rec")")"/plans/*/"$(basename "$rec")".plan.md 2>/dev/null | head -1)
echo "r7_born_events=$( [ -n "$pl" ] && ( . "$here/lib/reader.sh" && reader_facts "$pl" ) | /usr/bin/grep -c '^run/v1|ev=born|')"
# 8. whole passes: whole-run logs the record holds
echo "r8_whole_runs=$(ls "$rec" | /usr/bin/grep -c -E '^regression-run-[0-9a-f]+\.log$')"
