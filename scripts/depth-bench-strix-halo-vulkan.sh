#!/usr/bin/env bash
# Decode + prefill vs context depth, with and without MTP.
#
# Uses filler prompts of ~8k and ~32k tokens (results/filler/) and reports the
# [ Prompt: X t/s | Generation: Y t/s ] line llama-cli prints. --reasoning off
# keeps the 128-token generation budget from being eaten by a thinking block.
# q8_0 KV keeps the cache small at depth.
#
# usage: scripts/depth-bench-strix-halo-vulkan.sh [depths]   # e.g. "8k 32k"
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=${TARGET:-/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS.gguf}
DRAFT=${DRAFT:-/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf}
OUT=${OUT:-/home/user/source/haloq38flash/results}
FILLER=$OUT/filler
SHORT="Write a Python function that computes the nth Fibonacci number using memoization, with a docstring, type hints, and a short example."
DEPTHS=${1:-0 8k 32k}

declare -A PROMPT_CTX=( [0]=8192 [8k]=16384 [32k]=40960 [128k]=139264 [256k]=257024 )

run() {
    local depth=$1 mode=$2
    local tag="depth$depth-$mode"
    local log=$OUT/${TAGPREFIX:-}shvd-$tag.log
    local args=()
    if [ "$depth" = "0" ]; then
        args+=(-p "$SHORT")
    else
        args+=(-f "$FILLER/filler-$depth.txt")
    fi
    [ "$mode" = "mtp" ] && args+=(-md "$DRAFT" --spec-type draft-mtp \
                                   --spec-draft-n-max 6 --spec-draft-p-min 0.75)

    timeout 2400 "$BIN/llama-cli" -m "$TARGET" "${args[@]}" \
        -dev Vulkan0 -ngl 999 -c "${PROMPT_CTX[$depth]}" -fa on -ub 2048 \
        -ctk q8_0 -ctv q8_0 \
        -n 128 --temp 0 --reasoning off -no-cnv -st --simple-io > "$log" 2>&1
    printf '%-18s exit=%-3s %s %s\n' "$tag" "$?" \
        "$(grep -oE 'Prompt: [0-9.]+ t/s'  "$log" | tail -1)" \
        "$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1)"
}

for d in $DEPTHS; do
    run "$d" plain
    run "$d" mtp
done
