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
# Never overwrite an initialized/ambiguous destination or an existing backup.
for destination in "$root" "$root.legacy-backup"; do
  if [[ -e "$destination" || -L "$destination" ]]; then
    echo "contain: migration destination already exists: $destination" >&2
    exit 1
  fi
done
if [[ -e "$root.migrating" || -L "$root.migrating" ]]; then
  [[ -d "$root.migrating" && ! -L "$root.migrating" ]] || {
    echo "contain: interrupted staging path is not a real directory" >&2
    exit 1
  }
  # Keep the entire failed copy behind a private operator-owned directory.
  # Start over from the quiescent sources; never merge partial SQLite files.
  archive=$(mktemp -d "$root.interrupted.XXXXXXXX")
  chmod 0700 "$archive"
  mv -T -- "$root.migrating" "$archive/state"
  echo "contain: retained interrupted migration at $archive" >&2
fi
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
# Package managers create relative node_modules/.bin links. Preserve them only
# if they resolve within the same migrated tree, including through link chains.
if [[ -n "$(find "$root.migrating" ! -type d ! -type f ! -type l -print -quit)" ]]; then
  echo "contain: legacy runtime contains special files; review required" >&2
  exit 1
fi
staging=$(realpath -e -- "$root.migrating")
for kind in config data state; do
  while IFS= read -r -d '' link; do
    target=$(readlink -- "$link")
    resolved=$(realpath -e -- "$link") || {
      echo "contain: runtime link is dangling or cyclic: $link" >&2
      exit 1
    }
    case "$target" in
      /*)
        echo "contain: absolute runtime link requires review: $link" >&2
        exit 1
        ;;
    esac
    case "$resolved" in
      "$staging/$kind"|"$staging/$kind/"*) ;;
      *)
        echo "contain: runtime link escapes its tree: $link" >&2
        exit 1
        ;;
    esac
  done < <(find "$root.migrating/$kind" -type l -print0)
done
find "$root.migrating" -type d -exec chmod 0700 {} +
find "$root.migrating" -type f -exec chmod u+rw,go-rwx {} +
# Independent copies: SQLite WAL/SHM and credentials remain recoverable even
# after the new server changes its database. Do not hardlink live state.
cp -a -- "$root.migrating" "$root.legacy-backup"
chown -- "$(id -u):$(id -g)" "$root.legacy-backup"
chmod 0700 "$root.legacy-backup"
chown -hR -P -- "$owner:$group" "$root.migrating"
touch "$root.migrating/.ready"
mv -T -- "$root.migrating" "$root"
