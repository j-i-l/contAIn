#!/bin/sh
# SPDX-FileCopyrightText: 2024-2026 Jonas I. Liechti <j-i-l@t4d.ch>
#
# SPDX-License-Identifier: CC-BY-NC-4.0
# opencode-tui — Attach an interactive TUI to the running contain server
# ============================================================================
# This script runs inside the container and connects to the already-running
# OpenCode server instance, providing an interactive terminal UI.
#
# OpenCode v2 removed `opencode attach`; clients connect with the --server
# flag instead. If the server was started with OPENCODE_SERVER_PASSWORD
# (via the container's EnvironmentFile), the client authenticates with
# OPENCODE_PASSWORD.
#
# Usage:
#   podman exec -it contain opencode-tui
#   podman exec -it contain opencode-tui --session <id>
#
# The script reads HOST and PORT from the mounted config.json file.
# ============================================================================
set -eu

CONFIG="/etc/contain/config.json"

if [ ! -f "$CONFIG" ]; then
  echo "Error: Config file not found at $CONFIG" >&2
  echo "Make sure config.json is mounted into the container." >&2
  exit 1
fi

HOST=$(jq -r '.host // "127.0.0.1"' "$CONFIG")
PORT=$(jq -r '.port // 3000' "$CONFIG")

if [ -z "$HOST" ] || [ "$HOST" = "null" ]; then
  HOST="127.0.0.1"
fi

if [ -z "$PORT" ] || [ "$PORT" = "null" ]; then
  PORT="3000"
fi

# v2 clients authenticate with OPENCODE_PASSWORD; the server-side secret is
# OPENCODE_SERVER_PASSWORD from the container environment (EnvironmentFile).
# Only export it when set — an empty OPENCODE_PASSWORD would force auth on a
# server that has none.
if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  OPENCODE_PASSWORD="$OPENCODE_SERVER_PASSWORD"
  export OPENCODE_PASSWORD
fi

exec opencode --server "http://${HOST}:${PORT}" "$@"
