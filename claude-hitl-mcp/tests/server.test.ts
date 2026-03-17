import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { z } from "zod";

/**
 * Contract tests for the MCP server tool error responses.
 *
 * These tests verify that each tool returns the correct JSON error shape when
 * the HITL handler is not configured (getHandler() returns null). This covers
 * three conditions that all collapse to the same null-handler path:
 *   - No config file present
 *   - Telegram token missing
 *   - Telegram connection failure
 *
 * Rather than importing server.ts directly (it calls main() at module load),
 * we re-register the three tools with an always-null handler and drive them
 * through a real in-process MCP client→server pair.
 */

// Helper that extracts the text content from an MCP tool result.
function extractText(
  result: Awaited<ReturnType<Client["callTool"]>>,
): string {
  const first = result.content[0];
  if (first.type !== "text") {
    throw new Error(`Expected text content, got ${first.type}`);
  }
  return first.text;
}

describe("MCP server tool error responses (handler not configured)", () => {
  let client: Client;
  let server: McpServer;

  beforeAll(async () => {
    server = new McpServer({ name: "claude-hitl-test", version: "1.0.0" });

    // Simulate the unconfigured state: getHandler() always resolves to null.
    const getHandler = async () => null;

    // ------------------------------------------------------------------ //
    // ask_human — mirrors the real tool registration in server.ts          //
    // ------------------------------------------------------------------ //
    server.tool(
      "ask_human",
      "Ask a human for input (test stub)",
      {
        message: z.string(),
        priority: z.enum(["critical", "architecture", "preference"]),
        options: z
          .array(
            z.object({
              text: z.string(),
              description: z.string().optional(),
              default: z.boolean().optional(),
            }),
          )
          .optional(),
        context: z.string().optional(),
        timeout_minutes: z.number().optional(),
      },
      async (args) => {
        const h = await getHandler();
        if (!h) {
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({
                  status: "error",
                  response:
                    "HITL not configured. Run 'npx claude-hitl-mcp setup' to connect Telegram. Falling back to terminal prompts.",
                  response_time_seconds: 0,
                  priority: args.priority,
                  timed_out_action: null,
                }),
              },
            ],
          };
        }
        return { content: [{ type: "text" as const, text: "ok" }] };
      },
    );

    // ------------------------------------------------------------------ //
    // notify_human                                                          //
    // ------------------------------------------------------------------ //
    server.tool(
      "notify_human",
      "Notify a human (test stub)",
      {
        message: z.string(),
        level: z.enum(["info", "success", "warning", "error"]).optional(),
        silent: z.boolean().optional(),
      },
      async () => {
        const h = await getHandler();
        if (!h) {
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({ status: "error", message_id: "" }),
              },
            ],
          };
        }
        return { content: [{ type: "text" as const, text: "ok" }] };
      },
    );

    // ------------------------------------------------------------------ //
    // configure_hitl                                                        //
    // ------------------------------------------------------------------ //
    server.tool(
      "configure_hitl",
      "Configure HITL session (test stub)",
      {
        session_context: z.string().optional(),
        plan_path: z.string().optional(),
        timeout_overrides: z
          .object({
            architecture: z.number().optional(),
            preference: z.number().optional(),
          })
          .optional(),
      },
      async () => {
        const h = await getHandler();
        if (!h) {
          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({
                  status: "error",
                  error: "HITL not configured",
                }),
              },
            ],
          };
        }
        return { content: [{ type: "text" as const, text: "ok" }] };
      },
    );

    // Wire an in-process client↔server pair so no real I/O occurs.
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();

    client = new Client({ name: "test-client", version: "1.0.0" });

    await server.connect(serverTransport);
    await client.connect(clientTransport);
  });

  afterAll(async () => {
    await client.close();
    await server.close();
  });

  // -------------------------------------------------------------------- //
  // ask_human                                                               //
  // -------------------------------------------------------------------- //

  it("ask_human: returns status=error when handler is null", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Proceed?", priority: "architecture" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
  });

  it("ask_human: error message mentions HITL not configured", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Proceed?", priority: "architecture" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.response).toContain("HITL not configured");
  });

  it("ask_human: response_time_seconds is 0", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Proceed?", priority: "preference" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.response_time_seconds).toBe(0);
  });

  it("ask_human: timed_out_action is null", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Proceed?", priority: "preference" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.timed_out_action).toBeNull();
  });

  it("ask_human: error echoes the requested priority (architecture)", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Choose path", priority: "architecture" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.priority).toBe("architecture");
  });

  it("ask_human: error echoes the requested priority (critical)", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Danger!", priority: "critical" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.priority).toBe("critical");
  });

  it("ask_human: error echoes the requested priority (preference)", async () => {
    const result = await client.callTool({
      name: "ask_human",
      arguments: { message: "Pick style", priority: "preference" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.priority).toBe("preference");
  });

  // -------------------------------------------------------------------- //
  // notify_human                                                            //
  // -------------------------------------------------------------------- //

  it("notify_human: returns status=error when handler is null", async () => {
    const result = await client.callTool({
      name: "notify_human",
      arguments: { message: "Build complete" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
  });

  it("notify_human: error response has empty string message_id", async () => {
    const result = await client.callTool({
      name: "notify_human",
      arguments: { message: "Done" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.message_id).toBe("");
  });

  it("notify_human: works with optional level field", async () => {
    const result = await client.callTool({
      name: "notify_human",
      arguments: { message: "Warning!", level: "warning" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
    expect(parsed.message_id).toBe("");
  });

  it("notify_human: works with silent=true", async () => {
    const result = await client.callTool({
      name: "notify_human",
      arguments: { message: "Quiet", silent: true },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
  });

  // -------------------------------------------------------------------- //
  // configure_hitl                                                          //
  // -------------------------------------------------------------------- //

  it("configure_hitl: returns status=error when handler is null", async () => {
    const result = await client.callTool({
      name: "configure_hitl",
      arguments: {},
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
  });

  it("configure_hitl: error field is 'HITL not configured'", async () => {
    const result = await client.callTool({
      name: "configure_hitl",
      arguments: { session_context: "my-project" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.error).toBe("HITL not configured");
  });

  it("configure_hitl: works with plan_path argument", async () => {
    const result = await client.callTool({
      name: "configure_hitl",
      arguments: { plan_path: "tasks/todo.md" },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
    expect(parsed.error).toBe("HITL not configured");
  });

  it("configure_hitl: works with timeout_overrides argument", async () => {
    const result = await client.callTool({
      name: "configure_hitl",
      arguments: { timeout_overrides: { architecture: 30, preference: 10 } },
    });
    const parsed = JSON.parse(extractText(result));
    expect(parsed.status).toBe("error");
    expect(parsed.error).toBe("HITL not configured");
  });
});
