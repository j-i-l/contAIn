#!/usr/bin/env bash
set -euo pipefail
umask 0077

root=${1:?state root required}
home=${2:?legacy home required}
owner=${3:?agent UID required}
group=${4:?agent GID required}

[[ "$root" = /* && "$root" != / && ! -L "$root" ]] || exit 1
if [[ -f "$root/.ready" && ! -L "$root/.ready" ]]; then
  exit 0
fi
# Never overwrite an ambiguous destination or resume a partial SQLite copy.
for destination in "$root" "$root.migrating" "$root.legacy-backup"; do
  if [[ -e "$destination" || -L "$destination" ]]; then
    echo "contain: migration destination already exists: $destination" >&2
    exit 1
  fi
done
install -d -m 0700 "$root.migrating"
for kind in config data state; do
  case "$kind" in
    config) source="$home/.config/opencode" ;;
    data) source="$home/.local/share/opencode" ;;
    state) source="$home/.local/state/opencode" ;;
  esac
  if [[ -L "$source" ]]; then
    echo "contain: legacy runtime root is a symlink: $source" >&2
    exit 1
  fi
  install -d -m 0700 "$root.migrating/$kind"
  if [[ -d "$source" ]]; then
    cp -a -- "$source/." "$root.migrating/$kind/"
  fi
done
# Reject links and special files before changing ownership or permissions.
if [[ -n "$(find "$root.migrating" ! -type d ! -type f -print -quit)" ]]; then
  echo "contain: legacy runtime contains links or special files; review required" >&2
  exit 1
fi
find "$root.migrating" -type d -exec chmod 0700 {} +
find "$root.migrating" -type f -exec chmod u+rw,go-rwx {} +
# Independent copies: SQLite WAL/SHM and credentials remain recoverable even
# after the new server changes its database. Do not hardlink live state.
cp -a -- "$root.migrating" "$root.legacy-backup"
chown -- "$(id -u):$(id -g)" "$root.legacy-backup"
chmod 0700 "$root.legacy-backup"
chown -R -- "$owner:$group" "$root.migrating"
touch "$root.migrating/.ready"
mv -T -- "$root.migrating" "$root"
