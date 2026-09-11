#!/usr/bin/env bash
set -euo pipefail

# Downloads and installs fastchess and stockfish for use in CI.
# On Linux/macOS, stockfish is installed via the system package manager.
# On Windows (Git Bash), both are downloaded from GitHub releases.
# Usage: ./install-engines.sh [fastchess-dir] [stockfish-dir]
#   Directories default to ./fastchess-extract and ./stockfish-extract

FASTCHESS_DIR="${1:-./fastchess-extract}"
STOCKFISH_DIR="${2:-./stockfish-extract}"

PLATFORM="$(uname -s)-$(uname -m)"

case "$PLATFORM" in
  Linux-x86_64)
    OS=linux
    FC_URL="https://github.com/Disservin/fastchess/releases/download/v1.8.2-alpha/fastchess-linux-x86-64.tar"
    FC_SHA="1003f920bebe841acdab5e6d7871e93171a4586857b3ec91c21ef5777f26ff96"
    ;;
  Darwin-arm64)
    OS=macos
    FC_URL="https://github.com/Disservin/fastchess/releases/download/v1.8.2-alpha/fastchess-mac-arm64.tar"
    FC_SHA="a736371b1df3d7c67d4288dee66f6bb4e7e8193a945639c8a1d0aabfa612b551"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS=windows
    FC_URL="https://github.com/Disservin/fastchess/releases/download/v1.8.2-alpha/fastchess-windows-x86-64.zip"
    FC_SHA="007ce550dc809510b34622a1aeb43fd443d40284045bef5c1bc39c8941114143"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM" >&2
    exit 1
    ;;
esac

sha256check() {
  local file="$1" expected="$2"
  local actual
  if command -v sha256sum &>/dev/null; then
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
  else
    # Fallback for Windows Git Bash where sha256sum may not exist
    actual="$(certutil -hashfile "$file" SHA256 | sed -n '2p' | tr -d ' \r')"
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "SHA256 mismatch: expected $expected, got $actual" >&2
    rm -f "$file"
    exit 1
  fi
}

extract() {
  local archive="$1" dest="$2"
  if [[ "$archive" == *.zip ]]; then
    echo "archive zip: $archive"
    unzip -o "$archive" -d "$dest"
  else
    echo "archive tar: $archive"
    tar xf "$archive" -C "$dest"
  fi
}

# ── fastchess ──────────────────────────────────────────────────────────────
echo "Downloading fastchess"
FC_EXT="${FC_URL##*.}"
FC_ARCHIVE="$(mktemp).${FC_EXT}"
curl -fsSL -o "$FC_ARCHIVE" "$FC_URL"
sha256check "$FC_ARCHIVE" "$FC_SHA"

FC_TMPDIR="$(mktemp -d)"
echo "FC_ARCHIVE: $FC_ARCHIVE"
extract "$FC_ARCHIVE" "$FC_TMPDIR"
rm -f "$FC_ARCHIVE"

mkdir -p "$FASTCHESS_DIR"
find "$FC_TMPDIR" -type f -name 'fastchess*' -exec mv {} "$FASTCHESS_DIR/" \;
chmod +x "$FASTCHESS_DIR"/fastchess* 2>/dev/null || true
rm -rf "$FC_TMPDIR"

if [[ -f "$FASTCHESS_DIR/fastchess.exe" ]]; then
  mv "$FASTCHESS_DIR/fastchess.exe" "$FASTCHESS_DIR/fastchess"
fi
echo "fastchess installed to $FASTCHESS_DIR"

# ── stockfish ──────────────────────────────────────────────────────────────
case "$OS" in
  linux)
    sudo apt-get update -q
    sudo apt-get install -y -q stockfish
    STOCKFISH_BIN="$(command -v stockfish)"
    ;;
  macos)
    brew install stockfish
    STOCKFISH_BIN="$(command -v stockfish)"
    ;;
  windows)
    SF_URL="https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-windows-x86-64-universal.zip"
    SF_SHA="3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7"
    SF_ARCHIVE="$(mktemp)"
    curl -fsSL -o "$SF_ARCHIVE" "$SF_URL"
    sha256check "$SF_ARCHIVE" "$SF_SHA"

    SF_TMPDIR="$(mktemp -d)"
    unzip -o "$SF_ARCHIVE" -d "$SF_TMPDIR"
    rm -f "$SF_ARCHIVE"

    mkdir -p "$STOCKFISH_DIR"
    find "$SF_TMPDIR" -type f -name 'stockfish*.exe' -exec mv {} "$STOCKFISH_DIR/" \;
    rm -rf "$SF_TMPDIR"

    # Rename to extensionless for consistency with Linux/macOS
    SF_EXE="$(find "$STOCKFISH_DIR" -name 'stockfish*.exe' | head -1)"
    STOCKFISH_BIN="$PWD/$STOCKFISH_DIR/stockfish"
    mv "$SF_EXE" "$STOCKFISH_BIN"
    chmod +x "$STOCKFISH_BIN"
    ;;
esac
echo "stockfish installed: $STOCKFISH_BIN"

# ── Export paths for CI ────────────────────────────────────────────────────
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "FASTCHESS=$PWD/$FASTCHESS_DIR/fastchess" >> "$GITHUB_ENV"
  echo "TEST_ENGINE=$STOCKFISH_BIN" >> "$GITHUB_ENV"
fi
