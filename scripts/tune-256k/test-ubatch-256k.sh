#!/usr/bin/env bash
# 256k ubatch sweep under bounded Vulkan submissions and unified heap
set -u

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
FILLER=/home/user/source/haloq38flash/results/filler/filler-256k.txt
OUT=/home/user/source/haloq38flash/results/receipts-256k-opt

mkdir -p "$OUT"

run_ub() {
    local ub=$1
    local tag="ubatch-$ub-256k"
    local log="$OUT/$tag.log"

    echo "=== Running 256k sweep with -ub $ub ==="
    for p in llama-cli llama-server llama-perplexity; do
        if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p running"; exit 9; fi
    done

    export RADV_PERFTEST=unified_heap
    export GGML_VK_MAX_MB_PER_SUBMIT=2048

    bash /home/user/source/haloq38flash/scripts/guard-relaxed.sh 3600 "$log" \
        "$BIN/llama-cli" \
        -m "$PLE" -f "$FILLER" -c 257024 \
        -dev Vulkan0 -ngl 999 -fa on \
        -ub "$ub" -b 2048 \
        -ctk q8_0 -ctv q8_0 \
        -ctkd q4_0 -ctvd q4_0 \
        -t 4 -tb 16 \
        -lm mmap --tensor-read-lazy on \
        -n 128 --temp 0 --reasoning off -no-cnv -st --simple-io \
        -md "$Q80" --spec-type draft-mtp \
        --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
        --poll 100 --poll-draft 1

    local code=$?
    echo "--- Finished $tag with exit code $code ---"
    printf '%-30s exit=%-3s %s %s\n' "$tag" "$code" \
        "$(grep -oE 'Prompt: [0-9.]+ t/s' "$log" | tail -1 || echo 'Prompt: N/A')" \
        "$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo 'Generation: N/A')"
}

# Run ladder
case "${1:-1024}" in
    1024) run_ub 1024 ;;
    1536) run_ub 1536 ;;
    2048) run_ub 2048 ;;
    all)
        run_ub 1024
        run_ub 1536
        run_ub 2048
        ;;
    *) echo "Unknown ubatch $1 (use 1024, 1536, 2048, or all)" ;;
esac
