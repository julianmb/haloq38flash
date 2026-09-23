#!/usr/bin/env bash
# DEPRECATED — use scripts/build-engine-unified.sh (halo-box 8c1c282ec).
# Kept only to reproduce the original 5f851647f qualification build.
# (Retired 2026-09-23: unified engine supersedes it; see results/MANIFEST.md.)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${ENGINE_REPO_DIR:-$ROOT/repos/halo-box-strix-llama.cpp}"
BUILD_DIR="$REPO_DIR/build-5f851"
COMMIT="5f851647f"

if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning halo-box-strix-llama.cpp repository..."
    git clone https://github.com/halo-box/strix-llama.cpp "$REPO_DIR"
fi

cd "$REPO_DIR"
echo "Checking out qualified commit $COMMIT..."
git checkout "$COMMIT"

echo "Configuring CMake with GGML_VULKAN=ON..."
cmake -B "$BUILD_DIR" -S . \
    -DGGML_VULKAN=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=ON

echo "Building llama-cli, llama-server, and llama-perplexity..."
cmake --build "$BUILD_DIR" --target llama-cli llama-server llama-perplexity -j $(nproc)

echo "Build successful! Binaries available at $BUILD_DIR/bin/"
