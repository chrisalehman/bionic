---
name: motion
description: Use when building or polishing animated web UI — entrance/exit transitions, spring physics, layout & shared-element animation, scroll- and gesture-driven motion, or any "make this feel alive" task in a JS/React/Vue project. Teaches the current motion.dev (`motion`) API and the per-project install. Pairs with the impeccable design skills (animate, overdrive, delight).
layer: technique
needs: []
loading: deferred
---

# Motion (motion.dev)

## Overview

`motion` (motion.dev) is the animation library to reach for in web projects — a tiny, hardware-accelerated engine with first-class spring physics, layout animation, and scroll/gesture support, for vanilla JS, React, and Vue. It is the open-source successor to Framer Motion: same lineage, new unified package.

**Use the current names.** The package is `motion`; the React entry is `motion/react`. Do **not** install `framer-motion` or write `import … from "framer-motion"` — that is the deprecated package. If you see "Framer Motion" in older guidance (including some upstream design skills), translate it to `motion` / `motion/react`.

## Install (per project)

`motion` is an importable library, not a CLI — it lives in each project's dependencies. Add it to the project you're working in:

```bash
pnpm add motion        # npm install motion / yarn add motion
```

In a bionic-bootstrapped environment the package is pre-warmed in the pnpm content-addressable store, so `pnpm add motion` hard-links from the store — instant and offline. Migrating an old project? `npm uninstall framer-motion && npm install motion`, then rewrite imports (`framer-motion` → `motion/react`).

## Entry points

| Import | Use for |
|--------|---------|
| `motion` | Vanilla JS: `animate`, `scroll`, `inView`, `stagger`, `spring`, `hover`, `press` |
| `motion/mini` | Vanilla, minimal `animate` (~2.5kb) — uses native Web Animations API |
| `motion/react` | React: the `<motion />` component, `AnimatePresence`, hooks |
| `motion/react-mini` | React `useAnimate` with a smaller footprint |

## Core recipes

### Vanilla JS

```javascript
import { animate, scroll, inView, stagger } from "motion"

// Animate an element. Keyframes + transition.
animate("#box", { opacity: 1, transform: "translateY(0px)" }, { duration: 0.4, ease: "easeOut" })

// Stagger a list.
animate(".item", { opacity: 1, y: 0 }, { delay: stagger(0.05) })

// Run once when an element enters the viewport.
inView(".card", (el) => { animate(el, { opacity: 1 }); })

// Scroll-linked: tie a value to scroll progress.
scroll(animate(".progress", { scaleX: [0, 1] }))
```

### React

```jsx
import { motion, AnimatePresence } from "motion/react"

// Declarative: initial → animate, plus exit (needs AnimatePresence).
<AnimatePresence>
  {open && (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: 8 }}
      transition={{ duration: 0.25 }}
    />
  )}
</AnimatePresence>
```

Imperative sequences use `useAnimate`; scroll uses `useScroll` + `useTransform`.

## Spring physics — the default for natural motion

Springs are motion's signature. Prefer them over cubic-bezier easing for anything that should feel physical (drags, reveals, UI that responds to input). The modern, designer-friendly knobs are `bounce` + `visualDuration` (not raw stiffness/damping):

```jsx
<motion.div
  animate={{ x: 200 }}
  transition={{ type: "spring", bounce: 0.3, visualDuration: 0.5 }}
/>
```

- `visualDuration` — how long until it *visually* arrives (what users perceive).
- `bounce` — overshoot: `0` = no bounce, `~0.3` lively, higher = springier.
- `stiffness` / `damping` / `mass` — the physics-purist alternative when you need exact control.

React: `useSpring(value, { stiffness: 300 })` makes any value spring-track another.

## Layout & shared-element animation

`layout` and `layoutId` are the killer feature — animate between two layouts the browser would otherwise snap:

```jsx
<motion.div layout />                      // animates its own size/position changes
<motion.div layoutId="hero" />             // same id across views → shared-element transition
```

## Gestures

`whileHover`, `whileTap`, `whileDrag`, `whileFocus`, `whileInView`, and `drag` are declarative props on `<motion />`. In vanilla, use `hover()` and `press()`.

## Reduced motion is not optional

Every animation needs a reduced-motion path — typically a crossfade or instant state change instead of movement. This is an accessibility requirement, not a nicety.

- **React:** `const shouldReduceMotion = useReducedMotion()` → branch the animation (drop transforms, keep opacity).
- **Vanilla / CSS:** honor `@media (prefers-reduced-motion: reduce)`.

```jsx
const reduce = useReducedMotion()
<motion.div animate={reduce ? { opacity: 1 } : { opacity: 1, y: 0 }} />
```

## Performance

- Animate `transform` (x/y/scale/rotate) and `opacity` — they're GPU-composited. Avoid animating `width`/`height`/`top`/`left` (layout thrash); use `scale` or `layout` instead.
- Bound expensive effects (blur, filter, shadow) and verify smoothness in-browser before shipping.
- Reach for `motion/mini` when bundle size matters and you only need `animate`.

## When to use vs. plain CSS

CSS transitions/animations are right for simple, static, declarative state changes (hover color, a spinner). Reach for `motion` when you need: spring physics, orchestration/stagger, layout or shared-element transitions, scroll- or gesture-driven values, exit animations, or interruptible/dynamic animations driven by state. Don't pull in the library to fade one button.

## Relationship to the impeccable design skills

`impeccable`'s `animate`, `overdrive`, and `delight` decide *what* should move and *why* (choreography, restraint, premium materials). This skill is the *how* — the concrete, current `motion` API to implement them. When those skills say "use a library for advanced motion needs" or name "Framer Motion," that means `motion` / `motion/react` per this skill.
