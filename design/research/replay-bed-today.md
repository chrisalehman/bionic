---
ticket: chrisalehman/bionic#47 (spike kernel-map-20261026 §6)
kind: research
subject: what the replay bed replays today, and whether a fold over wave 46's record alone can print the release card's hand-holds line
written: 2026-10-26
tree: main @ 050fa567e (the worktree this was read in; tests and drivers cited by path and line there)
record: /Users/admin/workspace/personal/bionic/.bionic/docs/record/wave-46-asks-nothing/ (gitignored; read-only), the plan beside it under .bionic/docs/plans/
method: every suite and driver read whole; the six named suites run serially today and timed; the hand-holds fold run with this tree's code over a scratch copy of the record's files alone (scratch fold.sh, output quoted in §7); absence claims by /usr/bin/grep
---

# What the replay bed replays today

## Summary

The bed is eight gating suites, 2,797 lines, 38 sections (r7-tests.md:276), on three drivers. Six replay a whole
run or its close through the product's own verbs in a throwaway repository (`tests/lib/door.sh` builds it, `tests/lib/rehearsal.sh`
plays it): the four `rehearsal-*` suites each stop at one run state and read the sitrep sheet and card there;
`close-replay` carries the failed-review state through to close-out's `delivered:` and reads the close's own
`hand-holds: total=0` line; `door-card` walks the door fixture by verbs to the release approval card and reads its
replay table. The other two replay a landing (`door-landing`, the hand door and the release check's judge) and an
install (`fresh-home`, setup/doctor/remove on an empty `$HOME`); r7 classed both "replay", but neither reads a run
record. No suite replays a recorded run: every fixture is built from the tree under test at run time, under a
`mktemp -d` outside every checkout (world.sh:43), and is deleted on exit (world.sh:60-65). Nothing the bed reads is a
gitignored copy of a real run; the only gitignored inputs are the real project's `.bionic/` (its record, plan and
config) and the names list outside the repo, which the bed never touches.

What the suites assert is mostly exit codes and record facts, not card text: that a verb exits 0 (or is refused, exit
1 or 2), that the landing record holds a given `ev=` line, that the plan holds a given `proved:`, `approved:` or
`moved:` line, that the asks register holds a key in a state, and counts (how many verbs the log names, how many
reviews the entry lists). Text pins are few and short: the sheet's `ask:` keys, the card's head line, one `hand-holds:
total=0 ` prefix, a refusal's one sentence. Measured today, serially, on this machine, all six green: close-replay
644 s, door-card 409 s, rehearsal-release-waiting 413 s, rehearsal-failed-review 406 s, rehearsal 10 s,
rehearsal-stop-rule 14 s (§4a); door-landing and fresh-home are 136 s and 62 s by `tests/timing.tsv`. The cost is
wherever the release check or the release note runs over the real CHANGELOG; a state that lands no release is seconds.

