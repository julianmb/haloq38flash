#!/usr/bin/env bash
# ppl quality receipts for the published quants — sequential, guarded.
# usage: bench-ppl-quants.sh [f16-chunks]   (f16-chunks empty => skip F16)
set -u
cd "$(dirname "$0")/.."
RES=results; CORPUS=/mnt/ssd2/models/qwen38-flash-next/corpus/wiki.test.raw
PERP=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-perplexity
MDIR=/mnt/ssd2/models/qwen38-flash-next
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

die() { log "FATAL: $*"; exit 1; }
[ -s "$CORPUS" ] || die "corpus missing: $CORPUS"
[ -x "$PERP" ] || die "llama-perplexity missing: $PERP"

mem_mon() { # $1=pid $2=logfile
  ( while kill -0 "$1" 2>/dev/null; do
      rss=$(awk '/VmRSS/{print $2}' "/proc/$1/status" 2>/dev/null)
      swp=$(awk '/VmSwap/{print $2}' "/proc/$1/status" 2>/dev/null)
      echo "$(date -Is) PID=$1 VmRSS=${rss:-NA}_kB VmSwap=${swp:-NA}_kB" >> "$2"
      if [ "${swp:-0}" -gt 8192 ]; then
        c=$(grep -c "VmSwap=[89][0-9]\{6,\}" "$2" 2>/dev/null || echo 0)
        if [ "${c:-0}" -ge 2 ]; then
          log "GUARD: VmSwap over 8192 kB twice — killing PID $1"; kill "$1"; break
        fi
      fi
      sleep 30
    done ) &
  MON=$!
}

run_ppl() { # $1=name $2=model $3=extra-flags... $4=timeout
  local name=$1 model=$2 tmo=$4; shift 3
  pgrep -x llama-cli >/dev/null && die "GPU busy: llama-cli running"
  pgrep -x llama-perplexity >/dev/null && die "GPU busy: llama-perplexity running"
  log "=== ppl $name start ==="
  timeout -k 30 "$tmo" "$PERP" -m "$model" -f "$CORPUS" \
    -dev Vulkan0 -ngl 999 -fa on -t 4 "$@" \
    > "$RES/ppl-$name.log" 2>&1 &
  local pid=$!
  echo "$(date -Is) PID=$pid" > "$RES/ppl-$name.mem.log"
  mem_mon "$pid" "$RES/ppl-$name.mem.log"
  wait "$pid"; local rc=$?
  kill "$MON" 2>/dev/null; wait "$MON" 2>/dev/null
  if [ $rc -eq 0 ]; then
    log "ppl $name OK: $(grep -oE '\[?[0-9]+\]\.[0-9]+ (perplexity|per-token entropy)[^\n]*' "$RES/ppl-$name.log" | tail -n 2 | tr '\n' ' ')"
  else
    log "ppl $name FAILED rc=$rc — inspect $RES/ppl-$name.log"
  fi
  return $rc
}

mkdir -p "$RES"
# quality measurement: default f16 KV (no cache quant), consistent -fa on
run_ppl ple    "$MDIR/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf" -c 2048 -ub 2048 3600
run_ppl static "$MDIR/Qwen3.8-Flash-Next-IQ4_XS.gguf"     -c 2048 -ub 2048 3600
run_ppl m2     "$MDIR/Qwen3.8-Flash-Next-IQ4_XS-M2.gguf"  -c 2048 -ub 2048 3600

if [ -n "${1:-}" ]; then
  # F16 ground truth: 330G does not fit UMA — pure CPU, mmap, few chunks
  run_ppl f16 "$MDIR/Qwen3.8-Flash-Next-F16.gguf" -c 2048 -ngl 0 --chunks "$1" 7200
fi

log "=== ppl suite done ==="
grep -H "perplexity" "$RES"/ppl-*.log 2>/dev/null | grep -v mem || true
