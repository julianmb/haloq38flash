#!/usr/bin/env bash
# n=3 variance A/B: daily-driver vs merged engine, identical drafting (n_max 6).
# depths: 8k + 128k, modes: plain + mtp, 3 repeats each => 24 runs.
set -u
cd "$(dirname "$0")/.."
RES=results; FILL=results/filler
MDIR=/mnt/ssd2/models/qwen38-flash-next
DAILY=/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-cli
MERGED=/home/user/source/llamacpp-master/build-hq38/bin/llama-cli
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
die() { log "FATAL: $*"; exit 1; }
[ -x "$DAILY" ] && [ -x "$MERGED" ] || die "engine binary missing"

mem_mon() {
  ( while kill -0 "$1" 2>/dev/null; do
      rss=$(awk '/VmRSS/{print $2}' "/proc/$1/status" 2>/dev/null)
      swp=$(awk '/VmSwap/{print $2}' "/proc/$1/status" 2>/dev/null)
      echo "$(date -Is) PID=$1 VmRSS=${rss:-NA}_kB VmSwap=${swp:-NA}_kB" >> "$2"
      if [ "${swp:-0}" -gt 8192 ]; then
        c=$(grep -c "VmSwap=[89][0-9]\{6,\}" "$2" 2>/dev/null || echo 0)
        if [ "${c:-0}" -ge 2 ]; then
          log "GUARD: killing PID $1 (swap)"; kill "$1"; break
        fi
      fi
      sleep 30
    done ) &
  MON=$!
}

run_one() { # $1=engine-name $2=binary $3=depth $4=mode $5=repeat
  local eng=$1 bin=$2 depth=$3 mode=$4 rep=$5
  local ctx fill tmo
  case "$depth" in
    8k)   ctx=16384;  fill=$FILL/filler-8k.txt;   tmo=2400 ;;
    128k) ctx=139264; fill=$FILL/filler-128k.txt; tmo=3000 ;;
    *) die "bad depth $depth" ;;
  esac
  local out="$RES/n3-$eng-$depth-$mode-r$rep.log"
  pgrep -x llama-cli >/dev/null && die "GPU busy before $out"
  local args=(-m "$MDIR/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf" -f "$fill" -c "$ctx"
              -dev Vulkan0 -ngl 999 -fa on -ub 2048 -ctk q8_0 -ctv q8_0 -t 4
              -n 128 --temp 0 --reasoning off -st --simple-io)
  [ "$mode" = mtp ] && args+=(-md "$MDIR/mtp-Qwen3.8-Flash-Next-Q8_0.gguf"
              --spec-type draft-mtp --spec-draft-n-max 6 --spec-draft-p-min 0.75)
  log "=== $out start ==="
  echo "$(date -Is)" > "$out"
  timeout -k 30 "$tmo" "$bin" "${args[@]}" >> "$out" 2>&1 &
  local pid=$!
  mem_mon "$pid" "$out.mem.log"
  wait "$pid"; local rc=$?
  kill "$MON" 2>/dev/null; wait "$MON" 2>/dev/null
  grep -q "Generation" "$out" && log "$out OK: $(grep -o 'Prompt: [^|]*| Generation: [^]]*' "$out" | tail -n1)" \
    || log "$out FAILED rc=$rc"
  return 0  # keep going regardless; summary marks failures
}

mkdir -p "$RES"
for depth in 8k 128k; do
  for mode in plain mtp; do
    for rep in 1 2 3; do
      run_one daily  "$DAILY"  "$depth" "$mode" "$rep"
      run_one merged "$MERGED" "$depth" "$mode" "$rep"
    done
  done
done

log "=== summary (median / min / max per cell) ==="
python3 - <<'EOF'
import re, glob, statistics
cells = {}
for f in glob.glob("results/n3-*.log"):
    if f.endswith(".mem.log"): continue
    m = re.search(r"n3-(\w+)-(\w+)-(\w+)-r(\d)", f)
    if not m: continue
    txt = open(f, errors="replace").read()
    g = re.findall(r"Prompt: ([\d.]+) t/s \| Generation: ([\d.]+) t/s", txt)
    if g:
        pp, tg = map(float, g[-1])
        cells.setdefault(m.groups()[:3], []).append((pp, tg))
for k in sorted(cells):
    pp = [p for p, _ in cells[k]]; tg = [t for _, t in cells[k]]
    n = len(pp)
    print(f"{k[0]:6s} {k[1]:5s} {k[2]:5s} n={n}  pp median={statistics.median(pp):7.1f} spread={min(pp):.1f}-{max(pp):.1f}  tg median={statistics.median(tg):5.1f} spread={min(tg):.1f}-{max(tg):.1f}")
EOF
log "=== n3 A/B done ==="
