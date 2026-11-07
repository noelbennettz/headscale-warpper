#!/usr/bin/env bash
# Smoke tests for hs, driven by test/fakebin/headscale + test/fixtures.
# Run with: ./test/smoke.sh
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hs=$here/../hs
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export PATH=$here/fakebin:$PATH
export HS_LOG=$tmp/calls.log
: >"$HS_LOG"

pass=0
fail=0

ok() {
	pass=$((pass + 1))
	printf 'ok   %s\n' "$1"
}

ng() {
	fail=$((fail + 1))
	printf 'FAIL %s\n' "$1"
	[[ -n ${2:-} ]] && printf '     expected to contain: %s\n' "$2"
	[[ -n ${3:-} ]] && printf '     actual output: %s\n' "$3"
}

check_contains() {
	local name=$1 want=$2 got=$3
	if [[ $got == *"$want"* ]]; then ok "$name"; else ng "$name" "$want" "$got"; fi
}

check_status() {
	local name=$1 want=$2 got=$3
	if [[ $got == "$want" ]]; then ok "$name"; else ng "$name" "exit=$want" "exit=$got"; fi
}

# Clear the call log before each mutating command so we can assert on the
# exact arguments handed to headscale.
reset_log() { : >"$HS_LOG"; }
log_grep() { grep -qF -- "$1" "$HS_LOG"; }

# ---------------------------------------------------------------- nodes

out=$("$hs" ls)
check_contains "ls: header" "NAME" "$out"
check_contains "ls: node appears in list" "laptop" "$out"
check_contains "ls: online state rendered" "offline" "$out"

out=$("$hs" show laptop)
check_contains "show: name resolved to ID" "ID          1" "$out"
check_contains "show: approved routes shown" "approved    192.168.1.0/24" "$out"

out=$("$hs" show 2)
check_contains "show: accepts an ID" "hostname    pixel-8" "$out"

out=$("$hs" show lap 2>&1)
check_status "show: ambiguous name exits 1" 1 $?
check_contains "show: ambiguous name lists candidates" "1:laptop, 3:laptop2" "$out"

out=$("$hs" show nosuch 2>&1)
check_status "show: unknown node exits 1" 1 $?
check_contains "show: unknown node message" "no such node: nosuch" "$out"

reset_log
out=$("$hs" rm phone 2>&1 </dev/null)
check_status "rm: refuses in non-interactive shell" 1 $?
check_contains "rm: non-interactive hint" "--force" "$out"

reset_log
out=$("$hs" rm phone --force)
check_contains "rm: confirmation message" "deleted phone (ID 2)" "$out"
log_grep "nodes delete -i 2 --force" && ok "rm: headscale arguments" || ng "rm: headscale arguments" "nodes delete -i 2 --force" "$(cat "$HS_LOG")"

reset_log
"$hs" rename phone pixel >/dev/null
log_grep "nodes rename -i 2 pixel" && ok "rename: arguments" || ng "rename: arguments" "nodes rename -i 2 pixel" "$(cat "$HS_LOG")"

reset_log
"$hs" tag phone tag:mobile tag:test >/dev/null
log_grep "nodes tag -i 2 -t tag:mobile -t tag:test" && ok "tag: arguments" || ng "tag: arguments" "nodes tag -i 2 -t tag:mobile -t tag:test" "$(cat "$HS_LOG")"

reset_log
"$hs" expire phone >/dev/null
log_grep "nodes expire -i 2" && ok "expire: logout now" || ng "expire: logout now" "nodes expire -i 2" "$(cat "$HS_LOG")"

reset_log
"$hs" expire phone --at 2026-02-01T00:00:00Z >/dev/null
log_grep "nodes expire -i 2 -e 2026-02-01T00:00:00Z" && ok "expire: explicit timestamp" || ng "expire: explicit timestamp" "-e 2026-02-01T00:00:00Z" "$(cat "$HS_LOG")"

reset_log
"$hs" expire phone --disable >/dev/null
log_grep "nodes expire -i 2 --disable" && ok "expire: disable" || ng "expire: disable" "--disable" "$(cat "$HS_LOG")"

# ---------------------------------------------------------------- routes

out=$("$hs" route)
check_contains "route: lists nodes that have routes" "192.168.1.0/24" "$out"
[[ $out == *"laptop2"* ]] && ng "route: nodes without routes are hidden" "no laptop2" "$out" || ok "route: nodes without routes are hidden"

reset_log
out=$("$hs" route add laptop 10.10.0.0/16 172.16.0.0/12)
check_contains "route add: reports merged list" "10.10.0.0/16,172.16.0.0/12,192.168.1.0/24" "$out"
log_grep "nodes approve-routes -i 1 -r 10.10.0.0/16,172.16.0.0/12,192.168.1.0/24" &&
	ok "route add: merges with existing approved routes" || ng "route add: merge" "merged list" "$(cat "$HS_LOG")"

reset_log
"$hs" route rm laptop >/dev/null
log_grep "nodes approve-routes -i 1 -r " && ok "route rm: no cidr withdraws everything" || ng "route rm: withdraw all" "-r (empty)" "$(cat "$HS_LOG")"

reset_log
"$hs" route rm laptop 192.168.1.0/24 >/dev/null
log_grep "nodes approve-routes -i 1 -r " && ok "route rm: last route leaves an empty list" || ng "route rm: last route" "-r (empty)" "$(cat "$HS_LOG")"

