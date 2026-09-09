#!/usr/bin/env bash
# Build qualified halo-box engine (commit 5f851647f) for Strix Halo Vulkan
set -euo pipefail

REPO_DIR="/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp"
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
