#!/usr/bin/env bash
# contain-tui — Interactive TUI for contain
# =========================================================================
# Attaches an interactive TUI to the running contain container.
# All data (auth, database, model preferences) is persisted via the
# container's read-write bind mounts — no separate container needed.
#
# Authentication via /connect works directly: the server handles credential
# storage through its API and writes auth.json to the mounted data directory.
#
# The TUI's working directory decides the OpenCode session `directory`
# identity. Project paths are identity-mounted (host path == container
# path), so the workdir must be one of the configured project paths:
#   --dir <path>   explicit choice (a project path or a subdirectory of one)
#   (omitted)      single project path -> used directly;
#                  multiple            -> interactive numbered menu.
#
# Usage:
#   sudo contain-tui                          # Start interactive TUI
#   sudo contain-tui --dir /home/a/Projects   # Pick the project directory
#   sudo contain-tui --session X              # Resume session X
#
# =========================================================================
set -euo pipefail

# ── Check that the main container is running ─────────────────────────────
# Use systemctl is-active rather than `podman ps` because the container is
# managed as a rootful service; an unprivileged `podman ps` only sees the
# rootless namespace and would always report the container as not running.
if ! systemctl is-active --quiet contain.service; then
  echo "Error: contain container is not running." >&2
  echo "Start it with: systemctl start contain" >&2
  exit 1
fi

# ── Load project paths from the container's mounted config ───────────────
mapfile -t project_paths < <(podman exec contain jq -r '.project_paths[]' /etc/contain/config.json)
if [[ ${#project_paths[@]} -eq 0 ]]; then
  echo "Error: no project_paths configured in /etc/contain/config.json." >&2
  exit 1
fi

usage() {
  echo "Usage: contain-tui [--dir <project-path>] [opencode-tui args...]" >&2
  echo "Project paths:" >&2
  printf '  %s\n' "${project_paths[@]}" >&2
}

# ── Parse arguments ───────────────────────────────────────────────────────
workdir=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      workdir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

# ── Resolve the working directory ─────────────────────────────────────────
if [[ -n "$workdir" ]]; then
  # Accept a project path or any directory beneath one.
  ok=""
  for p in "${project_paths[@]}"; do
    if [[ "$workdir" == "$p" || "$workdir" == "$p"/* ]]; then
      ok=1
      break
    fi
  done
  if [[ -z "$ok" ]]; then
    echo "Error: --dir must be a configured project path (or a subdirectory of one)." >&2
    usage
    exit 1
  fi
elif [[ ${#project_paths[@]} -eq 1 ]]; then
  workdir="${project_paths[0]}"
else
  echo "Select project directory:" >&2
  i=1
  for p in "${project_paths[@]}"; do
    echo "  $i) $p" >&2
    i=$((i + 1))
  done
  printf 'Choice [1-%d]: ' "${#project_paths[@]}" >&2
  read -r choice
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#project_paths[@]} )); then
    echo "Invalid choice." >&2
    exit 1
  fi
  workdir="${project_paths[$((choice - 1))]}"
fi

# ── Attach TUI to the running container ──────────────────────────────────
# Run as the agent user (not root) so that files the TUI writes (model.json,
# prompt history, etc.) are owned by agent:primary_group and group-writable.
# The XDG variables ensure OpenCode resolves its config/data/state paths to
# the agent's home, matching the bind-mounted host directories.
# umask 002 mirrors the entrypoint's umask so new files are 664/dirs 775.
exec podman exec -it --user agent \
  --workdir "$workdir" \
  -e HOME=/home/agent \
  -e XDG_CONFIG_HOME=/home/agent/.config \
  -e XDG_DATA_HOME=/home/agent/.local/share \
  -e XDG_STATE_HOME=/home/agent/.local/state \
  contain sh -c 'umask 002 && exec opencode-tui "$@"' -- "${args[@]+"${args[@]}"}"
