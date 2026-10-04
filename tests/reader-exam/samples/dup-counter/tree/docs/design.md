# Design — run stamps

A run of a suite leaves one line behind in the checkout's git directory, so the landing step
can later ask what ran at the head it is about to land.

## Ownership

| concept | owner |
|---|---|
| the commit a checkout has out | lib/tree.sh `tree_head` |
| how many paths a checkout differs from its head by | lib/tree.sh `tree_dirty_count` |
| whether a checkout may land | lib/land.sh `land_refusal` |
| writing a run's stamp line | bin/stamp.sh |
