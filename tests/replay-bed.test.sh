#!/bin/bash
# tests/replay-bed.test.sh — the replay bed: closed runs replayed from tracked, scrubbed copies.
#
# The bed reads tests/fixtures/replay alone: version-14 copies of two closed runs and of one cut mid-run, and
# one expected key=value file per release card with the facts the record lost listed in `gaps`.
#
#   §TRACKED  every fixture is a tracked file, neither the bed nor the scrub names the project's own record
#             store, and the private-name scan passes over the fixtures.
#
# FIXTURE FIDELITY. The fixtures are real files; the scan runs over a scratch repository that holds only them.

set -uo pipefail
. "$(dirname "$0")/lib/resolve-roots.sh"
. "$(dirname "$0")/lib/assert.sh"
R="$BIONIC_SCRIPTS_DIR"; F=tests/fixtures/replay; GIT="git -C $R"
B='\.bio''nic/'

section "TRACKED"
for d in wave-46-asks-nothing wave-49-what-a-run-costs wave-49-mid; do
  expect_eq "$d: its plan and its landing record are tracked" "1 1" \
    "$($GIT ls-files "$F/$d" | grep -c '\.plan\.md$') $($GIT ls-files "$F/$d" | grep -c '/landing-proofs\.log$')"
done
expect_eq "one expected file per release card and the gaps list are tracked" "4 1" \
  "$($GIT ls-files "$F" | grep -c '/release-approval-\(93683c5e\|31da41f7\|fcbb975f\|f87acbfc\)\.facts$') $($GIT ls-files "$F/gaps" | wc -l | tr -d ' ')"
expect_eq "four card files, every expected line key=value, none empty" "4 0 0" \
  "$(ls "$R/$F"/release-approval-*.facts | wc -l | tr -d ' ') $(cat "$R/$F"/*.facts | grep -vc '^[A-Za-z][A-Za-z0-9.:_-]*=') $(find "$R/$F" -name '*.facts' -size 0 | wc -l | tr -d ' ')"
expect_true "the scrub is a tracked file" $GIT ls-files --error-unmatch tests/lib/replay-scrub.sh
expect_empty "no fixture file is untracked" "$($GIT ls-files --others "$F")"
expect_empty "neither the bed nor the scrub names the project's own record store" \
  "$(grep -n "$B" "$R/tests/replay-bed.test.sh" "$R/tests/lib/replay-scrub.sh" | grep -v 'config\.yaml')"
L="${BIONIC_NAME_LIST:-$(sed -n 's/^release-check:[[:space:]]*//p' "$R/.bionic/config.yaml" 2>/dev/null | awk '{print $NF}')}"
if [ -r "$L" ]; then
  S="$(mktemp -d)"; cp -R "$R/$F" "$S/"
  ( cd "$S" && export GIT_CONFIG_GLOBAL=/dev/null && git init -q && git add -A \
    && git -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixtures \
    && bash "$R/tests/lib/name-scan.sh" "$L" >"$S/scan.out" 2>&1 ); rc=$?
  expect_status "the private-name scan passes over every fixture" 0 "$rc"
  [ "$rc" -eq 0 ] || cat "$S/scan.out"
else
  advise "the private-name scan" "no list is readable here, so the release check alone admits the fixtures" false
fi

finish
