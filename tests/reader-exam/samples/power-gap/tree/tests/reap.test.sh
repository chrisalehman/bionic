#!/bin/bash
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.." || exit 1
. lib/reap.sh

tbl="$SCRATCH/table"
printf 'a 3 0 1\n' > "$tbl"
check "a landed clean checkout idle 3 days is listed" "a" "$(reap_scan "$tbl")"
printf 'b 3 1 1\n' > "$tbl"
check "a dirty landed checkout is not listed" "" "$(reap_scan "$tbl")"
printf 'c 0 0 1\n' > "$tbl"
check "a landed checkout idle less than a day is not listed" "" "$(reap_scan "$tbl")"
printf 'd 5 0 0\n' > "$tbl"
check "a checkout that has not landed is not listed" "" "$(reap_scan "$tbl")"
done_testing
