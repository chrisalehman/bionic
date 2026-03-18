import { describe, it, expect } from "vitest";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { buildMessage } from "../bin/session-start.mjs";

const SCRIPT = resolve(import.meta.dirname, "../bin/session-start.mjs");

describe("buildMessage", () => {
  const baseInput = { session_id: "sess-abc", cwd: "/Users/dev/my-project" };

  it("returns null when session_id is missing", () => {
    expect(buildMessage({}, {})).toBeNull();
  });

  it("produces local message when no RC env vars set", () => {
    const result = buildMessage({}, baseInput);
    expect(result!.text).toContain("(local)");
    expect(result!.text).toContain("[my-project]");
    expect(result!.text).not.toContain("https://claude.ai/code/");
  });

  it("produces RC message when CLAUDE_CODE_SESSION_ACCESS_TOKEN is set", () => {
    const env = { CLAUDE_CODE_SESSION_ACCESS_TOKEN: "sk-ant-si-xxx" };
    const result = buildMessage(env, baseInput);
    expect(result!.text).toContain("https://claude.ai/code/sess-abc");
    expect(result!.text).not.toContain("(local)");
  });

  it("produces RC message when CLAUDE_CODE_REMOTE is true", () => {
    const env = { CLAUDE_CODE_REMOTE: "true" };
    const result = buildMessage(env, baseInput);
    expect(result!.text).toContain("https://claude.ai/code/sess-abc");
    expect(result!.text).not.toContain("(local)");
  });

  it("produces RC message when both RC signals are set", () => {
    const env = {
      CLAUDE_CODE_REMOTE: "true",
      CLAUDE_CODE_SESSION_ACCESS_TOKEN: "sk-ant-si-xxx",
    };
    const result = buildMessage(env, baseInput);
    expect(result!.text).toContain("https://claude.ai/code/sess-abc");
  });

  it("omits project prefix when cwd is missing", () => {
    const result = buildMessage({}, { session_id: "sess-abc" });
    expect(result!.text).not.toContain("[");
    expect(result!.text).toContain("(local)");
  });

  it("includes session ID in returned object", () => {
    const result = buildMessage({}, baseInput);
    expect(result!.sessionId).toBe("sess-abc");
  });
});

describe("session-start hook (subprocess)", () => {
  const env = {
    NUDGE_TELEGRAM_TOKEN: "test-token",
    NUDGE_TELEGRAM_CHAT_ID: "12345",
    PATH: process.env.PATH,
    HOME: process.env.HOME,
  };

  it("exits silently when NUDGE_TELEGRAM_TOKEN is missing", () => {
    execFileSync("node", [SCRIPT], {
      input: JSON.stringify({ session_id: "abc", cwd: "/tmp/project" }),
      env: { PATH: process.env.PATH },
      timeout: 5000,
      encoding: "utf8",
    });
  });

  it("exits silently when session_id is missing", () => {
    execFileSync("node", [SCRIPT], {
      input: JSON.stringify({ cwd: "/tmp/project" }),
      env,
      timeout: 5000,
      encoding: "utf8",
    });
  });

  it("exits silently on invalid JSON input", () => {
    execFileSync("node", [SCRIPT], {
      input: "not json",
      env,
      timeout: 5000,
      encoding: "utf8",
    });
  });

  it("does not crash with valid input (fetch will fail silently)", () => {
    execFileSync("node", [SCRIPT], {
      input: JSON.stringify({
        session_id: "test-session-123",
        cwd: "/Users/dev/my-project",
      }),
      env: { ...env, NUDGE_TELEGRAM_TOKEN: "invalid-token" },
      timeout: 5000,
      encoding: "utf8",
    });
  });
});
