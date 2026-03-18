#!/usr/bin/env node
// session-start.mjs — SessionStart hook: send session notification via Telegram.
// In RC mode: sends a tappable Remote Control link.
// Without RC: sends a simple "session started" notification.

import { readFileSync } from "node:fs";
import { basename } from "node:path";

/**
 * Build the Telegram message text. Exported for testing.
 * @param {object} env - Environment variables (subset)
 * @param {object} input - Parsed JSON from stdin (session_id, cwd)
 * @returns {{ text: string, sessionId: string } | null}
 */
export function buildMessage(env, input) {
  const sessionId = input.session_id;
  if (!sessionId) return null;

  const project = input.cwd ? basename(input.cwd) : "";
  const prefix = project ? `[${project}] ` : "";
  const isRemote =
    env.CLAUDE_CODE_REMOTE === "true" ||
    !!env.CLAUDE_CODE_SESSION_ACCESS_TOKEN;

  let text;
  if (isRemote) {
    const url = `https://claude.ai/code/${sessionId}`;
    text = `🔔 ${prefix}Claude Code session started\n\n${url}`;
  } else {
    text = `🔔 ${prefix}Claude Code session started (local)`;
  }

  return { text, sessionId };
}

// --- Main (guarded so importing for tests doesn't trigger side effects) ---

const isMain = process.argv[1] &&
  new URL(process.argv[1], "file://").pathname ===
  new URL(import.meta.url).pathname;

if (isMain) {
  const token = process.env.NUDGE_TELEGRAM_TOKEN;
  const chatId = process.env.NUDGE_TELEGRAM_CHAT_ID;
  if (!token || !chatId) process.exit(0);

  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch {
    process.exit(0);
  }

  const msg = buildMessage(process.env, input);
  if (!msg) process.exit(0);

  try {
    await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text: msg.text }),
    });
  } catch {
    // Silent failure — don't block session start
  }
}
