#!/usr/bin/env bash
# Copies the compiled Rust sni-spoofing binary into the bundle directory.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

OUT_DIR="$APP_DIR/bundle"
mkdir -p "$OUT_DIR"

RUST_BIN="/Users/javad/projects/sni-spoofing/target/release/sni-spoofing"

if [[ ! -f "$RUST_BIN" ]]; then
  echo "error: Rust binary not found at $RUST_BIN" >&2
  echo "Please build the Rust project first: cargo build --release" >&2
  exit 1
fi

echo "Copying Rust sni-spoofing binary to bundle as cloak-core..."

# Copy to host architecture (arm64)
cp -f "$RUST_BIN" "$OUT_DIR/cloak-core-arm64"
chmod +x "$OUT_DIR/cloak-core-arm64"
echo "✔ Copied arm64 binary"

# Copy to x86_64 (as a copy to prevent swift packaging errors or warnings)
cp -f "$RUST_BIN" "$OUT_DIR/cloak-core-x86_64"
chmod +x "$OUT_DIR/cloak-core-x86_64"
echo "✔ Copied x86_64 binary (copy of arm64)"

echo "✔ Done! Rust backend integration successful."
