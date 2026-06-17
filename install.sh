#!/bin/sh
# tcast installer — downloads a prebuilt `tcast` binary from GitHub Releases,
# verifies its sha256, and installs it to ~/.local/bin (or /usr/local/bin).
#
#   curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/EijunnN/share-tui/main/install.sh | sh
#
# Env overrides:
#   TCAST_VERSION       release tag to install (default: latest)
#   TCAST_INSTALL_DIR   target directory (default: ~/.local/bin)
set -eu

REPO="EijunnN/share-tui"
BIN="tcast"
VERSION="${TCAST_VERSION:-latest}"

say() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "missing required tool: $1"; }

need uname
need tar
(command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1) || err "need curl or wget"

dl() {
  # dl <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -fLsS "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
  linux)  plat="unknown-linux-gnu" ;;
  darwin) plat="apple-darwin" ;;
  msys*|mingw*|cygwin*) err "on Windows use the PowerShell installer (install.ps1)" ;;
  *) err "unsupported OS: $os" ;;
esac

arch=$(uname -m | tr '[:upper:]' '[:lower:]')
case "$arch" in
  amd64|x86_64)  arch="x86_64" ;;
  arm64|aarch64) arch="aarch64" ;;
  *) err "no prebuilt binary for arch '$arch' — build from source with: cargo install --git https://github.com/$REPO tcast" ;;
esac

target="${arch}-${plat}"
asset="${BIN}-${target}.tar.gz"
base="https://github.com/${REPO}/releases"
if [ "$VERSION" = "latest" ]; then
  url="${base}/latest/download/${asset}"
else
  url="${base}/download/${VERSION}/${asset}"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "downloading ${asset} …"
dl "$url" "$tmp/$asset" || err "download failed (no prebuilt binary for $target?): $url"

# Verify checksum when the sidecar is available.
if dl "${url}.sha256" "$tmp/$asset.sha256" 2>/dev/null && [ -s "$tmp/$asset.sha256" ]; then
  ( cd "$tmp" && (sha256sum -c "$asset.sha256" >/dev/null 2>&1 || shasum -a 256 -c "$asset.sha256" >/dev/null 2>&1) ) \
    || err "checksum verification failed for $asset"
  say "checksum ok"
else
  say "warning: no checksum available, skipping verification"
fi

tar -xzf "$tmp/$asset" -C "$tmp"
# The archive holds a single staging dir containing the binary.
binpath=$(find "$tmp" -type f -name "$BIN" | head -n 1)
[ -n "$binpath" ] || err "binary '$BIN' not found in archive"

dir="${TCAST_INSTALL_DIR:-$HOME/.local/bin}"
if ! mkdir -p "$dir" 2>/dev/null; then
  dir="/usr/local/bin"
  SUDO="sudo"
fi
# Re-check writability; fall back to sudo for system dirs.
if [ ! -w "$dir" ] && [ -z "${SUDO:-}" ]; then SUDO="sudo"; fi

${SUDO:-} install -m 0755 "$binpath" "$dir/$BIN" || err "failed to install to $dir"
say "installed: $dir/$BIN"

case ":$PATH:" in
  *":$dir:"*) : ;;
  *)
    say ""
    say "note: $dir is not on your PATH. Add this to ~/.bashrc or ~/.zshrc:"
    say "    export PATH=\"$dir:\$PATH\""
    ;;
esac

say ""
say "done — try:  $BIN --help"
say "set your relay once:  $BIN config set-relay wss://relay.example.com"
