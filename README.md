# tcast — share-terminal

**Twitch/Kick, but for terminals.** A streamer shares their live terminal; spectators
open a CLI, browse the live streams (or join a private one by code) and watch in
real time — read-only.

```
┌─ HOST (streamer) ─┐        ┌─ RELAY (server) ─┐        ┌─ WATCH (spectator) ─┐
│ your shell in a   │  wss   │ registry + fan-  │  wss   │ ratatui browser +   │
│ PTY, mirrored     │ ─────▶ │ out + vt100      │ ─────▶ │ vt100/tui-term view │
│ locally + sent up │        │ snapshots        │        │ (read-only)         │
└───────────────────┘        └──────────────────┘        └─────────────────────┘
```

There are two programs:

- **`tcast`** — the client everyone installs. One command, with subcommands to
  stream (`tcast stream`) or watch (`tcast watch`).
- **`tcast-relay`** — the server. The operator runs one on a VPS; end users never
  install it.

## Install (end users)

Prebuilt binaries, no Rust toolchain needed:

```sh
# Linux / macOS
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/EijunnN/share-tui/main/install.sh | sh
```
```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/EijunnN/share-tui/main/install.ps1 | iex
```

The installer drops `tcast` on your `PATH`. Then point it at a relay once:

```sh
tcast config set-relay wss://relay.example.com
```

> No prebuilt binary for your platform? Install with Cargo instead:
> `cargo install --git https://github.com/EijunnN/share-tui tcast`

## Use it

```sh
tcast                       # open the stream browser (read-only viewer)
tcast watch                 # same as above
tcast watch <code>          # join a private stream directly by its code
tcast list                  # print the public directory (add --json for scripts)
tcast stream                # stream your terminal (private, code-only)
tcast stream --public       # …and list it in the public directory
```

Per-command relay override: `tcast --relay wss://other.example.com watch`, or set
the `TCAST_RELAY` environment variable. Precedence: `--relay` / `TCAST_RELAY` →
saved config (`tcast config set-relay`) → built-in default → `ws://127.0.0.1:4455`.

**Host hotkeys:** `Ctrl-O p` privacy toggle · `Ctrl-O q` quit · `Ctrl-O Ctrl-O` literal Ctrl-O.
**Watch keys:** `↑/↓` move · `Enter` watch · `r` refresh · `q`/`Esc` back/quit · `Ctrl-C` quit.

## Why it's safe to watch (and to stream)

- **Read-only by construction.** The wire protocol has *no* message that carries a
  spectator's keystrokes toward a host. A viewer literally cannot type into your
  shell — it's a property of the types, not a runtime check.
- **Privacy toggle.** Press `Ctrl-O p` in the host to pause what viewers see
  (e.g. while typing a password); press again to resume.
- **Private by default.** A stream is reachable only by its generated code unless
  you pass `--public` to list it in the global directory.
- **Optional host auth.** Operators can require a shared key (`--auth-key`) so not
  just anyone can stream through your relay.

## Workspace layout

| crate      | what it is                                                              |
|------------|-------------------------------------------------------------------------|
| `protocol` | shared message types + MessagePack codec (the wire contract)            |
| `host`     | library: spawns your shell in a PTY, mirrors output locally and up      |
| `watch`    | library: spectator TUI + non-interactive `list`                         |
| `cli`      | the `tcast` binary — clap front-end dispatching to `host` / `watch`     |
| `relay`    | the `tcast-relay` binary: stream registry, fan-out, late-join snapshots |

## Build from source

### Windows
Needs the MSVC toolchain **with the Windows SDK** (for `kernel32.lib` etc.):

```powershell
# one-time, if missing:
winget install --id Microsoft.WindowsSDK.10.0.26100 -e

# build (loads the VS dev environment first):
. .\tools\msvcenv.ps1
cargo build --release
```

### Linux / macOS
```bash
cargo build --release            # everything
cargo build --release -p tcast   # just the client
cargo build --release -p relay   # just the server (binary: tcast-relay)
```

This produces `target/release/tcast` and `target/release/tcast-relay`. TLS uses
`native-tls` (SChannel on Windows, Secure Transport / OpenSSL elsewhere),
avoiding the C toolchain that rustls/aws-lc would pull in.

## Run it locally (three terminals)

```bash
# 1) relay
cargo run -p relay                              # listens on 0.0.0.0:4455

# 2) host (streamer) — starts your shell, now being streamed
cargo run -p tcast -- stream --relay ws://127.0.0.1:4455 --public
#   prints a join code and share instructions

# 3) watch (spectator)
cargo run -p tcast -- watch --relay ws://127.0.0.1:4455
#   browse the list, ↑/↓ + Enter to watch; or join a private code:
cargo run -p tcast -- watch --relay ws://127.0.0.1:4455 <code>
```

## CLI reference

**tcast**
```
tcast [--relay URL] [--config PATH] [COMMAND]
  (no command)             open the watch browser
  stream [--name NAME] [--shell SHELL] [--public] [--auth-key KEY]
  watch  [CODE_OR_ID]
  list   [--json]
  config set-relay <URL> | set-auth-key <KEY> | set-name <NAME> | show [--path]
```

**tcast-relay** (operator only)
```
tcast-relay [--bind ADDR] [--auth-key KEY]
  --bind       default 0.0.0.0:4455
  --auth-key   shared host secret (or env SHARE_TERMINAL_AUTH_KEY)
```

## Deploy the relay on a VPS (internet, with TLS)

The relay speaks plain HTTP/WS and expects TLS to be terminated by a reverse proxy.

1. Build on the server: `cargo build --release -p relay` (binary: `target/release/tcast-relay`).
2. Put [Caddy](https://caddyserver.com) in front for automatic TLS — see
   [`deploy/Caddyfile`](deploy/Caddyfile). Caddy proxies WebSocket upgrades transparently.
3. Run the relay under systemd — see
   [`deploy/share-terminal-relay.service`](deploy/share-terminal-relay.service).
   Set `SHARE_TERMINAL_AUTH_KEY` to require a host key.

Then everyone uses `wss://relay.example.com`:
```
tcast config set-relay wss://relay.example.com
tcast stream --public --auth-key change-me
tcast watch
```

`GET /api/streams` returns the public list as JSON (handy for monitoring / a future web UI).

## Releases

Tagging a commit `vX.Y.Z` triggers [`.github/workflows/release.yml`](.github/workflows/release.yml),
which builds `tcast` for Linux (x86_64/aarch64, glibc), macOS (Intel/Apple Silicon)
and Windows (x86_64), and uploads the archives + sha256 checksums to a GitHub
Release. The `install.sh` / `install.ps1` one-liners above download from there.

To bake a default relay into the released binaries (so a fresh `tcast` works with
zero config), set the repository variable `TCAST_DEFAULT_RELAY` (e.g.
`wss://relay.example.com`).

## Status / roadmap

- [x] Read-only CLI streaming over wss, public list + private codes, late-join snapshots,
      privacy toggle, live viewer counts, resize handling.
- [x] Unified `tcast` client (stream/watch/list/config) + curl/PowerShell installers.
- [x] Robustness: watcher auto-reconnect with backoff (and auto-rejoin), frame-size limits,
      stream-count cap, constant-time auth-key check, private streams joinable only by code.
- [ ] Known follow-ups: static **musl** Linux build for Alpine/old-glibc (needs vendored
      OpenSSL or an rustls switch), per-IP connection limiting, watcher scrollback,
      in-TUI private-code entry, optional accounts, a web viewer.
```