# ---------------------------------------------------------------- pre-auth keys

reset_log
out=$("$hs" key new -u alice -e 24h -r -E -t tag:vpn)
check_contains "key new: prints the key only" "preauthkey-abc123" "$out"
log_grep "preauthkeys create -u 1 -e 24h --reusable --ephemeral --tags tag:vpn" &&
	ok "key new: user name resolved to ID" || ng "key new: arguments" "user 1" "$(cat "$HS_LOG")"

reset_log
out=$(HS_DEFAULT_USER=bob "$hs" key new -e 30m)
log_grep "preauthkeys create -u 2 -e 30m" && ok "key new: HS_DEFAULT_USER honored" || ng "key new: HS_DEFAULT_USER" "-u 2" "$(cat "$HS_LOG")"

out=$("$hs" key ls)
check_contains "key ls: lists keys" "pk-aaaaaaaaaaaa" "$out"
check_contains "key ls: tags take precedence over owner" "tag:mobile" "$out"

reset_log
out=$("$hs" key rm 1 2)
check_contains "key rm: multiple IDs" "key 2" "$out"
log_grep "preauthkeys delete -i 1" && log_grep "preauthkeys delete -i 2" &&
	ok "key rm: arguments" || ng "key rm: arguments" "delete -i 1 and -i 2" "$(cat "$HS_LOG")"

out=$("$hs" key rm abc 2>&1)
check_status "key rm: rejects non-numeric ID" 1 $?

reset_log
"$hs" key expire 2 >/dev/null
log_grep "preauthkeys expire -i 2" && ok "key expire: arguments" || ng "key expire: arguments" "expire -i 2" "$(cat "$HS_LOG")"

# ---------------------------------------------------------------- users

out=$("$hs" user ls)
check_contains "user ls: lists users" "alice@example.com" "$out"

reset_log
"$hs" user new carol >/dev/null
log_grep "users create carol" && ok "user new: arguments" || ng "user new: arguments" "users create carol" "$(cat "$HS_LOG")"

reset_log
"$hs" user rm bob --force >/dev/null
log_grep "users destroy --name bob --force" && ok "user rm: by name" || ng "user rm: by name" "--name bob" "$(cat "$HS_LOG")"

reset_log
"$hs" user rm 2 --force >/dev/null
log_grep "users destroy --identifier 2 --force" && ok "user rm: by ID" || ng "user rm: by ID" "--identifier 2" "$(cat "$HS_LOG")"

# ---------------------------------------------------------------- deps and errors

out=$("$hs" version)
check_contains "version" "0.29.0" "$out"

out=$("$hs" nosuchcmd 2>&1)
check_status "unknown command exits 1" 1 $?
check_contains "unknown command message" "unknown command: nosuchcmd" "$out"

# Missing jq: PATH holds only bash and the fake headscale, so hs must stop
# with a hint instead of failing somewhere in the middle.
mkdir -p "$tmp/nojq"
ln -sf "$(command -v bash)" "$tmp/nojq/bash"
ln -sf "$here/fakebin/headscale" "$tmp/nojq/headscale"
out=$(PATH="$tmp/nojq" "$hs" ls 2>&1)
check_status "missing jq: exits 1" 1 $?
check_contains "missing jq: install hint" "jq not found" "$out"
[[ $out == *"preauthkey"* ]] && ng "missing jq: no other output" "" "$out" || ok "missing jq: only the hint"

out=$(PATH=/usr/bin:/bin HS_HEADSCALE_BIN=/nonexistent/headscale "$hs" ls 2>&1)
check_status "missing headscale: exits 1" 1 $?
check_contains "missing headscale: hint" "headscale binary not found" "$out"

# ---------------------------------------------------------------- install / uninstall

bindir=$tmp/bin
mkdir -p "$bindir"

out=$(HS_SKIP_ROOT_CHECK=1 "$here/../install.sh" "$bindir/hs" 2>&1)
check_status "install: succeeds" 0 $?
[[ -x $bindir/hs ]] && ok "install: file is executable" || ng "install: file is executable"

out=$(PATH=$here/fakebin:$bindir:$PATH "$bindir/hs" version 2>&1)
check_contains "install: installed copy runs" "0.29.0" "$out"

# A foreign file must not be deleted by accident.
printf '#!/bin/sh\necho not hs\n' >"$tmp/stranger"
out=$(HS_SKIP_ROOT_CHECK=1 "$here/../uninstall.sh" "$tmp/stranger" 2>&1)
check_status "uninstall: refuses unknown file" 1 $?
[[ -f $tmp/stranger ]] && ok "uninstall: unknown file kept" || ng "uninstall: unknown file kept"

out=$(HS_SKIP_ROOT_CHECK=1 "$here/../uninstall.sh" "$bindir/hs" 2>&1)
check_status "uninstall: succeeds" 0 $?
[[ -e $bindir/hs ]] && ng "uninstall: file removed" "" "still present" || ok "uninstall: file removed"

out=$(HS_SKIP_ROOT_CHECK=1 "$here/../uninstall.sh" "$bindir/hs" 2>&1)
check_status "uninstall: idempotent" 0 $?
check_contains "uninstall: reports nothing to do" "not installed" "$out"

# ---------------------------------------------------------------- summary

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
