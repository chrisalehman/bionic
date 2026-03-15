import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { HitlConfig } from "./types.js";

export const HITL_CONFIG_DIR = path.join(os.homedir(), ".claude-hitl");
export const LEGACY_CONFIG_PATH = path.join(os.homedir(), ".claude-hitl.json");
const DEFAULT_CONFIG_PATH = path.join(HITL_CONFIG_DIR, "config.json");

export function resolveEnvValue(value: string): string {
  if (!value.startsWith("env:")) return value;
  const envKey = value.slice(4);
  const envVal = process.env[envKey];
  if (envVal === undefined) {
    throw new Error(
      `Environment variable ${envKey} is not set (referenced as "env:${envKey}" in config)`
    );
  }
  return envVal;
}

export function ensureConfigDir(dir: string): void {
  fs.mkdirSync(dir, { recursive: true });
}

export function migrateConfig(oldPath: string, newPath: string): void {
  if (!fs.existsSync(oldPath)) return;

  const newDir = path.dirname(newPath);
  ensureConfigDir(newDir);

  const content = fs.readFileSync(oldPath, "utf-8");

  // Verify it parses as valid JSON before writing
  JSON.parse(content);

  fs.writeFileSync(newPath, content, "utf-8");
  fs.unlinkSync(oldPath);
}

export function loadConfig(configPath?: string): HitlConfig | null {
  const filePath = configPath ?? process.env.CLAUDE_HITL_CONFIG ?? DEFAULT_CONFIG_PATH;
  if (!fs.existsSync(filePath)) return null;

  const raw = fs.readFileSync(filePath, "utf-8");
  const parsed = JSON.parse(raw);
  if (!parsed.adapter || typeof parsed.adapter !== "string") {
    throw new Error("Invalid config: missing required 'adapter' field");
  }
  return parsed as HitlConfig;
}

export function saveConfig(config: HitlConfig, configPath?: string): void {
  const filePath = configPath ?? DEFAULT_CONFIG_PATH;
  ensureConfigDir(path.dirname(filePath));
  fs.writeFileSync(filePath, JSON.stringify(config, null, 2) + "\n", "utf-8");
}
