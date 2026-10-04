# trellis

Keeps a record of what was proved about a branch and at which commit. Each line of
docs/proofs.txt reads `proved: kind=<kind> head=<sha> at=<ISO-UTC>`. `lib/` reads the
record; `bin/` holds the commands.
