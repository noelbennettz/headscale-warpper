#!/usr/bin/env bash
# Remove hs from the given path (default: /usr/local/bin/hs).
#
# Only touches the hs script itself: headscale, jq and any HS_DEFAULT_USER you
# exported in your shell profile are left alone.
#
# usage: ./uninstall.sh [path] [--force]
set -euo pipefail

die() { printf 'uninstall: %s\n' "$*" >&2; exit 1; }

dest=/usr/local/bin/hs
force=0
while (($#)); do
	case $1 in
	-f | --force) force=1 ;;
	-*) die "unknown option: $1" ;;
	*) dest=$1 ;;
	esac
	shift
done

# The marker that identifies a file as ours, so we never delete a stranger.
marker='name-based wrapper around the headscale'

if [[ ! -e $dest ]]; then
	printf 'uninstall: %s is not installed (nothing to do)\n' "$dest"
	exit 0
fi

if ! grep -qF -- "$marker" "$dest" 2>/dev/null; then
	if ((force == 0)); then
		die "$dest does not look like hs, refusing (use --force to delete anyway)"
	fi
	printf 'uninstall: deleting %s even though it does not look like hs (--force)\n' "$dest" >&2
fi

if [[ ${HS_SKIP_ROOT_CHECK:-0} != 1 && $(id -u) -ne 0 ]]; then
	die "root is required to write $dest"
fi

rm -f -- "$dest"
printf 'removed %s\n' "$dest"

# Warn when another hs earlier in PATH would now shadow (or replace) it.
if other=$(command -v hs 2>/dev/null); then
	printf 'note: %s is still on PATH, check it if you expected hs to be gone\n' "$other" >&2
fi
