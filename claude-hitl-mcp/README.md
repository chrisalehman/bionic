# claude-hitl-mcp

Human-in-the-loop MCP server for Claude Code. Walk away from the terminal -- respond from your phone via Telegram.

## Setup

### First time (once, interactive)

1. Message [@BotFather](https://t.me/BotFather) in Telegram, send `/newbot`, copy the token
2. Run:
   ```bash
   export TELEGRAM_BOT_TOKEN="your-token-here"
   cd claude-hitl-mcp && npm install && npm run build
   node dist/cli.js setup
   ```
3. Send `/start` to your bot when prompted
4. Verify: `node dist/cli.js test`

### After first time (automatic)

`./claude-bootstrap.sh` in the parent repo handles everything: build, MCP registration, hooks, and listener daemon. No manual steps.

## How It Works

```
                      Telegram
                         |
                 [Listener Daemon]     ← owns the bot, runs 24/7
                  ~/.claude-hitl/sock
                   /            \
          [MCP Server]    [MCP Server]  ← one per Claude Code session
          (project A)     (project B)
```

A single listener daemon maintains the Telegram connection. MCP servers (one per Claude Code session) connect to it over a Unix socket. This prevents Telegram `409 Conflict` errors from multiple bot connections.

## MCP Tools

| Tool | Behavior | Use case |
|------|----------|----------|
| `ask_human` | Blocks until response | Decisions needing human input |
| `notify_human` | Fire and forget | Status updates, progress |
| `configure_hitl` | Session config | Set project context, timeout overrides |

## Priority System

| Priority | On timeout | Default | Example |
|----------|-----------|---------|---------|
| `critical` | Block forever + reminders | Never | Destructive ops, security |
| `architecture` | Return "paused" | 2 hours | System design, data models |
| `preference` | Auto-pick default option | 30 min | Naming, style choices |
| `fyi` | Never blocks | n/a | Progress updates |

## CLI

```
node dist/cli.js setup               First-time setup
node dist/cli.js test                Send test notification
node dist/cli.js status              Show config and connection
node dist/cli.js install-listener    Install listener daemon
node dist/cli.js uninstall-listener  Remove listener daemon
node dist/cli.js start-listener      Start listener
node dist/cli.js stop-listener       Stop listener
node dist/cli.js listener-logs       Tail logs
```

## Telegram Commands

| Command | Action |
|---------|--------|
| `/status` | Active sessions and pending requests |
| `/quiet` | Toggle quiet hours |
| `/help` | Available commands |

## Troubleshooting

**409 Conflict** -- Multiple bot connections. Fix: `node dist/cli.js stop-listener && node dist/cli.js start-listener`

**No notifications** -- Check: `node dist/cli.js status`, then `node dist/cli.js listener-logs`

**MCP tools missing** -- Run `claude mcp list`. If `claude-hitl` absent, re-run `./claude-bootstrap.sh` or register manually:
```bash
claude mcp add claude-hitl -e "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" -s user -- node /path/to/dist/server.js
```

## Development

```bash
npm install && npm run build    # Build
npm test                        # Run tests
npm run dev                     # Watch mode
```
