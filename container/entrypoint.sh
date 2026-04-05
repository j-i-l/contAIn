#!/bin/sh
# entrypoint.sh — cont-ai-nerd container entrypoint
# =========================================================================
# This script runs as root at container startup. It:
#
#   1. Reads path_map from /etc/cont-ai-nerd/config.json
#   2. Creates symlinks from host-side paths to their /workspace equivalents
#      so that OpenCode clients can use host-side paths as working directories
#   3. Drops privileges to the agent user
#   4. Execs opencode with the original arguments
#
# Why symlinks?
#   OpenCode clients (neovim plugin, TUI) connect with the host-side project
#   path (e.g., /home/alice/projects/foo). OpenCode uses this as the cwd for
#   shell commands. Without symlinks, this path doesn't exist inside the
#   container, causing posix_spawn to fail with ENOENT.
#
#   The symlinks create a minimal directory structure inside the container
#   (e.g., /home/alice/projects -> /workspace/projects) so that host-side
#   paths resolve correctly.
#
# Security:
#   - Intermediate directories (e.g., /home/alice) are owned by root:root
#     with mode 755. They contain nothing except the symlinks.
#   - The agent user can traverse these directories but cannot create files
#     or read anything that isn't part of the /workspace mount.
#
# =========================================================================
set -eu

CONFIG="/etc/cont-ai-nerd/config.json"

# ── Create symlinks from host paths to /workspace paths ──────────────────
# Only attempt symlink creation if running as root (normal startup).
# When invoked with --user=agent (e.g., debug/TUI), skip this step.
if [ "$(id -u)" = "0" ] && [ -f "$CONFIG" ]; then
  # Extract path_map entries: { "/home/alice/Projects": "/workspace/Projects", ... }
  # For each pair, mkdir -p the parent dir and create a symlink.
  jq -r '.path_map // {} | to_entries[] | "\(.key)\t\(.value)"' "$CONFIG" | \
  while IFS="$(printf '\t')" read -r host_path container_path; do
    [ -z "$host_path" ] && continue
    parent="$(dirname "$host_path")"
    mkdir -p "$parent"
    # Create or update the symlink
    ln -sfn "$container_path" "$host_path"
  done
fi

# ── Drop privileges and exec opencode ────────────────────────────────────
# If already running as non-root (e.g., podman run --user agent), skip setpriv.
# Otherwise, drop from root to the agent user.
if [ "$(id -u)" = "0" ]; then
  AGENT_UID="$(id -u agent 2>/dev/null || echo 1001)"
  AGENT_GID="$(id -g agent 2>/dev/null || echo 1001)"
  exec setpriv --reuid="$AGENT_UID" --regid="$AGENT_GID" --init-groups \
    opencode "$@"
else
  exec opencode "$@"
fi
