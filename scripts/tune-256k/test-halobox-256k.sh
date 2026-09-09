#!/usr/bin/env bash
# 256k Context validation on halo-box master (5f851647f)
set -u

BIN=/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
FILLER=/home/user/source/haloq38flash/results/filler/filler-256k.txt
OUT=/home/user/source/haloq38flash/results/receipts-256k-opt
LOG="$OUT/halobox-256k-ub1024.log"

mkdir -p "$OUT"

for p in llama-cli llama-server llama-perplexity; do
    if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
done

echo "=== Running 256k context probe on halo-box master (5f851647f) ==="
export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

# Run via guard-relaxed with 3600s timeout
bash /home/user/source/haloq38flash/scripts/guard-relaxed.sh 3600 "$LOG" \
    "$BIN/llama-cli" \
    -m "$PLE" -f "$FILLER" -c 257024 \
    -dev Vulkan0 -ngl 999 -fa on \
    -ub 1024 -b 2048 \
    -ctk q8_0 -ctv q8_0 \
    -lm mmap -lzm on \
    -n 32 --temp 0 --reasoning off -st --simple-io \
    -md "$Q80" --spec-type draft-mtp \
    -t 4 -tb 16 \
    --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
    < /dev/null

echo "=== 256k halo-box probe finished ==="
