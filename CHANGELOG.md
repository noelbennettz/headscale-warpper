# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-11-13

First release: a name-based wrapper around the local headscale (v0.29) CLI.

### Added

- Node commands by name or ID: `hs ls [user]`, `hs show`, `hs rm`, `hs rename`,
  `hs tag`, `hs expire` (`--at RFC3339` / `--disable`).
- `hs node <verb> ...` — the headscale-style two-word spelling of the node
  commands, so muscle memory from the native CLI works.
- Subnet routes: `hs route [node]`, `hs route add`, `hs route rm`; `add` merges
  with the approved routes because `nodes approve-routes` replaces the list.
- Preauthkeys: `hs key new` (`-u`, `-e`, `-r`, `-E`, `-t`), `hs key ls`,
  `hs key rm`, `hs key expire`.
- Users: `hs user ls`, `hs user new`, `hs user rm`.
- `install.sh` and `uninstall.sh`: root-checked, idempotent, and refused on a
  file that does not carry the `hs` marker (override with `--force`).
- `test/smoke.sh`: 90 assertions driven by a fake `headscale` binary and fixed
  JSON fixtures; no real server needed.

### Changed

- Table output is aligned by `column` when available and by `awk` otherwise;
  trailing padding is stripped so piped output carries no trailing whitespace.
- Names match exactly first and then on a unique prefix; an ambiguous prefix
  lists the candidates instead of guessing.
- Headscale's own error text is preserved (the `rpc error: ... desc = ` prefix
  is dropped), e.g. `failed to list nodes (user: rm): user not found`.

### Notes

- Requires bash, `jq` and a local `headscale` binary (`HS_HEADSCALE_BIN` to
  override); `column` is optional.
- Parsing is verified against headscale v0.29 JSON output (`snake_case` fields,
  numeric IDs, protobuf `{seconds, nanos}` timestamps).
- Destructive commands (`hs rm`, `hs user rm`) refuse to run in a
  non-interactive shell unless `--force` is given.

[1.0.0]: https://github.com/noelbennettz/headscale-warpper/releases/tag/v1.0.0