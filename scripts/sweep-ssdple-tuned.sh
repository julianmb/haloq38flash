#!/usr/bin/env bash
# Sweep for tuned SSD-PLE across depths: 0, 8k, 32k, 128k, 256k
# Flags: -dev Vulkan0 -ngl 999 -fa on -ub 1024 -b 2048 -ctk q8_0 -ctv q8_0 -t 4 -tb 16 -lm mmap --tensor-read-lazy on
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
DRAFT=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
OUT=/home/user/source/haloq38flash/results
FILLER=$OUT/filler
SHORT="Write a Python function that computes the nth Fibonacci number using memoization, with a docstring, type hints, and a short example."
DEPTHS=${1:-0 8k 32k 128k 256k}

declare -A PROMPT_CTX=( [0]=8192 [8k]=16384 [32k]=40960 [128k]=139264 [256k]=257024 )

mkdir -p "$OUT/receipts"

run() {
    local depth=$1 mode=$2
    local tag="ssdple-tuned-depth$depth-$mode"
    local log=$OUT/receipts/$tag.log
    local args=()
    if [ "$depth" = "0" ]; then
        args+=(-p "$SHORT")
    else
        args+=(-f "$FILLER/filler-$depth.txt")
    fi
    [ "$mode" = "mtp" ] && args+=(-md "$DRAFT" --spec-type draft-mtp \
                                   --spec-draft-n-max 6 --spec-draft-p-min 0.75)

    timeout 2400 "$BIN/llama-cli" -m "$TARGET" "${args[@]}" \
        -dev Vulkan0 -ngl 999 -c "${PROMPT_CTX[$depth]}" -fa on \
        -ub 1024 -b 2048 \
        -ctk q8_0 -ctv q8_0 \
        -t 4 -tb 16 \
        -lm mmap --tensor-read-lazy on \
        -n 128 --temp 0 --reasoning off -no-cnv -st --simple-io > "$log" 2>&1
    local code=$?
    printf '%-32s exit=%-3s %s %s\n' "$tag" "$code" \
        "$(grep -oE 'Prompt: [0-9.]+ t/s'  "$log" | tail -1 || echo 'Prompt: N/A')" \
        "$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo 'Generation: N/A')"
}

echo "=== Starting SSD-PLE Tuned Sweep (depths: $DEPTHS) ==="
for d in $DEPTHS; do
    run "$d" plain
    run "$d" mtp
done
echo "=== Sweep Finished ==="
