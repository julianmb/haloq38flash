#!/usr/bin/env bash
# Build unified halo-box engine with QSA Pooled Key Cache and Recurrent Rollback MTP
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$ROOT/repos/halo-box-strix-llama.cpp"
BUILD_DIR="$REPO_DIR/build-unified"
COMMIT="dff600487" # Nathan Wilson v0.7.5 release base

if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning Nathanw1014/strix-halo-llamacpp repository..."
    git clone https://github.com/Nathanw1014/strix-halo-llamacpp.git "$REPO_DIR"
fi

cd "$REPO_DIR"
echo "Checking out base commit $COMMIT..."
git checkout "$COMMIT"

echo "Applying MTP recurrent rollback patch..."
git apply --check "$ROOT/patches/0001-mtp-recurrent-rollback-qwen4exp.patch" || true
git apply "$ROOT/patches/0001-mtp-recurrent-rollback-qwen4exp.patch" 2>/dev/null || echo "Patch already applied."

echo "Configuring CMake with GGML_VULKAN=ON..."
cmake -B "$BUILD_DIR" -S . \
    -DGGML_VULKAN=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=ON \
    -G Ninja

echo "Building llama-cli, llama-server, and llama-perplexity..."
ninja -C "$BUILD_DIR" llama-cli llama-server llama-perplexity

echo "Build successful! Binaries available at $BUILD_DIR/bin/"
