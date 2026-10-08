# trellis

Every suite run goes through `bin/run-suite.sh`, which leaves one stamp line per run in the
checkout's git directory (`trellis-stamps`). The landing check refuses a branch whose suite
runs at its head did not pass. What a release changed, and what it still cannot do, is in
`docs/CHANGELOG.md`.
