import { describe, it, expect, vi, beforeEach } from "vitest";
import { HitlToolHandler } from "../src/tools.js";
import type { ChatAdapter, AdapterConfig } from "../src/types.js";

function createMockAdapter(): ChatAdapter {
  return {
    name: "mock",
    capabilities: {
      inlineButtons: true,
      threading: false,
      messageEditing: true,
      silentMessages: true,
      richFormatting: true,
    },
    connect: vi.fn().mockResolvedValue(undefined),
    disconnect: vi.fn().mockResolvedValue(undefined),
    isConnected: vi.fn().mockReturnValue(true),
    awaitBinding: vi.fn().mockResolvedValue({
      userId: "u1",
      displayName: "Test",
      chatId: "c1",
    }),
    sendMessage: vi.fn().mockResolvedValue({ messageId: "m1" }),
    sendInteractiveMessage: vi.fn().mockResolvedValue({ messageId: "m2" }),
    editMessage: vi.fn().mockResolvedValue(undefined),
    onMessage: vi.fn(),
  };
}

describe("HitlToolHandler", () => {
  let handler: HitlToolHandler;
  let adapter: ChatAdapter;

  beforeEach(() => {
    adapter = createMockAdapter();
    handler = new HitlToolHandler(adapter);
  });

  describe("notify_human", () => {
    it("sends a message via adapter and returns immediately", async () => {
      const result = await handler.notifyHuman({
        message: "Build complete",
        level: "success",
      });
      expect(result.status).toBe("sent");
      expect(result.message_id).toBe("m1");
      expect(adapter.sendMessage).toHaveBeenCalledWith({
        text: "Build complete",
        level: "success",
        silent: undefined,
      });
    });

    it("returns error status when adapter.sendMessage throws", async () => {
      (adapter.sendMessage as any).mockRejectedValue(new Error("Network error"));
      const result = await handler.notifyHuman({ message: "Test" });
      expect(result.status).toBe("error");
      expect(result.message_id).toBe("");
    });

    it("prefixes message with session context when configured", async () => {
      await handler.configureHitl({ session_context: "auth-feature" });
      await handler.notifyHuman({ message: "Done" });
      expect(adapter.sendMessage).toHaveBeenCalledWith(
        expect.objectContaining({ text: "[auth-feature]\n\nDone" }),
      );
    });
  });

  describe("configure_hitl", () => {
    it("applies session context and returns merged config", async () => {
      const result = await handler.configureHitl({
        session_context: "Working on auth",
        timeout_overrides: { architecture: 60 },
      });
      expect(result.status).toBe("configured");
      expect(result.active_config.session_context).toBe("Working on auth");
      expect(result.active_config.timeouts.architecture).toBe(60);
    });

    it("propagates plan_path via sendConfigure", async () => {
      adapter.sendConfigure = vi.fn();
      await handler.configureHitl({
        session_context: "Working on X",
        plan_path: "/path/to/plan.md",
      });
      expect(adapter.sendConfigure).toHaveBeenCalledWith(
        "Working on X",
        undefined,
        "/path/to/plan.md",
      );
    });
  });

  describe("ask_human", () => {
    it("sends interactive message and resolves on adapter response", async () => {
      // Set up the adapter to capture the onMessage handler
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

      // Simulate user tapping "Postgres" button
      await vi.waitFor(() => {
        expect(adapter.sendInteractiveMessage).toHaveBeenCalled();
      });
      const callArgs = (adapter.sendInteractiveMessage as any).mock.calls[0][0];
      const requestId = callArgs.requestId;

      capturedHandler({
        text: "Postgres",
        messageId: "m2",
        isButtonTap: true,
        selectedIndex: 1,
        callbackData: requestId,
      });

      const result = await askPromise;
      expect(result.status).toBe("answered");
      expect(result.response).toBe("Postgres");
      expect(result.selected_option).toBe(1);
    });

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

    it("returns error when adapter.sendInteractiveMessage throws", async () => {
      (adapter.sendInteractiveMessage as any).mockRejectedValue(new Error("Send failed"));
      const result = await handler.askHuman({
        message: "Pick one",
        priority: "preference",
        options: [{ text: "A" }],
      });
      expect(result.status).toBe("error");
      expect(result.response).toContain("Failed to send message");
      expect(result.priority).toBe("preference");
    });

    it("auto-resolves during quiet hours for preference priority", async () => {
      await handler.configureHitl({});
      const now = new Date();
      const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
      const currentTime = now.toLocaleTimeString("en-US", {
        hour12: false,
        hour: "2-digit",
        minute: "2-digit",
        timeZone: tz,
      });
      const [h, m] = currentTime.split(":").map(Number);
      const startH = (h - 1 + 24) % 24;
      const endH = (h + 1) % 24;
      const start = `${String(startH).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
      const end = `${String(endH).padStart(2, "0")}:${String(m).padStart(2, "0")}`;

      const engine = (handler as any).engine;
      engine.setQuietHours({ start, end, timezone: tz, behavior: "skip_preference" });

      const result = await handler.askHuman({
        message: "Pick a color",
        priority: "preference",
        options: [{ text: "Blue", default: true }, { text: "Red" }],
      });

      expect(result.status).toBe("timed_out");
      expect(result.timed_out_action).toBe("used_default");
      expect(result.response).toBe("Blue");
      expect(result.selected_option).toBe(0);
      expect(result.response_time_seconds).toBe(0);
      expect(adapter.sendInteractiveMessage).not.toHaveBeenCalled();
    });

    it("prefixes ask message with session context", async () => {
      let capturedHandler: any;
      (adapter.onMessage as any).mockImplementation((h: any) => { capturedHandler = h; });
      handler = new HitlToolHandler(adapter);

      await handler.configureHitl({ session_context: "db-migration" });

      const askPromise = handler.askHuman({
        message: "Proceed?",
        priority: "preference",
        options: [{ text: "Yes" }],
        timeout_minutes: 1,
      });

      await vi.waitFor(() => { expect(adapter.sendInteractiveMessage).toHaveBeenCalled(); });
      const callArgs = (adapter.sendInteractiveMessage as any).mock.calls[0][0];
      expect(callArgs.text).toContain("[db-migration]");
      expect(callArgs.text).toContain("Proceed?");

      capturedHandler({
        text: "Yes",
        messageId: "m2",
        isButtonTap: true,
        selectedIndex: 0,
        callbackData: callArgs.requestId,
      });
      await askPromise;
    });

    it("edits message with confirmation after response", async () => {
      let capturedHandler: any;
      (adapter.onMessage as any).mockImplementation((h: any) => { capturedHandler = h; });
      handler = new HitlToolHandler(adapter);

      const askPromise = handler.askHuman({
        message: "Pick one",
        priority: "preference",
        options: [{ text: "A" }, { text: "B" }],
        timeout_minutes: 1,
      });

      await vi.waitFor(() => { expect(adapter.sendInteractiveMessage).toHaveBeenCalled(); });
      const callArgs = (adapter.sendInteractiveMessage as any).mock.calls[0][0];

      capturedHandler({
        text: "B",
        messageId: "m2",
        isButtonTap: true,
        selectedIndex: 1,
        callbackData: callArgs.requestId,
      });

      await askPromise;

      expect(adapter.editMessage).toHaveBeenCalledWith(
        expect.objectContaining({
          messageId: "m2",
          text: expect.stringContaining("Got it — continuing with: B"),
        }),
      );
    });

    it("does not edit message when adapter lacks messageEditing capability", async () => {
      (adapter as any).capabilities.messageEditing = false;
      let capturedHandler: any;
      (adapter.onMessage as any).mockImplementation((h: any) => { capturedHandler = h; });
      handler = new HitlToolHandler(adapter);

      const askPromise = handler.askHuman({
        message: "Pick one",
        priority: "preference",
        options: [{ text: "A" }],
        timeout_minutes: 1,
      });

      await vi.waitFor(() => { expect(adapter.sendInteractiveMessage).toHaveBeenCalled(); });
      const callArgs = (adapter.sendInteractiveMessage as any).mock.calls[0][0];

      capturedHandler({
        text: "A",
        messageId: "m2",
        isButtonTap: true,
        selectedIndex: 0,
        callbackData: callArgs.requestId,
      });

      await askPromise;
      expect(adapter.editMessage).not.toHaveBeenCalled();
    });
  });
});
