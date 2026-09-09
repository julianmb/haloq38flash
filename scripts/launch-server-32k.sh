#!/usr/bin/env bash
# Lightweight 32k/40k daily driver server with instant prompt caching
set -euo pipefail

BIN="${LLAMA_SERVER_BIN:-/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin/llama-server}"
PLE="${PLE_MODEL:-/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf}"
MTP="${MTP_MODEL:-/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf}"
PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"

export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

exec "$BIN" \
    -m "$PLE" \
    -md "$MTP" \
    --spec-type draft-mtp \
    --spec-draft-n-max 6 \
    --spec-draft-p-min 0.75 \
    -dev Vulkan0 -ngl 999 -fa on \
    -c 40960 -ub 1024 -b 2048 \
    -ctk q8_0 -ctv q8_0 \
    -t 4 -tb 16 \
    -lm mmap -lzm on \
    --cache-ram 8192 --ctx-checkpoints 32 --cache-prompt \
    --host "$HOST" --port "$PORT" \
    "$@"
