import { describe, it, expect, vi, beforeEach } from "vitest";
import { PriorityEngine } from "../src/priority-engine.js";

describe("PriorityEngine", () => {
  let engine: PriorityEngine;

  beforeEach(() => {
    engine = new PriorityEngine();
  });

  describe("getTimeout", () => {
    it("returns null for critical (infinite)", () => {
      expect(engine.getTimeoutMs("critical")).toBeNull();
    });

    it("returns default for architecture", () => {
      expect(engine.getTimeoutMs("architecture")).toBe(120 * 60 * 1000);
    });

    it("returns default for preference", () => {
      expect(engine.getTimeoutMs("preference")).toBe(30 * 60 * 1000);
    });

    it("respects overrides", () => {
      engine.setTimeoutOverrides({ architecture: 60, preference: 10 });
      expect(engine.getTimeoutMs("architecture")).toBe(60 * 60 * 1000);
      expect(engine.getTimeoutMs("preference")).toBe(10 * 60 * 1000);
    });

    it("ignores critical overrides", () => {
      engine.setTimeoutOverrides({ critical: null });
      expect(engine.getTimeoutMs("critical")).toBeNull();
    });

    it("respects per-request timeout_minutes override", () => {
      expect(engine.getTimeoutMs("preference", 5)).toBe(5 * 60 * 1000);
    });
  });

  describe("getTimeoutAction", () => {
    it("returns 'used_default' for preference with default option", () => {
      const options = [
        { text: "A", default: true },
        { text: "B" },
      ];
      expect(engine.getTimeoutAction("preference", options)).toEqual({
        action: "used_default",
        response: "A",
        selectedIndex: 0,
      });
    });

    it("returns 'paused' for architecture", () => {
      expect(engine.getTimeoutAction("architecture")).toEqual({
        action: "paused",
        response: "",
        selectedIndex: undefined,
      });
    });

    it("returns 'paused' for preference with no default", () => {
      const options = [{ text: "A" }, { text: "B" }];
      expect(engine.getTimeoutAction("preference", options)).toEqual({
        action: "paused",
        response: "",
        selectedIndex: undefined,
      });
    });
  });

  describe("isQuietHours", () => {
    it("returns false when quiet hours not configured", () => {
      expect(engine.isQuietHours()).toBe(false);
    });

    it("detects quiet hours correctly", () => {
      vi.useFakeTimers();
      engine.setQuietHours({
        start: "22:00",
        end: "08:00",
        timezone: "UTC",
        behavior: "queue",
      });
      vi.setSystemTime(new Date("2026-03-15T23:00:00Z"));
      expect(engine.isQuietHours()).toBe(true);
      vi.useRealTimers();
    });

    it("critical always overrides quiet hours", () => {
      vi.useFakeTimers();
      engine.setQuietHours({
        start: "22:00",
        end: "08:00",
        timezone: "UTC",
        behavior: "queue",
      });
      vi.setSystemTime(new Date("2026-03-15T23:00:00Z"));
      expect(engine.shouldDeliverDuringQuietHours("critical")).toBe(true);
      expect(engine.shouldDeliverDuringQuietHours("architecture")).toBe(false);
      vi.useRealTimers();
    });

    it("skip_preference auto-resolves preference during quiet hours", () => {
      vi.useFakeTimers();
      engine.setQuietHours({
        start: "22:00",
        end: "08:00",
        timezone: "UTC",
        behavior: "skip_preference",
      });
      vi.setSystemTime(new Date("2026-03-15T23:00:00Z"));
      expect(engine.shouldAutoResolve("preference")).toBe(true);
      expect(engine.shouldAutoResolve("architecture")).toBe(false);
      vi.useRealTimers();
    });
  });

  describe("formatMessage", () => {
    it("adds priority indicator to critical messages", () => {
      const formatted = engine.formatPriorityLabel("critical");
      expect(formatted).toContain("CRITICAL");
    });

    it("adds priority indicator to architecture messages", () => {
      const formatted = engine.formatPriorityLabel("architecture");
      expect(formatted).toContain("ARCHITECTURE");
    });
  });

  describe("reminder interval", () => {
    it("returns 15 min for critical", () => {
      expect(engine.getReminderIntervalMs("critical")).toBe(15 * 60 * 1000);
    });

    it("returns null for non-critical", () => {
      expect(engine.getReminderIntervalMs("architecture")).toBeNull();
      expect(engine.getReminderIntervalMs("preference")).toBeNull();
    });
  });
});
