#!/usr/bin/env bash
# Knob validation at 32k context on halo-box master (5f851647f)
set -u

BIN=/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
FILLER=/home/user/source/haloq38flash/results/filler/filler-32k.txt
OUT=/home/user/source/haloq38flash/results/receipts-256k-opt

mkdir -p "$OUT"

run_case() {
    local label=$1
    local env_vars=$2
    local extra_args=$3
    local log="$OUT/halobox-32k-$label.log"

    echo "--- Running $label ---"
    for p in llama-cli llama-server llama-perplexity; do
        if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
    done

    eval "$env_vars timeout 300 $BIN/llama-cli \
        -m \"$PLE\" -f \"$FILLER\" -c 40960 \
        -dev Vulkan0 -ngl 999 -fa on \
        -ub 1024 -b 2048 \
        -ctk q8_0 -ctv q8_0 \
        -lm mmap -lzm on \
        -n 64 --temp 0 --reasoning off -st --simple-io \
        -md \"$Q80\" --spec-type draft-mtp \
        $extra_args < /dev/null" > "$log" 2>&1
    local rc=$?

    local pp=$(grep -oE 'Prompt: [0-9.]+ t/s' "$log" | tail -1 || echo "Prompt: N/A")
    local tg=$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo "Generation: N/A")
    printf 'RESULT: %-25s rc=%-3s %s | %s\n' "$label" "$rc" "$pp" "$tg"
}

# 1. Baseline on halobox
run_case "01-baseline" \
    "" \
    "-t 4 -tb 16 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 2. Driver & submit bound + draft KV q40 + poll 100
run_case "02-tuned-stack" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

echo "=== Halo-box 32k Tests Completed ==="
