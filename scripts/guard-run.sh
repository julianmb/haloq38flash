#!/bin/bash
# usage: guard-run.sh <timeout_s> <log_path> <cmd...>
TMO=$1; LOG=$2; shift 2
for p in llama-cli llama-server llama-perplexity; do
  if pgrep -x "$p" >/dev/null 2>&1; then echo "PREFLIGHT FAIL: $p already running"; exit 9; fi
done
nohup "$@" > "$LOG" 2>&1 &
PID=$!
[ -w "/proc/$PID/oom_score_adj" ] && echo 500 > "/proc/$PID/oom_score_adj"
START=$(date +%s)
DEADLINE=$(( START + TMO ))
CONS=0
while kill -0 "$PID" 2>/dev/null; do
  sleep 30
  SWP=$(awk '/VmSwap/{print $2}' "/proc/$PID/status" 2>/dev/null); SWP=${SWP:-0}
  RSS=$(awk '/VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null); RSS=${RSS:-0}
  echo "$(date -Is) PID=$PID VmRSS=${RSS}_kB VmSwap=${SWP}_kB" >> "$LOG.mem.log"
  if [ ! -s "$LOG" ] && [ $(( $(date +%s) - START )) -ge 150 ]; then
    echo "$(date -Is) HANG: log empty after 150s; killing PID $PID" >> "$LOG.mem.log"
    kill "$PID"; sleep 5; kill -9 "$PID" 2>/dev/null; break
  fi
  if [ "$SWP" -gt 8192 ]; then CONS=$((CONS+1)); else CONS=0; fi
  if [ "$CONS" -ge 2 ]; then
    echo "$(date -Is) GUARD: two consecutive VmSwap samples >8192kB; killing exact PID $PID" >> "$LOG.mem.log"
    kill "$PID"; sleep 5; kill -9 "$PID" 2>/dev/null; break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "$(date -Is) DEADLINE: killing PID $PID" >> "$LOG.mem.log"
    kill "$PID"; sleep 5; kill -9 "$PID" 2>/dev/null; break
  fi
done
wait "$PID" 2>/dev/null
echo "rc=$?" >> "$LOG.mem.log"
exit 0
