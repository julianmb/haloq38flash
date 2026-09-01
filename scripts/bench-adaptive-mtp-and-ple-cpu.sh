#!/usr/bin/env bash
# Benchmark script for Adaptive MTP and PLE-CPU offload on Strix Halo
#
# Incorporates community findings from r/StrixHalo:
# 1. Adaptive MTP draft sizing (--spec-draft-adaptive -n-min 0 -n-max 7 -p-min 0.75)
# 2. PLE table CPU offload (--override-tensor "per_layer_token_embd=CPU")
# 3. OOM protection with swap guards and timeout -k 30
#
# usage:
#   scripts/bench-adaptive-mtp-and-ple-cpu.sh [depths]   # e.g. "8k 32k 128k 256k"
#   PLE_OFFLOAD=CPU scripts/bench-adaptive-mtp-and-ple-cpu.sh 256k

set -euo pipefail

BIN=${BIN:-/home/user/source/llamacpp-master/build-hq38/bin}
TARGET=${TARGET:-/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf}
DRAFT=${DRAFT:-/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf}
OUT=${OUT:-/home/user/source/haloq38flash/results}
FILLER=$OUT/filler
SHORT="Write a Python function that computes the nth Fibonacci number using memoization, with a docstring, type hints, and a short example."
DEPTHS=${1:-0 8k 32k 128k 256k}
PLE_OFFLOAD=${PLE_OFFLOAD:-NONE}

declare -A PROMPT_CTX=( [0]=8192 [8k]=16384 [32k]=40960 [128k]=139264 [256k]=257024 )

mkdir -p "$OUT"

check_preflight() {
    local free_gb
    free_gb=$(free -g | awk '/^Mem:/{print $7}')
    if [ "$free_gb" -lt 40 ]; then
        echo "Error: Only ${free_gb}GB available RAM. Aborting to avoid OOM." >&2
        return 1
    fi
    local existing_proc
    existing_proc=$(pgrep -x "llama-cli|llama-server" | wc -l || true)
    if [ "$existing_proc" -gt 0 ]; then
        echo "Error: Another llama process is currently active. Aborting." >&2
        return 1
    fi
    return 0
}

run() {
    local depth=$1 mode=$2
    local tag="adaptive-depth$depth-$mode"
    if [ "$PLE_OFFLOAD" = "CPU" ]; then
        tag="plecpu-$tag"
    fi
    local log=$OUT/$tag.log
    local memlog=$OUT/$tag.mem.log
    local args=()

    if [ "$depth" = "0" ]; then
        args+=(-p "$SHORT")
    else
        args+=(-f "$FILLER/filler-$depth.txt")
    fi

    if [ "$mode" = "mtp" ]; then
        args+=(
            -md "$DRAFT"
            --spec-type draft-mtp
            --spec-draft-adaptive
            --spec-draft-n-min 0
            --spec-draft-n-max 7
            --spec-draft-p-min 0.75
        )
    fi

    if [ "$PLE_OFFLOAD" = "CPU" ]; then
        args+=(--override-tensor "per_layer_token_embd=CPU")
    fi

    echo "=== Running $tag (ctx: ${PROMPT_CTX[$depth]}) ==="

    check_preflight

    # Launch with timeout and background swap monitor
    timeout -k 30 2400 "$BIN/llama-cli" \
        -m "$TARGET" \
        "${args[@]}" \
        -dev Vulkan0 \
        -ngl 999 \
        -c "${PROMPT_CTX[$depth]}" \
        -fa on \
        -ub 2048 \
        -ctk q8_0 \
        -ctv q8_0 \
        --lazy-mode auto \
        --fit off \
        -n 128 \
        --temp 0 \
        --reasoning off \
        -st \
        --simple-io > "$log" 2>&1 &
    
    local pid=$!
    if [ -d "/proc/$pid" ]; then
        echo 500 > "/proc/$pid/oom_score_adj" 2>/dev/null || true
    fi

    # Monitor VmSwap
    : > "$memlog"
    local swap_trips=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ -f "/proc/$pid/status" ]; then
            local vmswap
            vmswap=$(awk '/VmSwap:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
            local vmrss
            vmrss=$(awk '/VmRSS:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
            echo "$(date '+%Y-%m-%d %H:%M:%S') PID=$pid VmRSS=${vmrss}kB VmSwap=${vmswap}kB" >> "$memlog"
            if [ "${vmswap:-0}" -gt 8192 ]; then
                swap_trips=$((swap_trips + 1))
                if [ "$swap_trips" -ge 2 ]; then
                    echo "WARNING: VmSwap exceeded threshold (>8MB) twice (${vmswap}kB). Killing PID $pid..." >> "$memlog"
                    kill -9 "$pid" 2>/dev/null || true
                    break
                fi
            else
                swap_trips=0
            fi
        fi
        sleep 5
    done

    wait "$pid" 2>/dev/null || true
    local exit_code=$?

    printf '%-28s exit=%-3s %s %s\n' "$tag" "$exit_code" \
        "$(grep -oE 'Prompt: [0-9.]+ t/s'  "$log" | tail -1 || echo 'Prompt: N/A')" \
        "$(grep -oE 'Generation: [0-9.]+ t/s' "$log" | tail -1 || echo 'Generation: N/A')"
}

for d in $DEPTHS; do
    run "$d" plain
    run "$d" mtp
done
