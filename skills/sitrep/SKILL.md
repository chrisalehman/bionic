---
name: sitrep
description: 'Use when the user asks where the run stands: /bionic:sitrep, "sitrep", "status", "where are we", "how is it going", "what is left". Runs the situation report''s verb on the bound plan, weighs its facts, writes the judgment, and shows the card the card verb prints from both, unaltered.'
layer: technique
needs: []
loading: deferred
---

# Sitrep

The situation report is one card: the head, Call to action, Task list, Metrics, Assessment, Blocked on you and Predicted close. The verb gathers every fact. You write only the judgment. The card verb draws the card from both and checks it before it prints anything.

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

4. Write the judgment to the card verb's stdin, one tagged line each, and pass the plan last when you named one:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep card [<plan>] <<'JUDGMENT'
   call: <the single first move>
   grade: <A-F>
   point: <one row of the Assessment>
   ask <key>: <what is asked> — recommend <answer>
   close: <what the close depends on>
   JUDGMENT
   ```

   - `call:` is the single first move. Never restate the whole Blocked on you list. When an ask is open, the call names one of them by its id.
   - `grade:` is one letter, A to F.
   - `point:` gives one to five lines, each a row of the Assessment.
   - `ask <key>:` is one line for every `ask:` line on the sheet. Copy its key, then write what is asked and `— recommend <answer>`. Never list a decision's options.
   - `ask +:` is optional: an ask the sheet lacks.
   - `close:` is one line: what the close depends on.

5. If the card verb exits with rc 1, it prints the reasons and no card. Fix the judgment and run it again. Never show a refused card, and never write a card by hand.

6. Show the card exactly as printed, inside one fenced code block, and add nothing after it.

## The words

Say "review", never "reading" or "reader". A goal nobody measures is "not measured". The card verb refuses a judgment that breaks either rule.

## Asks

Before you put any ask to the user in chat, record it through its verb so the sheet reads it. Record a decision or a stop-rule call with `decisions put D<n> '<what is decided>'`. Approvals and waivers are opened by the verbs and cards that raise them. An ask the sheet does not hold is missing from the card, so the user cannot see it is owed.

## The rules

- Every fact on the card comes from the verb. Your words reach the card only through the judgment.
- Both verbs first close any ask whose decision the design ledger already reads as ruled. Apart from that and the asks you record, nothing here changes a plan, a record or a run.
