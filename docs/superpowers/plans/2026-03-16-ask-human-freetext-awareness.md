# ask_human Free-Text Response Awareness Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude aware that humans can respond to `ask_human` with free text instead of buttons, and normalize `selected_option` to explicit `null` for consistent JSON parsing.

**Architecture:** Description-only changes to MCP tool definitions in `server.ts`, one-liner normalization in `session-manager.ts`, type widening in `types.ts`. Transport and routing layers are untouched — they already handle free text.

**Tech Stack:** TypeScript, Vitest, MCP SDK (zod schemas)

**Spec:** `docs/superpowers/specs/2026-03-16-ask-human-freetext-awareness-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `claude-hitl-mcp/src/server.ts` | Modify lines 52, 67 | MCP tool descriptions |
| `claude-hitl-mcp/src/types.ts` | Modify line 96 | Widen `selected_option` type |
| `claude-hitl-mcp/src/session-manager.ts` | Modify line 148 | Normalize `selectedIndex ?? null` |
| `claude-hitl-mcp/src/tools.ts` | Modify line 54 | Normalize quiet-hours `selected_option` |
| `claude-hitl-mcp/tests/session-manager.test.ts` | Add test | Free-text routing with options |
| `claude-hitl-mcp/tests/tools.test.ts` | Add test | Free-text response end-to-end |

---

### Task 1: Widen `selected_option` type and normalize to explicit `null`

**Files:**
- Modify: `claude-hitl-mcp/src/types.ts:96`
- Modify: `claude-hitl-mcp/src/session-manager.ts:148`
- Modify: `claude-hitl-mcp/src/tools.ts:54`
- Test: `claude-hitl-mcp/tests/session-manager.test.ts`

- [ ] **Step 1: Write the failing test in `session-manager.test.ts`**

Add inside the `response routing` describe block, after the existing "routes prefixed free-text" test:

```typescript
it("returns selected_option as null for free-text when options were provided", async () => {
  const { requestId, promise } = manager.createRequest("preference", null, [
    { text: "Redis" },
    { text: "Postgres" },
  ]);
  manager.setMessageId(requestId, "msg-1");

  manager.routeResponse({
    text: "Actually use SQLite",
    messageId: "msg-999",
    isButtonTap: false,
  });

  const result = await promise;
  expect(result.status).toBe("answered");
  expect(result.response).toBe("Actually use SQLite");
  expect(result.selected_option).toBeNull();
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd claude-hitl-mcp && npx vitest run tests/session-manager.test.ts --reporter=verbose`

Expected: FAIL — `selected_option` is `undefined`, not `null`.

- [ ] **Step 3: Widen the type in `types.ts`**

In `claude-hitl-mcp/src/types.ts` line 96, change:
```typescript
selected_option?: number;
```
to:
```typescript
selected_option?: number | null;
```

- [ ] **Step 4: Normalize in `session-manager.ts` `resolveRequest`**

In `claude-hitl-mcp/src/session-manager.ts` line 148, change:
```typescript
selected_option: selectedIndex,
```
to:
```typescript
selected_option: selectedIndex ?? null,
```

- [ ] **Step 5: Normalize in `session-manager.ts` `handleTimeout`**

In `claude-hitl-mcp/src/session-manager.ts` line 167, change:
```typescript
selected_option: action.selectedIndex,
```
to:
```typescript
selected_option: action.selectedIndex ?? null,
```

- [ ] **Step 6: Normalize in `tools.ts` quiet-hours early return**

In `claude-hitl-mcp/src/tools.ts` line 54, change:
```typescript
selected_option: action.selectedIndex,
```
to:
```typescript
selected_option: action.selectedIndex ?? null,
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd claude-hitl-mcp && npx vitest run tests/session-manager.test.ts --reporter=verbose`

Expected: All tests PASS, including the new one.

- [ ] **Step 8: Run the full test suite**

Run: `cd claude-hitl-mcp && npx vitest run --reporter=verbose`

Expected: All tests PASS. No regressions.

- [ ] **Step 9: Commit**

```bash
git add claude-hitl-mcp/src/types.ts claude-hitl-mcp/src/session-manager.ts claude-hitl-mcp/src/tools.ts claude-hitl-mcp/tests/session-manager.test.ts
git commit -m "fix(hitl): normalize selected_option to explicit null for free-text responses"
```

---

### Task 2: Update MCP tool descriptions

**Files:**
- Modify: `claude-hitl-mcp/src/server.ts:52,67`
- Test: `claude-hitl-mcp/tests/tools.test.ts`

- [ ] **Step 1: Write the failing test in `tools.test.ts`**

Add inside the `ask_human` describe block, after the existing button-tap test:

```typescript
it("resolves free-text response when options were provided", async () => {
  let capturedHandler: any;
  (adapter.onMessage as any).mockImplementation((h: any) => {
    capturedHandler = h;
  });
  handler = new HitlToolHandler(adapter);

  const askPromise = handler.askHuman({
    message: "Redis or Postgres?",
    priority: "preference",
    options: [
      { text: "Redis", default: true },
      { text: "Postgres" },
    ],
    timeout_minutes: 1,
  });

  await vi.waitFor(() => {
    expect(adapter.sendInteractiveMessage).toHaveBeenCalled();
  });

  // Simulate user typing free text instead of tapping a button
  capturedHandler({
    text: "Actually use SQLite",
    messageId: "m3",
    isButtonTap: false,
  });

  const result = await askPromise;
  expect(result.status).toBe("answered");
  expect(result.response).toBe("Actually use SQLite");
  expect(result.selected_option).toBeNull();
});
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd claude-hitl-mcp && npx vitest run tests/tools.test.ts --reporter=verbose`

Expected: PASS (the normalization from Task 1 makes this work).

- [ ] **Step 3: Update `ask_human` tool description in `server.ts`**

In `claude-hitl-mcp/src/server.ts` line 52, change:
```typescript
"Send a question to the human and wait for their response. Use priority tiers: critical (irreversible actions), architecture (design decisions), preference (aesthetic choices).",
```
to:
```typescript
"Send a question to the human and wait for their response. Use priority tiers: critical (irreversible actions), architecture (design decisions), preference (aesthetic choices). Always provide options as suggestions, but the human may respond with free text instead of selecting an option. When this happens, selected_option will be null and response will contain their verbatim text. Handle both structured and free-text responses gracefully.",
```

- [ ] **Step 4: Update `options` field description in `server.ts`**

In `claude-hitl-mcp/src/server.ts` line 67, change:
```typescript
.describe("Selectable options with optional default"),
```
to:
```typescript
.describe("Suggested options shown as buttons. The human may tap one or ignore them and reply with free text instead."),
```

- [ ] **Step 5: Run full test suite**

Run: `cd claude-hitl-mcp && npx vitest run --reporter=verbose`

Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add claude-hitl-mcp/src/server.ts claude-hitl-mcp/tests/tools.test.ts
git commit -m "feat(hitl): document free-text response support in ask_human tool description"
```
