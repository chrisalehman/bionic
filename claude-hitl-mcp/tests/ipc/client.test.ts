// tests/ipc/client.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { IpcClient } from "../../src/ipc/client.js";
import { IpcServer } from "../../src/ipc/server.js";
import * as os from "node:os";
import * as path from "node:path";

describe("IpcClient", () => {
  let server: IpcServer;
  let client: IpcClient;
  let socketPath: string;

  beforeEach(async () => {
    socketPath = path.join(
      os.tmpdir(),
      `claude-hitl-test-${Date.now()}-${Math.random().toString(36).slice(2)}.sock`
    );
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();
  });

  afterEach(async () => {
    await client?.disconnect();
    await server?.stop();
  });

  it("connects and registers with the server", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");
    expect(client.isConnected()).toBe(true);
    expect(server.getSessions()).toHaveLength(1);
  });

  it("sends messages to the server", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");

    const received: any[] = [];
    server.onMessage((_session, msg) => received.push(msg));

    client.sendNotify("notif_1", "Hello", "info", false);
    await new Promise((r) => setTimeout(r, 100));

    expect(received).toHaveLength(1);
    expect(received[0].type).toBe("notify");
    expect(received[0].message).toBe("Hello");
  });

  it("receives messages from the server", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");

    const responses: any[] = [];
    client.onMessage((msg) => responses.push(msg));

    server.sendToSession("sess1", {
      type: "response",
      requestId: "req_1",
      text: "Postgres",
      selectedIndex: 0,
      isButtonTap: true,
    });

    await new Promise((r) => setTimeout(r, 100));
    expect(responses).toHaveLength(1);
    expect(responses[0].text).toBe("Postgres");
  });

  it("disconnects gracefully with deregister", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");
    await client.disconnect();
    await new Promise((r) => setTimeout(r, 100));
    expect(server.getSessions()).toHaveLength(0);
    expect(server.getDisconnectedSessions()).toHaveLength(0);
  });

  it("throws on connect when socket does not exist", async () => {
    client = new IpcClient("/tmp/nonexistent.sock");
    await expect(
      client.connect("sess1", "project", "/tmp")
    ).rejects.toThrow();
  });

  it("reconnects with exponential backoff after server restart", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");

    await server.stop();
    await new Promise((r) => setTimeout(r, 200));
    expect(client.isConnected()).toBe(false);

    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();

    await new Promise((r) => setTimeout(r, 3000));
    expect(client.isConnected()).toBe(true);
    expect(server.getSessions()).toHaveLength(1);
  }, 10000);

  it("handles shutdown message and triggers reconnection", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");

    server.sendToSession("sess1", { type: "shutdown" });
    await new Promise((r) => setTimeout(r, 200));
    expect(client.isConnected()).toBe(false);
  });
});
