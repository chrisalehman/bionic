---
name: decision
description: "Use whenever you put a decision to the user: numbered options, a choice between approaches, a fork only they can rule on. When the user asks which of several options to use, that is a decision too: put it in the shape, never in prose. Applies at any step and with no run open, and when the user types /bionic:decision. Puts the decision in one fixed shape, Goal, Options, Recommendation, Significance, ending on one reply line."
layer: technique
needs: []
loading: deferred
---

# Decision

One shape for every decision put to the user, so a decision reads the same whoever raises it and at whatever step.

Typed as `/bionic:decision` with no argument, it puts what was last under discussion to the user in this shape. With an argument, it puts that.

## The shape

```text
**D<n> · Step <s>**

**Goal:** <one sentence: what is being decided, and why it matters now>

<optional: a short plain paragraph that explains the problem>

**Options:**

1. <the idea, named>: <what it means for the user, what it costs>
2. <the idea, named>: <what it means for the user, what it costs>
3. <the idea, named>: <what it means for the user, what it costs>

**Recommendation:** Option 2, because <the principle that decides it>. Not 1: <why not>. Not 3: <why not>.

**Significance:** <the rule it sets for later work, what follows downstream, what compounds, how hard it is to reverse>

Reply 1, 2 or 3 · or matrix, diagram, page
```

- The heading numbers the decision. `D<n>` counts the decisions of a run in one sequence, in the order asked, and never restarts; `Step <s>` is the step it is asked at. With no run open the heading is `D<n>` alone. The user can answer by the number.
- The four labels are bold, end in a colon, and come in this order. Nothing else is a label.
- The reasoning lives inside Recommendation. There is no separate rationale part.
- Options are a numbered list of two or more, never lettered or bulleted.
- One blank line separates the last option from Recommendation.
- Recommendation opens on the option number and says why it wins. Then it says why not each other option.
- Significance says what follows downstream, what compounds, and how hard the choice is to reverse.
- The reply line is the last line, and nothing follows it.

## Altitude

The failure to avoid is a brief written at the level of mechanisms: the files, functions, rows and versions the work touches. It makes the user rebuild the concept before they can choose. Those names belong in the record, never in the brief.

- Frame the decision as concepts, not mechanisms: its Goal and Options carry no file, function, row, task or version identifiers.
- Plain language.
- Pitch it at the level of abstraction that makes the options differ most.
- The goal says what and why: what is being decided, and why it matters now. The Goal is one sentence.
- A short plain paragraph after the Goal explains the problem before any option. It is optional: use it when the concept is complex, and keep it brief.
- Each option is named as an idea and says what it means for the user.
- By default the recommendation favours the most architecturally elegant choice, reasoned from first principles, and names the principle that decides it.
- Significance names the rule the choice sets for later work.
- Concise. Cut every sentence that does not change the choice.

## Worked pairs

Each pair is one decision written twice: first at the level of mechanisms, the failure, then at design altitude. Write the second.

### How a rule is enforced

Mechanism level:

> **Goal:** Decide whether `walls.sh` keeps T3's script-start carry once `gate.sh` reads `<git-dir>/bionic-agent`, given T36's bypass-mode carry retires under REQ-1.
>
> 1. Retire both carries: fold the marker read into the existing `git rev-parse` call; AC-1.5's residual stands.
> 2. Keep T3's carry for out-of-tree starts: two sources of `who`, reconciled in the gate.

Design altitude:

> **Goal:** Decide how the system tells which worker is asking to run tests, so each is held to its own budget.
>
> Today a worker's name rides on every command it runs, and a command that loses the name counts as the main thread, which no budget limits.
>
> 1. Identity from place: the folder a worker works in says who it is, and no command is rewritten. A test started outside that folder counts as the main thread.
> 2. Identity carried, place as a fallback: the name still rides on commands, and the folder fills in when it is lost. Two sources that can disagree.
>
> **Recommendation:** Option 1, because who is asking is a fact about where the work happens, and a fact read from one place cannot drift. Not 2: a second source is a second answer.
>
> **Significance:** Sets the rule that identity is read where work happens, never written into commands.

