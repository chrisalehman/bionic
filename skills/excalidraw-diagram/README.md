# Excalidraw Diagram Skill (vendored fork)

Generates Excalidraw diagrams that **argue visually**, with a Playwright render pipeline so the agent can see and fix its own output.

**This is a vendored fork of `coleam00/excalidraw-diagram-skill`.** Upstream is unmaintained and broken: it imports `@excalidraw/excalidraw?bundle` unpinned from esm.sh, whose transitive-dep resolution drifted and now 404s `@braintree/sanitize-url` `constants.mjs`, breaking the renderer on every diagram. Upstream HEAD is still unpinned and won't be fixed.

**The pin lives at `references/render_template.html:16`** — `@excalidraw/excalidraw@0.18.0`. Bump it deliberately and verify a real render first. Do not re-clone from upstream; that reinstates the breakage.

## Renderer setup

```bash
cd ~/.claude/skills/excalidraw-diagram/references
uv sync
uv run playwright install chromium
```

## Customize colors

Edit `references/color-palette.md` — the single source of truth for all colors. Everything else is universal design methodology.
