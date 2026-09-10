#!/usr/bin/env bash
# Production 256k llama-server on halo-box engine with SSD-PLE, MTP, and Prompt Caching (<=96GB RAM)
set -euo pipefail

BIN="${LLAMA_SERVER_BIN:-/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-unified/bin/llama-server}"
if [ ! -f "$BIN" ]; then
    BIN="/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin/llama-server"
fi

PLE="${PLE_MODEL:-/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf}"
MTP="${MTP_MODEL:-/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf}"
if [ ! -f "$MTP" ]; then
    MTP="/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf"
fi

PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"

# Driver optimizations for AMD Strix Halo unified LPDDR5X
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SCRIPT_DIR/driver/radeon_icd.x86_64.json" ]; then
    export VK_ICD_FILENAMES="$SCRIPT_DIR/driver/radeon_icd.x86_64.json"
    export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
    export LD_LIBRARY_PATH="$SCRIPT_DIR/driver:$SCRIPT_DIR/repos/halo-box-strix-llama.cpp/build-unified/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

# Curated Vulkan MMID & Wavefront tuning for RDNA 3.5 (gfx1151)
export GGML_VK_MMID_ROWLISTS=1
export GGML_VK_MMID_SMALLN=1
export GGML_VK_MMID_BM64=1
export GGML_VK_MMID_WAVE32=1
export GGML_VK_MMID_F16B=1
export GGML_VK_MMID_M128=1
export GGML_VK_FA_WAVE32=0

echo "Starting unified llama-server at http://${HOST}:${PORT}..."
echo "Memory budget: ~94.1 GB resident peak (within 96 GB target)"
echo "- Weights (SSD PLE): ~64.2 GB"
echo "- MTP Draft Sidecar: ~2.6 GB (shared head) / ~3.9 GB"
echo "- 256k KV Cache (q8_0): ~18.0 GB"
echo "- Prompt Cache (RAM): ~8.0 GB"
echo "- CPU Pinning: CCX0 (cores 0-7)"

exec taskset -c 0-7 "$BIN" \
    -m "$PLE" \
    -md "$MTP" \
    --spec-type draft-mtp \
    --spec-draft-n-max 6 \
    --spec-draft-p-min 0.75 \
    -dev Vulkan0 -ngl 999 -fa on \
    -c 257024 -ub 2048 -b 4096 \
    -ctk q8_0 -ctv q8_0 \
    -t 4 -tb 16 \
    -lm mmap -lzm on \
    --cache-ram 8192 --ctx-checkpoints 32 --cache-prompt \
    --jinja \
    --host "$HOST" --port "$PORT" \
    "$@"
