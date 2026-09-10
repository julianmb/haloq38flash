#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="/tmp/v075/vulkan/llama-cli"
PLE="/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf"
FILLER="$ROOT/results/filler/filler-250k.txt"
OUT_DIR="$ROOT/results/receipts-further-opts"
mkdir -p "$OUT_DIR"

RUN_LOG="$OUT_DIR/14-v075-plain-250k.log"
MEM_LOG="$OUT_DIR/14-v075-plain-250k-mem.log"

echo "=== Benchmarking v0.7.5 QSA Pooled Key Cache at 250k tokens ==="
echo "Model: $PLE"
echo "Prompt: $FILLER"
echo "Context: 262144"
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

export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

# Run llama-cli
timeout 1200 "$BIN" \
    -m "$PLE" \
    -f "$FILLER" \
    -c 262144 \
    -dev Vulkan0 \
    -ngl 999 \
    -fa on \
    -ub 1024 \
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

echo "=== Execution Summary ==="
grep -E "Prompt:|Generation:|total time|load time" "$RUN_LOG" || tail -n 25 "$RUN_LOG"

echo "=== Memory Summary ==="
PEAK_RSS=$(awk -F, 'NR>1 {if($3>max) max=$3} END {print max}' "$MEM_LOG")
PEAK_SYS=$(awk -F, 'NR>1 {if($5>max) max=$5} END {print max}' "$MEM_LOG")
MIN_AVAIL=$(awk -F, 'NR>1 {if(min=="" || $6<min) min=$6} END {print min}' "$MEM_LOG")
echo "Peak llama-cli RSS: ${PEAK_RSS} MB ($(( PEAK_RSS / 1024 )) GB)"
echo "Peak System Used RAM: ${PEAK_SYS} MB ($(( PEAK_SYS / 1024 )) GB)"
echo "Minimum Available RAM remaining: ${MIN_AVAIL} MB ($(( MIN_AVAIL / 1024 )) GB)"
