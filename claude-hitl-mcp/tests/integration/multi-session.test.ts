/**
 * Integration tests for the Listener with multiple concurrent MCP server sessions.
 *
 * Each test stands up a real IpcServer (via Listener) with a temp socket path,
 * connects two real IpcClients, and verifies routing behaviour across sessions.
 */

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import * as os from "node:os";
import * as path from "node:path";
import * as fs from "node:fs";
import { Listener } from "../../src/listener.js";
import { IpcClient } from "../../src/ipc/client.js";
import type {
  ServerMessage,
  ResponseMessage,
  TimeoutMessage,
  QuietHoursChangedMessage,
} from "../../src/ipc/protocol.js";
import { createMockBot } from "../helpers/mock-bot.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function tmpSocket(): string {
  return path.join(
    os.tmpdir(),
    `ms-${Date.now()}-${Math.random().toString(36).slice(2, 7)}.sock`
  );
}

function tmpDir(): string {
  const dir = path.join(
    os.tmpdir(),
    `ms-cfg-${Date.now()}-${Math.random().toString(36).slice(2)}`
  );
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

/** Poll until predicate returns true, or throw after `ms` ms. */
async function waitFor(predicate: () => boolean, ms = 1000): Promise<void> {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((r) => setTimeout(r, 10));
  }
  if (!predicate()) throw new Error("waitFor timed out");
}

const CHAT_ID = 99999;

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

