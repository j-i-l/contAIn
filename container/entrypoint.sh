#!/bin/sh
# entrypoint.sh — contain container entrypoint
# =========================================================================
# This script runs as root at container startup. It:
#
#   1. Ensures required subdirectories exist inside bind-mounted volumes
#   2. Drops privileges to the agent user
#   3. Execs opencode with the original arguments
#
# Path identity:
#   Project directories are bind-mounted at their IDENTICAL host paths
#   (identity mounts, e.g. /home/alice/Projects -> /home/alice/Projects).
#   OpenCode clients (neovim plugin, TUI) therefore see exactly the same
#   directory strings inside and outside the container, which keeps
#   directory-scoped session listing stable. Podman creates the mountpoint
#   skeleton (root-owned, mode 755) automatically; the intermediate
#   directories contain nothing besides the mountpoints, so the agent can
#   traverse them but cannot read or create anything outside the mounts.
#
# Umask:
#   Sets umask 002 so agent-created files are 664 (group-writable) and
#   directories are 775. This ensures the primary user retains full access
#   to files the agent creates, via their shared group.
#
# =========================================================================
set -eu

# ── Ensure required subdirectories exist inside bind-mounted volumes ──────
# The host bind mount over ~/.local/share/opencode hides directories created
# at image build time. Create any subdirectories OpenCode expects here.
if [ "$(id -u)" = "0" ]; then
  mkdir -p /home/agent/.local/share/opencode/log
  chown agent: /home/agent/.local/share/opencode/log
fi

# ── Set umask for agent-created files ─────────────────────────────────────
# umask 002 → files are 664 (rw-rw-r--), dirs are 775 (rwxrwxr-x).
# This ensures the primary user can always read and write files created by
# the agent via group permissions (since agent shares the primary user's GID).
umask 002

# ── Drop privileges and exec opencode ────────────────────────────────────
# If already running as non-root (e.g., podman run --user agent), skip setpriv.
# Otherwise, drop from root to the agent user.
if [ "$(id -u)" = "0" ]; then
  AGENT_UID="$(id -u agent 2>/dev/null)"
  AGENT_GID="$(id -g agent 2>/dev/null)"
  AGENT_HOME="$(getent passwd agent 2>/dev/null | cut -d: -f6)"
  AGENT_HOME="${AGENT_HOME:-/home/agent}"
  exec setpriv --reuid="$AGENT_UID" --regid="$AGENT_GID" --init-groups \
    env HOME="$AGENT_HOME" \
        XDG_CONFIG_HOME="$AGENT_HOME/.config" \
        XDG_DATA_HOME="$AGENT_HOME/.local/share" \
        XDG_STATE_HOME="$AGENT_HOME/.local/state" \
    opencode "$@"
else
  exec opencode "$@"
fi
