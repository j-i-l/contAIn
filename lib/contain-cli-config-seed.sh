#!/usr/bin/env bash
# Merge declarative CLI preferences without replacing unrelated runtime keys.
set -euo pipefail
umask 0077

destination=${1:?CLI config destination required}
owner=${2:?agent UID required}
group=${3:?shared GID required}
seed=${4:?CLI settings seed required}

if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
  echo "contain: CLI config destination is not a regular file: $destination" >&2
  exit 1
fi
inputs=()
if [[ -e "$destination" ]]; then
  if ! jq -e 'type == "object"' "$destination" > /dev/null; then
    echo "contain: existing cli.json is not a strict JSON object; left unchanged" >&2
    exit 1
  fi
  inputs+=("$destination")
fi
if ! jq -e 'type == "object"' "$seed" > /dev/null; then
  echo "contain: CLI settings seed is not a strict JSON object" >&2
  exit 1
fi
inputs+=("$seed")
temporary=$(mktemp "$(dirname "$destination")/.cli.json.XXXXXXXX")
trap 'rm -f -- "$temporary"' EXIT
jq -s 'reduce .[] as $x ({}; . * $x)' "${inputs[@]}" > "$temporary"
chown -- "$owner:$group" "$temporary"
chmod 0600 "$temporary"
mv -fT -- "$temporary" "$destination"
