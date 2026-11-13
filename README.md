# hs — a minimal command line wrapper for headscale

Replaces headscale v0.29's `--identifier <id>` workflow with short, name-based
commands and stable table output that is easy to read and safe to pipe.

Built for running **on the headscale server itself** (root, systemd): no auth
layer, no transport, no web UI — it just calls the local `headscale` binary.

Typical use case: a handful of nodes on one box, where the stock CLI's
`--identifier` workflow is tedious and the web UI brings its own problems
(browser compatibility, expiring keys, OIDC setup).

## Requirements

- headscale (verified against the v0.29 CLI/JSON output)
- `jq` — a **hard dependency**. When it is missing, `hs` prints a hint and
  exits instead of failing halfway through:

  ```
  hs: jq not found. Install it first (Debian/Ubuntu: apt-get install -y jq, RHEL family: dnf install -y jq)
  ```

- `column` (util-linux) is optional; without it, an internal awk fallback
  aligns the columns.

Tested on Debian/Ubuntu with bash 5.x against headscale v0.29; nothing in the
script is Linux-specific beyond the usual coreutils.

## Install

```sh
./install.sh                 # copies to /usr/local/bin/hs (default)
./install.sh /usr/bin/hs     # or pick another path
```

You can also run it straight from the checkout; `HS_HEADSCALE_BIN` points it at
a specific binary:

```sh
HS_HEADSCALE_BIN=/usr/local/bin/headscale ./hs ls
```

## Uninstall

```sh
./uninstall.sh               # removes /usr/local/bin/hs
./uninstall.sh /usr/bin/hs   # if you installed it somewhere else
```

It only deletes the `hs` script and refuses to touch a file that does not look
like `hs` (use `--force` to override). Nothing else is removed: headscale, jq
and anything you exported yourself (`HS_DEFAULT_USER` etc.) are untouched.
Running it twice is fine — the second run reports nothing to do.

## Tests

`test/smoke.sh` uses a fake `headscale` (`test/fakebin/`) plus fixed JSON
fixtures (`test/fixtures/`) to check argument construction and parsing. It does
not need a real headscale and does not touch anything:

```sh
./test/smoke.sh     # 90 passed, 0 failed
```

The install/uninstall cases write into a temporary directory and need
`HS_SKIP_ROOT_CHECK=1`, which the test sets for itself; you should never need
that variable in normal use.

## Commands

