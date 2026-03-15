# HITL Status Listener Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent listener daemon that owns the Telegram bot, enabling `/status`, `/quiet`, `/help` commands from Telegram, and refactor the MCP server to communicate through the listener via Unix socket IPC.

**Architecture:** The listener daemon (launchd user agent) owns the Telegram bot connection and handles bot commands. MCP servers connect to the listener over a Unix socket at `~/.claude-hitl/sock` using a JSON-line IPC protocol. A new `ListenerClientAdapter` implements `ChatAdapter` over IPC, while the existing `TelegramAdapter` is preserved for fallback.

**Tech Stack:** Node.js, TypeScript, node-telegram-bot-api, Unix sockets (net module), launchd, vitest

**Spec:** `docs/superpowers/specs/2026-03-15-hitl-status-listener-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `src/ipc/protocol.ts` | IPC message type definitions, serialization/deserialization, protocol version constant |
| `src/ipc/server.ts` | Unix socket server for the listener; accepts connections, tracks sessions, routes messages |
| `src/ipc/client.ts` | Unix socket client for MCP server; connects, reconnects with backoff, sends/receives |
| `src/adapters/listener-client.ts` | `ListenerClientAdapter` implementing `ChatAdapter` over IPC |
| `src/adapters/factory.ts` | Adapter factory: picks `ListenerClientAdapter` or `TelegramAdapter` based on socket availability |
| `src/listener.ts` | Listener daemon entrypoint; wires Telegram bot + IPC server + command handlers |
| `src/commands/status.ts` | `/status` command handler; reads sessions, `_plan.md`, formats response |
| `src/commands/quiet.ts` | `/quiet` command handler; toggle UI with inline buttons |
| `src/commands/help.ts` | `/help` command handler |
| `tests/ipc/protocol.test.ts` | Protocol serialization/deserialization tests |
| `tests/ipc/server.test.ts` | IPC server lifecycle, session tracking, routing tests |
| `tests/ipc/client.test.ts` | IPC client connect, reconnect, send/receive tests |
| `tests/adapters/listener-client.test.ts` | ListenerClientAdapter tests |
| `tests/adapters/factory.test.ts` | Adapter factory selection tests |
| `tests/commands/status.test.ts` | Status command formatting and plan reading tests |
| `tests/commands/quiet.test.ts` | Quiet toggle and persistence tests |
| `tests/listener.test.ts` | Listener integration tests |
| `tests/integration/multi-session.test.ts` | Multi-session routing integration tests |

### Modified Files
| File | Changes |
|------|---------|
| `src/config.ts` | Update `DEFAULT_CONFIG_PATH` to `~/.claude-hitl/config.json`; add migration function; add `ensureConfigDir()` |
| `src/types.ts` | Remove `quiet_hours` from `ConfigureHitlInput`; add `QuietHoursState` type with `manualOverride` |
| `src/server.ts` | Use adapter factory instead of direct `TelegramAdapter`; remove `quiet_hours` from `configure_hitl` schema |
| `src/tools.ts` | Remove quiet hours from `configureHitl()`; handle `quiet_hours_changed` IPC messages |
| `src/cli.ts` | Add `install-listener`, `uninstall-listener`, `start-listener`, `stop-listener`, `listener-logs` commands; update `setup` to install daemon; update config paths |
| `src/priority-engine.ts` | No API changes; `setQuietHours` now called from IPC push rather than `configure_hitl` |
| `tests/config.test.ts` | Add migration tests |
| `tests/tools.test.ts` | Update for removed quiet_hours from configure_hitl |

---

## Chunk 1: IPC Protocol & Client/Server

### Task 1: IPC Protocol Types

**Files:**
- Create: `src/ipc/protocol.ts`
- Test: `tests/ipc/protocol.test.ts`

- [ ] **Step 1: Write failing tests for protocol serialization**

```typescript
// tests/ipc/protocol.test.ts
import { describe, it, expect } from "vitest";
import {
  PROTOCOL_VERSION,
  serialize,
  deserialize,
  type RegisterMessage,
  type RegisteredMessage,
  type ErrorMessage,
} from "../../src/ipc/protocol.js";

