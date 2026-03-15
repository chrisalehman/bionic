// tests/adapters/listener-client.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as os from "node:os";
import * as path from "node:path";
import { IpcServer } from "../../src/ipc/server.js";
import { ListenerClientAdapter } from "../../src/adapters/listener-client.js";
import type { InboundMessage } from "../../src/types.js";
import { serialize } from "../../src/ipc/protocol.js";

function makeSocketPath(): string {
  return path.join(
    os.tmpdir(),
    `hitl-lc-${Date.now()}-${Math.random().toString(36).slice(2)}.sock`
  );
}

describe("ListenerClientAdapter", () => {
  let server: IpcServer;
  let adapter: ListenerClientAdapter;
  let socketPath: string;

  beforeEach(async () => {
    socketPath = makeSocketPath();
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();
    adapter = new ListenerClientAdapter(socketPath);
  });

  afterEach(async () => {
    if (adapter.isConnected()) {
      await adapter.disconnect();
    }
    await server.stop();
  });

  // ------------------------------------------------------------------ metadata

  describe("metadata", () => {
    it("has name 'listener-client'", () => {
      expect(adapter.name).toBe("listener-client");
    });

    it("declares same capabilities as TelegramAdapter", () => {
      expect(adapter.capabilities).toEqual({
        inlineButtons: true,
        threading: false,
        messageEditing: true,
        silentMessages: true,
        richFormatting: true,
      });
    });
  });

  // ------------------------------------------------------------------ connect / disconnect

  describe("connect / disconnect", () => {
    it("connects to the IPC server and registers", async () => {
      await adapter.connect({ token: "" });
      expect(adapter.isConnected()).toBe(true);
      expect(server.getSessions()).toHaveLength(1);
    });

    it("disconnects gracefully", async () => {
      await adapter.connect({ token: "" });
      await adapter.disconnect();
      await new Promise((r) => setTimeout(r, 100));
      expect(adapter.isConnected()).toBe(false);
      expect(server.getSessions()).toHaveLength(0);
      // Graceful deregister — should not be in disconnected list
      expect(server.getDisconnectedSessions()).toHaveLength(0);
    });

    it("throws when socket does not exist", async () => {
      const badAdapter = new ListenerClientAdapter("/tmp/nonexistent-hitl.sock");
      await expect(badAdapter.connect({ token: "" })).rejects.toThrow();
    });

    it("isConnected returns false before connect", () => {
      expect(adapter.isConnected()).toBe(false);
    });
  });

  // ------------------------------------------------------------------ awaitBinding

  describe("awaitBinding", () => {
    it("throws — binding is handled by listener/setup", async () => {
      await adapter.connect({ token: "" });
      await expect(adapter.awaitBinding()).rejects.toThrow();
    });
  });

  // ------------------------------------------------------------------ sendMessage (notify)

  describe("sendMessage", () => {
    it("sends a notify IPC message and awaits notified ack", async () => {
      await adapter.connect({ token: "" });

      const received: any[] = [];
      server.onMessage((_session, msg) => {
        received.push(msg);
        // Simulate listener acking with notified
        if (msg.type === "notify") {
          server.sendToSession(_session.sessionId, {
            type: "notified",
            requestId: msg.requestId,
            messageId: "tg_42",
          });
        }
      });

      const result = await adapter.sendMessage({ text: "Hello world" });
      expect(result.messageId).toBeDefined();
      expect(typeof result.messageId).toBe("string");

      expect(received).toHaveLength(1);
      expect(received[0].type).toBe("notify");
      expect(received[0].message).toBe("Hello world");
    });

    it("passes level and silent fields through", async () => {
      await adapter.connect({ token: "" });

      const received: any[] = [];
      server.onMessage((_session, msg) => {
        received.push(msg);
        if (msg.type === "notify") {
          server.sendToSession(_session.sessionId, {
            type: "notified",
            requestId: msg.requestId,
            messageId: "tg_99",
          });
        }
      });

      await adapter.sendMessage({ text: "Warning!", level: "warning", silent: true });

      expect(received[0].level).toBe("warning");
      expect(received[0].silent).toBe(true);
    });

    it("uses incrementing requestIds for successive notifies", async () => {
      await adapter.connect({ token: "" });

      const requestIds: string[] = [];
      server.onMessage((_session, msg) => {
        if (msg.type === "notify") {
          requestIds.push(msg.requestId);
          server.sendToSession(_session.sessionId, {
            type: "notified",
            requestId: msg.requestId,
            messageId: `tg_${msg.requestId}`,
          });
        }
      });

      await adapter.sendMessage({ text: "first" });
      await adapter.sendMessage({ text: "second" });

      expect(requestIds).toHaveLength(2);
      expect(requestIds[0]).not.toBe(requestIds[1]);
    });

    it("returns the messageId from notified ack", async () => {
      await adapter.connect({ token: "" });

      server.onMessage((_session, msg) => {
        if (msg.type === "notify") {
          server.sendToSession(_session.sessionId, {
            type: "notified",
            requestId: msg.requestId,
            messageId: "tg_telegram_msg_id",
          });
        }
      });

      const result = await adapter.sendMessage({ text: "test" });
      expect(result.messageId).toBe("tg_telegram_msg_id");
    });

    it("throws when not connected", async () => {
      await expect(adapter.sendMessage({ text: "test" })).rejects.toThrow();
    });
  });

  // ------------------------------------------------------------------ sendInteractiveMessage (ask)

  describe("sendInteractiveMessage", () => {
    it("sends an ask IPC message and returns messageId immediately", async () => {
      await adapter.connect({ token: "" });

      const received: any[] = [];
      server.onMessage((_session, msg) => received.push(msg));

      const result = await adapter.sendInteractiveMessage({
        text: "Choose a DB",
        requestId: "req-abc",
        options: [
          { text: "Postgres", isDefault: true },
          { text: "MySQL" },
        ],
        priority: "architecture",
      });

      // Give time for IPC message to arrive
      await new Promise((r) => setTimeout(r, 100));

      expect(result.messageId).toBe("req-abc");
      expect(received).toHaveLength(1);
      expect(received[0].type).toBe("ask");
      expect(received[0].requestId).toBe("req-abc");
      expect(received[0].message).toBe("Choose a DB");
      expect(received[0].priority).toBe("architecture");
      expect(received[0].options).toHaveLength(2);
    });

    it("sends ask message even when context is provided (context is ChatAdapter-level, not in IPC protocol)", async () => {
      await adapter.connect({ token: "" });

      const received: any[] = [];
      server.onMessage((_session, msg) => received.push(msg));

      await adapter.sendInteractiveMessage({
        text: "Proceed?",
        requestId: "req-ctx",
        context: "About to migrate the database",
        priority: "critical",
      });

      await new Promise((r) => setTimeout(r, 100));

      // context is not a field in AskMessage (IPC protocol) — the message
      // should still be delivered; the context field is silently dropped.
      expect(received).toHaveLength(1);
      expect(received[0].type).toBe("ask");
      expect(received[0].requestId).toBe("req-ctx");
      expect(received[0].priority).toBe("critical");
    });

    it("throws when not connected", async () => {
      await expect(
        adapter.sendInteractiveMessage({
          text: "test",
          requestId: "req-x",
          priority: "preference",
        })
      ).rejects.toThrow();
    });
  });

  // ------------------------------------------------------------------ editMessage

  describe("editMessage", () => {
    it("is a no-op (resolves without error)", async () => {
      await adapter.connect({ token: "" });
      await expect(
        adapter.editMessage({ messageId: "tg_42", text: "Updated text" })
      ).resolves.toBeUndefined();
    });

    it("resolves even when not connected", async () => {
      await expect(
        adapter.editMessage({ messageId: "tg_42", text: "Updated text" })
      ).resolves.toBeUndefined();
    });
  });

  // ------------------------------------------------------------------ onMessage / response routing

  describe("onMessage / response routing", () => {
    it("translates IPC response to InboundMessage for button tap", async () => {
      await adapter.connect({ token: "" });

      const messages: InboundMessage[] = [];
      adapter.onMessage((msg) => messages.push(msg));

      const session = server.getSessions()[0];
      server.sendToSession(session.sessionId, {
        type: "response",
        requestId: "req-1",
        text: "Postgres",
        selectedIndex: 0,
        isButtonTap: true,
      });

      await new Promise((r) => setTimeout(r, 100));

      expect(messages).toHaveLength(1);
      expect(messages[0]).toEqual({
        text: "Postgres",
        messageId: "req-1",
        isButtonTap: true,
        selectedIndex: 0,
        callbackData: "req-1",
      });
    });

    it("translates IPC response for text reply (non-button tap)", async () => {
      await adapter.connect({ token: "" });

      const messages: InboundMessage[] = [];
      adapter.onMessage((msg) => messages.push(msg));

      const session = server.getSessions()[0];
      server.sendToSession(session.sessionId, {
        type: "response",
        requestId: "req-2",
        text: "yes",
        isButtonTap: false,
      });

      await new Promise((r) => setTimeout(r, 100));

      expect(messages).toHaveLength(1);
      expect(messages[0].text).toBe("yes");
      expect(messages[0].isButtonTap).toBe(false);
      expect(messages[0].selectedIndex).toBeUndefined();
      expect(messages[0].callbackData).toBe("req-2");
    });

    it("ignores non-response server messages (does not crash)", async () => {
      await adapter.connect({ token: "" });

      const messages: InboundMessage[] = [];
      adapter.onMessage((msg) => messages.push(msg));

      const session = server.getSessions()[0];
      // Send a timeout message — should be silently ignored by the response handler
      server.sendToSession(session.sessionId, {
        type: "timeout",
        requestId: "req-3",
      });

      await new Promise((r) => setTimeout(r, 100));
      expect(messages).toHaveLength(0);
    });
  });

  // ------------------------------------------------------------------ quiet_hours_changed

  describe("quiet_hours_changed handling", () => {
    it("forwards quiet_hours_changed to registered handler", async () => {
      await adapter.connect({ token: "" });

      const changes: any[] = [];
      adapter.onQuietHoursChanged((qh) => changes.push(qh));

      const session = server.getSessions()[0];
      server.sendToSession(session.sessionId, {
        type: "quiet_hours_changed",
        quietHours: {
          enabled: true,
          manual: false,
          start: "22:00",
          end: "08:00",
          timezone: "America/Chicago",
          behavior: "queue",
        },
      });

      await new Promise((r) => setTimeout(r, 100));

      expect(changes).toHaveLength(1);
      expect(changes[0].enabled).toBe(true);
      expect(changes[0].start).toBe("22:00");
    });

    it("does not throw when no quiet_hours handler registered", async () => {
      await adapter.connect({ token: "" });

      const session = server.getSessions()[0];
      // Sending quiet_hours_changed with no handler registered should not throw
      expect(() => {
        server.sendToSession(session.sessionId, {
          type: "quiet_hours_changed",
          quietHours: { enabled: false, manual: false },
        });
      }).not.toThrow();

      await new Promise((r) => setTimeout(r, 100));
    });
  });

  // ------------------------------------------------------------------ session identity

  describe("session identity", () => {
    it("registers a session with project name derived from cwd", async () => {
      await adapter.connect({ token: "" });

      const sessions = server.getSessions();
      expect(sessions).toHaveLength(1);
      // Project name should be a non-empty string (basename of git root or cwd)
      expect(sessions[0].project).toBeTruthy();
      expect(typeof sessions[0].project).toBe("string");
    });

    it("generates a unique sessionId per instance", async () => {
      const socketPath2 = makeSocketPath();
      const server2 = new IpcServer(socketPath2, { maxConnections: 10 });
      await server2.start();

      const adapter2 = new ListenerClientAdapter(socketPath2);
      try {
        await adapter.connect({ token: "" });
        await adapter2.connect({ token: "" });

        const s1 = server.getSessions()[0];
        const s2 = server2.getSessions()[0];
        expect(s1.sessionId).not.toBe(s2.sessionId);
      } finally {
        await adapter2.disconnect();
        await server2.stop();
      }
    });
  });
});
