---
governing-skill: agent-skills:documentation-and-adrs
sdlc-step: 2
epic: epic-23-bionic-tech-debt
wave: wave-53-one-home
intent: build
rigor: double
scale: wave
canonical_sdlc_version: 15
surface_type: cli-plugin
language: bash
has_ui: false
multi_agent: true
deploy_target: n/a
cleanup_on_finish: true
use_worktree: false
walk: required
design-interview: true
model_plan: orchestrator=claude-fable-5-2; implementor=sonnet-high; senior-implementor=opus-high; researcher=opus-high; test-runner=haiku-high; auditor=opus-high; critic=opus-high
status: Proposed (Step 7, 2026-11-27)
created: 2026-11-22
---
# ADR-087 — One home, and the check that guards it

## Status

**Proposed** (Step 7, 2026-11-27). Drafted with the spec of wave 53 on 2026-11-22, before the build. Checked here against the settled head of the run, `5074682017bb`, its two reviews and the sum of its prune. The copy check's shapes and the size ruling were trued at `24ce9a53`, after the fix rows.

## Context

The tool's shell code said many things in more than one place. The register of debts held 30 such concepts when 2.2.0 closed. A survey found 24 more that nobody had registered. In 2.2.0 the copies made real defects. Three sums of the same libraries disagreed, and a cache served one copy's facts to another. Two answers to "does this row have a writer" let a close write over what a writer left.

The person ruled D2 on 2026-11-22, "D2: 2": the prune covers everything found.

Nothing stopped a copy from coming back. The check that counts second readers and second writers ran in one test suite, and at a landing only one of its seven counts could refuse.

## Decision

Each of the 54 concepts has one home, named in the spec's ownership table, and a landing that adds a copy is refused.

- A concept is merged at every site that holds the copy. The register's line numbers are not the list: a row finds its sites by what the copy does.
- The first home built is one function of the library loader, `bionic_need <lib> <marker>`, which loads a library once. Most other homes are reached through it, so it landed alone, before the rest.
- A pair that cannot be one place, such as a page against code, two pages, or a merge that would move a print, is held equal by a test that reads both sides.
- A copy that must stay is kept by name in one list the check reads, `KEPT_COPIES` in `payload/scripts/one-reader-check.sh`, each entry for a stated reason. An entry that matches no line is a finding, so the list cannot outlive its copy. Where a kept copy has an original to match, a test holds the two equal.
- The check, `payload/scripts/one-reader-check.sh`, has twelve counts, and each refuses. It refuses in two places. The landing's lint runs it over the files a row changed and names the line and the home it should use. The release check runs it over the whole tree at the head. A count was turned on only once the tree read zero for it.
- Each prune row measures the code before and after itself, by the release check's own count (`tests/lib/release-check.sh --count <rev>`).

## Consequences

- A change to a rule, a key or a read is made in one place.
- A hook that fails closed, or that a test copies alone, now loads a library it did not load. The homes record named twenty-one homes with such a constraint, each with a second choice.
- A row whose home is a new library function a hook calls reads red in the suites that copy that hook alone, until their fixtures carry the loader too. On this run two fixtures were changed for it.
- The check costs one read of the tree at every landing, about 9 s on a loaded machine.
- A writer that adds a hand-written copy of a counted idiom is turned back at its landing, with the home named.

## What the build taught

- **The target was met by one sweep, and the tree grew.** The 32 prune rows removed 27,074 non-whitespace characters of code, against a target of 25,000. Of that, 24,921 came from the loader's sweep. The other 26 rows together removed 2,153, and four of the seven families added code, because a new home, its header and the reasons beside it cost more than the copies they replaced. Over the release the code grew by 38,526 characters and the tests by 180,758, at the head before the release entry. The requirement's title says the code is 25,000 characters smaller, while its criterion asks for the prune rows' sum. The audit of the whole holds the sum met and the smaller tree missed. The person waived the smaller tree for this release (D31, 2026-11-27), and the next wave opens with a target on the size of the whole codebase.
- **Twelve counts refuse, and zero was reached three ways.** Some sites were converted by a ruling. Fourteen were kept by name, each with the reason a landed row recorded: an install root's own folder finder, a reader that must tell an empty value from an absent one, or a wall that fails closed and reads the roster's path before it loads the roster library. Most of those fourteen have no original to match, so no test holds them equal; they stand on their reason. And three counts were defined more narrowly. A field reader is a key read at a walked field. A load guard counts only when its marker stands before the source. The roster path counts in the shape `tmp/roster-$`. The `homes` count knows five shapes (the roster path, the pinned clock, the preamble's words, the random name and the instant now). With the load guard, the git home and the field reader, the check searches eight of the 54 concepts by shape. The other 46 rest on each prune row's own count at its commit, which nothing at the head repeats. The audit of the whole found one copy that slipped through that way: the close spelt the instant now by hand, in a file that already loads the time library. The close now calls the library's `iso_now`, and the instant is the fifth shape, so that copy is held. A copy of any other unsearched home, such as the clock read without the pin or the English list, passes the check too.
- **Some copies were kept on purpose and are not on the list.** The clock has one home, four functions in `payload/scripts/lib/time.sh`. Three `now_epoch` copies and several inline `date +%s` reads stay, because the library's clock follows a pinned test clock and these reads must not. No count reads them. The field cleaner's two copies in the poker and the sweeper stay apart from the library's, which drops what follows a byte that is not valid UTF-8. Three whole-function copies (the skill-name test two hooks carry, the session start's kill-tree pair and a third link-target finder) are held equal by tests, and the check counts no whole-function copy. So the design's rule that every kept copy is on the one list the check reads does not hold for these three. A test holds each, which the requirement accepts.
- **One home moved from the table.** The decision key's home is the plan reader's library, not the owed library the table named. The owed library already loads the reader, and the reverse would pull four libraries into every plan reader, at the cost of one `awk` start a call.
- **The prune made three new debts, and the structure review registered them.** A second shell field reader, `line_field`, stands beside `line_value` in `payload/scripts/lib/fields.sh`, and the two read differently. The check names `line_value` as the home while the library's header names `line_field`, and no test holds them equal. And the English list's home, `payload/scripts/lib/english.sh`, stands beside one inline copy in `hooks/poker/plan.sh`. The register's 54 earlier lines are burned, and these three stand.
- **The tests reached their cap.** The release check bounds the tests' size against the code's. The tests grew with every family, since each row added agreement checks, plants and mutants. The cap was met by deleting 442 comment lines that held only a drawn rule from 21 test files, 45,887 characters, each file parsing to the same code before and after. No check was removed.
- **This run's own landings were judged by the 2.2.0 release check,** as its plan set, so the tree-wide refusal judges landings from the next release on. Inside the run a new copy was turned back by the lint over a row's changed files, once the counts were turned on.

## Alternatives rejected

- The register only: it holds what reviewers happened to raise, about a quarter of the copies by size.
- The copies that can cause a defect only: the guard against regrowth is simple only at zero, and anything left needs a list of exceptions longer than the kept list.
- A guard held by a test suite alone, as before: a row meets it only if its landing names that suite, or at a whole run.
- A per-process counter for unique names: under bash 3.2 a counter is copied into each child, so siblings collide as they do on `$RANDOM`. A name the tool makes comes from `bionic_new` or `bionic_id` instead.
