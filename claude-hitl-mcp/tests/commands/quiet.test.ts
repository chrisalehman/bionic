import { describe, it, expect } from "vitest";
import { formatQuietStatus, handleQuietAction, type QuietState } from "../../src/commands/quiet.js";

describe("formatQuietStatus", () => {
  it("shows off state with turn-on button", () => {
    const state: QuietState = { enabled: false, manual: false };
    const result = formatQuietStatus(state);
    expect(result.text).toContain("OFF");
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Turn On", callbackData: "quiet:on" })
    );
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Set Schedule", callbackData: "quiet:schedule" })
    );
  });

  it("shows manual-on state with turn-off button", () => {
    const state: QuietState = { enabled: true, manual: true };
    const result = formatQuietStatus(state);
    expect(result.text).toContain("ON");
    expect(result.text).toContain("manually");
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Turn Off", callbackData: "quiet:off" })
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
      expect.objectContaining({ text: "Turn Off Now", callbackData: "quiet:off" })
    );
    expect(result.buttons).toContainEqual(
      expect.objectContaining({ text: "Edit Schedule", callbackData: "quiet:schedule" })
    );
  });
});

describe("handleQuietAction", () => {
  it("turns on quiet hours manually", () => {
    const state: QuietState = { enabled: false, manual: false, start: "22:00", end: "08:00", timezone: "America/New_York" };
    const result = handleQuietAction("on", state);
    expect(result.enabled).toBe(true);
    expect(result.manual).toBe(true);
    expect(result.start).toBe("22:00"); // preserves schedule
  });

  it("turns off quiet hours", () => {
    const state: QuietState = { enabled: true, manual: true };
    const result = handleQuietAction("off", state);
    expect(result.enabled).toBe(false);
    expect(result.manual).toBe(false);
  });

  it("returns state unchanged for schedule action", () => {
    const state: QuietState = { enabled: false, manual: false };
    const result = handleQuietAction("schedule", state);
    expect(result).toEqual(state);
  });
});