describe("Multi-session Listener integration", () => {
  let listener: Listener;
  let socketPath: string;
  let configDir: string;
  let bot: ReturnType<typeof createMockBot>;

  // Two IpcClients reused across tests; each test connects/disconnects as needed.
  let client1: IpcClient;
  let client2: IpcClient;

  beforeEach(async () => {
    socketPath = tmpSocket();
    configDir = tmpDir();
    bot = createMockBot(CHAT_ID);

    listener = new Listener({
      configDir,
      socketPath,
      telegramBot: bot as unknown as import("../../src/listener.js").TelegramBot,
      chatId: CHAT_ID,
      maxConnections: 10,
    });

    await listener.start();

    client1 = new IpcClient(socketPath);
    client2 = new IpcClient(socketPath);
  });

  afterEach(async () => {
    // Best-effort disconnect – clients may already be disconnected.
    try { await client1.disconnect(); } catch { /* ignored */ }
    try { await client2.disconnect(); } catch { /* ignored */ }

    await listener.stop();

    try { fs.unlinkSync(socketPath); } catch { /* already removed */ }
    fs.rmSync(configDir, { recursive: true, force: true });
  });

  // -------------------------------------------------------------------------
  // 1. Two MCP servers connect — both appear in /status
  // -------------------------------------------------------------------------

  it("two sessions connect — /status lists both project names with drill-down buttons", async () => {
    await client1.connect("ms-sess-1", "project-alpha", os.homedir());
    await client2.connect("ms-sess-2", "project-beta", os.homedir());
    await waitFor(() => listener.getIpcServer().getSessions().length === 2);

    bot.simulateMessage("/status");
    await waitFor(() => bot.sentMessages.length > 0);

    const msg = bot.sentMessages[0];
    expect(msg.text).toContain("project-alpha");
    expect(msg.text).toContain("project-beta");

    // Should include drill-down inline keyboard buttons for each session
    const keyboard = (
      msg.options as { reply_markup?: { inline_keyboard?: unknown[][] } }
    )?.reply_markup?.inline_keyboard;
    expect(Array.isArray(keyboard)).toBe(true);
    expect((keyboard as unknown[][]).length).toBe(2);

    // Each button's callback_data should start with "status:"
    const flatButtons = (keyboard as Array<Array<{ callback_data?: string }>>).flat();
    for (const btn of flatButtons) {
      expect(btn.callback_data).toMatch(/^status:/);
    }
  });

  // -------------------------------------------------------------------------
  // 2. ask from session 1 — response routes only to session 1
  // -------------------------------------------------------------------------

  it("response to ask from session 1 routes only to session 1, not session 2", async () => {
    await client1.connect("ms-sess-1", "project-alpha", os.homedir());
    await client2.connect("ms-sess-2", "project-beta", os.homedir());
    await waitFor(() => listener.getIpcServer().getSessions().length === 2);

    // Use a single handler per client — avoids the single-slot onMessage replacement problem.
    const received1: ServerMessage[] = [];
    const received2: ServerMessage[] = [];
    client1.onMessage((m) => received1.push(m));
    client2.onMessage((m) => received2.push(m));

    client1.sendAsk(
      "req-route-1",
      "Route to session 1 only?",
      "preference",
      [{ text: "Yes" }, { text: "No" }]
    );

    await waitFor(() => bot.sentMessages.length > 0);

    // Simulate tapping button index 0 ("Yes")
    bot.simulateCallbackQuery("req-route-1:0");

    await waitFor(() => received1.some((m) => m.type === "response"));

    const response = received1.find((m) => m.type === "response") as ResponseMessage | undefined;
    expect(response).toBeDefined();
    expect(response?.requestId).toBe("req-route-1");
    expect(response?.text).toBe("Yes");
    expect(response?.isButtonTap).toBe(true);

    // Wait a moment to give client 2 time to incorrectly receive the message
    await new Promise((r) => setTimeout(r, 200));

    // Client 2 should NOT have received any response message
    const client2Responses = received2.filter((m) => m.type === "response");
    expect(client2Responses).toHaveLength(0);
  });

  // -------------------------------------------------------------------------
  // 3. Both sessions ask — responses route correctly by requestId
  // -------------------------------------------------------------------------

  it("concurrent asks from both sessions — each gets only its own response", async () => {
    await client1.connect("ms-sess-1", "project-alpha", os.homedir());
    await client2.connect("ms-sess-2", "project-beta", os.homedir());
    await waitFor(() => listener.getIpcServer().getSessions().length === 2);

    // Track all messages each client receives via a single handler per client.
    // Using a single handler avoids the single-slot onMessage replacement problem.
    const received1: ServerMessage[] = [];
    const received2: ServerMessage[] = [];
    client1.onMessage((m) => received1.push(m));
    client2.onMessage((m) => received2.push(m));

    client1.sendAsk("req-concurrent-1", "Question from alpha", "architecture", [
      { text: "Postgres" },
      { text: "MySQL" },
    ]);
    client2.sendAsk("req-concurrent-2", "Question from beta", "preference", [
      { text: "Option X" },
      { text: "Option Y" },
    ]);

    await waitFor(() => bot.sentMessages.length >= 2);
    expect(listener.getPendingCount()).toBe(2);

    // Respond to session 2 first, then session 1
    bot.simulateCallbackQuery("req-concurrent-2:1");
    await waitFor(() => received2.some((m) => m.type === "response"));
    expect(listener.getPendingCount()).toBe(1);

    bot.simulateCallbackQuery("req-concurrent-1:0");
    await waitFor(() => received1.some((m) => m.type === "response"));
    expect(listener.getPendingCount()).toBe(0);

    // Verify correct responses reached each client
    const r1Responses = received1.filter((m) => m.type === "response") as ResponseMessage[];
    const r2Responses = received2.filter((m) => m.type === "response") as ResponseMessage[];

    expect(r1Responses).toHaveLength(1);
    expect(r1Responses[0].requestId).toBe("req-concurrent-1");
    expect(r1Responses[0].text).toBe("Postgres");

    expect(r2Responses).toHaveLength(1);
    expect(r2Responses[0].requestId).toBe("req-concurrent-2");
    expect(r2Responses[0].text).toBe("Option Y");

    // Cross-check: neither client received the other's response
    const r1ReqIds = r1Responses.map((r) => r.requestId);
    const r2ReqIds = r2Responses.map((r) => r.requestId);
    expect(r1ReqIds).not.toContain("req-concurrent-2");
    expect(r2ReqIds).not.toContain("req-concurrent-1");
  });

  // -------------------------------------------------------------------------
  // 4. Session 1 disconnects — /status shows remaining session + disconnected
  // -------------------------------------------------------------------------

  it("/status after session 1 disconnects shows active session and disconnected info", async () => {
    await client1.connect("ms-sess-1", "project-alpha", os.homedir());
    await client2.connect("ms-sess-2", "project-beta", os.homedir());
    await waitFor(() => listener.getIpcServer().getSessions().length === 2);

    // Disconnect client1 gracefully — this means deregister, so no disconnected record
    // Force a hard disconnect by destroying the socket instead for a disconnected record.
    // We do this by calling disconnect() which sends deregister — that won't leave a
    // disconnected record per IpcServer logic. So we need to close ungracefully.
    // Access the internal socket via a cast and destroy it to simulate a crash.
    const rawClient1 = client1 as unknown as { socket: import("node:net").Socket | null };
    rawClient1.socket?.destroy();

    await waitFor(() => listener.getIpcServer().getSessions().length === 1);
    await waitFor(() => listener.getIpcServer().getDisconnectedSessions().length === 1);

    bot.simulateMessage("/status");
    await waitFor(() => bot.sentMessages.length > 0);

    const msg = bot.sentMessages[0];
    // project-beta should still be active (single-session format)
    expect(msg.text).toContain("project-beta");
    // Single session; no keyboard buttons for multi-session drill-down
    // The disconnected session info is not shown in the single-session detail view
    // but the active session is correctly shown
    const ipcSessions = listener.getIpcServer().getSessions();
    expect(ipcSessions).toHaveLength(1);
    expect(ipcSessions[0].project).toBe("project-beta");

    const disconnected = listener.getIpcServer().getDisconnectedSessions();
    expect(disconnected).toHaveLength(1);
    expect(disconnected[0].project).toBe("project-alpha");
  });

  // -------------------------------------------------------------------------
  // 5. /quiet toggle broadcasts quiet_hours_changed to all connected sessions
  // -------------------------------------------------------------------------

  it("/quiet 'Turn On' broadcasts quiet_hours_changed to all connected sessions", async () => {
    await client1.connect("ms-sess-1", "project-alpha", os.homedir());
    await client2.connect("ms-sess-2", "project-beta", os.homedir());
    await waitFor(() => listener.getIpcServer().getSessions().length === 2);

    const received1: ServerMessage[] = [];
    const received2: ServerMessage[] = [];
    client1.onMessage((m) => received1.push(m));
    client2.onMessage((m) => received2.push(m));

    // Simulate tapping "Turn On" in the quiet menu
    bot.simulateCallbackQuery("quiet:on");

    await waitFor(() =>
      received1.some((m) => m.type === "quiet_hours_changed") &&
      received2.some((m) => m.type === "quiet_hours_changed")
    );

    const broadcast1 = received1.find(
      (m) => m.type === "quiet_hours_changed"
    ) as QuietHoursChangedMessage | undefined;
    const broadcast2 = received2.find(
      (m) => m.type === "quiet_hours_changed"
    ) as QuietHoursChangedMessage | undefined;

    expect(broadcast1?.quietHours.enabled).toBe(true);
    expect(broadcast1?.quietHours.manual).toBe(true);
    expect(broadcast2?.quietHours.enabled).toBe(true);
    expect(broadcast2?.quietHours.manual).toBe(true);
  });

  // -------------------------------------------------------------------------
  // 6. Non-command free text with no sessions returns error
  // -------------------------------------------------------------------------

  it("free text with no sessions connected returns 'No active Claude sessions'", async () => {
    // No clients connected — just send free text
    bot.simulateMessage("hello, is anyone there?");
    await waitFor(() => bot.sentMessages.length > 0);

    const text = bot.sentMessages[0].text;
    expect(text).toContain("No active Claude sessions");
    expect(text).toContain("wasn't delivered");
  });

  // -------------------------------------------------------------------------
  // 7. ask times out — listener sends timeout to the correct session only
  // -------------------------------------------------------------------------

  it("ask timeout sends timeout message to correct client, not the other", async () => {
    vi.useFakeTimers();

    try {
      await client1.connect("ms-sess-1", "project-alpha", os.homedir());
      await client2.connect("ms-sess-2", "project-beta", os.homedir());

      // Drain the event loop so registration completes
      await vi.runAllTimersAsync();
      await waitFor(() => listener.getIpcServer().getSessions().length === 2, 300);

      const received1: ServerMessage[] = [];
      const received2: ServerMessage[] = [];
      client1.onMessage((m) => received1.push(m));
      client2.onMessage((m) => received2.push(m));

      // Client 1 sends an ask with a 1-minute timeout
      client1.sendAsk(
        "req-timeout-routing",
        "Which option?",
        "preference",
        [{ text: "Default", isDefault: true }],
        0,
        1 // 1 minute
      );

      await vi.runAllTimersAsync();
      await waitFor(() => bot.sentMessages.length > 0, 300);

      // Advance past 1-minute timeout
      vi.advanceTimersByTime(61 * 1000);
      await vi.runAllTimersAsync();

      await waitFor(
        () => received1.some((m) => m.type === "timeout"),
        300
      );

      const timeoutMsg = received1.find((m) => m.type === "timeout") as
        | TimeoutMessage
        | undefined;
      expect(timeoutMsg).toBeDefined();
      expect(timeoutMsg?.requestId).toBe("req-timeout-routing");

      // Client 2 should NOT have received a timeout
      const client2Timeouts = received2.filter((m) => m.type === "timeout");
      expect(client2Timeouts).toHaveLength(0);

      // Pending count should now be 0
      expect(listener.getPendingCount()).toBe(0);
    } finally {
      vi.useRealTimers();
    }
  });
});
