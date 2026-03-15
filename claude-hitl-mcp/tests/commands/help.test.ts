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
