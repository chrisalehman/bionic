import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { loadConfig, resolveEnvValue, saveConfig, migrateConfig, ensureConfigDir } from "../src/config.js";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("resolveEnvValue", () => {
  it("resolves env: prefix from environment", () => {
    vi.stubEnv("MY_TOKEN", "secret123");
    expect(resolveEnvValue("env:MY_TOKEN")).toBe("secret123");
    vi.unstubAllEnvs();
  });

  it("returns literal value when no env: prefix", () => {
    expect(resolveEnvValue("literal-token")).toBe("literal-token");
  });

  it("throws when env var is not set", () => {
    expect(() => resolveEnvValue("env:MISSING_VAR")).toThrow("MISSING_VAR");
  });
});

describe("loadConfig", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "hitl-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("loads valid config file", () => {
    const configPath = path.join(tmpDir, ".claude-hitl.json");
    fs.writeFileSync(configPath, JSON.stringify({
      adapter: "telegram",
      telegram: { bot_token: "test-token", chat_id: 12345 },
    }));
    const config = loadConfig(configPath);
    expect(config?.adapter).toBe("telegram");
    expect(config?.telegram?.chat_id).toBe(12345);
  });

  it("returns null when file does not exist", () => {
    const config = loadConfig(path.join(tmpDir, "nope.json"));
    expect(config).toBeNull();
  });

  it("throws on invalid JSON", () => {
    const configPath = path.join(tmpDir, ".claude-hitl.json");
    fs.writeFileSync(configPath, "not json");
    expect(() => loadConfig(configPath)).toThrow();
  });

  it("resolves CLAUDE_HITL_CONFIG env var as config path", () => {
    const configPath = path.join(tmpDir, "custom.json");
    fs.writeFileSync(configPath, JSON.stringify({ adapter: "telegram" }));
    vi.stubEnv("CLAUDE_HITL_CONFIG", configPath);
    const config = loadConfig();
    expect(config?.adapter).toBe("telegram");
    vi.unstubAllEnvs();
  });

  it("throws when config is missing required adapter field", () => {
    const configPath = path.join(tmpDir, ".claude-hitl.json");
    fs.writeFileSync(configPath, JSON.stringify({ telegram: {} }));
    expect(() => loadConfig(configPath)).toThrow("adapter");
  });
});

describe("saveConfig", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "hitl-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes config as formatted JSON", () => {
    const configPath = path.join(tmpDir, ".claude-hitl.json");
    const config = { adapter: "telegram", telegram: { bot_token: "env:TOKEN", chat_id: 123 } };
    saveConfig(config, configPath);
    const raw = fs.readFileSync(configPath, "utf-8");
    expect(JSON.parse(raw)).toEqual(config);
    expect(raw).toContain("\n");
  });
});

describe("config migration", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "hitl-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("migrates config from old path to new directory", async () => {
    const oldPath = path.join(tmpDir, ".claude-hitl.json");
    const newDir = path.join(tmpDir, ".claude-hitl");
    const newPath = path.join(newDir, "config.json");

    fs.writeFileSync(oldPath, JSON.stringify({ adapter: "telegram" }));
    migrateConfig(oldPath, newPath);

    expect(fs.existsSync(newPath)).toBe(true);
    expect(fs.existsSync(oldPath)).toBe(false);
    const content = JSON.parse(fs.readFileSync(newPath, "utf-8"));
    expect(content.adapter).toBe("telegram");
  });

  it("handles case where both old and new exist (re-attempt)", () => {
    const oldPath = path.join(tmpDir, ".claude-hitl.json");
    const newDir = path.join(tmpDir, ".claude-hitl");
    const newPath = path.join(newDir, "config.json");

    fs.mkdirSync(newDir, { recursive: true });
    fs.writeFileSync(oldPath, JSON.stringify({ adapter: "telegram" }));
    fs.writeFileSync(newPath, JSON.stringify({ adapter: "old" }));

    migrateConfig(oldPath, newPath);

    const content = JSON.parse(fs.readFileSync(newPath, "utf-8"));
    expect(content.adapter).toBe("telegram");
    expect(fs.existsSync(oldPath)).toBe(false);
  });

  it("no-ops when old path does not exist", () => {
    const oldPath = path.join(tmpDir, "nonexistent.json");
    const newPath = path.join(tmpDir, ".claude-hitl", "config.json");

    migrateConfig(oldPath, newPath);
    expect(fs.existsSync(newPath)).toBe(false);
  });
});

describe("ensureConfigDir", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "hitl-test-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("creates directory if it does not exist", () => {
    const dir = path.join(tmpDir, "new-dir");
    ensureConfigDir(dir);
    expect(fs.existsSync(dir)).toBe(true);
  });

  it("no-ops if directory already exists", () => {
    const dir = path.join(tmpDir, "existing-dir");
    fs.mkdirSync(dir);
    ensureConfigDir(dir);
    expect(fs.existsSync(dir)).toBe(true);
  });
});
