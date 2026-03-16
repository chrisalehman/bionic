import { describe, it, expect, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import {
  formatStatusMessage,
  readPlanFile,
  readDeclaredPlan,
  hasUncheckedItems,
  truncatePlan,
  formatSessionDetail,
  formatStateIndicator,
  type StatusSession,
} from "../../src/commands/status.js";

function tmpProjectDir(): string {
  const dir = path.join(
    os.tmpdir(),
    `status-test-${Date.now()}-${Math.random().toString(36).slice(2)}`
  );
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

describe("formatStatusMessage", () => {
  it("shows no sessions message when empty", () => {
    const msg = formatStatusMessage([], []);
    expect(msg.text).toContain("No active Claude sessions");
    expect(msg.buttons).toBeUndefined();
  });

  it("shows last disconnected session when no active sessions", () => {
    const msg = formatStatusMessage([], [
      { project: "claude-setup", lastSeen: new Date(Date.now() - 900_000) },
    ]);
    expect(msg.text).toContain("claude-setup");
    expect(msg.text).toContain("disconnected");
  });

  it("shows full details for single session", () => {
    const sessions: StatusSession[] = [{
      sessionId: "s1",
      project: "claude-setup",
      worktree: "feature/status",
      sessionContext: "Building status feature",
      plan: "## Phase 1\n- [x] Done\n## Phase 2\n- [ ] In progress",
      pendingCount: 1,
      oldestPendingAge: 720,
    }];
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
      { sessionId: "s1", project: "claude-setup", plan: null, pendingCount: 1, oldestPendingAge: 720 },
      { sessionId: "s2", project: "modamily", plan: null, pendingCount: 0 },
    ];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("#1 claude-setup");
    expect(msg.text).toContain("#2 modamily");
    expect(msg.buttons).toHaveLength(2);
    expect(msg.buttons![0].callbackData).toBe("status:s1");
  });

  it("shows no pending questions when count is 0", () => {
    const sessions: StatusSession[] = [{
      sessionId: "s1", project: "test", plan: null, pendingCount: 0,
    }];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("No pending questions");
  });

  it("shows worktree info in compact summary for multiple sessions", () => {
    const sessions: StatusSession[] = [
      { sessionId: "s1", project: "proj-a", worktree: "feature/x", plan: null, pendingCount: 0 },
      { sessionId: "s2", project: "proj-b", plan: null, pendingCount: 0 },
    ];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("feature/x");
    expect(msg.buttons![1].callbackData).toBe("status:s2");
    expect(msg.buttons![1].text).toContain("proj-b");
  });

  it("shows most recent disconnected session (latest lastSeen) when no active sessions", () => {
    const msg = formatStatusMessage([], [
      { project: "older", lastSeen: new Date(Date.now() - 3_600_000) },
      { project: "newer", lastSeen: new Date(Date.now() - 60_000) },
    ]);
    expect(msg.text).toContain("newer");
  });

  it("shows no active plan when plan is null for single session", () => {
    const sessions: StatusSession[] = [{
      sessionId: "s1", project: "test", plan: null, pendingCount: 0,
    }];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("No active plan");
  });

  it("formats pending age correctly for single session", () => {
    const sessions: StatusSession[] = [{
      sessionId: "s1", project: "test", plan: null, pendingCount: 2, oldestPendingAge: 45,
    }];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("2 pending questions");
    expect(msg.text).toContain("45s ago");
  });

  it("shows state indicator instead of plan first-line in multi-session compact view", () => {
    const sessions: StatusSession[] = [
      { sessionId: "s1", project: "proj-a", plan: null, pendingCount: 0, lastActivityAge: 5 },
      { sessionId: "s2", project: "proj-b", plan: null, pendingCount: 0, lastActivityAge: 300 },
    ];
    const msg = formatStatusMessage(sessions, []);
    expect(msg.text).toContain("Active");
    expect(msg.text).toContain("Idle");
  });
});

describe("truncatePlan", () => {
  it("returns plan as-is when under limit", () => {
    expect(truncatePlan("Short plan", 3000)).toBe("Short plan");
  });

  it("returns plan as-is when exactly at limit", () => {
    const plan = "x".repeat(3000);
    expect(truncatePlan(plan, 3000)).toBe(plan);
  });

  it("truncates and adds suffix when over limit", () => {
    const longPlan = "x".repeat(4000);
    const result = truncatePlan(longPlan, 3000);
    expect(result.length).toBeLessThan(3100);
    expect(result).toContain("truncated");
  });

  it("truncated result starts with the original content prefix", () => {
    const longPlan = "A".repeat(4000);
    const result = truncatePlan(longPlan, 3000);
    expect(result.startsWith("A".repeat(3000))).toBe(true);
  });
});

describe("readPlanFile", () => {
  it("returns null for null cwd", () => {
    expect(readPlanFile(null)).toBeNull();
  });

  it("returns null for nonexistent file", () => {
    expect(readPlanFile("/tmp/nonexistent-dir-abc123")).toBeNull();
  });

  it("returns null for a directory with no plan files", () => {
    expect(readPlanFile("/tmp")).toBeNull();
  });

  it("finds plan in docs/superpowers/plans/ directory", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      fs.writeFileSync(path.join(plansDir, "2026-03-15-feature.md"), "## Plan\n- [ ] Do stuff");
      expect(readPlanFile(dir)).toBe("## Plan\n- [ ] Do stuff");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("picks most recent plan when multiple exist", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      fs.writeFileSync(path.join(plansDir, "2026-03-13-old.md"), "Old plan\n- [ ] Old");
      fs.writeFileSync(path.join(plansDir, "2026-03-15-middle.md"), "Middle plan\n- [ ] Mid");
      fs.writeFileSync(path.join(plansDir, "2026-03-16-newest.md"), "Newest plan\n- [ ] Todo");
      expect(readPlanFile(dir)).toBe("Newest plan\n- [ ] Todo");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("finds plan in tasks/todo.md", () => {
    const dir = tmpProjectDir();
    try {
      fs.mkdirSync(path.join(dir, "tasks"), { recursive: true });
      fs.writeFileSync(path.join(dir, "tasks", "todo.md"), "Task list plan\n- [ ] Todo");
      expect(readPlanFile(dir)).toBe("Task list plan\n- [ ] Todo");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("prefers superpowers plan over tasks/todo.md and _plan.md", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      fs.writeFileSync(path.join(plansDir, "2026-03-16-feature.md"), "Superpowers plan\n- [ ] Todo");
      fs.mkdirSync(path.join(dir, "tasks"), { recursive: true });
      fs.writeFileSync(path.join(dir, "tasks", "todo.md"), "Tasks plan\n- [ ] Todo");
      fs.writeFileSync(path.join(dir, "_plan.md"), "Legacy plan");
      expect(readPlanFile(dir)).toBe("Superpowers plan\n- [ ] Todo");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("prefers tasks/todo.md over _plan.md", () => {
    const dir = tmpProjectDir();
    try {
      fs.mkdirSync(path.join(dir, "tasks"), { recursive: true });
      fs.writeFileSync(path.join(dir, "tasks", "todo.md"), "Tasks plan\n- [ ] Todo");
      fs.writeFileSync(path.join(dir, "_plan.md"), "Legacy plan");
      expect(readPlanFile(dir)).toBe("Tasks plan\n- [ ] Todo");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("falls back to _plan.md when no other plans exist", () => {
    const dir = tmpProjectDir();
    try {
      fs.writeFileSync(path.join(dir, "_plan.md"), "Legacy plan");
      expect(readPlanFile(dir)).toBe("Legacy plan");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("ignores non-matching files in plans directory", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      fs.writeFileSync(path.join(plansDir, "README.md"), "Not a plan");
      fs.writeFileSync(path.join(plansDir, "notes.txt"), "Also not a plan");
      expect(readPlanFile(dir)).toBeNull();
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("returns null when plans directory exists but is empty", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      expect(readPlanFile(dir)).toBeNull();
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("skips completed plans (no unchecked items) in superpowers dir", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      fs.writeFileSync(path.join(plansDir, "2026-03-16-done.md"), "## Done\n- [x] All done");
      expect(readPlanFile(dir)).toBeNull();
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("finds older plan if newest is completed", () => {
    const dir = tmpProjectDir();
    try {
      const plansDir = path.join(dir, "docs", "superpowers", "plans");
      fs.mkdirSync(plansDir, { recursive: true });
      fs.writeFileSync(path.join(plansDir, "2026-03-16-done.md"), "## Done\n- [x] All done");
      fs.writeFileSync(path.join(plansDir, "2026-03-15-active.md"), "## Active\n- [ ] In progress");
      expect(readPlanFile(dir)).toBe("## Active\n- [ ] In progress");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("readDeclaredPlan", () => {
  it("returns null for undefined path", () => {
    expect(readDeclaredPlan(undefined)).toBeNull();
  });

  it("returns null for empty string path", () => {
    expect(readDeclaredPlan("")).toBeNull();
  });

  it("returns null for nonexistent path", () => {
    expect(readDeclaredPlan("/tmp/nonexistent-plan-abc123.md")).toBeNull();
  });

  it("reads content from a valid path", () => {
    const dir = tmpProjectDir();
    try {
      const planPath = path.join(dir, "plan.md");
      fs.writeFileSync(planPath, "## My Plan\n- [ ] Do thing");
      expect(readDeclaredPlan(planPath)).toBe("## My Plan\n- [ ] Do thing");
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("hasUncheckedItems", () => {
  it("returns true when plan has unchecked items", () => {
    expect(hasUncheckedItems("## Plan\n- [ ] Step 1\n- [x] Step 2")).toBe(true);
  });

  it("returns false when all items are checked", () => {
    expect(hasUncheckedItems("## Plan\n- [x] Step 1\n- [x] Step 2")).toBe(false);
  });

  it("returns false when plan has no checkboxes", () => {
    expect(hasUncheckedItems("## Plan\nJust some text")).toBe(false);
  });

  it("returns true for indented unchecked items", () => {
    expect(hasUncheckedItems("- [x] Done\n  - [ ] Sub-task")).toBe(true);
  });
});

describe("formatSessionDetail", () => {
  it("formats a full detail view", () => {
    const session: StatusSession = {
      sessionId: "s1",
      project: "claude-setup",
      worktree: "feature/x",
      sessionContext: "Working on X",
      plan: "Some plan",
      pendingCount: 0,
    };
    const text = formatSessionDetail(session);
    expect(text).toContain("claude-setup");
    expect(text).toContain("feature/x");
    expect(text).toContain("Working on X");
    expect(text).toContain("Some plan");
  });

  it("omits worktree line when not provided", () => {
    const session: StatusSession = {
      sessionId: "s1",
      project: "myproject",
      plan: null,
      pendingCount: 0,
    };
    const text = formatSessionDetail(session);
    expect(text).not.toContain("worktree:");
  });

  it("omits context line when not provided", () => {
    const session: StatusSession = {
      sessionId: "s1",
      project: "myproject",
      plan: null,
      pendingCount: 0,
    };
    const text = formatSessionDetail(session);
    expect(text).not.toContain("Context:");
  });

  it("shows pending questions with age when pendingCount > 0", () => {
    const session: StatusSession = {
      sessionId: "s1",
      project: "myproject",
      plan: null,
      pendingCount: 3,
      oldestPendingAge: 7500,
    };
    const text = formatSessionDetail(session);
    expect(text).toContain("3 pending questions");
    expect(text).toContain("2h ago");
  });

  it("shows state indicator when activity data is present", () => {
    const session: StatusSession = {
      sessionId: "s1",
      project: "myproject",
      plan: null,
      pendingCount: 0,
      lastActivityAge: 5,
    };
    const text = formatSessionDetail(session);
    expect(text).toContain("Active");
    expect(text).toContain("5s ago");
  });

  it("shows blocked state in detail view", () => {
    const session: StatusSession = {
      sessionId: "s1",
      project: "myproject",
      plan: null,
      pendingCount: 0,
      blockedOn: "Bash",
      blockedAge: 10,
      lastActivityAge: 10,
    };
    const text = formatSessionDetail(session);
    expect(text).toContain("Waiting for permission");
    expect(text).toContain("Bash");
  });
});

describe("formatStateIndicator", () => {
  it("returns 'Active' when lastActivityAge < 30", () => {
    const result = formatStateIndicator({ lastActivityAge: 12 });
    expect(result).toContain("Active");
    expect(result).toContain("12s ago");
  });

  it("returns 'Thinking' when lastActivityAge is 30-120", () => {
    const result = formatStateIndicator({ lastActivityAge: 45 });
    expect(result).toContain("Thinking");
    expect(result).toContain("45s ago");
  });

  it("returns 'Idle' when lastActivityAge > 120", () => {
    const result = formatStateIndicator({ lastActivityAge: 300 });
    expect(result).toContain("Idle");
    expect(result).toContain("5m ago");
  });

  it("returns 'Waiting for permission' when blockedOn is set", () => {
    const result = formatStateIndicator({ lastActivityAge: 5, blockedOn: "Bash" });
    expect(result).toContain("Waiting for permission");
    expect(result).toContain("Bash");
  });

  it("returns 'No activity data' when lastActivityAge is undefined", () => {
    const result = formatStateIndicator({});
    expect(result).toContain("No activity data");
  });

  it("auto-clears blockedOn when blockedAge exceeds 60s", () => {
    const result = formatStateIndicator({ lastActivityAge: 90, blockedOn: "Bash", blockedAge: 65 });
    expect(result).not.toContain("Waiting for permission");
    expect(result).toContain("Thinking");
  });
});
