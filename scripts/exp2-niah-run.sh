#!/usr/bin/env bash
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
DRAFT=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
OUT=/home/user/source/haloq38flash/results
FIXTURES=$OUT/niah_fixtures

mkdir -p "$OUT/experiments/exp2"

run_niah() {
    local ctx_name=$1 depth_pct=$2 ctx_size=$3
    local tag="niah-${ctx_name}-d${depth_pct}"
    local fixture="$FIXTURES/niah-${ctx_name}-depth${depth_pct}.txt"
    local log="$OUT/experiments/exp2/${tag}.log"

    echo "Running NIAH test: context=$ctx_name needle_depth=${depth_pct}% ..."
    timeout 1200 "$BIN/llama-cli" -m "$TARGET" \
        -md "$DRAFT" --spec-type draft-mtp \
        --spec-draft-n-max 4 --spec-draft-p-min 0.75 \
        -dev Vulkan0 -ngl 999 -c "$ctx_size" -fa on \
        -ub 1024 -b 2048 \
        -ctk q8_0 -ctv q8_0 \
        -t 4 -tb 16 \
        -lm mmap --tensor-read-lazy on \
        -f "$fixture" \
        -n 32 --temp 0 --reasoning off -no-cnv -st --simple-io > "$log" 2>&1
    local code=$?

    # Check if needle answer is in the output
    local answer=$(grep -iE "Zephyr|Golden Falcon" "$log" || echo "MISSED")
    local pp=$(grep -oE 'Prompt: [0-9.]+ t/s' "$log" | tail -1 || echo 'Prompt: N/A')
    local tg=$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo 'Generation: N/A')
    
    if [ "$answer" != "MISSED" ]; then
        local status="PASS (Retrieved: $(echo "$answer" | head -c 40))"
    else
        local status="FAIL (Not Found)"
    fi
    printf '%-22s exit=%-3s %-45s %-18s %s\n' "$tag" "$code" "$status" "$pp" "$tg"
}

echo "=== Experiment 2: Needle-In-A-Haystack Long Context Retrieval ==="
run_niah "32k" 25 40960
run_niah "32k" 95 40960
run_niah "64k" 50 73728
