---
name: sitrep
description: 'Use when the user asks where the run stands: /bionic:sitrep, "sitrep", "status", "where are we", "how is it going", "what is left". Runs the situation report''s verb on the bound plan, shows its page with every rendered line unaltered and two judgment slots filled (a Bottom line first, a Diagnosis under Assessment), and records the Bottom line so the next report, the handoff head and the Patrol''s tick start from it.'
layer: technique
needs: []
loading: deferred
---

# Sitrep

The situation report: what the run has done, how it is going, what it needs from the user, and when it closes. One verb prints every fact; this skill adds only judgment, in two labelled slots.

Typed as `/bionic:sitrep` with no argument, it reports on this session's bound run. With an argument, it reports on the plan named (absolute, project-relative or docs-root-relative).

`<plugin-root>` below is the plugin's root, two directories above this skill's own.

## The steps

1. Run the verb and read its page:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep [<plan>]
   ```

   A refusal (no plan bound, no plan at the path) is the answer: say it in one line and stop.

2. Write the two slots from the page alone.
   - **Bottom line:** two to four items, each one claim that changes what the user does next. An item is a fact cited to the rendered line it reads, `(line n)`, or a judgment labelled `hypothesis:`, `diagnosis:` or `projection:`. A diagnosis or a projection cites the lines it rests on. A hypothesis says what would confirm it. Each item ends with the recommended move and its cost, `— <move> · <cost>`, when there is one.
   - **Diagnosis:** at most five lines, each a judgment about the Assessment's three indicators that cites the line it reads, `(line n)`. Say what is working as well as what is broken, and the cause when the page shows it.
   - `(line n)` is the line's number on the verb's page as step 1 printed it, the title line being 1.

3. Record the items, each quoted, the plan last when one was named:

   ```bash
   bash <plugin-root>/hooks/session-poker.sh sitrep bottom-line '<item>' ['<item>' …] [<plan>]
   ```

   A refused item is named on stderr; correct it and record again. An item may not hold `|` or a line break.

4. Show the report in the shape below, then quote the verb's confirmation line under it (`poker: sitrep bottom-line — <n> item(s) recorded at …`).

## The shape

```text
Sitrep · <wave> · <release> · <local date and time> · step <n>
Bottom line
- <fact> (line n) — <move> · <cost>
- hypothesis: <claim> — <move> · <cost>

Situation
<the verb's Situation lines>

Assessment
<the verb's three indicator lines>

Diagnosis
<one to five lines, each citing (line n)>

Blockers
<the verb's Blockers lines>

Forecast
<the verb's four Forecast lines>
```

## The rules

- A fact outside the verb's output is a contract violation: every line but the two slots is the verb's, byte for byte and in the verb's order, and a fact the verb does not print is not in the report.
- The shape and length rules: the headings are the six above, title case, in that order, with no rule line; the Bottom line holds two to four items and replaces the verb's own Bottom line section; Diagnosis holds at most five lines and sits directly under Assessment.
- The report has three surfaces, all from the one verb: `/bionic:sitrep` is this full report, the handoff file's head is the report with the last recorded Bottom line and its time, and the Patrol's tick prints the one-line form `poker: sitrep <glyphs> · owed: <n> · closes ~<time>` on every tick.
- Quote the verb's confirmation line after the report, so the user sees the Bottom line was recorded.
- Nothing here changes a plan, a record or a run beyond the `sitrep.log` line the verb writes.
