---
name: sitrep
description: 'Use when the user asks where the run stands: /bionic:sitrep, "sitrep", "status", "where are we", "how is it going", "what is left". Runs the situation report''s verb on the bound plan, weighs its facts, writes the judgment, and shows the card the card verb prints from both, unaltered.'
layer: technique
needs: []
loading: deferred
---

# Sitrep

The situation report is one card: the handful of facts that change what you do next. The verb gathers the facts into a sheet. Code draws every row that is a fact: the head, the Task list, the Metrics table, one counted line of the asks that wait on events, Blocked on you, and the predicted close's time and basis. You write only the judgment, seven lines, and the card verb checks them against the sheet before it prints anything.

Typed as `/bionic:sitrep` with no argument, it reports on this session's bound run. With an argument, it reports on the plan named (absolute, project-relative or docs-root-relative). Pass that plan as `[<plan>]` to both verbs below.

`<plugin-root>` below is the plugin's root, two directories above this skill's own.

## The steps

1. Run the verb and read the fact sheet:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep [<plan>]
   ```

   The sheet is input for you; never show it, quote it or summarize it to the user. A refusal (no plan bound, no plan at the path) is the answer: say it in one line and stop.

2. Before you write, weigh these six questions against the sheet. Each fact states what it measures, its unit and its source after its value: read that before you use a number, and compare only measurements that share a unit. A task's sized minutes are never wall clock, so never set them against a clock time or an elapsed time.
   - **Pace.** Is the work running on pace? Compare `pace.work-landed` with `pace.time-used`: the share of the work landed against the share of the forecast time used. Then compare `close.predicted` with the end in `clock.forecast`, and say why it moved: slower work, or work added (`work.added`).
   - **Correctness.** Of the red tests, failed reviews and open findings, which matter and which are cosmetic?
   - **Waste.** What effort was lost to dropped tasks, discarded runs, ready tasks left unstarted, or the minutes the work waited on the user?
   - **Purpose.** What is the wave for, and is it on course? Weigh `run.goal:` against each `goal:` line's `for=` and status.
   - **Leverage.** What single thing would most change the outcome now?
   - **Change.** What is new since the last sitrep? What does the user need to know that the numbers don't show?

3. Grade the run by this rubric. The grade is for the run, not the code. Pace sets it: the run is on pace when `pace.work-landed` is at least `pace.time-used`, and behind when it is lower. When work added since the approval is the reason it is behind, name the added work in a point; never hide it.
   - **A**: on pace, correct, and nothing held on the user.
   - **B**: one thing held or slipping, with a clear way through.
   - **C**: behind pace, or a real defect open.
   - **D**: at risk of missing the close or shipping something wrong.
   - **F**: stopped.

4. Write the judgment, in plain words and nothing else: the card draws the Task list, the Metrics and the rest, so you write no row for them. Pipe it to the card verb's stdin, one tagged line each, and pass the plan last when you named one:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep card [<plan>] <<'JUDGMENT'
   purpose: The card gets short enough to act on at a glance; on course, the build done and green.
   call: Rule on the failed structure review: the merge into main waits on it.
   grade: B
   point: The build is done and green, and the work is ahead of the time.
   point: Only the failed structure review stands between the run and the merge.
   ask waive:structure, hold:merge: Waive the failed structure review and merge 8/9 anyway? — recommend no; fix the findings and review again
   close: It holds if you answer the review now and the fix lands in one pass.
   JUDGMENT
   ```

   - `purpose:` is what the wave is for and whether it is on course, one row. It opens the Assessment.
   - `call:` is the single first move for the user, in words. "Nothing tonight" or its like is allowed only when every open ask waits on an event, and the card verb refuses it while an ask blocks.
   - `grade:` is one letter, A to F.
   - `point:` gives one to three rows of the Assessment, after the purpose.
   - `ask <key>:` answers each ask that waits on the user, once: copy its key from the sheet's `ask:` line, say what is asked, name the label of every task it holds, and end `— recommend <answer>`. Two keys that are one decision share a row: `ask <key>, <key>: …`. Write none for an ask that waits on an event; the counted line carries it. You never choose the card's section for an ask: the sheet says whom it waits on and what it holds, and the card verb places the row.
   - `close:` is one row: the condition the predicted close depends on, `close.waits-on-you` among it. The card draws the time and its basis, so say only what it depends on, in words.

   The card puts a held ask under Blocked on you, an unheld one under the Assessment, and an ask that waits on an event on its counted line, and Blocked on you is None when nothing is held.

   Every number in a row is a value the sheet holds, set beside the word the sheet sets it beside; the card verb refuses any other, so prefer words to figures. Never print a register key (`waive:structure`) or a raw sheet field (`holds=`, `state=held`) on a row; a key belongs only in an `ask` tag.

   The card verb draws within 10 minutes of the sheet; after that it refuses, and you run step 1 again.

5. If the card verb exits with rc 1, it prints the reasons and no card. Fix the judgment and run it again. Never show a refused card, and never write a card by hand.

6. Show the card exactly as printed, inside one fenced code block, and add nothing after it.

## The words

Say "review", never "reading" or "reader". A goal nobody measures is "not measured". The card verb refuses a judgment that breaks either rule.

## Asks

Before you put any ask to the user in chat, record it through its verb so the sheet reads it. Record a decision or a stop-rule call with `decisions put D<n> '<what is decided>'`. Approvals and waivers are opened by the verbs and cards that raise them. An ask the sheet does not hold is missing from the card, so the user cannot see it is owed.

## The rules

- Every fact on the card comes from the verb: the card verb refuses a row that drops or contradicts one. Your words reach the card only through the judgment.
- Both verbs first close any ask whose decision the design ledger already reads as ruled. Apart from that and the asks you record, nothing here changes a plan, a record or a run.
