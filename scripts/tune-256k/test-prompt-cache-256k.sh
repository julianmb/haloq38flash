#!/usr/bin/env bash
# 256k Server Prompt Caching within 96 GB RAM budget
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
OUT=/home/user/source/haloq38flash/results/receipts-256k-opt
LOG="$OUT/server-prompt-cache-256k.log"
PORT=8089

mkdir -p "$OUT"

for p in llama-cli llama-server llama-perplexity; do
    if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
done

echo "=== Launching llama-server with 8GB prompt cache at 256k ==="
export RADV_PERFTEST=unified_heap
export GGML_VK_MAX_MB_PER_SUBMIT=2048

# Launch server in background via guard-relaxed
bash /home/user/source/haloq38flash/scripts/guard-relaxed.sh 4000 "$LOG" \
    "$BIN/llama-server" \
    -m "$PLE" -md "$Q80" \
    -dev Vulkan0 -ngl 999 -fa on \
    -c 257024 -ub 1024 -b 2048 \
    -ctk q8_0 -ctv q8_0 \
    -ctkd q4_0 -ctvd q4_0 \
    -t 4 -tb 16 \
    -lm mmap --tensor-read-lazy on \
    --cache-ram 8192 --ctx-checkpoints 32 --cache-prompt \
    --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
    --poll 100 --poll-draft 1 \
    --host 127.0.0.1 --port "$PORT" &
SERVER_GUARD_PID=$!

echo "Waiting for server to become healthy on port $PORT..."
for i in $(seq 1 60); do
    if curl -s "http://127.0.0.1:$PORT/health" | grep -q 'ok'; then
        echo "Server is healthy!"
        break
    fi
    sleep 2
done

# Cold turn: Send 256k document
echo "=== Sending Turn 1 (Cold 256k Prompt) ==="
T1_START=$(date +%s%N)
RES1=$(curl -s "http://127.0.0.1:$PORT/completion" \
    -H "Content-Type: application/json" \
    -d @- <<JSON
{
  "prompt": "$(cat /home/user/source/haloq38flash/results/filler/filler-256k.txt | tr '\n' ' ' | sed 's/"/\\"/g')\n\nQuestion: Summarize the main topic in one sentence.",
  "n_predict": 64,
  "temperature": 0.0
}
JSON
)
T1_END=$(date +%s%N)
T1_DUR=$(( (T1_END - T1_START) / 1000000000 ))
echo "Turn 1 finished in ${T1_DUR}s"
echo "Turn 1 response: $(echo "$RES1" | grep -oE '"content":"[^"]*"' | head -1)"

# Warm turn: Send follow-up using same 256k prefix
echo "=== Sending Turn 2 (Warm Turn using cached 256k prefix) ==="
T2_START=$(date +%s%N)
RES2=$(curl -s "http://127.0.0.1:$PORT/completion" \
    -H "Content-Type: application/json" \
    -d @- <<JSON
{
  "prompt": "$(cat /home/user/source/haloq38flash/results/filler/filler-256k.txt | tr '\n' ' ' | sed 's/"/\\"/g')\n\nQuestion: Summarize the main topic in one sentence.\nAnswer: $(echo "$RES1" | grep -oE '"content":"[^"]*"' | head -1)\n\nQuestion: What was the second key point?",
  "n_predict": 64,
  "temperature": 0.0
}
JSON
)
T2_END=$(date +%s%N)
T2_DUR=$(( (T2_END - T2_START) / 1000000000 ))
echo "Turn 2 finished in ${T2_DUR}s"
echo "Turn 2 response: $(echo "$RES2" | grep -oE '"content":"[^"]*"' | head -1)"

# Teardown
pkill -f "llama-server.*$PORT"
wait "$SERVER_GUARD_PID" 2>/dev/null
echo "=== Server Prompt Cache Test Complete ==="
