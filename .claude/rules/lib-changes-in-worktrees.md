---
paths:
  - "payload/scripts/lib/*.sh"
  - "hooks/*.sh"
---

# A copied-hook test sees library changes only after landing

**The rule.** A writer working in a spawned worktree must expect any test that COPIES a hook
outside the repo to resolve that hook's libraries against the MAIN checkout, not against the
worktree — so a new or changed `payload/scripts/lib/*.sh` is invisible to that test until the
branch lands. Design the change so the copied file carries what it needs, or accept the red and
say so in the report; never conclude the library edit is broken.

**What produced it.** Wave-01 verification-cannot-lie, slice S15 (plan A-14; slice report at
`.bionic/docs/record/wave-verification-cannot-lie/s15-report.md:13-45`). S15 needed one shared
`landing-swept/v1` writer called from two hooks and built it three ways:

1. A new file `payload/scripts/lib/swept-marker.sh`, sourced by both hooks via a new
   `BIONIC_LIB_WANT` entry. Syntactically clean, and it broke
   `tests/landing-gate.test.sh`'s `15h-mut` at 123/124. That test copies `hooks/landing-gate.sh`
   into a scratch directory outside the repo and runs it standalone. The loader's fallback chain
   resolves a copied hook's libraries through `~/.claude/plugins/known_marketplaces.json`'s
   directory-source path (`payload/scripts/lib/loader.sh:100-101`) — on this machine the main
   checkout, not the worktree — and that checkout does not have the uncommitted new file.
   `BIONIC_LIB_WANT` requires every named basename from ONE candidate directory, so the new
   required basename made every candidate fail and `loader_fail_open`
   (`payload/scripts/lib/loader.sh:131`) fired: the copied hook wrote nothing.
2. The writer moved into `payload/scripts/lib/run.sh`, a file already in both hooks'
   `BIONIC_LIB_WANT`. Same failure, 123/124. **The fallback resolves to the main checkout's copy of
   the lib file regardless of which basename is missing** — so ANY behaviour change to ANY sourced
   lib file breaks a copied-hook test the same way, mid-wave, whichever file it lives in.
3. What shipped: the writer function lives directly inside `hooks/landing-gate.sh`, self-contained,
   so a copy of the file carries the function with it. The second hook needs only the
   `SWEPT_SCHEMA="landing-swept/v1"` constant, which each hook now carries
   (`hooks/landing-gate.sh:164`, `hooks/session-poker.sh:313`) and which is byte-pinned to agree in
   `tests/cross-gate-agreement.test.sh` §S15b — the same duplicated-but-pinned shape
   `payload/scripts/lib/loader.sh`'s own block already uses, for the identical reason: two hook
   processes have no shared memory to source an in-process value from.

**How to tell this apart from a real bug.** The signature is a copied-hook test failing while the
library edit is correct in the tree, and the hook writing nothing rather than writing something
wrong — a fail-open, not a wrong value. Confirm by checking whether the main checkout has the file
or the function yet; a `git log` on the branch is not the answer, a look at the main checkout is.

**It does not fire on every fixture.** S13's own dogfood run recorded that A-14 "did not bite" —
its copied-hook fixtures resolve libraries against the worktree. The trap is specific to a fixture
that copies the hook OUTSIDE the repo, where the loader falls through to the marketplace's
directory-source path. Check which shape the failing fixture uses before concluding anything.

**Two ways out, both legitimate.** Keep the change inside the hook file so a copy carries it (what
S15 did), or accept the mid-wave red on the copied-hook test and record it in the slice report,
knowing it clears at Step 8 when the main checkout catches up
(`.bionic/docs/record/wave-verification-cannot-lie/s15-report.md:54-59`). Choosing the second
without recording it is the failure — the next reader sees an unexplained red.
