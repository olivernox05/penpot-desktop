#!/usr/bin/env bash
# Detects the running Penpot Desktop local instance and registers its
# MCP server with Claude Code and/or Claude Desktop.
#
# Usage:  ./scripts/setup-mcp.sh [port]
set -euo pipefail

PORT="${1:-}"

if [ -z "$PORT" ]; then
  # Find the published host port of a running Penpot frontend container.
  PORT="$(docker ps --filter "name=penpot-frontend" --format '{{.Ports}}' \
          | grep -oE '0\.0\.0\.0:[0-9]+->8080' | head -1 | cut -d: -f2 | cut -d- -f1 || true)"
fi

if [ -z "$PORT" ]; then
  echo "No running Penpot instance found."
  echo "Start one from Penpot Desktop (Settings -> Instances -> create a local instance),"
  echo "or pass the port explicitly:  ./scripts/setup-mcp.sh 9001"
  exit 1
fi

URL="http://localhost:${PORT}/mcp/stream"
echo "Penpot instance : http://localhost:${PORT}"
echo "MCP endpoint    : ${URL}"

echo -n "Checking MCP endpoint... "
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  -X POST "$URL" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"setup","version":"1.0"}}}' || true)"

if [ "$CODE" != "200" ]; then
  echo "FAILED (HTTP $CODE)"
  echo "The instance may still be booting - wait ~30s and retry."
  exit 1
fi
echo "OK"

if command -v claude >/dev/null 2>&1; then
  claude mcp remove penpot --scope user >/dev/null 2>&1 || true
  claude mcp add --scope user --transport http penpot "$URL"
  echo "Registered with Claude Code (user scope)."
else
  echo "Claude Code CLI not found; skipping."
fi

CD_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
if [ -f "$CD_CFG" ]; then
  cp "$CD_CFG" "${CD_CFG}.bak.$(date +%s)"
  node -e '
    const fs = require("fs");
    const p = process.argv[1], url = process.argv[2];
    const cfg = JSON.parse(fs.readFileSync(p, "utf8"));
    cfg.mcpServers = cfg.mcpServers || {};
    cfg.mcpServers.penpot = { type: "http", url };
    fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
  ' "$CD_CFG" "$URL"
  echo "Registered with Claude Desktop (backup saved). Restart Claude Desktop to load it."
fi

echo
echo "Next: in Penpot, open a file and choose  File -> MCP Server -> Connect."
