#!/bin/bash
. "$(dirname "$0")/lib.sh"
status="$(cd "$(dirname "$0")/.." && pwd)/bin/status.sh"

f="$SCRATCH/proofs.txt"
printf 'proved: kind=floor head=aaa at=2026-01-01T00:00:00Z\nproved: kind=floor head=bbb at=2026-01-02T00:00:00Z\n' > "$f"
check "the newest floor proof's head, and no review" "floor bbb
review none" "$(PROOFS_FILE="$f" bash "$status")"
done_testing
