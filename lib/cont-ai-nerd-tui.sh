#!/usr/bin/env bash
# cont-ai-nerd-tui — Interactive TUI for cont-ai-nerd
# =========================================================================
# Attaches an interactive TUI to the running cont-ai-nerd container.
# All data (auth, database, model preferences) is persisted via the
# container's read-write bind mounts — no separate container needed.
#
# Authentication via /connect works directly: the server handles credential
# storage through its API and writes auth.json to the mounted data directory.
#
# Usage:
#   sudo cont-ai-nerd-tui              # Start interactive TUI
#   sudo cont-ai-nerd-tui --session X  # Resume session X
#
# =========================================================================
set -euo pipefail

# ── Check that the main container is running ─────────────────────────────
# Use systemctl is-active rather than `podman ps` because the container is
# managed as a rootful service; an unprivileged `podman ps` only sees the
# rootless namespace and would always report the container as not running.
if ! systemctl is-active --quiet cont-ai-nerd.service; then
  echo "Error: cont-ai-nerd container is not running." >&2
  echo "Start it with: systemctl start cont-ai-nerd" >&2
  exit 1
fi

# ── Attach TUI to the running container ──────────────────────────────────
# Run as the agent user (not root) so that files the TUI writes (model.json,
# prompt history, etc.) are owned by agent:primary_group and group-writable.
# The XDG variables ensure OpenCode resolves its config/data/state paths to
# the agent's home, matching the bind-mounted host directories.
# umask 002 mirrors the entrypoint's umask so new files are 664/dirs 775.
exec podman exec -it --user agent \
  -e HOME=/home/agent \
  -e XDG_CONFIG_HOME=/home/agent/.config \
  -e XDG_DATA_HOME=/home/agent/.local/share \
  -e XDG_STATE_HOME=/home/agent/.local/state \
  cont-ai-nerd sh -c 'umask 002 && exec opencode-tui "$@"' -- "$@"
