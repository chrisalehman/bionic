---
name: sitrep
description: 'Use when the user asks where the run stands: /bionic:sitrep, "sitrep", "status", "where are we", "how is it going", "what is left". Runs the situation report''s verb on the bound plan, writes the one judgment its page leaves open (a grade and a rationale that names an indicator line), records it with the verb, and shows the page the verb then prints, unaltered.'
layer: technique
needs: []
loading: deferred
---

# Sitrep

The situation report: what you owe, what is next, what is done and when it closes, then every task, the run's score, what is blocked on you and the predicted close. The verb prints every fact on the page. This skill writes one thing, the grade and its rationale, and the verb records it and prints it.

Typed as `/bionic:sitrep` with no argument, it reports on this session's bound run. With an argument, it reports on the plan named (absolute, project-relative or docs-root-relative).

`<plugin-root>` below is the plugin's root, two directories above this skill's own.

## The steps

1. Run the verb and read its page:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep [<plan>]
   ```

   A refusal (no plan bound, no plan at the path) is the answer: say it in one line and stop.

2. Grade the run from the Score's five indicator lines alone, A to F. The grade grades the run, never the code, and never moves on a fact the page does not print. Write one rationale of one or two sentences that names an indicator line it rests on: schedule, correctness, waste, decisions or goals. Say the cause when the page shows it.

3. Record the grade, the rationale quoted, the plan last when one was named:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep grade <A-F> '<rationale>' [<plan>]
   ```

   The verb refuses a letter outside A to F and a rationale that names no indicator line or holds `|` or a line break; nothing is recorded. Correct it and record again.

4. Run the verb of step 1 again and show its page inside one fenced code block, byte for byte.

## The shape

```text
Sitrep · <project> <release> · <weekday> <time> · step <n> of 9 · <k> of <m> tasks done (<p>%)

Bottom line
- You owe <what, or nothing now>.
- Next: <tasks in flight; blocked; then the next ones>.
- Done: <steps and tasks, the last one at its time>.
- Close: not before <floor> · likely <clock> (<whose pace>), or why there is none.

Task list
<glyph> <step>: <name> (<time>), or — <state>
<glyph> <step>/<task>: <description> (<time>), or — <state>

Score: <grade> (graded <time>)
<mark> schedule — <what it measured>
<mark> correctness — <what it measured>
<mark> waste — <what it measured>
<mark> decisions — <what it measured>
<mark> goals — <what it measured>
- <your rationale>

Blocked on you
- <what to do>: <what waits on it>
```

## The rules

- A fact outside the verb's output is a contract violation: every line of the page is the verb's, byte for byte and in the verb's order. The grade and the rationale reach the page through the grade verb, never typed into it.
- The rationale names an indicator line, one of schedule, correctness, waste, decisions or goals; the verb refuses one that names none.
- The page has three surfaces, all from the one verb: `/bionic:sitrep` is this page, the handoff file's head is its Bottom line, and the Patrol's tick prints the one-line form `poker: sitrep <marks> · owed: <n> · <the close>` on every tick.
- Nothing here changes a plan, a record or a run beyond the `sitrep.log` line the grade verb writes.
