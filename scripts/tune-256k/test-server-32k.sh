#!/usr/bin/env bash
# Server prompt cache validation on halo-box master (5f851647f)
set -u

BIN=/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
OUT=/home/user/source/haloq38flash/results/receipts-256k-opt
LOG="$OUT/server-prompt-cache-32k.log"
PORT=8092

mkdir -p "$OUT"

for p in llama-cli llama-server llama-perplexity; do
    if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
done

echo "=== Launching llama-server with 8GB prompt cache at 32k ==="
export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

nohup "$BIN/llama-server" \
    -m "$PLE" -md "$Q80" \
    -dev Vulkan0 -ngl 999 -fa on \
    -c 40960 -ub 1024 -b 2048 \
    -ctk q8_0 -ctv q8_0 \
    -t 4 -tb 16 \
    -lm mmap -lzm on \
    --cache-ram 8192 --ctx-checkpoints 32 --cache-prompt \
    --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
    --host 127.0.0.1 --port "$PORT" > "$LOG" 2>&1 &
SERVER_PID=$!

echo "Waiting for server to become healthy on port $PORT..."
for i in $(seq 1 45); do
    if curl -s "http://127.0.0.1:$PORT/health" | grep -q 'ok'; then
        echo "Server is healthy!"
        break
    fi
    sleep 2
done

python3 /home/user/source/haloq38flash/scripts/tune-256k/bench-prompt-cache.py "$PORT" /home/user/source/haloq38flash/results/filler/filler-32k.txt

RSS_KB=$(awk '/VmRSS/{print $2}' "/proc/$SERVER_PID/status" 2>/dev/null || echo 0)
echo "Server VmRSS: $(( RSS_KB / 1024 )) MB"

kill "$SERVER_PID" 2>/dev/null
echo "=== Server Prompt Cache Test Complete ==="