| Command | Description |
| --- | --- |
| `hs` / `hs ls [user]` | List nodes (ID, name, user, addresses, online, last seen, expiry, tags) |
| `hs node <verb> ...` | The same node commands spelled headscale-style: `hs node rm gw-fmt-1` = `hs rm gw-fmt-1` |
| `hs show <node>` | Details for one node, including approved/available/serving routes |
| `hs rm <node...> [--force]` | Delete nodes, asks first |
| `hs rename <node> <new-name>` | Rename a node |
| `hs tag <node> <tag...>` | Overwrite tags; each tag must be `tag:lowercase` (see [Tags](#tags)) |
| `hs expire <node>` | Log out (forces re-authentication) |
| `hs expire <node> --at 2026-02-01T00:00:00Z` | Set an explicit expiry (RFC3339, see [Dates, durations and numbers](#dates-durations-and-numbers)) |
| `hs expire <node> --disable` | Disable expiry |
| `hs route [node]` | List nodes that have routes |
| `hs route add <node> <cidr...>` | Approve routes (**merged** with the existing ones) |
| `hs route rm <node> [cidr...]` | Withdraw routes; no cidr withdraws all |
| `hs key new [-u user] [-e 24h] [-r] [-E] [-t tag]` | Create a preauthkey (`-e` defaults to `1h`); stdout is the key only |
| `hs key ls` / `hs key rm <id...>` / `hs key expire <id...>` | List / delete / expire keys |
| `hs user ls` / `hs user new <name>` / `hs user rm <name\|id> [--force]` | User management |
| `hs version` / `hs help` | Version and help |

### Naming nodes

`<node>` accepts an ID or a name (matched against `given_name`, then
`hostname`). Names also match on a unique **prefix** — a name that only
contains the query does not match, so `hs show top` will not hit `laptop`. When
several nodes match, the candidates are listed and you are asked to use the ID:

```
$ hs show lap
hs: ambiguous node name: lap matches several (1:laptop, 3:laptop2), use the ID instead
```

### `hs node <verb>` — headscale-style spelling

Node commands also accept the two-word form you may be used to from the native
CLI: `hs node ls`, `hs node show`, `hs node rm`, `hs node rename`, `hs node
tag`, `hs node expire`, `hs node route` are exactly `hs ls`, `hs show`,
`hs rm`, ... An unknown verb is an error rather than a user filter:

```
$ hs node frobnicate gw
hs: unknown node subcommand: frobnicate (available: ls, show, rm, rename, tag, expire, route; to filter by user use: hs ls <user>)
```

### When headscale fails

`hs` keeps headscale's own explanation and drops the gRPC noise, so a wrong
user or a stopped server says why instead of just "failed":

```
$ hs ls rm
hs: failed to list nodes (user: rm): user not found (hs user ls lists the users)
```

### Dates, durations and numbers

`hs` forwards these values to headscale instead of re-implementing them, so the
formats and limits below are exactly what headscale v0.29 accepts. Anything else
comes back from the server as `parsing expiry time: ...` or
`parsing duration: ...`.

#### Expiry timestamps — `hs expire --at`

`--at` is a **point in time in RFC3339 form**: full date, time and a timezone
(`Z` or `±hh:mm`). It is not a duration and not a Unix timestamp. `hs` checks
that shape before calling headscale, so typos fail fast with an `hs:` hint
instead of a server-side parse error.

| Input | Accepted | Why |
| --- | --- | --- |
| `2026-02-01T00:00:00Z` | yes | UTC |
| `2026-02-01T08:00:00+08:00` | yes | explicit offset |
| `2026-02-01T00:00:00.500Z` | yes | fractional seconds are allowed |
| `2026-02-01` | no | date only |
| `2026-02-01T00:00:00` | no | missing timezone |
| `2026-02-01 00:00:00Z` | no | space instead of `T` |
| `1767225600` | no | epoch seconds; use the expanded date/time |
| `24h`, `7d` | no | `--at` is a timestamp, not a duration |

What the timestamp means:

- no `--at` → the node expires **now** (it is logged out and has to
  re-authenticate);
- `--at` in the past → same as expiring now;
- `--at` in the future → the node keeps working until that moment, then drops
  off and has to re-authenticate;
- `--disable` → the expiry is removed entirely (the node never expires), and the
  `EXPIRY` column of `hs ls` shows `-`;
- `--disable` together with `--at` → `--disable` wins: the expiry is removed and
  `--at` is not sent, though its shape is still checked so a typo does not go
  unnoticed.

Times are printed back in **UTC**, so a `+08:00` expiry comes back shifted.

Note the letter clash: `-e` means *timestamp* in `hs expire` but *duration* in
`hs key new`. Same letter, different grammar:

```sh
hs expire phone --at 2026-02-01T00:00:00Z   # a point in time
hs key new -u alice -e 24h                 # 24 hours from now
```

#### Preauthkey lifetime — `hs key new -e`

`-e` is a **duration counted from now**, parsed by headscale with Prometheus'
duration parser. Rules:

- units: `y` (365 d), `w` (7 d), `d` (24 h), `h`, `m`, `s`, `ms` — nothing else
  (`us`, `ns`, `M` for month are rejected);
- whole numbers only: `1.5h` is invalid, write `90m`;
- units must run from largest to smallest: `1d12h30m` is fine, `30m1d` is not;
- no negatives and no spaces;
- `0` is accepted but means "expires immediately", **not** "never expires";
- the default when `-e` is omitted is `1h` (headscale's own default);
- the upper bound is Go's `time.Duration`, about 292 years (`2562047h`); larger
  values fail with `duration out of range`.

```sh
hs key new -u alice            # expires in 1h
hs key new -u alice -e 30m     # half an hour to enroll the node
hs key new -u alice -e 7d -r   # one week, reusable
hs key new -u alice -e 8760h   # one year
```

Durations are the only way to get a long-lived key: there is no "forever"
preauthkey option, and `-e 0` hands you a key that is already expired.

#### IDs

Node, user and preauthkey IDs are unsigned integers assigned by headscale and
count from **1**; `0` is treated as "unset" and can never be a valid ID.
`hs key rm` and `hs key expire` take plain decimal numbers only — anything else
fails with `key ID must be numeric: <value>`, and `0` is refused locally with
`... must be 1 or greater: 0` rather than being sent to headscale. `hs rm`,
`hs show`, `hs rename`, `hs tag` and `hs expire` take an ID *or* a name;
`hs user rm` treats an all-digit argument as an ID and everything else as a
name.

### Tags

Tags come from headscale's ACL vocabulary and are validated server-side: each
one must start with `tag:` (so `tag:mobile`, not `mobile`), must be lowercase
and must not contain spaces. `hs tag <node> <tag...>` replaces the whole list,
so a node ends up with exactly the tags you name.

A node cannot be left with zero tags in v0.29 — headscale rejects an empty tag
list — so `hs tag <node>` with no tags fails immediately instead of sending a
request that cannot succeed:

```
$ hs tag phone
hs: headscale v0.29 cannot remove all tags from a node; pass at least one tag (e.g. tag:mobile)
```

### Environment

- `HS_HEADSCALE_BIN` — path to the headscale binary (default: `headscale`)
- `HS_DEFAULT_USER` — used when `-u` is omitted and only one user exists; set
  it to pin a user

## Sample output

```console
$ hs ls
ID  NAME     USER   ADDRESS                       ONLINE   LAST SEEN             EXPIRY                TAGS
1   laptop   alice  100.64.0.1,fd7a:115c:a1e0::1  online   2026-01-01T00:00:00Z  2027-01-15T08:00:00Z
2   phone    alice  100.64.0.2                    offline  2025-12-31T16:53:20Z  -                     tag:mobile
3   laptop2  bob    100.64.0.3                    online   2026-01-01T20:40:00Z  2023-11-14T22:13:20Z

$ hs show laptop
ID          1
name        laptop
hostname    laptop-hp
user        alice
address     100.64.0.1, fd7a:115c:a1e0::1
online      yes
last seen   2026-01-01T00:00:00Z
expiry      2027-01-15T08:00:00Z
tags        -
approved    192.168.1.0/24
available   192.168.1.0/24, 10.10.0.0/16
serving     192.168.1.0/24

$ hs route
ID  NAME    APPROVED        AVAILABLE                    SERVING
1   laptop  192.168.1.0/24  192.168.1.0/24,10.10.0.0/16  192.168.1.0/24

$ hs key ls
ID  KEY              REUSABLE  EPHEMERAL  USED  EXPIRY                OWNER
1   pk-aaaaaaaaaaaa  yes       no         no    2026-01-02T00:00:00Z  tag:mobile
2   pk-bbbbbbbbbbbb  no        yes        yes   2026-01-01T20:40:00Z  bob
```

(The rows above come from `test/fixtures`, i.e. synthetic data.)

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success, or the user cancelled a confirmation prompt |
| 1 | Anything else: missing jq/headscale, unknown node, ambiguous name, headscale itself failing, refusal in a non-interactive shell |

## Mapping to the native CLI

| hs | headscale |
| --- | --- |
| `hs ls` | `headscale nodes list -o json` + jq |
| `hs rm laptop --force` | `headscale nodes delete -i <id> --force` |
| `hs tag phone tag:x` | `headscale nodes tag -i <id> -t tag:x` |
| `hs expire phone` | `headscale nodes expire -i <id>` |
| `hs expire phone --at T` | `headscale nodes expire -i <id> -e T` |
| `hs expire phone --disable` | `headscale nodes expire -i <id> --disable` |
| `hs route add gw 10.0.0.0/8` | read `approved_routes`, then `nodes approve-routes -i <id> -r <merged>` |
| `hs route rm gw` | `nodes approve-routes -i <id> -r ""` |
| `hs key new -u alice -e 24h -r` | `preauthkeys create -u <user id> -e 24h --reusable` |
| `hs key rm 3` | `preauthkeys delete -i 3` |
| `hs user rm bob --force` | `users destroy --name bob --force` |

## Implementation notes

- Parsing assumptions: in v0.29, `--output json` is `encoding/json` marshalling
  the protobuf structs directly, so keys are **snake_case** (`given_name`,
  `approved_routes`, `ip_addresses`, ...), `id` is a number rather than a
  string, and timestamps look like `{"seconds":…,"nanos":…}`. Re-check these
  when bumping headscale by a major version.
- Timestamps are always shown in **UTC** (jq's `todate`).
- `hs route add` sends the full merged list because headscale's
  `approve-routes` is a replace operation.
- Destructive commands refuse to run in a non-interactive shell (pipe, cron)
  unless `--force` is given.
- Reads and writes both go through the same `headscale` binary; `hs` keeps no
  state of its own.

## License

MIT — see [LICENSE](LICENSE).

Release history: [CHANGELOG.md](CHANGELOG.md).
