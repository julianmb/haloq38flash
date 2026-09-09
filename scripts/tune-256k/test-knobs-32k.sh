#!/usr/bin/env bash
# Rapid knob validation at 32k context on daily driver (ad914eb)
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
FILLER=/home/user/source/haloq38flash/results/filler/filler-32k.txt
OUT=/home/user/source/haloq38flash/results/receipts-256k-opt

mkdir -p "$OUT"

run_case() {
    local label=$1
    local env_vars=$2
    local extra_args=$3
    local log="$OUT/knob-32k-$label.log"

    echo "--- Running $label ---"
    for p in llama-cli llama-server llama-perplexity; do
        if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
    done

    eval "$env_vars timeout 300 $BIN/llama-cli \
        -m \"$PLE\" -f \"$FILLER\" -c 40960 \
        -dev Vulkan0 -ngl 999 -fa on \
        -ub 1024 -b 2048 \
        -ctk q8_0 -ctv q8_0 \
        -lm mmap --tensor-read-lazy on \
        -n 64 --temp 0 --reasoning off -st --simple-io \
        -md \"$Q80\" --spec-type draft-mtp \
        $extra_args < /dev/null" > "$log" 2>&1
    local rc=$?

    local pp=$(grep -oE 'Prompt: [0-9.]+ t/s' "$log" | tail -1 || echo "Prompt: N/A")
    local tg=$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo "Generation: N/A")
    printf 'RESULT: %-25s rc=%-3s %s | %s\n' "$label" "$rc" "$pp" "$tg"
}

# 1. Baseline (ad914eb defaults: -t 4 -tb 16, --poll 50, n_max 6, p_min 0.75)
run_case "01-baseline" \
    "" \
    "-t 4 -tb 16 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 2. Driver & submit bounding: RADV_PERFTEST=unified_heap + GGML_VK_MAX_MB_PER_SUBMIT=2048
run_case "02-driver-submit-bound" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 4 -tb 16 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 3. Draft KV quantization: -ctkd q4_0 -ctvd q4_0
run_case "03-draft-kv-q40" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 4. Polling level: --poll 100 --poll-draft 1
run_case "04-poll-100" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 5. Draft horizon: n_max 4 vs 5 vs 6
run_case "05-draft-n4" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 4 --spec-draft-p-min 0.75"

run_case "06-draft-n5" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 5 --spec-draft-p-min 0.75"

# 6. Threads: -t 6 vs -t 4
run_case "07-threads-t6" \
    "RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048" \
    "-t 6 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

echo "=== All 32k Knob Tests Completed ==="