### What a wave builds

Mechanism level:

> **Goal:** Decide whether REQ-14 adopts items 1–5 of `inbound/bionic-1.16.0-w1-feedback.md` (adopt liveness, the handoff, `line.sh:1159`) or carries them with items 6–9.
>
> 1. Adopt items 1–5 as REQ-14 with AC-14.1 to AC-14.5; carry 6–9 and Jest support.
> 2. Carry all nine to the next charter.

Design altitude:

> **Goal:** Decide whether this wave fixes the defects another project just reported, or holds to its planned scope.
>
> A project on the last release met five places where the tool told it something false or refused correct work, and four where it was merely awkward.
>
> 1. Fix the five false ones now, carry the four awkward ones: the wave grows, and the release stops misleading its users.
> 2. Carry all nine: the plan holds, and users keep meeting false reports until the next wave.
>
> **Recommendation:** Option 1, because a tool that reports falsely costs more trust than a late feature does. Not 2: it ships a known lie.
>
> **Significance:** Sets the rule that a defect in what the tool tells its user outranks planned scope; friction waits its turn.

### How a shared resource is shared

Mechanism level:

> **Goal:** Decide how `gate.sh` admits a whole test run: room under the share alone or a reserved width, and whether `ready` or the tick launches it.
>
> 1. Room under the share alone: the run waits its turn like any heavy command.
> 2. Reserve a fixed width of 4 for the run in `tests/run.sh`.

Design altitude:

> **Goal:** Decide how a full test run shares the machine with the workers building the code.
>
> The full run catches what each worker's own tests miss, but it wants every core, and the workers and their landings need them too.
>
> 1. Spare capacity only: the run takes what is free, keeps some back for the next landing, and steps aside when anyone needs more. It may start late.
> 2. A fixed share: the run always holds part of the machine. It starts on time, and every worker runs slower.
>
> **Recommendation:** Option 1, because a check must never slow the work it checks, and one that starts late still finishes. Not 2: it taxes every worker for a result nobody needs yet.
>
> **Significance:** Sets the rule that a check takes only what is spare; anything added later asks the same way.

## Forms

Every decision arrives first as the four parts, in the terminal. A richer form adds to them and never replaces them, and the recommendation always appears in the terminal.

- **Matrix**, in the terminal under Options, when there are three or more options or the options differ on three or more criteria. Rows are options; columns are criteria.
- **Diagram**, offered at medium significance or above when the options differ in structure the user has not seen: what connects, what moves, what comes first.
- **Page**, a figure and a matrix with the reasons, offered only when the decision is hard to reverse or crosses waves.
- Video and raster images are never forms of a decision.

A diagram is an SVG file and a page an HTML file. Write it locally and print its path. It leaves the machine only when the user asks for a link.

Significance sets the cap:

- Trivial: reversible in minutes, nothing downstream. The cap is the matrix.
- Medium: shapes later work, reversible at a cost. The cap is the diagram.
- Momentous: hard to reverse, crosses waves, or reaches users or their data. The cap is the page.

## The reply line

The last line names the option numbers, then the forms still available, as in the shape above. It lists only the forms not yet shown and allowed by the significance. With none left it carries the options alone: `Reply 1 or 2`.

A reply that names a form gets that form directly, with no form in between. The decision then ends on a fresh reply line.

## When it applies

- Any decision put to the user, at any step and with no run open. The requirements interview and the design interview are its heaviest users.
- Small decisions may share a turn, at your discretion, when they make sense together: each in the full shape, with its own number and reply line. A momentous decision always goes alone.
- Approvals and reversible calls stay out. An approval keeps its own card. A call you can reverse is yours: make it and say so.

Nothing is run or written when a decision is made: no hook checks it and no file records it. The fixed labels and the reply line let a reader find decisions in a transcript afterwards.
