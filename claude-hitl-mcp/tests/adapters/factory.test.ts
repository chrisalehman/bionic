import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { createAdapter } from "../../src/adapters/factory.js";
import { ListenerClientAdapter } from "../../src/adapters/listener-client.js";
import { TelegramAdapter } from "../../src/adapters/telegram.js";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import * as net from "node:net";

describe("createAdapter", () => {
  let socketPath: string;
  let tempServer: net.Server;

  beforeEach(() => {
    socketPath = path.join(os.tmpdir(), `hitl-af-${Date.now()}.sock`);
  });

  afterEach(() => {
    tempServer?.close();
    try { fs.unlinkSync(socketPath); } catch {}
  });

  it("returns ListenerClientAdapter when socket exists", async () => {
    tempServer = net.createServer();
    await new Promise<void>((r) => tempServer.listen(socketPath, r));
    const adapter = createAdapter(socketPath);
    expect(adapter).toBeInstanceOf(ListenerClientAdapter);
  });

  it("returns TelegramAdapter when socket does not exist", () => {
    const adapter = createAdapter("/tmp/nonexistent.sock");
    expect(adapter).toBeInstanceOf(TelegramAdapter);
  });

  it("returns TelegramAdapter when path exists but is not a socket", () => {
    fs.writeFileSync(socketPath, "not a socket");
    const adapter = createAdapter(socketPath);
    expect(adapter).toBeInstanceOf(TelegramAdapter);
    fs.unlinkSync(socketPath);
  });
});
