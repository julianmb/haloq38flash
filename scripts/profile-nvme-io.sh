#!/usr/bin/env bash
set -u

OUT=/home/user/source/haloq38flash/results/experiments/exp5
mkdir -p "$OUT"

BIN=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin
TARGET=/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf
DRAFT=/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
FILLER=/home/user/source/haloq38flash/results/filler/filler-32k.txt

echo "=== Experiment 5: Profiling NVMe I/O during 32k SSD-PLE run ==="

# Record initial memory and disk stats
iostat -xz 1 nvme1n1 > "$OUT/iostat.log" 2>&1 &
IOSTAT_PID=$!

vmstat 1 > "$OUT/vmstat.log" 2>&1 &
VMSTAT_PID=$!

echo "Starting 32k MTP run..."
"$BIN/llama-cli" -m "$TARGET" \
    -md "$DRAFT" --spec-type draft-mtp \
    --spec-draft-n-max 6 --spec-draft-p-min 0.75 \
    -dev Vulkan0 -ngl 999 -c 40960 -fa on \
    -ub 1024 -b 2048 \
    -ctk q8_0 -ctv q8_0 \
    -t 4 -tb 16 \
    -lm mmap --tensor-read-lazy on \
    -f "$FILLER" \
    -n 128 --temp 0 --reasoning off -no-cnv -st --simple-io > "$OUT/run.log" 2>&1

kill $IOSTAT_PID $VMSTAT_PID 2>/dev/null || true

echo "=== Run complete. Analyzing NVMe I/O statistics ==="
awk '/nvme1n1/ { r_mb += $6/1024; count++; if($6/1024 > max_r) max_r=$6/1024; if($14 > max_util) max_util=$14 } END { if(count>0) printf("Average Read: %.2f MB/s | Peak Read: %.2f MB/s | Peak Disk Util: %.1f%%\n", r_mb/count, max_r, max_util) }' "$OUT/iostat.log"

grep -oE 'Prompt: [0-9.]+ t/s' "$OUT/run.log"
grep -oE 'Generation: [0-9.]+ t/s' "$OUT/run.log"
