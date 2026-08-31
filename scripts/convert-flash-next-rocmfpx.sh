#!/usr/bin/env bash
# convert-flash-next-rocmfpx.sh — Qwen3.8-Flash-Next FP8 safetensors -> ROCmFP4_FAST GGUF
#
# Lives in haloq38flash; the engine (converter + llama-quantize) is ~/source/ROCmFPX
# (branch port-qwen4exp, PR #98).
#
# Pipeline:
#   1. convert_hf_to_gguf.py -> F16 GGUF (PLE fp8 scale captured + applied)
#   2. llama-quantize -> Q4_0_ROCMFP4_FAST (per_layer_token_embd protected to Q8_0;
#      banded/streaming quantizer keeps RAM bounded)
#   3. smoke: llama-completion (NOT llama-cli) with bounded -c and a timer
#
set -eo pipefail

SRC_DIR="${SRC_DIR:-/mnt/ssd2/models/qwen38-flash-next/meta-fp8}"
WORK_DIR="${WORK_DIR:-/mnt/ssd2/models/qwen38-flash-next}"
ENGINE="${ENGINE:-/home/user/source/ROCmFPX}"
OUT_F16="${WORK_DIR}/Qwen3.8-Flash-Next-F16.gguf"
OUT_QUANT="${WORK_DIR}/Qwen3.8-Flash-Next-ROCmFP4_FAST.gguf"
SMOKE_CTX="${SMOKE_CTX:-8192}"

mkdir -p "${WORK_DIR}"

if [ ! -f "${SRC_DIR}/config.json" ]; then
    echo "ERROR: ${SRC_DIR}/config.json missing - download not complete?" >&2
    exit 1
fi

echo "=== [1/3] convert FP8 safetensors -> F16 GGUF ==="
if [ ! -f "${OUT_F16}" ]; then
    cd "${ENGINE}"
    setsid nohup python3 convert_hf_to_gguf.py "${SRC_DIR}" \
        --outfile "${OUT_F16}" \
        --outtype f16
else
    echo "F16 GGUF exists, skipping: ${OUT_F16}"
fi

echo "=== [2/3] quantize -> Q4_0_ROCMFP4_FAST ==="
if [ ! -f "${OUT_QUANT}" ]; then
    /usr/bin/time -v "${ENGINE}/build-strix-rocmfp4/bin/llama-quantize" \
        "${OUT_F16}" \
        "${OUT_QUANT}" \
        Q4_0_ROCMFP4_FAST
else
    echo "quant exists, skipping: ${OUT_QUANT}"
fi

echo "=== [3/3] smoke: llama-completion, bounded context, timer ==="
/usr/bin/time -v timeout 900 "${ENGINE}/build-strix-rocmfp4/bin/llama-completion" \
    -m "${OUT_QUANT}" \
    -dev Vulkan0 -ngl 47 -c "${SMOKE_CTX}" -fa on -ub 2048 \
    -p "The capital of France is" -n 64 --temp 0 -no-cnv --simple-io 2>&1 | tail -40

ls -lah "${OUT_F16}" "${OUT_QUANT}"
echo "DONE"