Against wave 46: the record holds the landing record (1,065 lines: 713 `ev=verdict`, 193 `ev=run`, 28 `ev=published`, 1
`ev=stop-run`, 3 `ev=matrix-set`, no `ev=refusal`), the asks register (23 keys, all closed), the fill ledger (118
lines, no decline), the plan with its proof, approval and `moved:` lines, the release approval pages at two heads with
their `Replay` tables, the release-check and regression logs, the three rounds of critic reads, the walk, and the
continuation. **A fold over those files alone, with this tree's code, prints every field of the card's line at
93683c5e except one**: `hand-holds: total=0 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 ·
extensions=0 · waivers=0 · status-writes=0 · second-regressions=0 · adoptions=0 · fixed=0 · needs-you=0` comes out
exactly, and `unplaced=4` comes out `unplaced=0` (§7). The four unplaced lines were the rosters' adoption rows, which
the fold places in no window (line.sh:791) and which lived in `.bionic/tmp`, wiped by close-out's act 3; close-out
copies them to a `mktemp` file outside the record (close-out.sh:711-716), not into it, so they are gone. For the same
reason the whole-run window reads `amends=0` today where the walk, with the rosters present, read `amends=14`
(walk.md:68): the zeros for amends, holds, extensions and adoptions are read by absence (line.sh:688 "an absent source
counts zero"), not from evidence. The card's window must also be taken from the card's own instant: it runs from the
last build landing at render time (T31, 13:05:56Z, not the walk's T25) to the page's `at=2026-10-26T14:11:12Z`
(release-approval-93683c5e.md:79); with the walk's start the fold reads `status-writes=1`, which is what the earlier
card at 31da41f7 printed (release-approval-31da41f7.md:15-17). Close-out's line at `delivered:` is `total=1 ·
stop-runs=1` (continuation.md:186), from the `ev=stop-run` at 14:16:01Z after the card, and the fold reproduces that
too, again with `unplaced=0`.

Outside the hand-holds line, three card facts need more than the record: `n commits behind` and `n landings before
this head` are `git rev-list` counts over the repository (plan.sh:3148; proof.sh), "changes the release check" is a git
diff over the release range against `release-check-files:` in the gitignored `.bionic/config.yaml` (plan.sh:3193,
worktree.sh:1008-1012), and the landings line's `killed=` reads the gate store under `~/.claude/bionic/gate`, pruned
(line.sh:465-475, gate.sh:11): the walk read `killed=5`, the record-only fold reads `killed=0`. The 188 `ev=run` logs
the record cites under `.bionic/tmp/runs/` are gone (every one missing; the 83 under the record's `line/` and the five
regression logs are present), but the fold reads the `ev=run` lines, not the logs.

## 1. The eight suites

| suite | lines | sections | first commit | driver | replays | fixtures it reads |
|---|---:|---:|---|---|---|---|
| tests/rehearsal.test.sh | 79 | 3 | cb86091b2 2026-10-21 | rehearsal.sh `rehearse clean` | one run state: build landed by hand, release row active, no ask open (rehearsal.sh:36) | the sandbox's sheet and card, its `rehearsal.log` |
| tests/rehearsal-stop-rule.test.sh | 84 | 3 | 19075b068 2026-10-22 | `rehearse stop-rule` | a stop-rule decision put, a row reading it (rehearsal.sh:34-35, 459-463) | the same |
| tests/rehearsal-release-waiting.test.sh | 94 | 3 | 19075b068 2026-10-22 | `rehearse release-waiting` | the release order, build landed through ready, Steps 5-7, five reviews, the check, the release landed, the card rendered (rehearsal.sh:30-33, 257-290) | the same, plus the plan's regression proof and the branch head (lines 86-88) |
| tests/rehearsal-failed-review.test.sh | 83 | 3 | 19075b068 2026-10-22 | `rehearse failed-review` | release-waiting, then the user's reply, Step 8, a whole structure review failing, main merged, close-out refused (rehearsal.sh:27-29, 466-474) | the same, plus the plan's `approved: merge-unproved` line (line 53) |
| tests/close-replay.test.sh | 456 | 9 | eb5c841e2 2026-10-22 | `rehearse delivered` (and `single-verify`) | the close: failed-review carried through the verbs alone to close-out's `delivered:` (rehearsal.sh:20-26, 358-402) | `rehearsal.log`, the sandbox's `asks.state`, `landing-proofs.log`, `fill-ledger.log`, the archived plan, the release approval pages, the stand-in `gh.log`, the sandbox's git refs and CHANGELOG |
| tests/door-card.test.sh | 299 | 3 | 612dfced9 2026-10-20 | door.sh `door_world`, verbs called by the suite | the end state before the release card, by verbs; the card on it; mutants of the card and the judge; `matrix-render` growth | the plan, the release approval page's replay table (line 74-77), the judge and card source text (lines 171-177) |
| tests/door-landing.test.sh | 770 | 12 | 6a656ef5a 2026-10-20 | door.sh, `door_land` | a landing through the hand door, judged by the fixture's own copy of the release check (header lines 1-45) | the sandbox's landing record (line 86), plan rows (line 88), the sentinel `door-seen` (door.sh:27-28), release-check logs (line 169) |
| tests/fresh-home.test.sh | 932 | 2 | 9d91961f2 2026-08-22 | none (its own shims) | an install: `setup.sh --all` all-yes, `doctor.sh`, `remove.sh --all` on an empty `$HOME` with faked brew/npm/uv/claude (lines 15-17, 46-56) | a manifest of files under the fixture `$HOME`, settings.json by jq, the dependency table (lines 60-66) |

The line and section counts are r7's (r7-tests.md:73, 100, 102, 128, 221-224) and `wc -l` today agrees. r7's class
"replay" rests on the suite header; six of the eight arrived after the census head (r7-tests.md:428), all in waves 44
to 46, and the drivers `tests/lib/rehearsal.sh` (502 lines), `tests/lib/rehearsal-read.sh` (197) and `tests/lib/door.sh`
(245) are non-gating framework (r7-tests.md:49, 145, 154-155). Every suite gates by location: `tests/run.sh` reads
`tests/*.test.sh` at run time (run.sh header, lines 8-20). All eight passed in wave 46's last whole run at 6b7563af
(regression-run-6b7563af….log:25, 49, 51, 59, 93-96); at 402980ec three were red, which T25 and T27 fixed in the
tests, not the product (T25-report.md "Nothing under payload/ or hooks/ changed"; T27-report.md "No product file").

## 2. The drivers and where the fixtures live

**The world.** `tests/lib/world.sh` makes `WORLD_ROOT` with `mktemp -d "${TMPDIR:-/tmp}/world.XXXXXX"` when sourced
(world.sh:43), refuses a root inside any git checkout (world.sh:50-54), exports `WORLD_SID`, a gate store and a verb
log under it (world.sh:56-58), and removes the whole directory on exit (world.sh:60-65). Nothing a replay suite
builds survives the suite, and nothing is tracked or ignored in this repository: `git status --ignored tests/` lists
nothing (checked at 050fa567e).

**The door fixture** (`door_world`, door.sh:94-182) is a real `git init` under the world: it copies `hooks/`,
`payload/scripts/`, `tests/lib/`, `tests/run.sh` and `plugin.json` from the tree under test (door.sh:109-112), takes
`CHANGELOG.md` from the tree's HEAD commit (door.sh:113, "the real file of more than a pipe's buffer"), plants a
sentinel line in its copy of `tests/lib/release-check.sh` so a test can tell which copy ran (door.sh:114-116), commits
all of it as the accepted head on `wave/x` (door.sh:118-120), and then writes the ignored parts: the sandbox's own
`.gitignore` ignores `.bionic` and `.worktrees/` (door.sh:117); the names list is one file beside the root, outside
every checkout (door.sh:122-123); `.bionic/config.yaml` declares `release-check: bash tests/lib/release-check.sh <list>`
and `release-check-files:` (door.sh:125-126); the plan is a Step-3 plan at `.bionic/docs/plans/epic-x/wave-x.plan.md`
with rows T1 (build) and T2 (the release), `rigor:`, `scale:`, one Eval design row and one matrix row (door.sh:140-179),
bound to `WORLD_SID` (door.sh:180). So within the sandbox the plan, config and record are ignored copies in the sense
the project's own `.bionic` is ignored; none is a copy of a real run. `door_run` strips every variable and PATH entry
naming the tree under test before each command (door.sh:225-239), so the verbs are the sandbox's own copies.

**The rehearsal** (`rehearse <state> <dir>`, rehearsal.sh:405-480) builds a door world, lays the plugin's context files
beside its scripts and excludes them from the sandbox's git (rehearsal.sh:422-423), writes the project's config
declaring the real check for `delivered` and the name scan alone for every other state (rehearsal.sh:428-434), edits the
plan's prose (integration branch, goals, the build suite as AC-1.1's eval, a fresh approval stamp; rehearsal.sh:442-453)
and then runs commands. Each command goes through `door_run` and is logged with its exit, seconds and output
(rehearsal.sh:104-115); each hand write is logged with a kind from `prose record code typed launch` (rehearsal.sh:83-84,
125). The user's typed reply is planted in a transcript built from the tracked fixtures
`tests/fixtures/transcript-move/frame.jsonl` and `typed.jsonl` (rehearsal.sh:133-145), the one tracked fixture the bed
reads. Reviewer roster rows go through the production writer `roster_row` (rehearsal.sh:218-219), and the pull request
goes through a stand-in `gh` written beside the sandbox (rehearsal.sh:331-356). What the rehearsal never writes: a
register line, a ledger line a verb owns, a proof line, a step line, an approval or a landing record line
(rehearsal.sh:56-57); close-replay §REAL pins that (close-replay.test.sh:370-377).

**fresh-home** has no world: `$HOME` is a `mktemp -d` subdirectory and PATH is replaced by a bin of stateful shims
(fresh-home.test.sh:35-56, 113-118); the package-to-binary map is read from the dependency table, not restated
(lines 60-66).

**Gitignored copies, the real project.** `.gitignore` ignores `.bionic` without a trailing slash so the worktree
symlink is covered too (.gitignore, "Project notebook"). Everything in §5 is therefore gitignored: the wave-46
record, its plan, `.bionic/config.yaml` (which names the names list at `/Users/admin/.config/bionic/release-names.list`,
outside the repository; config.yaml:2) and `.bionic/tmp`. The bed reads none of it; the fold in §7 read copies of it.

## 3. What the suites assert

By kind, with the rows that carry it:

- **Exit codes of the product's verbs.** Every `dc_verb` row in door-card is `expect_eq … "0" "$DOOR_RC"`
  (door-card.test.sh:62-69, 96-145); `current 8 --check` refuses with exit 1 and one refusal line (lines 154-158); the
  card exits 0 (line 163); a mutant card exits 1 (line 211); `matrix-render` on an unknown type exits 1 with the plan
  unchanged (lines 295-296). door-landing: land exits 0, 2 on a planted name (lines 151, 253, 480); the check verb's exit
  (lines 168, 273). The rehearsals: `rehearse` itself exits 0 (RT_RC), the sheet exits 0, a judgment answering every ask
  renders (rc 0, empty stderr), one naming an unknown ask is refused (rc 1, empty stdout) (rehearsal-read.sh:68-93).
  close-replay: each logged verb's exit, read back from the log (`cr_rc`, close-replay.test.sh:77, 184-198, 268-283).
- **Record facts.** The landing record's events by field: `ev=published … kind=queue` for the fix row and its
  `numbers=` commit (close-replay.test.sh:185, 192), `ev=integrate|row=T4|part=reviews` and that main's head is that
  commit (lines 182-183, 193-194, 333-349), `ev=published … kind=hand` under a mutant door (door-landing.test.sh:492),
  every commit after the fix named by a published event (close-replay.test.sh:341-347). The plan's lines: `approved:
  release` and `approved: merge-unproved` naming the approved head (close-replay.test.sh:195-196,
  rehearsal-failed-review.test.sh:53), `proved: kind=check` at main's parent and not `result=fail` (close-replay.test.sh:194),
  `moved: … to=fixed row=T5 by=landing` (line 256), `- Step 9: delivered:` (line 173), matrix cells and block keys
  (lines 396-407, 434-443), `current: 7` and no `approved: release` (door-card.test.sh:149-151). The register's key and
  its closer (`cr_ask`, close-replay.test.sh:119-129, 186-190). The plan rows' `landed-by-hand:` and `judged-by=`
  (door-landing.test.sh:157-161, 193-195, 284-285).
- **Counts.** How many verbs the replay's log names, by name, in order (`CR_VERBS`, `cr_held`; close-replay.test.sh:85,
  203-204, 268-269); every non-zero exit is a followed refusal (lines 270-272); the entry's reviews part lists as many
  bullets as the plan registers reviews and waivers (lines 324-327); the check ran twice, both the judge's copy
  (door-landing.test.sh:164-166, 174); a decline planted a second after the card raises `declines=` by one
  (close-replay.test.sh:232-237); the sitrep's `reviews` count folds a review passed then failed once
  (rehearsal-failed-review.test.sh:78-80); the T4 row's note names every read it waits on
  (rehearsal-release-waiting.test.sh:81-83); the whole-run line's landings count is git's own `rev-list --count`
  between the proof's head and the branch's (lines 86-91).
- **Text.** Short, anchored: the sheet's `ask:` keys and holds exactly (rehearsal-read.sh:70-72), `sheet/v1` and
  `Sitrep · ` first lines (lines 69, 79), `Sitrep · project 99.0.0` with the clock stripped (line 132), every card line
  at most `BIONIC_LINE_WIDTH` columns (line 80-81), the measured keys each with a measure, unit and source
  (lines 102-108, 145-146), `hand-holds: total=0 ` as a prefix of close-out's line (close-replay.test.sh:201, 257), the
  window's `until <delivered:> (delivered:)` (line 230-231), `Release approval · door 99.0.0` (door-card.test.sh:164),
  the judge's refusal sentence spelled once and read by the card through one function (lines 173-177), `LANDED
  branch=wt/T2 onto=wave/x` and `REFUSED reason=check-failed …` (door-landing.test.sh:152, 483). fresh-home's manifest
  is bytes: `cmp` against the shipped layout, jq over settings.json, file tests (fresh-home.test.sh:19-25).
- **Mutants and controls.** door-card deletes the card's `approve:release` settle and rewords the judge
  (door-card.test.sh:200-225); door-landing plants a quitting carrier test, a check that passes a planted name, a
  runner whose judge is the head (lines 179-218, 305-321, 487-494); the rehearsals trade two numbers between their
  words and expect the refusal (rehearsal-read.sh:168-197).

The suites read the sandbox through the product's own readers in the sandbox's own copies (`rt_poker`,
rehearsal-read.sh:19-24; `door_run`), never through a parser of their own, except `cr_names`/`cr_held` over the
rehearsal log (close-replay.test.sh:91-109) and `dc_keys` over the page's replay table (door-card.test.sh:74-77).

## 4. How long

| suite | timing.tsv (1.17.0 pass, or a lone run) | header or record | measured today, serial, this machine |
|---|---:|---|---:|
| rehearsal.test.sh | no row (added after 1.17.0) | one rehearsal and its reads | see §4a |
| rehearsal-stop-rule.test.sh | no row | the same | see §4a |
| rehearsal-release-waiting.test.sh | no row | the same, with the regression and five reviews | see §4a |
| rehearsal-failed-review.test.sh | no row | release-waiting plus the reply, Step 8, a review, close-out refused | see §4a |
| close-replay.test.sh | no row | "about seven minutes when the replay reaches delivered: (four and a half to failed-review, two more for the replay's release check) … §SINGLE about a minute more" (close-replay.test.sh:47-48) | see §4a |
| door-card.test.sh | 230 s (timing.tsv:6, 2026-10-20 at 07ced9cc; "two release-check runs of about 94 s each are most of it") | | see §4a |
| door-landing.test.sh | 136 s (timing.tsv:7, 47; 2026-10-20) | | not run today |
| fresh-home.test.sh | 62 s (timing.tsv:55) | | not run today |

The cost is the release check: door.sh's fixture carries the real CHANGELOG so the check's carrier test and its report
run over the real file (door.sh:39-40; door-landing §LAND header), and `rehearse delivered` declares the real check
where every other state declares the name scan alone (rehearsal.sh:428-434), which is why close-replay is the long one.
The rehearsal suites were split by state so "no suite runs longer than one rehearsal and its reads"
(rehearsal.test.sh:3-5; T32 at 19075b068).

### 4a. Measured today

Run one after another with `/usr/bin/time -p bash tests/<suite>.test.sh` from the worktree at 050fa567e, 2026-10-26
16:40 to 17:12 local, load average about 3 on 8 cores with other agents' work beside it (so these are upper bounds on
a quiet machine; timing.tsv's door-card row was 230 s alone):

| suite | rc | verdict line | real | user+sys |
|---|---:|---|---:|---:|
| rehearsal.test.sh | 0 | 24/24 passed, sections=3 | 10.4 s | 10.3 s |
| rehearsal-stop-rule.test.sh | 0 | 26/26 passed, sections=3 | 13.6 s | 13.9 s |
| rehearsal-release-waiting.test.sh | 0 | 31/31 passed, sections=3 | 412.9 s | 409.8 s |
| rehearsal-failed-review.test.sh | 0 | 29/29 passed, sections=3 | 405.7 s | 403.1 s |
| close-replay.test.sh | 0 | 66/66 passed, sections=9 | 644.0 s | 637.0 s |
| door-card.test.sh | 0 | 67/67 passed, sections=3 setup=1 | 408.9 s | 407.6 s |
| six together, serial | | | 1,895 s (31.6 min) | |

The two cheap states are the ones that land no release (clean, stop-rule: a build row by hand, rehearsal.sh:455-463);
every state that reaches the release row pays for `door_release` (release-note over the real CHANGELOG, door.sh:202-223),
the door's check at the landing, and the release-check verb, so the four expensive suites cost about the same and
close-replay adds the replay's second check and the single-rigor world.

## 5. Wave 46's record: what it holds

The directory holds 232 entries at the top level, 86 under `line/`, 45 briefs. The files a fold would read, and
their shape:

| file | lines | what it is | in the record |
|---|---:|---|---|
| landing-proofs.log | 1,065 | 1,037 `line/v1|ev=…` lines and 28 `landed:` headers; by event: verdict 713, run 193, candidate 39, ready 37, published 28, settled 12, returned 5, matrix-set 3, standing 2, integrate 2, walk 1, stop-run 1, doc 1; no `ev=refusal` (`/usr/bin/grep -c 'ev=refusal'` is 0) | yes |
| asks.state | 23 | `owed/v1` rows, every one `state=closed`; the card's two approvals, six carries, `delivered:` | yes |
| fill-ledger.log | 118 | `fill-ledger/v1` rows: 101 `state=ok`, 17 `state=hold`, no decline or lift | yes |
| the plan (…/wave-46-asks-nothing.plan.md) | 504 | `current: 9`; `approved-by:` and two `approved:` lines (405-408); Step lines 0-9 (449-469); 5 `proved: kind=regression`, 4 `kind=check`, 9 `kind=review`, 1 `kind=walk` (472-500); 3 `moved: … to=fixed` (475, 484, 497); 7 `deferred:`; 0 `waived:`; 0 matrix `waiver:` blocks; two `## Handoff` sections (394, 502) | gitignored, present |
| release-approval-93683c5e.md | 90 | the card's text (1-75) and its `## Replay` table: `at=2026-10-26T14:11:12Z`, two decisions, six carries, the applied and replied lines (79-90) | yes |
| release-approval-31da41f7.md | 76 | the earlier card, `status-writes=1` (15-17) | yes |
| release-check-<head>.log ×4 | 9 each | `head= rc= base= judged-by= command:` and the check's lines (`test-ratio: 101380/101462` at 93683c5e) | yes |
| regression-run-<head>.log ×5 | 141-1,346 | the whole run's output at five heads | yes |
| line/*.log | 86 files | the landing line's per-suite verdict logs; 78 of them cited by `log=` | yes |
| critic-{evidence,adversarial,structure}[-2,-3].md | 29-80 each | the three rounds of reads; findings read by `disposition` | yes |
| walk.md, continuation.md, debt.md, design-ledger.md, assumptions.md | 61-218 | the walk's own readings (hand-holds at 54, 68, 81), the close's output (hand-holds at 186), the ledger | yes |
| step0-3-card.txt, T<n>-report.md, T<n>*.log, briefs/ | | the Step cards, each row's report and its red/green logs | yes |

What the record names and does not hold: the 193 `ev=run` lines cite 188 distinct logs under `.bionic/tmp/runs/`, every
one missing today; the 78 `line/` logs and the 5 regression logs cited are present. The three sessions' roster files
(`roster-<sid>.state` for 9be0f408, edfc2bd8, a9d1c095, the session ids in the fill ledger) are gone from
`.bionic/tmp`; the three there now hold no row for this plan (`/usr/bin/grep -c wave-46-asks-nothing.plan.md` over them
is 0). The gate store's requests are under `~/.claude/bionic/gate` and pruned (gate.sh:11; line.sh:414-417). The
adoption the record does describe is in prose: `poker-adopt/v1|…|from=edfc2bd8…|name=w46-T25` (resume-recap.md:5).

Per-wave volume for the bed's sizing is in the spike (spike-kernel-map-20261026.md:94-100): 1,065 landing-record lines
and 23 register keys for wave 46 against 663/33, 328/41 and 692/35 for waves 43 to 45.

## 6. The card at 93683c5e, fact by fact

The card is `hooks/poker/plan.sh`'s `release-approval` verb rendering through `card.sh release`. Each line's source,
and whether the record alone yields it:

| card line (release-approval-93683c5e.md) | source | from the record alone? |
|---|---|---|
| `head 93683c5e · 32 of 35 tasks landed` (1) | the plan's Tasks table status cells, `units_rows` (plan.sh:2933-2936) | yes (plan) |
| `every check holds at 93683c5e` (4) | `card.sh early` and the walls' rulings (plan.sh:2920-2927, 2990-3010) | mostly: the gates read the plan, the record and the register; the merge rule needs git (below) |
| `This release changes the release check: … and 8 more` (5-7) | `_wt_check_judge` over the release range against `release-check-files:` in `.bionic/config.yaml` (plan.sh:3186-3193; worktree.sh:1008-1012; config.yaml:4) | no: git diff over the repository and the gitignored config |
| `Every criterion is proved` / `34 of 35 criteria discharged, open: REQ-4` (8, 13) | the matrix rows ruled by walls.sh (plan.sh:2996-3010), goals by `plan_goals_read` (plan.sh:3124) | yes (plan, landing record for the walk's `ev=walk`) |
| `You owe 2 decisions` (9), Decisions 1-2 (70-73) | the register (`owed_list_plan`, plan.sh:2952) and the merge-unproved rule `proof_merge_unproved` (plan.sh:3105) | the register yes; the rule compares the regression proof's head to the branch head and counts landings by git |
| `hand-holds: …` (15-17) | `hand_holds_window` for the start, `hand_holds_report --until <render instant>` (plan.sh:3168-3174) | every field but `unplaced=4` (§7) |
| `test-ratio: 101380/101462` (18) | the release check's log at the head (plan.sh:3179-3183; release-check-93683c5e….log:8) | yes |
| `acceptance — 34 of 35 criteria proved; 1 owed by the close` (21) | the matrix rows, `owed:9` for the close row (plan.sh:3003-3012) | yes (plan) |
| `whole suite: red at 6b7563af, 3 landings before this head` (22) | `proof_whole_text` (plan.sh:3102): the newest `proved: kind=regression` head and `git rev-list --first-parent --count` to the branch head | the head yes (plan:493); the count needs git |
| `evidence/adversarial/structure — critic at 6b7563af, 5 commits behind` (25-27) | `proof_last_line … review` and `git rev-list --count "$h..$RR_HEAD"` (plan.sh:3141-3156) | the reader and head yes (plan:494-498); "5 commits behind" needs git |
| `Findings — 19: 3 fixed · 16 carried` (29-68) | `session-poker.sh disposition` over the registered reviews' records, the plan's `moved:` and `deferred:` lines (plan.sh:3022-3050) | yes (critic-*.md, plan) |
| `Replay` table, `carried:`, `applied:`, `replied:` (79-90) | written by the card and the reply verb | yes: it is the record |

## 7. The hand-holds fold, re-run over the record alone

`hand_holds_report` (line.sh:720-831) reads four sources: the landing record for by-hand, stop-runs, status-writes,
second-regressions and needs-you (line.sh:729-750); the fill ledger for declines and lifts (752-761); the rosters under
`<root>/.bionic/tmp/roster-*.state`, or the file `BIONIC_HH_ROSTERS` names, for amends, holds, extensions and adoptions
(762-792); and the plan for waivers, fixed and the older regression proofs (793-823). It is fail-soft: "an absent source
counts zero" (688). The window start is the newest `ev=published` of a build row (839-846), the end the plan's
`delivered:` minute once closed, else the caller's `--until` (847-853); the card passes its render instant
(plan.sh:3171-3174). An adoption row is placed by `hh_take("")`, which no window can place (791, 698-708), so with any
window every adoption is `unplaced` and never counted.

I copied `landing-proofs.log`, `fill-ledger.log`, `asks.state`, the plan and `config.yaml` into a scratch project with an
empty git repository and no roster, and ran this tree's `session-poker.sh landing-report --hand-holds` there
(scratch `fold.sh`; the verb takes `--until` to the second, so close-out's minute end is written as its last second):

```
== since the last build landing at the card's render (T31, 13:05:56Z) until the card's at= (14:11:12Z)
hand-holds: total=0 · by-hand=0 · stop-runs=0 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · status-writes=0 · second-regressions=0 · adoptions=0 · fixed=0 · needs-you=0 · unplaced=0
== the same start, until delivered: 14:16:59Z
hand-holds: total=1 · by-hand=0 · stop-runs=1 · declines=0 · lifts=0 · amends=0 · holds=0 · extensions=0 · waivers=0 · status-writes=0 · second-regressions=0 · adoptions=0 · fixed=0 · needs-you=0 · unplaced=0
== no ends given: the window read from records
hand-holds: total=1 · … · stop-runs=1 · … · unplaced=0
hand-holds window: since 2026-10-26T13:05:56Z (the last build landing, T31) · until 2026-10-26T14:16Z (delivered:)
== since 2026-10-25T00:00:00Z, the whole run (walk.md:67-68 read amends=14 here with the rosters present)
hand-holds: total=2 · … · amends=0 · … · status-writes=1 · … · unplaced=0
```

Against the record: the card's line (release-approval-93683c5e.md:15-17) is reproduced field for field except
`unplaced=4` (fold: 0); close-out's line (continuation.md:186) likewise. The `status-writes=1` the whole-run window finds
is `ev=matrix-set|ac=AC-4.1|cells=task|at=2026-10-26T04:58:30Z` (landing-proofs.log), inside the earlier card's window
(after T29's landing at 04:56:34Z) and outside this one's, which is the difference between `status-writes=1` at
31da41f7 and `0` at 93683c5e. The `stop-runs=1` is `ev=stop-run|run=regression_93683c5e-run.sh|…|at=2026-10-26T14:16:01Z`,
after the card's instant and inside the `delivered:` minute. The three `moved:` lines all fall before their rows'
first landing (T29 landed 04:56:34Z after its two moves; T34 landed 13:54:23Z after its move), so `fixed=0` is read from
evidence; the `unplaced=4` is the one figure that was read from the rosters, consistent with `adoptions=0 · unplaced=4`
on every line the run printed with a window (walk.md:54, 68, 81; the two cards; the continuation) and `unplaced=0` for
wave 45 (walk.md:103), and with three sessions' adoptions recorded only in prose (resume-recap.md:5, 22).

## 8. What the record cannot yield, and what a replay of wave 46 would need

1. **Roster-derived counts** (amends, holds, extensions, adoptions, and so `unplaced`): the rows were in `.bionic/tmp`,
   wiped at close; `co_hh_keep` copies them to `mktemp` outside the record (close-out.sh:701-716). A fold prints
   zeros by absence. To replay the close from the record, the rosters the close read (or the four `amended=`, `held=`,
   `extended=`, `source=adopted` facts) would have to be in the record.
2. **Git-derived counts and ranges**: `n landings before this head`, `n commits behind`, the release range's changed
   check files (plan.sh:3148, 3193; proof.sh). The record names heads; the counts need the repository at those heads.
   The rehearsals pin this the same way, by asking git (rehearsal-release-waiting.test.sh:86-91).
3. **Gate-store facts**: `killed=` on the landings line (line.sh:465-475, 595-600), and the asked-to-admitted tallies the
   report deliberately does not read (414-417). Absent today.
4. **The run logs** `.bionic/tmp/runs/*.log` (188 cited, 0 present): the `ev=run` lines carry `rc=` and `sha256=`, so the
   fold needs the lines, not the logs; a re-render of a verdict's text would.
5. **The window's instant**: the card's start and end are a render-time reading; the record holds the end (`at=` on the
   Replay line) and the landings the start is read from, so a fold can take both from the record, as §7 did. The walk's
   window differs from the card's because three build rows landed between them.
6. **What the bed does not do today**: no suite reads a real record. The rehearsal builds a run of two to five rows in a
   repository it makes (door.sh:140-179); wave 46 is 35 rows, 1,065 record lines, three sessions and two release cards.
   A replay of wave 46 would be a seventh rehearsal state, or a different driver, that takes a record directory and a
   plan as input and runs the readers over it, with git at the heads the record names (the repository holds them:
   `93683c5e` is on main) and either the rosters restored or the roster-derived fields declared unread.

## Sources

- tests/close-replay.test.sh, tests/door-card.test.sh, tests/door-landing.test.sh, tests/fresh-home.test.sh,
  tests/rehearsal.test.sh, tests/rehearsal-failed-review.test.sh, tests/rehearsal-release-waiting.test.sh,
  tests/rehearsal-stop-rule.test.sh; tests/lib/rehearsal.sh, tests/lib/rehearsal-read.sh, tests/lib/door.sh,
  tests/lib/world.sh; tests/timing.tsv; tests/run.sh (at 050fa567e)
- hooks/poker/line.sh:392-420, 465-475, 595-600, 616-878; hooks/poker/plan.sh:2920-3193; payload/scripts/close-out.sh:697-716;
  payload/scripts/lib/worktree.sh:1000-1012; payload/scripts/lib/gate.sh:11; payload/scripts/lib/patrol.sh:986-989
- .bionic/docs/record/spike-kernel-map-20261026/r7-tests.md:41-49, 73, 100, 102, 128, 145-155, 221-224, 276, 379-382, 405-428
- .bionic/docs/spikes/spike-kernel-map-20261026.md:47-100 (§1), 266-282 (§6)
- .bionic/docs/record/wave-46-asks-nothing/: landing-proofs.log, asks.state, fill-ledger.log, release-approval-93683c5e.md,
  release-approval-31da41f7.md, release-check-93683c5e….log, continuation.md:183-186, walk.md:40-110, resume-recap.md:1-24,
  T25-report.md, T27-report.md, regression-run-402980ec….log, regression-run-6b7563af….log
- .bionic/docs/plans/epic-23-bionic-tech-debt/wave-46-asks-nothing.plan.md:1-25, 394-502; .bionic/config.yaml
- scratch: /private/tmp/claude-501/-Users-admin-workspace-personal-bionic/8b151fe5-46c7-4fda-8c27-b48dd87e1ad8/scratchpad/fold.sh (the fold re-run), timings.txt and *.time (the suite runs)