describe("IPC Protocol", () => {
  describe("serialize", () => {
    it("serializes a message to a JSON line", () => {
      const msg: RegisterMessage = {
        type: "register",
        protocolVersion: PROTOCOL_VERSION,
        sessionId: "abc123",
        project: "test-project",
        cwd: "/home/user/project",
      };
      const line = serialize(msg);
      expect(line).toBe(JSON.stringify(msg) + "\n");
    });

    it("handles messages with optional fields omitted", () => {
      const msg: RegisterMessage = {
        type: "register",
        protocolVersion: PROTOCOL_VERSION,
        sessionId: "abc123",
        project: "test-project",
        cwd: "/home/user/project",
      };
      const parsed = JSON.parse(serialize(msg).trim());
      expect(parsed.worktree).toBeUndefined();
    });
  });

  describe("deserialize", () => {
    it("deserializes a JSON line to a message", () => {
      const msg: RegisterMessage = {
        type: "register",
        protocolVersion: PROTOCOL_VERSION,
        sessionId: "abc123",
        project: "test-project",
        cwd: "/home/user/project",
      };
      const result = deserialize(JSON.stringify(msg));
      expect(result).toEqual(msg);
    });

    it("throws on invalid JSON", () => {
      expect(() => deserialize("not json")).toThrow();
    });

    it("throws on message missing type field", () => {
      expect(() => deserialize('{"sessionId":"abc"}')).toThrow(/type/);
    });
  });

  describe("PROTOCOL_VERSION", () => {
    it("is 1", () => {
      expect(PROTOCOL_VERSION).toBe(1);
    });
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/protocol.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement protocol types and serialization**

```typescript
// src/ipc/protocol.ts
export const PROTOCOL_VERSION = 1;

// --- MCP Server → Listener messages ---

export interface RegisterMessage {
  type: "register";
  protocolVersion: number;
  sessionId: string;
  project: string;
  cwd: string;
  worktree?: string;
}

export interface ConfigureMessage {
  type: "configure";
  sessionId: string;
  sessionContext?: string;
  timeoutOverrides?: { architecture?: number; preference?: number };
}

export interface AskMessage {
  type: "ask";
  sessionId: string;
  requestId: string;
  message: string;
  priority: "critical" | "architecture" | "preference";
  options?: Array<{ text: string; description?: string; isDefault?: boolean }>;
  defaultIndex?: number;
  timeoutMinutes?: number;
}

export interface NotifyMessage {
  type: "notify";
  sessionId: string;
  requestId: string;
  message: string;
  level?: "info" | "success" | "warning" | "error";
  silent?: boolean;
}

export interface DeregisterMessage {
  type: "deregister";
  sessionId: string;
}

export type ClientMessage =
  | RegisterMessage
  | ConfigureMessage
  | AskMessage
  | NotifyMessage
  | DeregisterMessage;

// --- Listener → MCP Server messages ---

export interface RegisteredMessage {
  type: "registered";
  sessionId: string;
  protocolVersion: number;
}

export interface ResponseMessage {
  type: "response";
  requestId: string;
  text: string;
  selectedIndex?: number;
  isButtonTap: boolean;
}

export interface TimeoutMessage {
  type: "timeout";
  requestId: string;
  defaultIndex?: number;
}

export interface NotifiedMessage {
  type: "notified";
  requestId: string;
  messageId: string;
}

export interface QuietHoursChangedMessage {
  type: "quiet_hours_changed";
  quietHours: {
    enabled: boolean;
    manual: boolean;
    start?: string;
    end?: string;
    timezone?: string;
    behavior?: "queue" | "skip_preference";
  };
}

export interface ShutdownMessage {
  type: "shutdown";
}

export interface ErrorMessage {
  type: "error";
  requestId?: string;
  code:
    | "unknown_session"
    | "protocol_mismatch"
    | "delivery_failed"
    | "invalid_message"
    | "max_connections";
  message: string;
}

export type ServerMessage =
  | RegisteredMessage
  | ResponseMessage
  | TimeoutMessage
  | NotifiedMessage
  | QuietHoursChangedMessage
  | ShutdownMessage
  | ErrorMessage;

export type IpcMessage = ClientMessage | ServerMessage;

export function serialize(msg: IpcMessage): string {
  return JSON.stringify(msg) + "\n";
}

export function deserialize(line: string): IpcMessage {
  const parsed = JSON.parse(line.trim());
  if (!parsed || typeof parsed.type !== "string") {
    throw new Error("Invalid IPC message: missing type field");
  }
  return parsed as IpcMessage;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/protocol.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/ipc/protocol.ts tests/ipc/protocol.test.ts
git commit -m "feat: add IPC protocol types and serialization"
```

---

### Task 2: IPC Server (Listener Side)

**Files:**
- Create: `src/ipc/server.ts`
- Test: `tests/ipc/server.test.ts`

- [ ] **Step 1: Write failing tests for IPC server**

```typescript
// tests/ipc/server.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { IpcServer, type SessionInfo } from "../../src/ipc/server.js";
import { IpcClient } from "../../src/ipc/client.js";
import { PROTOCOL_VERSION } from "../../src/ipc/protocol.js";
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
    // Create a stale socket file
    fs.writeFileSync(socketPath, "stale");
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();
    expect(fs.existsSync(socketPath)).toBe(true);
  });

  it("tracks sessions after registration", async () => {
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();

    // Simulate a client connecting
    const client = new IpcClient(socketPath);
    await client.connect("sess1", "test-project", "/tmp/project");

    // Wait for registration
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/server.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement IPC server**

```typescript
// src/ipc/server.ts
import * as net from "node:net";
import * as fs from "node:fs";
import {
  PROTOCOL_VERSION,
  serialize,
  deserialize,
  type ClientMessage,
  type ServerMessage,
  type RegisterMessage,
} from "./protocol.js";

export interface SessionInfo {
  sessionId: string;
  project: string;
  cwd: string | null; // null if cwd validation failed (no _plan.md reading)
  worktree?: string;
  sessionContext?: string;
  connectedAt: Date;
  socket: net.Socket;
}

export interface IpcServerOptions {
  maxConnections: number;
}

export type ClientMessageHandler = (
  session: SessionInfo,
  message: ClientMessage
) => void;

export class IpcServer {
  private server: net.Server | null = null;
  private sessions = new Map<string, SessionInfo>();
  private socketToSession = new Map<net.Socket, string>();
  private disconnectedSessions = new Map<
    string,
    { project: string; lastSeen: Date }
  >();
  private messageHandler: ClientMessageHandler | null = null;

  constructor(
    private socketPath: string,
    private options: IpcServerOptions
  ) {}

  onMessage(handler: ClientMessageHandler): void {
    this.messageHandler = handler;
  }

  async start(): Promise<void> {
    // Clean up stale socket
    if (fs.existsSync(this.socketPath)) {
      fs.unlinkSync(this.socketPath);
    }

    return new Promise((resolve, reject) => {
      this.server = net.createServer((socket) => this.handleConnection(socket));
      this.server.on("error", reject);
      this.server.listen(this.socketPath, () => resolve());
    });
  }

  async stop(): Promise<void> {
    // Notify all connected sessions
    for (const session of this.sessions.values()) {
      this.send(session.socket, { type: "shutdown" });
      session.socket.destroy();
    }
    this.sessions.clear();
    this.socketToSession.clear();

    return new Promise((resolve) => {
      if (this.server) {
        this.server.close(() => {
          try {
            fs.unlinkSync(this.socketPath);
          } catch {}
          resolve();
        });
      } else {
        resolve();
      }
    });
  }

  getSessions(): SessionInfo[] {
    return Array.from(this.sessions.values());
  }

  getDisconnectedSessions(): Array<{
    project: string;
    lastSeen: Date;
  }> {
    return Array.from(this.disconnectedSessions.values());
  }

  send(socket: net.Socket, message: ServerMessage): void {
    socket.write(serialize(message));
  }

  sendToSession(sessionId: string, message: ServerMessage): boolean {
    const session = this.sessions.get(sessionId);
    if (!session) return false;
    this.send(session.socket, message);
    return true;
  }

  broadcastAll(message: ServerMessage): void {
    for (const session of this.sessions.values()) {
      this.send(session.socket, message);
    }
  }

  private handleConnection(socket: net.Socket): void {
    if (this.sessions.size >= this.options.maxConnections) {
      this.send(socket, {
        type: "error",
        code: "max_connections",
        message: `Maximum ${this.options.maxConnections} connections reached`,
      });
      socket.destroy();
      return;
    }

    let buffer = "";

    socket.on("data", (data) => {
      buffer += data.toString();
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const msg = deserialize(line) as ClientMessage;
          this.handleMessage(socket, msg);
        } catch {
          this.send(socket, {
            type: "error",
            code: "invalid_message",
            message: "Failed to parse IPC message",
          });
        }
      }
    });

    socket.on("close", () => {
      const sessionId = this.socketToSession.get(socket);
      if (sessionId) {
        const session = this.sessions.get(sessionId);
        if (session) {
          this.disconnectedSessions.set(sessionId, {
            project: session.project,
            lastSeen: new Date(),
          });
        }
        this.sessions.delete(sessionId);
        this.socketToSession.delete(socket);
      }
    });

    socket.on("error", () => {
      socket.destroy();
    });
  }

  private handleMessage(socket: net.Socket, msg: ClientMessage): void {
    if (msg.type === "register") {
      this.handleRegister(socket, msg);
      return;
    }

    // All other messages require a registered session
    const sessionId = this.socketToSession.get(socket);
    if (!sessionId) {
      this.send(socket, {
        type: "error",
        code: "unknown_session",
        message: "Must register before sending messages",
      });
      return;
    }

    if (msg.type === "configure") {
      const session = this.sessions.get(sessionId);
      if (session) {
        session.sessionContext = msg.sessionContext;
      }
    }

    if (msg.type === "deregister") {
      this.sessions.delete(sessionId);
      this.socketToSession.delete(socket);
      // Graceful deregister — no "last seen" record
      this.disconnectedSessions.delete(sessionId);
      socket.destroy();
      return;
    }

    const session = this.sessions.get(sessionId);
    if (session && this.messageHandler) {
      this.messageHandler(session, msg);
    }
  }

  private handleRegister(socket: net.Socket, msg: RegisterMessage): void {
    if (msg.protocolVersion !== PROTOCOL_VERSION) {
      this.send(socket, {
        type: "error",
        code: "protocol_mismatch",
        message: `Expected protocol version ${PROTOCOL_VERSION}, got ${msg.protocolVersion}`,
      });
      socket.destroy();
      return;
    }

    // Validate cwd is under home directory — if not, record as null (no _plan.md reading)
    const home = process.env.HOME ?? "";
    const validCwd = home && msg.cwd.startsWith(home) ? msg.cwd : null;

    const session: SessionInfo = {
      sessionId: msg.sessionId,
      project: msg.project,
      cwd: validCwd,
      worktree: msg.worktree,
      connectedAt: new Date(),
      socket,
    };

    this.sessions.set(msg.sessionId, session);
    this.socketToSession.set(socket, msg.sessionId);
    this.disconnectedSessions.delete(msg.sessionId);

    this.send(socket, {
      type: "registered",
      sessionId: msg.sessionId,
      protocolVersion: PROTOCOL_VERSION,
    });
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/server.test.ts`
Expected: PASS

**Note:** Server tests import `IpcClient` from Task 3. Implement Tasks 2 and 3 together — write both source files before running either test suite. Run `npx vitest run tests/ipc/` after both are complete.

- [ ] **Step 5: Commit**

```bash
git add src/ipc/server.ts tests/ipc/server.test.ts
git commit -m "feat: add IPC server for listener daemon"
```

---

### Task 3: IPC Client (MCP Server Side)

**Files:**
- Create: `src/ipc/client.ts`
- Test: `tests/ipc/client.test.ts`

- [ ] **Step 1: Write failing tests for IPC client**

```typescript
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

    // Simulate server sending a response
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
    // Graceful deregister should not leave a disconnected record
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

    // Kill the server
    await server.stop();
    await new Promise((r) => setTimeout(r, 200));
    expect(client.isConnected()).toBe(false);

    // Restart the server
    server = new IpcServer(socketPath, { maxConnections: 10 });
    await server.start();

    // Client should reconnect automatically
    await new Promise((r) => setTimeout(r, 3000));
    expect(client.isConnected()).toBe(true);
    expect(server.getSessions()).toHaveLength(1);
  }, 10000);

  it("handles shutdown message and triggers reconnection", async () => {
    client = new IpcClient(socketPath);
    await client.connect("sess1", "my-project", "/tmp/project");

    // Server sends shutdown
    server.sendToSession("sess1", { type: "shutdown" });
    await new Promise((r) => setTimeout(r, 200));

    // Client should be disconnected but attempting to reconnect
    expect(client.isConnected()).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/client.test.ts`
Expected: FAIL — module not found

- [ ] **Step 3: Implement IPC client**

```typescript
// src/ipc/client.ts
import * as net from "node:net";
import {
  PROTOCOL_VERSION,
  serialize,
  deserialize,
  type ClientMessage,
  type ServerMessage,
} from "./protocol.js";

type ServerMessageHandler = (message: ServerMessage) => void;

const BACKOFF_INITIAL_MS = 1000;
const BACKOFF_MAX_MS = 30000;
const BACKOFF_MULTIPLIER = 2;

export class IpcClient {
  private socket: net.Socket | null = null;
  private sessionId = "";
  private project = "";
  private cwd = "";
  private worktree?: string;
  private connected = false;
  private intentionalDisconnect = false;
  private messageHandler: ServerMessageHandler | null = null;
  private buffer = "";
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectDelay = BACKOFF_INITIAL_MS;

  constructor(private socketPath: string) {}

  async connect(
    sessionId: string,
    project: string,
    cwd: string,
    worktree?: string
  ): Promise<void> {
    this.sessionId = sessionId;
    this.project = project;
    this.cwd = cwd;
    this.worktree = worktree;
    this.intentionalDisconnect = false;
    return this.doConnect();
  }

  private doConnect(): Promise<void> {
    return new Promise((resolve, reject) => {
      const isReconnect = this.connected === false && this.sessionId !== "";

      this.socket = net.createConnection(this.socketPath, () => {
        this.sendRaw({
          type: "register",
          protocolVersion: PROTOCOL_VERSION,
          sessionId: this.sessionId,
          project: this.project,
          cwd: this.cwd,
          worktree: this.worktree,
        });
      });

      this.socket.on("data", (data) => {
        this.buffer += data.toString();
        const lines = this.buffer.split("\n");
        this.buffer = lines.pop() ?? "";

        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const msg = deserialize(line) as ServerMessage;

            if (msg.type === "registered" && !this.connected) {
              this.connected = true;
              this.reconnectDelay = BACKOFF_INITIAL_MS;
              resolve();
              continue;
            }

            if (msg.type === "error" && !this.connected) {
              reject(new Error(`${msg.code}: ${msg.message}`));
              this.socket?.destroy();
              continue;
            }

            // Handle shutdown — trigger reconnection
            if (msg.type === "shutdown") {
              this.connected = false;
              this.socket?.destroy();
              this.scheduleReconnect();
              continue;
            }

            if (this.messageHandler) {
              this.messageHandler(msg);
            }
          } catch {
            // Ignore malformed messages
          }
        }
      });

      this.socket.on("error", (err) => {
        if (!this.connected) {
          reject(err);
        }
      });

      this.socket.on("close", () => {
        const wasConnected = this.connected;
        this.connected = false;
        if (wasConnected && !this.intentionalDisconnect) {
          this.scheduleReconnect();
        }
      });
    });
  }

  private scheduleReconnect(): void {
    if (this.intentionalDisconnect || this.reconnectTimer) return;

    this.reconnectTimer = setTimeout(async () => {
      this.reconnectTimer = null;
      try {
        await this.doConnect();
      } catch {
        // Increase backoff and retry
        this.reconnectDelay = Math.min(
          this.reconnectDelay * BACKOFF_MULTIPLIER,
          BACKOFF_MAX_MS
        );
        this.scheduleReconnect();
      }
    }, this.reconnectDelay);
  }

  async disconnect(): Promise<void> {
    this.intentionalDisconnect = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.socket && this.connected) {
      this.sendRaw({ type: "deregister", sessionId: this.sessionId });
      await new Promise<void>((resolve) => {
        this.socket!.on("close", resolve);
        this.socket!.end();
      });
    }
    this.connected = false;
    this.socket = null;
  }

  isConnected(): boolean {
    return this.connected;
  }

  onMessage(handler: ServerMessageHandler): void {
    this.messageHandler = handler;
  }

  sendConfigure(
    sessionContext?: string,
    timeoutOverrides?: { architecture?: number; preference?: number }
  ): void {
    this.sendRaw({
      type: "configure",
      sessionId: this.sessionId,
      sessionContext,
      timeoutOverrides,
    });
  }

  sendAsk(
    requestId: string,
    message: string,
    priority: "critical" | "architecture" | "preference",
    options?: Array<{ text: string; description?: string; isDefault?: boolean }>,
    defaultIndex?: number,
    timeoutMinutes?: number
  ): void {
    this.sendRaw({
      type: "ask",
      sessionId: this.sessionId,
      requestId,
      message,
      priority,
      options,
      defaultIndex,
      timeoutMinutes,
    });
  }

  sendNotify(
    requestId: string,
    message: string,
    level?: "info" | "success" | "warning" | "error",
    silent?: boolean
  ): void {
    this.sendRaw({
      type: "notify",
      sessionId: this.sessionId,
      requestId,
      message,
      level,
      silent,
    });
  }

  private sendRaw(msg: ClientMessage): void {
    if (!this.socket || this.socket.destroyed) {
      throw new Error("Not connected");
    }
    this.socket.write(serialize(msg));
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/client.test.ts`
Expected: PASS

- [ ] **Step 5: Run server tests too (they depend on client)**

Run: `cd claude-hitl-mcp && npx vitest run tests/ipc/`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add src/ipc/client.ts tests/ipc/client.test.ts
git commit -m "feat: add IPC client for MCP server to listener communication"
```

---

## Chunk 2: Adapter Refactoring

### Task 4: ListenerClientAdapter

**Files:**
- Create: `src/adapters/listener-client.ts`
- Test: `tests/adapters/listener-client.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/adapters/listener-client.test.ts
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { ListenerClientAdapter } from "../../src/adapters/listener-client.js";
import { IpcServer } from "../../src/ipc/server.js";
import * as os from "node:os";
import * as path from "node:path";

describe("ListenerClientAdapter", () => {
  let server: IpcServer;
  let adapter: ListenerClientAdapter;
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
    await adapter?.disconnect();
    await server?.stop();
  });

  it("implements ChatAdapter interface", async () => {
    adapter = new ListenerClientAdapter(socketPath);
    expect(adapter.name).toBe("listener-client");
    expect(adapter.capabilities.inlineButtons).toBe(true);
  });

  it("connects to listener", async () => {
    adapter = new ListenerClientAdapter(socketPath);
    await adapter.connect({ token: "", chatId: "123" });
    expect(adapter.isConnected()).toBe(true);
  });

  it("sends messages via IPC and returns message ID", async () => {
    adapter = new ListenerClientAdapter(socketPath);
    await adapter.connect({ token: "", chatId: "123" });

    // Set up server to ack notifications
    server.onMessage((session, msg) => {
      if (msg.type === "notify") {
        server.sendToSession(session.sessionId, {
          type: "notified",
          requestId: msg.requestId,
          messageId: "tg_42",
        });
      }
    });

    const result = await adapter.sendMessage({ text: "Hello", level: "info" });
    expect(result.messageId).toBe("tg_42");
  });

  it("sends interactive messages and waits for response", async () => {
    adapter = new ListenerClientAdapter(socketPath);
    await adapter.connect({ token: "", chatId: "123" });

    // Set up server to forward ask and respond
    server.onMessage((session, msg) => {
      if (msg.type === "ask") {
        // Simulate user clicking a button
        setTimeout(() => {
          server.sendToSession(session.sessionId, {
            type: "response",
            requestId: msg.requestId,
            text: "Option A",
            selectedIndex: 0,
            isButtonTap: true,
          });
        }, 50);
      }
    });

    // onMessage should fire with the response
    const received: any[] = [];
    adapter.onMessage((msg) => received.push(msg));

    await adapter.sendInteractiveMessage({
      text: "Pick one",
      requestId: "req_1",
      options: [{ text: "Option A" }],
      priority: "preference",
    });

    await new Promise((r) => setTimeout(r, 200));
    // The response routing happens through onMessage
  });

  it("disconnects cleanly", async () => {
    adapter = new ListenerClientAdapter(socketPath);
    await adapter.connect({ token: "", chatId: "123" });
    await adapter.disconnect();
    expect(adapter.isConnected()).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/adapters/listener-client.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement ListenerClientAdapter**

The adapter implements the `ChatAdapter` interface from `types.ts`, translating each method into IPC messages sent through `IpcClient`. Key behaviors:
- `connect()` creates an `IpcClient`, connects to the socket, generates a `sessionId` from `crypto.randomUUID()`
- `sendMessage()` sends a `notify` IPC message, waits for `notified` ack, returns `{ messageId }`
- `sendInteractiveMessage()` sends an `ask` IPC message (but does NOT wait for response — response routing goes through `onMessage` handler, same as `TelegramAdapter`)
- `onMessage()` registers a handler that receives `response` IPC messages translated to `InboundMessage` format
- `editMessage()` is a no-op (message editing happens on the listener side)
- `disconnect()` calls `client.disconnect()`
- `awaitBinding()` throws — binding is handled by the listener/setup flow

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/adapters/listener-client.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/adapters/listener-client.ts tests/adapters/listener-client.test.ts
git commit -m "feat: add ListenerClientAdapter implementing ChatAdapter over IPC"
```

---

### Task 5: Adapter Factory

**Files:**
- Create: `src/adapters/factory.ts`
- Test: `tests/adapters/factory.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/adapters/factory.test.ts
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
    socketPath = path.join(
      os.tmpdir(),
      `claude-hitl-test-${Date.now()}.sock`
    );
  });

  afterEach(() => {
    tempServer?.close();
    try { fs.unlinkSync(socketPath); } catch {}
  });

  it("returns ListenerClientAdapter when socket exists", async () => {
    // Create a socket to simulate listener running
    tempServer = net.createServer();
    await new Promise<void>((r) => tempServer.listen(socketPath, r));

    const adapter = createAdapter(socketPath);
    expect(adapter).toBeInstanceOf(ListenerClientAdapter);
  });

  it("returns TelegramAdapter when socket does not exist", () => {
    const adapter = createAdapter("/tmp/nonexistent.sock");
    expect(adapter).toBeInstanceOf(TelegramAdapter);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/adapters/factory.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement adapter factory**

```typescript
// src/adapters/factory.ts
import * as fs from "node:fs";
import * as net from "node:net";
import { ChatAdapter } from "../types.js";
import { ListenerClientAdapter } from "./listener-client.js";
import { TelegramAdapter } from "./telegram.js";

export function createAdapter(socketPath: string): ChatAdapter {
  // Check if socket file exists and is a socket
  try {
    const stat = fs.statSync(socketPath);
    if (stat.isSocket()) {
      return new ListenerClientAdapter(socketPath);
    }
  } catch {
    // Socket doesn't exist — fall back
  }

  return new TelegramAdapter();
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/adapters/factory.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/adapters/factory.ts tests/adapters/factory.test.ts
git commit -m "feat: add adapter factory for listener vs direct Telegram selection"
```

---

## Chunk 3: Config Migration & Types Update

> **Parallelization note:** Chunks 3 and 4 have no dependencies on each other. If using subagents, they can be implemented in parallel.

### Task 6: Config Migration

**Files:**
- Modify: `src/config.ts`
- Modify: `tests/config.test.ts`

- [ ] **Step 1: Write failing tests for migration**

Add to `tests/config.test.ts`:

```typescript
describe("config migration", () => {
  it("migrates config from old path to new directory", async () => {
    // Write config to old path
    const oldPath = path.join(tmpDir, ".claude-hitl.json");
    const newDir = path.join(tmpDir, ".claude-hitl");
    const newPath = path.join(newDir, "config.json");

    fs.writeFileSync(oldPath, JSON.stringify({ adapter: "telegram" }));

    await migrateConfig(oldPath, newPath);

    expect(fs.existsSync(newPath)).toBe(true);
    expect(fs.existsSync(oldPath)).toBe(false);
    const content = JSON.parse(fs.readFileSync(newPath, "utf-8"));
    expect(content.adapter).toBe("telegram");
  });

  it("handles case where both old and new exist (re-attempt)", async () => {
    const oldPath = path.join(tmpDir, ".claude-hitl.json");
    const newDir = path.join(tmpDir, ".claude-hitl");
    const newPath = path.join(newDir, "config.json");

    fs.mkdirSync(newDir, { recursive: true });
    fs.writeFileSync(oldPath, JSON.stringify({ adapter: "telegram" }));
    fs.writeFileSync(newPath, JSON.stringify({ adapter: "old" }));

    await migrateConfig(oldPath, newPath);

    // New file should be overwritten with old content
    const content = JSON.parse(fs.readFileSync(newPath, "utf-8"));
    expect(content.adapter).toBe("telegram");
    expect(fs.existsSync(oldPath)).toBe(false);
  });

  it("no-ops when old path does not exist", async () => {
    const oldPath = path.join(tmpDir, ".claude-hitl.json");
    const newPath = path.join(tmpDir, ".claude-hitl", "config.json");

    await migrateConfig(oldPath, newPath);
    // No error, no files created
    expect(fs.existsSync(newPath)).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/config.test.ts`
Expected: FAIL — `migrateConfig` not found

- [ ] **Step 3: Update config.ts**

Update `DEFAULT_CONFIG_PATH` to `~/.claude-hitl/config.json`. Add `ensureConfigDir()` and `migrateConfig()` functions. Add `LEGACY_CONFIG_PATH` constant for migration detection. The `migrateConfig` function: copies old to new, verifies JSON parse, then deletes old.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/config.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/config.ts tests/config.test.ts
git commit -m "feat: migrate config to ~/.claude-hitl/config.json"
```

---

### Task 7: Update Types (Remove quiet_hours from configure_hitl)

**Files:**
- Modify: `src/types.ts`
- Modify: `src/tools.ts`
- Modify: `src/server.ts`
- Modify: `tests/tools.test.ts`

- [ ] **Step 1: Update types.ts**

Remove `quiet_hours` from `ConfigureHitlInput` interface. Add `QuietHoursState` type:

```typescript
export interface QuietHoursState {
  enabled: boolean;
  manual: boolean;
  start?: string;
  end?: string;
  timezone?: string;
  behavior?: "queue" | "skip_preference";
}
```

- [ ] **Step 2: Update tools.ts**

Remove quiet hours handling from `configureHitl()` method. Quiet hours will be pushed from the listener via IPC `quiet_hours_changed` messages.

- [ ] **Step 3: Update server.ts**

Remove `quiet_hours` from the `configure_hitl` Zod schema. Use adapter factory instead of direct `TelegramAdapter` instantiation.

- [ ] **Step 4: Update tests/tools.test.ts**

Remove test cases for quiet hours in `configure_hitl`. Add note that quiet hours are now managed by the listener.

- [ ] **Step 5: Run all existing tests**

Run: `cd claude-hitl-mcp && npx vitest run`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
git add src/types.ts src/tools.ts src/server.ts tests/tools.test.ts
git commit -m "refactor: move quiet hours ownership to listener, remove from configure_hitl"
```

---

## Chunk 4: Telegram Command Handlers

### Task 8: `/help` Command

**Files:**
- Create: `src/commands/help.ts`
- Test: `tests/commands/help.test.ts`

- [ ] **Step 1: Write failing test**

```typescript
// tests/commands/help.test.ts
import { describe, it, expect } from "vitest";
import { formatHelpMessage } from "../../src/commands/help.js";

describe("formatHelpMessage", () => {
  it("returns available commands", () => {
    const msg = formatHelpMessage();
    expect(msg).toContain("/status");
    expect(msg).toContain("/quiet");
    expect(msg).toContain("/help");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd claude-hitl-mcp && npx vitest run tests/commands/help.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement help command**

```typescript
// src/commands/help.ts
export function formatHelpMessage(): string {
  return [
    "Available commands:",
    "",
    "/status — What's Claude working on?",
    "/quiet — Manage quiet hours",
    "/help — Show this message",
  ].join("\n");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd claude-hitl-mcp && npx vitest run tests/commands/help.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/commands/help.ts tests/commands/help.test.ts
git commit -m "feat: add /help command handler"
```

---

### Task 9: `/status` Command

**Files:**
- Create: `src/commands/status.ts`
- Test: `tests/commands/status.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/commands/status.test.ts
import { describe, it, expect } from "vitest";
import {
  formatStatusMessage,
  readPlanFile,
  truncatePlan,
  type StatusSession,
} from "../../src/commands/status.js";

describe("formatStatusMessage", () => {
  it("shows no sessions message when empty", () => {
    const msg = formatStatusMessage([], []);
    expect(msg.text).toContain("No active Claude sessions");
  });

  it("shows last disconnected session when no active sessions", () => {
    const msg = formatStatusMessage([], [
      { project: "claude-setup", lastSeen: new Date(Date.now() - 900_000) },
    ]);
    expect(msg.text).toContain("claude-setup");
    expect(msg.text).toContain("disconnected");
  });

  it("shows full details for single session", () => {
    const sessions: StatusSession[] = [
      {
        sessionId: "s1",
        project: "claude-setup",
        worktree: "feature/status",
        sessionContext: "Building status feature",
        plan: "## Phase 1\n- [x] Done\n## Phase 2\n- [ ] In progress",
        pendingCount: 1,
        oldestPendingAge: 720, // 12 minutes in seconds
      },
    ];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("claude-setup");
    expect(msg.text).toContain("feature/status");
    expect(msg.text).toContain("Building status feature");
    expect(msg.text).toContain("Phase 1");
    expect(msg.text).toContain("1 pending question");
    expect(msg.buttons).toBeUndefined();
  });

  it("shows compact summary with buttons for multiple sessions", () => {
    const sessions: StatusSession[] = [
      {
        sessionId: "s1",
        project: "claude-setup",
        pendingCount: 1,
        oldestPendingAge: 720,
      },
      {
        sessionId: "s2",
        project: "modamily",
        pendingCount: 0,
      },
    ];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("#1 claude-setup");
    expect(msg.text).toContain("#2 modamily");
    expect(msg.buttons).toHaveLength(2);
  });
});

describe("truncatePlan", () => {
  it("returns plan as-is when under limit", () => {
    expect(truncatePlan("Short plan", 3000)).toBe("Short plan");
  });

  it("truncates and adds suffix when over limit", () => {
    const longPlan = "x".repeat(4000);
    const result = truncatePlan(longPlan, 3000);
    expect(result.length).toBeLessThan(3100);
    expect(result).toContain("truncated");
  });
});

describe("readPlanFile", () => {
  it("returns null for nonexistent file", () => {
    expect(readPlanFile("/tmp/nonexistent")).toBeNull();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/commands/status.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement status command**

The `formatStatusMessage` function takes sessions and disconnected records, returns `{ text: string; buttons?: Array<{ text: string; callbackData: string }> }`. It reads `_plan.md` from each session's `cwd`. Truncates plans to 3000 chars. Formats pending question counts with age. Single session = full details, no buttons. Multiple sessions = compact + drill-down buttons with `status:sessionId` callback data.

`formatSessionDetail(session)` renders the full detail view for a single session (used for both single-session status and drill-down button responses).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/commands/status.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/commands/status.ts tests/commands/status.test.ts
git commit -m "feat: add /status command handler with plan reading"
```

---

### Task 10: `/quiet` Command

**Files:**
- Create: `src/commands/quiet.ts`
- Test: `tests/commands/quiet.test.ts`

- [ ] **Step 1: Write failing tests**

```typescript
// tests/commands/quiet.test.ts
import { describe, it, expect } from "vitest";
import {
  formatQuietStatus,
  type QuietState,
} from "../../src/commands/quiet.js";

describe("formatQuietStatus", () => {
  it("shows off state with turn-on button", () => {
    const state: QuietState = { enabled: false, manual: false };
    const result = formatQuietStatus(state);
    expect(result.text).toContain("OFF");
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Turn On" })
    );
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Set Schedule" })
    );
  });

  it("shows manual-on state with turn-off button", () => {
    const state: QuietState = { enabled: true, manual: true };
    const result = formatQuietStatus(state);
    expect(result.text).toContain("ON");
    expect(result.text).toContain("manually");
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Turn Off" })
    );
  });

  it("shows scheduled-on state with schedule info", () => {
    const state: QuietState = {
      enabled: true,
      manual: false,
      start: "22:00",
      end: "08:00",
      timezone: "America/New_York",
    };
    const result = formatQuietStatus(state);
    expect(result.text).toContain("ON");
    expect(result.text).toContain("22:00");
    expect(result.text).toContain("08:00");
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Turn Off Now" })
    );
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/commands/quiet.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement quiet command**

The `formatQuietStatus` function takes current `QuietState`, returns `{ text, buttons }`. The `handleQuietAction(action, config)` function processes button callbacks (`quiet:on`, `quiet:off`, `quiet:schedule`), updates config, saves to disk, returns updated `QuietState` for broadcasting to MCP servers.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/commands/quiet.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/commands/quiet.ts tests/commands/quiet.test.ts
git commit -m "feat: add /quiet command handler with toggle UI"
```

---

## Chunk 5: Listener Daemon

### Task 11: Listener Entrypoint

**Files:**
- Create: `src/listener.ts`
- Test: `tests/listener.test.ts`

- [ ] **Step 1: Write failing tests**

First, create test helpers at `tests/helpers/mock-bot.ts` — a mock `node-telegram-bot-api` that tracks sent messages, provides `createMockBot()`, `simulateTelegramMessage(bot, text)`, and `simulateButtonTap(bot, callbackData)` helpers. The mock bot stores `sentMessages` array for assertions and exposes the message/callback_query event handlers so tests can simulate incoming Telegram messages.

```typescript
// tests/listener.test.ts
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { Listener } from "../src/listener.js";
import { IpcClient } from "../src/ipc/client.js";
import { createMockBot, simulateTelegramMessage, simulateButtonTap } from "./helpers/mock-bot.js";
import * as os from "node:os";
import * as path from "node:path";

describe("Listener", () => {
  let listener: Listener;
  let socketPath: string;
  let configDir: string;

  beforeEach(() => {
    configDir = path.join(
      os.tmpdir(),
      `claude-hitl-test-${Date.now()}`
    );
    socketPath = path.join(configDir, "sock");
  });

  afterEach(async () => {
    await listener?.stop();
  });

  it("starts IPC server and accepts connections", async () => {
    // Use a mock Telegram bot
    listener = new Listener({
      configDir,
      socketPath,
      telegramBot: createMockBot(),
    });
    await listener.start();

    const client = new IpcClient(socketPath);
    await client.connect("s1", "test", "/tmp/test");
    expect(client.isConnected()).toBe(true);
    await client.disconnect();
  });

  it("routes /status command to handler", async () => {
    listener = new Listener({
      configDir,
      socketPath,
      telegramBot: createMockBot(),
    });
    await listener.start();

    // Simulate /status message from Telegram
    const bot = listener.getBot();
    const response = await simulateTelegramMessage(bot, "/status");
    expect(response).toContain("No active Claude sessions");
  });

  it("routes ask messages from MCP to Telegram and responses back", async () => {
    const mockBot = createMockBot();
    listener = new Listener({
      configDir,
      socketPath,
      telegramBot: mockBot,
    });
    await listener.start();

    // Connect an MCP server
    const client = new IpcClient(socketPath);
    await client.connect("s1", "test", "/tmp/test");

    const responses: any[] = [];
    client.onMessage((msg) => responses.push(msg));

    // MCP server sends ask
    client.sendAsk("req_1", "Pick one", "preference", [
      { text: "A" },
      { text: "B" },
    ]);

    await new Promise((r) => setTimeout(r, 100));

    // Verify bot sent the interactive message
    expect(mockBot.sentMessages).toHaveLength(1);

    // Simulate user tapping button
    simulateButtonTap(mockBot, "req_1:0");
    await new Promise((r) => setTimeout(r, 100));

    // MCP server should receive the response
    expect(responses).toContainEqual(
      expect.objectContaining({
        type: "response",
        requestId: "req_1",
        selectedIndex: 0,
      })
    );

    await client.disconnect();
  });
});
```

Note: `createMockBot` and `simulateTelegramMessage` are test helpers that mock `node-telegram-bot-api` methods. The mock bot tracks `sentMessages` for assertions.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/listener.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement listener**

The `Listener` class wires together:
- `IpcServer` — accepts MCP server connections
- Telegram bot (from `node-telegram-bot-api`) — owns the bot connection
- Command handlers — intercept `/status`, `/quiet`, `/help`
- Message routing — non-command messages from Telegram route to the correct MCP server session
- Session tracking — maps `requestId` to `sessionId` so responses route correctly

Key responsibilities:
- On IPC `ask` message: send interactive Telegram message, store `requestId → sessionId` mapping
- On IPC `notify` message: send Telegram message, send `notified` ack back
- On IPC `configure` message: update session context in IPC server
- On Telegram message starting with `/`: dispatch to command handler
- On Telegram callback query: parse `requestId:index`, find session, send `response` IPC message
- On Telegram text (not `/`): route to most recent pending request's session (LIFO)
- Quiet hours state: load from config on start, broadcast `quiet_hours_changed` on toggle

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/listener.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/listener.ts tests/listener.test.ts tests/helpers/mock-bot.ts
git commit -m "feat: add listener daemon with Telegram command routing"
```

---

### Task 12: Multi-Session Integration Tests

**Files:**
- Create: `tests/integration/multi-session.test.ts`

- [ ] **Step 1: Write integration tests**

Test scenarios:
1. Two MCP servers connect, both appear in `/status`
2. `ask_human` from session 1, response routes only to session 1
3. `ask_human` from both sessions, responses route correctly by `requestId`
4. Session 1 disconnects, `/status` shows remaining session + disconnected record
5. `/quiet` toggle pushes `quiet_hours_changed` to all connected sessions
6. Session reconnects after listener restart — re-registers successfully
7. Non-command message with no sessions connected returns "No active Claude sessions" message
8. Timeout routing: when `ask` times out, listener sends `timeout` IPC message to correct session

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/integration/multi-session.test.ts`
Expected: FAIL

- [ ] **Step 3: Fix any issues found**

Test helpers (`tests/helpers/mock-bot.ts`) were created in Task 11. Reuse them here.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/integration/`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/integration/ tests/helpers/
git commit -m "test: add multi-session integration tests"
```

---

## Chunk 6: CLI & Daemon Management

### Task 13: CLI Commands for Listener Management

**Files:**
- Modify: `src/cli.ts`
- Test: Add to existing `tests/` or create `tests/cli.test.ts`

- [ ] **Step 1: Write failing tests for new CLI commands**

Test `install-listener`:
- Generates correct plist with resolved node path and package directory
- Writes plist to `~/Library/LaunchAgents/`
- Calls `launchctl load`

Test `uninstall-listener`:
- Calls `launchctl unload`
- Removes plist file

Test `start-listener` / `stop-listener`:
- Calls correct `launchctl start/stop` commands

Test setup migration:
- When old config exists, migrates before proceeding

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd claude-hitl-mcp && npx vitest run tests/cli.test.ts`
Expected: FAIL

- [ ] **Step 3: Implement CLI commands**

Add to `cli.ts`:
- `install-listener`: resolve `which node`, resolve `__dirname` for package path, write plist template with substitutions, run `launchctl load`
- `uninstall-listener`: run `launchctl unload`, remove plist
- `start-listener` / `stop-listener`: `launchctl start/stop com.claude-hitl.listener`
- `listener-logs`: `tail -f ~/.claude-hitl/listener.log`
- Update `setup` to call `migrateConfig()` first, then `install-listener` at the end
- Update command routing in the main switch

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd claude-hitl-mcp && npx vitest run tests/cli.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add src/cli.ts tests/cli.test.ts
git commit -m "feat: add CLI commands for listener daemon management"
```

---

### Task 14: Update server.ts to Use Adapter Factory

**Files:**
- Modify: `src/server.ts`

- [ ] **Step 1: Update server.ts imports**

Replace direct `TelegramAdapter` import with `createAdapter` from factory. Determine socket path from config directory (`~/.claude-hitl/sock`).

- [ ] **Step 2: Update lazy initialization**

In the `ensureInitialized()` function, use `createAdapter(socketPath)` instead of `new TelegramAdapter()`. This automatically picks `ListenerClientAdapter` when the listener is running, or falls back to `TelegramAdapter`.

- [ ] **Step 3: Remove quiet_hours from configure_hitl Zod schema**

Remove the `quiet_hours` input parameter from the `configure_hitl` tool definition.

- [ ] **Step 4: Run full test suite**

Run: `cd claude-hitl-mcp && npx vitest run`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add src/server.ts
git commit -m "refactor: use adapter factory in MCP server for listener/direct selection"
```

---

## Chunk 7: Build & Rollout

### Task 15: Update Build Configuration

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Add listener entrypoint to tsup config**

The build should produce both `dist/cli.js` (existing) and `dist/listener.js` (new entrypoint for the daemon).

- [ ] **Step 2: Update bin field**

Add `claude-hitl-listener` bin entry pointing to `dist/listener.js` if needed for direct invocation.

- [ ] **Step 3: Build and verify**

Run: `cd claude-hitl-mcp && npm run build`
Expected: Both `dist/cli.js` and `dist/listener.js` exist

- [ ] **Step 4: Commit**

```bash
git add package.json tsup.config.ts
git commit -m "build: add listener entrypoint to build config"
```

---

### Task 16: End-to-End Verification

- [ ] **Step 1: Build the project**

Run: `cd claude-hitl-mcp && npm run build`

- [ ] **Step 2: Run full test suite**

Run: `cd claude-hitl-mcp && npx vitest run`
Expected: ALL PASS

- [ ] **Step 3: Run setup (if not already configured)**

Run: `cd claude-hitl-mcp && node dist/cli.js setup`
This should migrate config, install the listener daemon, and send a test notification.

- [ ] **Step 4: Verify listener is running**

Run: `launchctl list | grep claude-hitl`
Expected: Shows the listener process

- [ ] **Step 5: Test /help from Telegram**

Send `/help` in Telegram. Expected: command list response.

- [ ] **Step 6: Test /status with no sessions**

Send `/status` in Telegram. Expected: "No active Claude sessions"

- [ ] **Step 7: Start a Claude Code session and test /status**

Start Claude Code in any project. Send `/status` in Telegram. Expected: see the session listed.

- [ ] **Step 8: Test ask_human round-trip**

From Claude Code, trigger an `ask_human` call. Verify it appears in Telegram. Respond via button tap. Verify Claude Code receives the response.

- [ ] **Step 9: Test /quiet toggle**

Send `/quiet` in Telegram. Tap "Turn On". Send `/quiet` again. Verify it shows "ON (manually)". Tap "Turn Off". Verify it shows "OFF".

- [ ] **Step 10: Test listener restart recovery**

Run: `node dist/cli.js stop-listener && sleep 2 && node dist/cli.js start-listener`
Verify Claude Code session reconnects (check listener logs).

- [ ] **Step 11: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end verification"
```
