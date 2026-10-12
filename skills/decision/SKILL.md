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
**Goal:** <what is being decided, and why it matters now>

**Options:**

1. <option>: <what it does, what it costs>
2. <option>: <what it does, what it costs>
3. <option>: <what it does, what it costs>

**Recommendation:** Option 2, because <why it wins>. Not 1: <why not>. Not 3: <why not>.

**Significance:** <what follows downstream, what compounds, how hard it is to reverse>

Reply 1, 2 or 3 · or matrix, diagram, page
```

- The four labels are bold, end in a colon, and come in this order. Nothing else is a label.
- The reasoning lives inside Recommendation. There is no separate rationale part.
- Options are a numbered list of two or more, never lettered or bulleted.
- One blank line separates the last option from Recommendation.
- Recommendation opens on the option number and says why it wins. Then it says why not each other option.
- Significance says what follows downstream, what compounds, and how hard the choice is to reverse.
- The reply line is the last line, and nothing follows it.

## Altitude

- Plain language.
- Pitch it at the level of abstraction that makes the options differ most.
- The goal says what and why: what is being decided, and why it matters now.
- By default the recommendation favours the most architecturally elegant choice, reasoned from first principles.
- Concise. Cut every sentence that does not change the choice.

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
- One decision per interview turn. A report may carry several, each in the shape.
- Approvals and reversible calls stay out. An approval keeps its own card. A call you can reverse is yours: make it and say so.

Nothing is run or written when a decision is made: no hook checks it and no file records it. The fixed labels and the reply line let a reader find decisions in a transcript afterwards.
