#!/usr/bin/env bash
# Production 256k llama-server on halo-box engine with SSD-PLE, MTP, and Prompt Caching (<=96GB RAM)
set -euo pipefail

BIN="${LLAMA_SERVER_BIN:-/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin/llama-server}"
PLE="${PLE_MODEL:-/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf}"
MTP="${MTP_MODEL:-/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf}"
PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"

# Driver optimizations for AMD Strix Halo unified LPDDR5X
export RADV_PERFTEST=unified_heap
# Bound submission command buffers to prevent GPU watchdog lockups (amdgpu 10s timeout)
export GGML_VK_MAX_MB_PER_SUBMIT=2048

echo "Starting llama-server at http://${HOST}:${PORT}..."
echo "Memory budget: ~94.1 GB resident peak (within 96 GB target)"
echo "- Weights (SSD PLE): ~64.2 GB"
echo "- MTP Draft Sidecar: ~3.9 GB"
echo "- 256k KV Cache (q8_0): ~18.0 GB"
echo "- Prompt Cache (RAM): ~8.0 GB"

exec "$BIN" \
    -m "$PLE" \
    -md "$MTP" \
    --spec-type draft-mtp \
    --spec-draft-n-max 6 \
    --spec-draft-p-min 0.75 \
    -dev Vulkan0 -ngl 999 -fa on \
    -c 257024 -ub 1024 -b 2048 \
    -ctk q8_0 -ctv q8_0 \
    -t 4 -tb 16 \
    -lm mmap -lzm on \
    --cache-ram 8192 --ctx-checkpoints 32 --cache-prompt \
    --host "$HOST" --port "$PORT" \
    "$@"
