#!/bin/bash
# Test 1: Aggressive prefill scaling (-ub 2048 -b 2048 -tb 16) with SSD-PLE at 256k context
set -u
cd /home/user/source/haloq38flash
DAILY=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-cli
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf

bash scripts/guard-relaxed.sh 3000 results/probe-256k-mtp-ssdple-ub2048.log \
  "$DAILY" -m "$PLE" -f results/filler/filler-256k.txt -c 257024 \
  -dev Vulkan0 -ngl 999 -fa on \
  -ub 2048 -b 2048 \
  -ctk q8_0 -ctv q8_0 \
  -t 4 -tb 16 \
  -n 128 --temp 0 --reasoning off -st --simple-io \
  -lm mmap --tensor-read-lazy on \
  -md "$Q80" --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75

echo "ssd-ple-ub2048 256k mtp: $(grep -o 'Prompt: [^|]*| Generation: [^]]*' results/probe-256k-mtp-ssdple-ub2048.log | tail -n1)"
echo "=== memory trajectory ==="
grep -oE "VmRSS=[0-9]+_kB VmSwap=[0-9]+_kB avail=[0-9]+MB" results/probe-256k-mtp-ssdple-ub2048.log.mem.log 2>/dev/null | tail -n 4
