#!/usr/bin/env python3
import json
import time
import urllib.request
import sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8092
prompt_file = sys.argv[2] if len(sys.argv) > 2 else "/home/user/source/haloq38flash/results/filler/filler-32k.txt"

with open(prompt_file, "r") as f:
    filler = f.read().strip()

url = f"http://127.0.0.1:{port}/completion"

# Turn 1: Cold
print("Sending Turn 1 (Cold)...")
payload1 = {
    "prompt": f"{filler}\n\nQuestion: Summarize the mood in one sentence.",
    "n_predict": 32,
    "temperature": 0.0,
}
data1 = json.dumps(payload1).encode("utf-8")
req1 = urllib.request.Request(url, data=data1, headers={"Content-Type": "application/json"})

t1_start = time.perf_counter()
with urllib.request.urlopen(req1) as resp:
    res1 = json.loads(resp.read().decode("utf-8"))
t1_end = time.perf_counter()

t1_total = (t1_end - t1_start) * 1000
t1_prompt_ms = res1.get("timings", {}).get("prompt_ms", 0.0)
t1_content = res1.get("content", "").strip()

print(f"Turn 1 total: {t1_total:.1f} ms | prompt_ms: {t1_prompt_ms:.1f} ms")
print(f"Turn 1 content: {t1_content[:80]}")

# Turn 2: Warm (reuse prefix)
print("\nSending Turn 2 (Warm - reusing 32k prefix)...")
payload2 = {
    "prompt": f"{filler}\n\nQuestion: Summarize the mood in one sentence.\nAnswer: {t1_content}\n\nQuestion: What should we do next?",
    "n_predict": 32,
    "temperature": 0.0,
}
data2 = json.dumps(payload2).encode("utf-8")
req2 = urllib.request.Request(url, data=data2, headers={"Content-Type": "application/json"})

t2_start = time.perf_counter()
with urllib.request.urlopen(req2) as resp:
    res2 = json.loads(resp.read().decode("utf-8"))
t2_end = time.perf_counter()

t2_total = (t2_end - t2_start) * 1000
t2_prompt_ms = res2.get("timings", {}).get("prompt_ms", 0.0)
t2_content = res2.get("content", "").strip()

print(f"Turn 2 total: {t2_total:.1f} ms | prompt_ms: {t2_prompt_ms:.1f} ms")
print(f"Turn 2 content: {t2_content[:80]}")

if t2_prompt_ms > 0:
    speedup = t1_prompt_ms / t2_prompt_ms
    print(f"\nPrompt Processing Speedup: {speedup:.1f}x (from {t1_prompt_ms:.1f} ms down to {t2_prompt_ms:.1f} ms)")
