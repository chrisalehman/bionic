---
paths:
  - "payload/scripts/lib/*.sh"
  - "hooks/*.sh"
---

# A copied-hook test sees the library its fixture lays beside the copy

**The rule.** A hook finds its library through the eight-line stub under its `BIONIC_LIB_WANT`
line, which looks for `lib/loader.sh` at `../scripts/lib/` and then `../payload/scripts/lib/`,
relative to the hook file. A test that COPIES a hook outside the repo therefore sees exactly the
library its fixture lays beside the copy:

- **No `loader.sh` beside the copy:** the hook finds no loader at all. A fail-open hook steps
  aside and writes nothing; a blocking hook refuses. This is the broken-install shape, not a
  library bug.
- **`loader.sh` beside the copy, a wanted library missing or damaged there:** `bionic_load`
  walks on to the marketplace source tree named in `~/.claude/plugins/known_marketplaces.json`
  and the newest cache version — on this machine the main checkout, not the worktree — so a new
  or changed `payload/scripts/lib/*.sh` is invisible to that test until the branch lands.

Design the fixture to lay the worktree's own `scripts/lib/` beside the copy, keep the change
inside the hook file so a copy carries it, or accept the red and say so in the report; never
conclude the library edit is broken.

**What produced it.** Wave-01 verification-cannot-lie, slice S15 (plan A-14; slice report at
`.bionic/docs/record/wave-verification-cannot-lie/s15-report.md:13-45`). S15 needed one shared
`landing-swept/v1` writer called from two hooks. A new library file, and then the same writer in
an existing one, each broke `tests/landing-gate.test.sh`'s `15h-mut`, which copied the hook into
a scratch directory: the library came from the main checkout, which had neither change. What
shipped was the writer inside `hooks/landing-gate.sh` itself, so a copy carried it.

**How to tell this apart from a real bug.** The signature is a copied-hook test failing while the
library edit is correct in the tree, and the hook writing nothing rather than writing something
wrong — a fail-open, not a wrong value. Check what the fixture lays beside the copy, and whether
the main checkout has the file or the function yet; a `git log` on the branch is not the answer.

**Two ways out, both legitimate.** Make the copy carry what it needs (the hook's own code, or the
worktree's library laid beside it), or accept the mid-wave red on the copied-hook test and record
it, knowing it clears when the main checkout catches up. Choosing the second without recording it
is the failure — the next reader sees an unexplained red.
