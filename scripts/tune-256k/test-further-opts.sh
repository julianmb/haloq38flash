#!/usr/bin/env bash
# Exploration of further optimizations: CCX pinning, batch sizes, MTP draft tuning
set -u

BIN=/home/user/source/haloq38flash/repos/halo-box-strix-llama.cpp/build-5f851/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
FILLER=/home/user/source/haloq38flash/results/filler/filler-32k.txt
OUT=/home/user/source/haloq38flash/results/receipts-further-opts

mkdir -p "$OUT"

run_case() {
    local label=$1
    local env_vars=$2
    local prefix_cmd=$3
    local extra_args=$4
    local log="$OUT/$label.log"

    echo "--- Running $label ---"
    for p in llama-cli llama-server llama-perplexity; do
        if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
    done

    eval "$env_vars $prefix_cmd timeout 300 $BIN/llama-cli \
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
    local draft_acc=$(grep -oE 'draft acceptance rate: [0-9.]+' "$log" | tail -1 || echo "draft acc: N/A")
    printf 'RESULT: %-30s rc=%-3s %s | %s | %s\n' "$label" "$rc" "$pp" "$tg" "$draft_acc"
}

ENV_DEFAULT="RADV_PERFTEST=unified_heap GGML_VK_MAX_MB_PER_SUBMIT=2048"

# 1. Baseline Tuned (reference: ~434 t/s pp, ~26.7 t/s tg)
run_case "01-tuned-reference" \
    "$ENV_DEFAULT" "" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 2. CCX 0 Pinning (taskset -c 0-7,16-23)
run_case "02-ccx0-pinned" \
    "$ENV_DEFAULT" "taskset -c 0-7,16-23" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 3. Logical Batch Size 4096 (-b 4096 -ub 1024)
run_case "03-b4096" \
    "$ENV_DEFAULT" "" \
    "-b 4096 -t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75"

# 4. MTP draft-n-max 5
run_case "04-draft-n5" \
    "$ENV_DEFAULT" "" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 5 --spec-draft-p-min 0.75"

# 5. MTP draft-n-max 7
run_case "05-draft-n7" \
    "$ENV_DEFAULT" "" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 7 --spec-draft-p-min 0.75"

# 6. MTP draft-p-min 0.70
run_case "06-draft-pmin070" \
    "$ENV_DEFAULT" "" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.70"

# 7. MTP draft-p-min 0.80
run_case "07-draft-pmin080" \
    "$ENV_DEFAULT" "" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.80"

# 8. Adaptive MTP Drafting (--spec-draft-adaptive)
run_case "08-draft-adaptive" \
    "$ENV_DEFAULT" "" \
    "-t 4 -tb 16 -ctkd q4_0 -ctvd q4_0 --poll 100 --poll-draft 1 --spec-draft-n-max 6 --spec-draft-p-min 0.75 --spec-draft-adaptive"

echo "=== Further Optimization Exploration Finished ==="
