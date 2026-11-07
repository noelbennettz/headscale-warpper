#!/usr/bin/env bash
# Install hs to the given path (default: /usr/local/bin/hs).
set -euo pipefail

src=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hs
dest=${1:-/usr/local/bin/hs}

[[ -f $src ]] || {
	printf 'install: %s not found\n' "$src" >&2
	exit 1
}
[[ $(id -u) -eq 0 ]] || {
	printf 'install: root is required to write %s\n' "$dest" >&2
	exit 1
}

install -m 0755 "$src" "$dest"
printf 'installed %s\n' "$dest"

for bin in jq headscale; do
	command -v "$bin" >/dev/null 2>&1 ||
		printf 'warning: %s not found, hs will complain about it at runtime\n' "$bin" >&2
done
