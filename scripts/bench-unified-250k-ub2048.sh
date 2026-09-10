#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/repos/halo-box-strix-llama.cpp/build-unified/bin/llama-cli"
PLE="/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf"
FILLER="$ROOT/results/filler/filler-250k.txt"
OUT_DIR="$ROOT/results/receipts-further-opts"
mkdir -p "$OUT_DIR"

RUN_LOG="$OUT_DIR/15-unified-ub2048-250k.log"
MEM_LOG="$OUT_DIR/15-unified-ub2048-250k-mem.log"

echo "=== Benchmarking Unified Engine (ub 2048, CCX0, QSA key cache) at 250k tokens ==="
echo "Binary: $BIN"
echo "Model: $PLE"
echo "Prompt: $FILLER"
echo "Context: 262144"
echo "Microbatch (-ub): 2048"
echo "Batch (-b): 4096"
echo "Started at: $(date -Iseconds)"

# Start memory monitor in background
(
  echo "timestamp,elapsed_s,rss_mb,vsz_mb,sys_used_mb,sys_avail_mb" > "$MEM_LOG"
  START_TIME=$(date +%s)
  while true; do
    CURR_TIME=$(date +%s)
    ELAPSED=$((CURR_TIME - START_TIME))
    PID=$(pgrep -f "llama-cli.*filler-250k" | head -n 1 || true)
    if [ -n "$PID" ]; then
      PS_OUT=$(ps -p "$PID" -o rss=,vsz= 2>/dev/null || echo "0 0")
      RSS_KB=$(echo "$PS_OUT" | awk '{print $1}')
      VSZ_KB=$(echo "$PS_OUT" | awk '{print $2}')
      RSS_MB=$((RSS_KB / 1024))
      VSZ_MB=$((VSZ_KB / 1024))
    else
      RSS_MB=0
      VSZ_MB=0
    fi
    SYS_USED_MB=$(free -m | awk '/Mem:/ {print $3}')
    SYS_AVAIL_MB=$(free -m | awk '/Mem:/ {print $7}')
    echo "$(date +%T),$ELAPSED,$RSS_MB,$VSZ_MB,$SYS_USED_MB,$SYS_AVAIL_MB" >> "$MEM_LOG"
    sleep 5
  done
) &
MONITOR_PID=$!

trap "kill $MONITOR_PID 2>/dev/null || true" EXIT

# Driver & Vulkan environment variables
if [ -f "$ROOT/driver/radeon_icd.x86_64.json" ]; then
    export VK_ICD_FILENAMES="$ROOT/driver/radeon_icd.x86_64.json"
    export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
    export LD_LIBRARY_PATH="$ROOT/driver:$ROOT/repos/halo-box-strix-llama.cpp/build-unified/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

export GGML_VK_MMID_ROWLISTS=1
export GGML_VK_MMID_SMALLN=1
export GGML_VK_MMID_BM64=1
export GGML_VK_MMID_WAVE32=1
export GGML_VK_MMID_F16B=1
export GGML_VK_MMID_M128=1
export GGML_VK_FA_WAVE32=0

# Run llama-cli pinned to CCX0 (cores 0-7)
timeout 1200 taskset -c 0-7 "$BIN" \
    -m "$PLE" \
    -f "$FILLER" \
    -c 262144 \
    -dev Vulkan0 \
    -ngl 999 \
    -fa on \
    -ub 2048 \
    -b 4096 \
    -ctk q8_0 \
    -ctv q8_0 \
    -lm mmap \
    -n 16 \
    --temp 0 \
    --reasoning off \
    -st \
    --simple-io \
    -t 4 \
    -tb 16 \
    < /dev/null > "$RUN_LOG" 2>&1

echo "Finished at: $(date -Iseconds)"
kill "$MONITOR_PID" 2>/dev/null || true
trap - EXIT

grep -E "Prompt:|Generation:" "$RUN_LOG" || true
