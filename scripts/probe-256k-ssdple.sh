#!/bin/bash
# SSD-backed PLE 256k MTP probe (daily driver): mmap + lazy tensors keep the
# 27G PLE table on NVMe (~2.5G resident) instead of UMA. Tests whether the
# 256k upfront-allocation wall disappears when ~25G leaves the UMA budget.
set -u
cd /home/user/source/haloq38flash
DAILY=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-cli
PLE=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
Q80=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
bash scripts/guard-relaxed.sh 3000 results/probe-256k-mtp-ssdple.log \
  "$DAILY" -m "$PLE" -f results/filler/filler-256k.txt -c 257024 \
  -dev Vulkan0 -ngl 999 -fa on -ub 512 -b 512 -ctk q8_0 -ctv q8_0 -t 4 -n 128 \
  --temp 0 --reasoning off -st --simple-io \
  -lm mmap --tensor-read-lazy on \
  -md "$Q80" --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75
echo "ssd-ple 256k mtp: $(grep -o 'Prompt: [^|]*| Generation: [^]]*' results/probe-256k-mtp-ssdple.log | tail -n1)"
echo "=== memory trajectory (VmRSS should sit ~65-70G, not ~95G) ==="
grep -oE "VmRSS=[0-9]+_kB VmSwap=[0-9]+_kB avail=[0-9]+MB" results/probe-256k-mtp-ssdple.log.mem.log 2>/dev/null | tail -n 4
