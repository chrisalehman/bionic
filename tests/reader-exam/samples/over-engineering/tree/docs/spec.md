# Spec — task branch names

## Requirements

**REQ-1.** A task's branch name is derived from its id and title, so everyone who names a
task's branch names it the same way.

- **AC-1.1.** `bin/branch-name.sh T7 'Fix the Stamp reader'` prints `wt/T7-fix-the-stamp-reader`:
  `wt/`, the id, a dash, and the title's slug. Fails when: the printed name's slug differs
  from `slug_of` of the title.
- **AC-1.2.** An id not shaped `T<n>`, or a title with no letter or digit, is refused: exit 2
  and nothing on stdout. Fails when: a refused input prints a name.

## Design

- **D1.** `bin/branch-name.sh` checks the id, takes the slug from `slug_of`, refuses an empty
  slug, and prints the name. (REQ-1)

| concept | owner |
|---|---|
| the slug of a text | lib/names.sh `slug_of` |
| a task's branch name | bin/branch-name.sh |
