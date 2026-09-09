#!/usr/bin/env bash
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
DRAFT=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
OUT=/home/user/source/haloq38flash/results
FILLER=$OUT/filler

mkdir -p "$OUT/experiments/exp4"

run_kv() {
    local ctk=$1 ctv=$2 mode=$3 depth=$4
    local tag="exp4-kv-${ctk}_${ctv}-${mode}-${depth}"
    local log="$OUT/experiments/exp4/${tag}.log"
    local ctx=16384
    [ "$depth" = "32k" ] && ctx=40960

    local args=()
    [ "$mode" = "mtp" ] && args+=(-md "$DRAFT" --spec-type draft-mtp \
                                   --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
                                   --spec-draft-type-k "$ctk" --spec-draft-type-v "$ctv")

    echo "Running KV test: ctk=$ctk ctv=$ctv mode=$mode depth=$depth ..."
    timeout 600 "$BIN/llama-cli" -m "$TARGET" "${args[@]}" \
        -dev Vulkan0 -ngl 999 -c "$ctx" -fa on \
        -ub 1024 -b 2048 \
        -ctk "$ctk" -ctv "$ctv" \
        -t 4 -tb 16 \
        -lm mmap --tensor-read-lazy on \
        -f "$FILLER/filler-$depth.txt" \
        -n 128 --temp 0 --reasoning off -no-cnv -st --simple-io > "$log" 2>&1
    local code=$?

    local pp=$(grep -oE 'Prompt: [0-9.]+ t/s' "$log" | tail -1 || echo 'Prompt: N/A')
    local tg=$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo 'Generation: N/A')
    printf '%-35s exit=%-3s %-20s %s\n' "$tag" "$code" "$pp" "$tg"
}

echo "=== Experiment 4: KV Cache Quantization Benchmark at 8k ==="
run_kv "q8_0" "q8_0" "plain" "8k"
run_kv "q4_0" "q4_0" "plain" "8k"
run_kv "q8_0" "q4_0" "plain" "8k"
run_kv "q5_1" "q5_1" "plain" "8k"
run_kv "q4_0" "q4_0" "mtp"   "8k"
run_kv "q8_0" "q4_0" "mtp"   "8k"

echo "=== Experiment 4: KV Cache Quantization Benchmark at 32k ==="
run_kv "q8_0" "q8_0" "plain" "32k"
run_kv "q4_0" "q4_0" "plain" "32k"
run_kv "q8_0" "q4_0" "plain" "32k"
run_kv "q4_0" "q4_0" "mtp"   "32k"
