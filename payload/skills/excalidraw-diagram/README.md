# Excalidraw Diagram Skill (vendored fork)

Generates Excalidraw diagrams that **argue visually**, with a Playwright render pipeline so the agent can see and fix its own output.

**This is a vendored fork of `coleam00/excalidraw-diagram-skill`.** Upstream is unmaintained and broken: it imports `@excalidraw/excalidraw?bundle` unpinned from esm.sh, whose transitive-dep resolution drifted and now 404s `@braintree/sanitize-url` `constants.mjs`, breaking the renderer on every diagram. Upstream HEAD is still unpinned and won't be fixed.

**The pin lives at `references/render_template.html:16`** — `@excalidraw/excalidraw@0.18.0`. Bump it deliberately and verify a real render first. Do not re-clone from upstream; that reinstates the breakage.

**Ships with the plugin**: this skill is part of bionic's payload, so installing bionic installs it. Nothing to copy, nothing to place.

## Renderer setup

Nothing here is run by hand. The renderer's two halves are `when-needed` rows in bionic's dependency table (`payload/scripts/lib/deps.sh`) — `excalidraw-renderer`, the synced uv project at `${CLAUDE_PLUGIN_ROOT}/skills/excalidraw-diagram/references`, and `playwright-chromium`, the browser it drives — and SKILL.md routes the render workflow through `jit_check`/`jit_offer` (`payload/scripts/lib/jit.sh`), which offers each one on consent the first time a render needs it. `/bionic:doctor` reports both.

## Customize colors

Edit `references/color-palette.md` — the single source of truth for all colors. Everything else is universal design methodology.
