#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2024-2026 Jonas I. Liechti <j-i-l@t4d.ch>
#
# SPDX-License-Identifier: CC-BY-NC-4.0
# contain-watcher.sh
# ---------------------------------------------------------------------------
# Inotify-based daemon that reassigns ownership of files created by the agent
# user back to the primary (human) user.
#
# Project files use the primary user's GID (mapped inside the container).
# The watcher also defensively ensures group-write (and setgid on directories)
# so that permissions are correct regardless of how the file was created
# (e.g. via entrypoint with umask 002, or via podman exec which inherits 022).
#
# Usage: contain-watcher.sh <primary_user> <agent_user> <project-dir>... --exclude <dir>...
# Legacy --runtime paths are exclusions too: private state is never normalized.
# ---------------------------------------------------------------------------
set -euo pipefail

PRIMARY_USER="${1:?Usage: $0 <primary_user> <agent_user> <dir> [<dir>...]}"
AGENT_USER="${2:?Usage: $0 <primary_user> <agent_user> <dir> [<dir>...]}"
shift 2

WATCH_DIRS=()
RUNTIME_DIRS=()
runtime=0
for dir in "$@"; do
  if [[ "$dir" == "--runtime" || "$dir" == "--exclude" ]]; then
    runtime=1
  elif [[ "$runtime" == 0 ]]; then
    WATCH_DIRS+=("$dir")
  else
    RUNTIME_DIRS+=("$dir")
  fi
done
if [[ ${#WATCH_DIRS[@]} -eq 0 ]]; then
  echo "Error: at least one project directory is required." >&2
  exit 1
fi

PRIMARY_UID=$(id -u "$PRIMARY_USER")
AGENT_UID=$(id -u "$AGENT_USER")
PRIMARY_GID=$(id -g "$PRIMARY_USER")

echo "contain watcher starting: primary=${PRIMARY_USER}(${PRIMARY_UID}) agent=${AGENT_USER}(${AGENT_UID})"
echo "Watching projects: ${WATCH_DIRS[*]}"
echo "Excluded private runtime: ${RUNTIME_DIRS[*]}"

ALL_WATCH_DIRS=("${WATCH_DIRS[@]}")

# Monitor for file creation and moves (which look like creates to the target).
# --recursive watches subdirectories as they appear.
inotifywait -m -r \
  -e create \
  -e moved_to \
  --format '%w%f' \
  "${ALL_WATCH_DIRS[@]}" | \
while IFS= read -r filepath; do
  # Guard: the path may have been deleted between event and processing.
  [[ -e "$filepath" && ! -L "$filepath" ]] || continue

  file_uid=$(stat -c '%u' "$filepath" 2>/dev/null) || continue

  is_runtime=0
  for runtime_dir in "${RUNTIME_DIRS[@]}"; do
    case "$filepath" in
      "$runtime_dir"|"$runtime_dir"/*) is_runtime=1; break ;;
    esac
  done

  if [[ "$is_runtime" == 1 ]]; then
    continue
  fi

  case "$filepath" in
    */.git|*/.git/*) continue ;;
  esac

  if [[ "$file_uid" == "$AGENT_UID" ]]; then
    chown --no-dereference "$PRIMARY_UID:$PRIMARY_GID" "$filepath" 2>/dev/null || true
    # Defensively ensure group-write (and setgid on directories) regardless
    # of the umask that was active when the file was created.
    if [[ -d "$filepath" ]]; then
      chmod u+rwx,g+rwx,g+s,o-rwx "$filepath" 2>/dev/null || true
    else
      chmod u+rw,g+rw,g+X,o-rwx "$filepath" 2>/dev/null || true
    fi
  fi
done
