#!/usr/bin/env bash
set -euo pipefail

# Downloads and installs a fastchess binary into ./fastchess-extract/
# Usage: ./install-fastchess.sh [install-dir]
#   install-dir defaults to ./fastchess-extract

INSTALL_DIR="${1:-./fastchess-extract}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    URL="https://github.com/Disservin/fastchess/releases/download/v1.8.0-alpha/fastchess-linux-x86-64.tar"
    EXPECTED_SHA="23bc3774213a2e7db2755510ac974eb5bdc8397867ab1805cc57ccb8c635ba07"
    ;;
  Darwin-arm64)
    URL="https://github.com/Disservin/fastchess/releases/download/v1.8.0-alpha/fastchess-mac-arm64.tar"
    EXPECTED_SHA="5f5a313b8f8d6222a9914ba76f000197e3bfb3c919a12b9e92e6ac5d516b91fc"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    URL="https://github.com/Disservin/fastchess/releases/download/v1.8.0-alpha/fastchess-windows-x86-64.zip"
    EXPECTED_SHA="dcd5ad5c72237410f54dfc6e1af59f1088e72c2f67c29244fc974100791f3d13"
    ;;
  *)
    echo "Unsupported platform: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

ARCHIVE="$(mktemp)"
curl -sL -o "$ARCHIVE" "$URL"

if command -v sha256sum &>/dev/null; then
  ACTUAL_SHA="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
else
  # Fallback for Windows Git Bash where sha256sum may not exist
  ACTUAL_SHA="$(certutil -hashfile "$ARCHIVE" SHA256 | sed -n '2p' | tr -d ' ')"
fi
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "SHA256 mismatch for fastchess: expected $EXPECTED_SHA, got $ACTUAL_SHA" >&2
  rm -f "$ARCHIVE"
  exit 1
fi

TMPDIR="$(mktemp -d)"
if [[ "$URL" == *.zip ]]; then
  unzip -o "$ARCHIVE" -d "$TMPDIR"
else
  tar xf "$ARCHIVE" -C "$TMPDIR"
fi
rm -f "$ARCHIVE"

# Flatten: move the fastchess binary to INSTALL_DIR regardless of nesting
mkdir -p "$INSTALL_DIR"
find "$TMPDIR" -type f -name 'fastchess*' -exec mv {} "$INSTALL_DIR/" \;
chmod +x "$INSTALL_DIR"/fastchess* 2>/dev/null || true
rm -rf "$TMPDIR"

echo "fastchess installed to $INSTALL_DIR"
