#!/usr/bin/env bash
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
DRAFT=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
OUT=/home/user/source/haloq38flash/results
FILLER=$OUT/filler

mkdir -p "$OUT/experiments/exp1"

run_mtp() {
    local depth=$1 n_max=$2 p_min=$3
    local tag="exp1-mtp-d${depth}-n${n_max}-p${p_min}"
    local log="$OUT/experiments/exp1/${tag}.log"
    local ctx=16384
    [ "$depth" = "32k" ] && ctx=40960

    echo "Running depth=$depth n_max=$n_max p_min=$p_min ..."
    timeout 600 "$BIN/llama-cli" -m "$TARGET" \
        -md "$DRAFT" --spec-type draft-mtp \
        --spec-draft-n-max "$n_max" --spec-draft-p-min "$p_min" \
        -dev Vulkan0 -ngl 999 -c "$ctx" -fa on \
        -ub 1024 -b 2048 \
        -ctk q8_0 -ctv q8_0 \
        -t 4 -tb 16 \
        -lm mmap --tensor-read-lazy on \
        -f "$FILLER/filler-$depth.txt" \
        -n 128 --temp 0 --reasoning off -no-cnv -st --simple-io > "$log" 2>&1
    local code=$?

    local pp=$(grep -oE 'Prompt: [0-9.]+ t/s' "$log" | tail -1 || echo 'Prompt: N/A')
    local tg=$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo 'Generation: N/A')
    local draft=$(grep -oE 'draft acceptance.*' "$log" | tail -1 || echo '')
    printf '%-30s exit=%-3s %-20s %-20s %s\n' "$tag" "$code" "$pp" "$tg" "$draft"
}

echo "=== Experiment 1: MTP Tuning at 8k ==="
run_mtp "8k" 4 0.75
run_mtp "8k" 6 0.75
run_mtp "8k" 8 0.75
run_mtp "8k" 6 0.85
run_mtp "8k" 8 0.85

echo "=== Experiment 1: MTP Tuning at 32k ==="
run_mtp "32k" 4 0.75
run_mtp "32k" 6 0.75
run_mtp "32k" 8 0.75
