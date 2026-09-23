#!/usr/bin/env bash
# Build unified halo-box engine with QSA Pooled Key Cache and Recurrent Rollback MTP
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$ROOT/repos/halo-box-strix-llama.cpp"
BUILD_DIR="$REPO_DIR/build-unified"
COMMIT="8c1c282ecb194e8f02613defcc4a07c22b6d1c08" # halo-box master 2026-09-17 (upstream sync #64 + pwilkin #63)

if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning halo-box/strix-llama.cpp repository..."
    git clone https://github.com/halo-box/strix-llama.cpp "$REPO_DIR"
fi

cd "$REPO_DIR"
echo "Fetching and checking out base commit $COMMIT..."
git fetch origin "$COMMIT"
git checkout FETCH_HEAD

echo "Verifying upstream recurrent rollback MTP is present (retires patches/0001-mtp-*.patch)..."
grep -q TAG_RECURRENT_ROLLBACK_SPLITS src/models/qwen4exp.cpp \
    || { echo "ERROR: upstream recurrent rollback missing — MTP decode will regress. Aborting." >&2; exit 1; }
grep -q "case LLM_ARCH_QWEN4EXP:" src/llama-arch.cpp \
    || { echo "ERROR: QWEN4EXP rs-rollback arch gate missing. Aborting." >&2; exit 1; }

echo "Configuring CMake with GGML_VULKAN=ON..."
cmake -B "$BUILD_DIR" -S . \
    -DGGML_VULKAN=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=ON \
    -G Ninja

echo "Building llama-cli, llama-server, and llama-perplexity..."
ninja -C "$BUILD_DIR" llama-cli llama-server llama-perplexity

echo "Build successful! Binaries available at $BUILD_DIR/bin/"
