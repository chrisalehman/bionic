#!/bin/bash
# Fixture test that is RED before any mutation. An already-failing test cannot
# be shown to discriminate — "red under mutation" would be indistinguishable
# from "red always" — so the harness must report the baseline, not a verdict.
echo "FAIL: intentionally red baseline"
exit 1
