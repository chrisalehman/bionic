import * as fs from "node:fs";
import { type ChatAdapter } from "../types.js";
import { ListenerClientAdapter } from "./listener-client.js";
import { TelegramAdapter } from "./telegram.js";

export function createAdapter(socketPath: string): ChatAdapter {
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
