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

2. Before you write, weigh these six questions against the sheet. Each fact states what it measures, its unit and its source after its value: read that before you use a number, and compare only measurements that share a unit. A task's sized minutes are never wall clock, so never set them against a clock time or an elapsed time.
   - **Pace.** Is the work running on pace? Compare `pace.work-landed` with `pace.time-used`: the share of the work landed against the share of the forecast time used. Then compare `close.predicted` with the end in `clock.forecast`, and say why it moved: slower work, or work added (`work.added`). The Pace row may give the forecast's hours as the sheet writes them, "10 h 30 min".
   - **Correctness.** Of the red tests, failed reviews and open findings, which matter and which are cosmetic?
   - **Waste.** What effort was lost to dropped tasks, discarded runs, ready tasks left unstarted, or the minutes the work waited on the user?
   - **Goals.** Which goals are met, which are not, and which are not measured yet?
   - **Leverage.** What single thing would most change the outcome now?
   - **Change.** What is new since the last sitrep? What does the user need to know that the numbers don't show?

3. Grade the run by this rubric. The grade is for the run, not the code. Pace sets it: the run is on pace when `pace.work-landed` is at least `pace.time-used`, and behind when it is lower. When work added since the approval is the reason it is behind, name the added work in the Assessment; never hide it.
   - **A**: on pace, correct, and nothing held on the user.
   - **B**: one thing held or slipping, with a clear way through.
   - **C**: behind pace, or a real defect open.
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
   metric: Completed: 8 tasks landed, 380 of 420 sized minutes, 90%; 1 task left, 40 minutes.
   metric: Pace: 90% of the work landed in 80% of the forecast time.
   metric: Correctness: 23 suites run, 23 green and 0 red; 1 review failed, with 2 open findings.
   metric: Waste: Nothing dropped and no suite run thrown away; 25 minutes waiting on you.
   metric: Goals: The asks check met; your verdict on the cards not measured yet.
   grade: B
   point: The build is done and green, and the work is ahead of the time: 90% landed in 80% of the forecast.
   point: Only the failed structure review stands between it and the merge; its two findings are in the card's check.
   ask waive:structure, hold:merge: Waive the failed structure review and merge 8/9 anyway? — recommend no; fix the two findings and review again
   close: 7:40 PM, against the forecast end of 8:15 PM.
   close: That is the 40 minutes of the merge row from now, at the pace the landed tasks kept against their size.
   close: It holds if you answer the review now and the fix lands in one pass.
   JUDGMENT
   ```

   - `call:` is the single first move, in words. Never restate the whole Blocked on you list. While an ask that holds something is open, the call never says nothing is owed, and while none is, it names no key: the card verb refuses both. An ask that holds nothing owes the user nothing, so the call may say so over it.
   - `task:` is the Task list, written `task: <label>: <text>`, in the sheet's step order. Every step on the sheet has a row: by its own label `N`, by one of its tasks `N/x`, or by a range of its finished tasks `N/a–N/b`. Every open task has a row of its own, and a step's own row never sits above its tasks. A row for a waiting task says what it waits on in words: "waiting on your approval of the release", never "waits on step 8 +2". A task row is one line, so keep it short. The card verb draws the icon from the sheet: done or open. A task's own row never says what its state on the sheet denies: an open task never landed, done, finished, merged or green, and a done task never building, waiting, held or running.
   - `metric:` is five rows, `metric: <Label>: <text>`: Completed, Pace, Correctness, Waste and Goals, in that order. Each states the sheet's measurements in a sentence: Completed from `work.landed` and `work.left`, Pace from `pace.work-landed`, `pace.time-used`, `work.added` and `clock.forecast`, Correctness from the `tests.`, `reviews` and `findings.open` lines, Waste from the `waste.` lines, Goals from the `goal:` lines counted by status. A comparison sets side by side only two measurements of one unit. The card verb refuses a number that is not in the measured values (the text before ` — `) of the row's own lines, and a goal count the `goal:` lines do not add up to, so never round one, add two, work one out or borrow one from a clock or another row. A number is the value of the line whose word stands beside it, so put each number before the word that names its line, "37% of the work landed in 60% of the time", or behind it with a comma between, "work landed 37%, time used 60%"; the verb refuses a number set beside another line's word, as the two shares traded.
   - `grade:` is one letter, A to F.
   - `point:` gives one to five lines, each a row of the Assessment.
   - `ask <key>:` answers every `ask:` line on the sheet once, whether it holds something or nothing. Copy its key into the tag, then write what is asked, naming the label of every task it holds (the sheet's `holds=`), and `— recommend <answer>`. When two keys are one decision, such as a waiver and the merge it holds, answer both in one row: `ask <key>, <key>: <what> — recommend <answer>`. Never list a decision's options. You never choose the card's section for an ask: the sheet's `blocks=` says whether it blocks the user, and the card verb places the row from that.
   - `ask +:` is optional: an ask the sheet lacks.
   - `close:` gives one to three rows. The first opens on the time in `close.predicted`. Restate its basis in words, never as a ratio: the chain left (`close.chain`) from now, scaled or not by the landed tasks' own time against their size. Say what it depends on, `close.waits-on-you` among it, and agree with the work the Task list has left.

   Blocked on you lists only what blocks the user: the rows for asks that hold a task, the release or the merge. An ask that holds nothing, such as a goal-missed decision, blocks nothing, so the card verb draws its row under the Assessment, after your points, as "Open, blocking nothing". When no ask is held, the card verb draws Blocked on you as None, and you write no row to say so. The ask keeps its register item and closes as it always did.

   The card verb capitalizes the first letter of each row. It checks your rows against the sheet you wrote from, the one step 1 printed, with the open asks read again from the register. Draw the card within 10 minutes of that sheet: after that, the card verb refuses it and you run step 1 again.

5. If the card verb exits with rc 1, it prints the reasons and no card. Fix the judgment and run it again. Never show a refused card, and never write a card by hand.

6. Show the card exactly as printed, inside one fenced code block, and add nothing after it.

## The words

Say "review", never "reading" or "reader". A goal nobody measures is "not measured". The card verb refuses a judgment that breaks either rule.

## Asks

Before you put any ask to the user in chat, record it through its verb so the sheet reads it. Record a decision or a stop-rule call with `decisions put D<n> '<what is decided>'`. Approvals and waivers are opened by the verbs and cards that raise them. An ask the sheet does not hold is missing from the card, so the user cannot see it is owed.

## The rules

- Every fact on the card comes from the verb: the card verb refuses a row that drops or contradicts one. Your words reach the card only through the judgment.
- Both verbs first close any ask whose decision the design ledger already reads as ruled. Apart from that and the asks you record, nothing here changes a plan, a record or a run.
