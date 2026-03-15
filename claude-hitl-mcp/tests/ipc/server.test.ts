// tests/ipc/server.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { IpcServer } from "../../src/ipc/server.js";
import { IpcClient } from "../../src/ipc/client.js";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

describe("IpcServer", () => {
  let server: IpcServer;
  let socketPath: string;

  beforeEach(() => {
    socketPath = path.join(
      os.tmpdir(),
      `claude-hitl-test-${Date.now()}-${Math.random().toString(36).slice(2)}.sock`
    );
  });

  afterEach(async () => {
    await server?.stop();
    try { fs.unlinkSync(socketPath); } catch {}
  });

  it("starts and creates socket file", async () => {
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();
    expect(fs.existsSync(socketPath)).toBe(true);
  });

  it("cleans up stale socket on start", async () => {
    fs.writeFileSync(socketPath, "stale");
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();
    expect(fs.existsSync(socketPath)).toBe(true);
  });

  it("tracks sessions after registration", async () => {
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();

    const client = new IpcClient(socketPath);
    await client.connect("sess1", "test-project", "/tmp/project");
    await new Promise((r) => setTimeout(r, 100));

    const sessions = server.getSessions();
    expect(sessions).toHaveLength(1);
    expect(sessions[0].sessionId).toBe("sess1");
    expect(sessions[0].project).toBe("test-project");

    await client.disconnect();
  });

  it("removes session on disconnect", async () => {
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();

    const client = new IpcClient(socketPath);
    await client.connect("sess1", "test-project", "/tmp/project");
    await new Promise((r) => setTimeout(r, 100));
    expect(server.getSessions()).toHaveLength(1);

    await client.disconnect();
    await new Promise((r) => setTimeout(r, 100));
    expect(server.getSessions()).toHaveLength(0);
  });

  it("rejects connections over max limit", async () => {
    server = new IpcServer(socketPath, { maxConnections: 1 });
    await server.start();

    const client1 = new IpcClient(socketPath);
    await client1.connect("sess1", "test-project", "/tmp/p1");
    await new Promise((r) => setTimeout(r, 100));

    const client2 = new IpcClient(socketPath);
    await expect(
      client2.connect("sess2", "test-project", "/tmp/p2")
    ).rejects.toThrow(/max_connections/);

    await client1.disconnect();
  });

  it("stops cleanly and removes socket", async () => {
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();
    await server.stop();
    expect(fs.existsSync(socketPath)).toBe(false);
  });
});
