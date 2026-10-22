---
name: sitrep
description: 'Use when the user asks where the run stands: /bionic:sitrep, "sitrep", "status", "where are we", "how is it going", "what is left". Runs the situation report''s verb on the bound plan, weighs its facts, writes the judgment, and shows the card the card verb prints from both, unaltered.'
layer: technique
needs: []
loading: deferred
---

# Sitrep

The situation report is one card: the head, Call to action, Task list, Metrics, Assessment, Blocked on you and Predicted close. The verb gathers every fact. You write every row of the card, as the judgment. The card verb draws the head, the section labels, the bullets and each task's icon, and checks your rows against the facts before it prints anything.

Typed as `/bionic:sitrep` with no argument, it reports on this session's bound run. With an argument, it reports on the plan named (absolute, project-relative or docs-root-relative). Pass that plan as `[<plan>]` to both verbs below.

`<plugin-root>` below is the plugin's root, two directories above this skill's own.

## The steps

1. Run the verb and read the fact sheet:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep [<plan>]
   ```

   The sheet is input for you; never show it, quote it or summarize it to the user. A refusal (no plan bound, no plan at the path) is the answer: say it in one line and stop.

2. Before you write, weigh these six questions against the sheet:
   - **Pace.** Is the run on pace? Compare the predicted close with the forecast, and say why it is ahead or behind.
   - **Correctness.** Of the red tests, failed reviews and open findings, which matter and which are cosmetic?
   - **Waste.** What effort was lost to dropped tasks, discarded runs, idle time or waiting on the user?
   - **Goals.** Which goals are met, which are not, and which are not measured yet?
   - **Leverage.** What single thing would most change the outcome now?
   - **Change.** What is new since the last sitrep? What does the user need to know that the numbers don't show?

3. Grade the run by this rubric. The grade is for the run, not the code.
   - **A**: on pace, correct, and nothing held on the user.
   - **B**: one thing held or slipping, with a clear way through.
   - **C**: behind, or a real defect open.
   - **D**: at risk of missing the close or shipping something wrong.
   - **F**: stopped.

4. Write the judgment: every row of the card, for the user, in plain words. Never print a register key (`waive:structure`, `approve:release`) or a raw sheet field (`holds=`, `state=held`, `waits on step 8 +2`) on a row; a key belongs only in an `ask` tag. Pipe it to the card verb's stdin, one tagged line each, and pass the plan last when you named one:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep card [<plan>] <<'JUDGMENT'
   call: Rule on the failed structure review: the merge into main waits on it.
   task: 0: Configure
   task: 1: Scope
   task: 2: Design
   task: 3: Plan
   task: 4: Implement, all 6 tasks landed
   task: 5/7–5/8: The regression and the four cards, both green
   task: 6: Review, the structure review failed at 5:50 PM
   task: 7: Document
   task: 8/9: Merge into main, waiting on your ruling on the failed review
   task: 9: Close-out
   metric: Completed: 8 of 9 tasks landed, 89%.
   metric: Pace: 8 tasks took 3 h 10 min, against the 4 h 30 min the plan allowed.
   metric: Correctness: 23 suites ran, all green at their last run; 1 review failed.
   metric: Waste: Nothing dropped and no suite run thrown away; 12 minutes idle.
   metric: Goals: 1 of 2 met; 1 not measured yet.
   grade: C
   point: The build is done and green; only the structure review stands between it and the merge.
   point: The failed review names two findings, both in the card's check.
   ask waive:structure, hold:merge: Waive the failed structure review and merge 8/9 anyway? — recommend no; fix the two findings and review again
   close: 7:40 PM, against the 8:15 PM forecast.
   close: It holds if the fix lands in one pass and the second review passes.
   JUDGMENT
   ```

   - `call:` is the single first move, in words. Never restate the whole Blocked on you list.
   - `task:` is the Task list, written `task: <label>: <text>`, in the sheet's step order. Every step on the sheet has a row: by its own label `N`, by one of its tasks `N/x`, or by a range of its finished tasks `N/a–N/b`. Every open task has a row of its own, and a step's own row never sits above its tasks. A row for a waiting task says what it waits on in words: "waiting on your approval of the release", never "waits on step 8 +2". A task row is one line, so keep it short. The card verb draws the icon from the sheet: done or open.
   - `metric:` is five rows, `metric: <Label>: <text>`: Completed, Pace, Correctness, Waste and Goals, in that order. Each states the sheet's numbers in a sentence. The card verb refuses a number the sheet does not hold, so never round one, add two or work one out.
   - `grade:` is one letter, A to F.
   - `point:` gives one to five lines, each a row of the Assessment.
   - `ask <key>:` answers every `ask:` line on the sheet once. Copy its key into the tag, then write what is asked, naming the label of every task it holds (the sheet's `holds=`), and `— recommend <answer>`. When two keys are one decision, such as a waiver and the merge it holds, answer both in one row: `ask <key>, <key>: <what> — recommend <answer>`. Never list a decision's options.
   - `ask +:` is optional: an ask the sheet lacks.
   - `close:` gives one to three rows. The first opens on the sheet's predicted close time; the others say what the close depends on, and agree with the work the Task list has left.

   The card verb capitalizes the first letter of each row.

5. If the card verb exits with rc 1, it prints the reasons and no card. Fix the judgment and run it again. Never show a refused card, and never write a card by hand.

6. Show the card exactly as printed, inside one fenced code block, and add nothing after it.

## The words

Say "review", never "reading" or "reader". A goal nobody measures is "not measured". The card verb refuses a judgment that breaks either rule.

## Asks

Before you put any ask to the user in chat, record it through its verb so the sheet reads it. Record a decision or a stop-rule call with `decisions put D<n> '<what is decided>'`. Approvals and waivers are opened by the verbs and cards that raise them. An ask the sheet does not hold is missing from the card, so the user cannot see it is owed.

## The rules

- Every fact on the card comes from the verb: the card verb refuses a row that drops or contradicts one. Your words reach the card only through the judgment.
- Both verbs first close any ask whose decision the design ledger already reads as ruled. Apart from that and the asks you record, nothing here changes a plan, a record or a run.
