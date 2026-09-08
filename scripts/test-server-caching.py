import subprocess
import time
import json
import requests
import sys
import os

PORT = 18092
HOST = "127.0.0.1"
BASE_URL = f"http://{HOST}:{PORT}"

cmd = [
    "/home/user/source/llama.cpp-strix-halo-vulkan/build/bin/llama-server",
    "-m", "/mnt/ssd2/models/qwen38-flash-next/Qwen3.8-Flash-Next-IQ4_XS-PLE.gguf",
    "-md", "/mnt/ssd2/models/qwen38-flash-next/mtp-Qwen3.8-Flash-Next-Q8_0.gguf",
    "--spec-type", "draft-mtp",
    "--spec-draft-n-max", "6",
    "--spec-draft-p-min", "0.75",
    "-dev", "Vulkan0",
    "-ngl", "999",
    "-fa", "on",
    "-ub", "1024",
    "-b", "2048",
    "-ctk", "q8_0",
    "-ctv", "q8_0",
    "-t", "4",
    "-tb", "16",
    "-lm", "mmap",
    "--tensor-read-lazy", "on",
    "--cache-ram", "8192",
    "--ctx-checkpoints", "32",
    "-c", "40960",
    "-np", "1",
    "--port", str(PORT),
    "--host", HOST,
    "-lv", "1"
]

log_path = "results/server-caching-test.log"
print("Starting llama-server...")
with open(log_path, "w") as log_file:
    proc = subprocess.Popen(cmd, stdout=log_file, stderr=subprocess.STDOUT)

try:
    # Wait for server ready
    ready = False
    start_wait = time.time()
    while time.time() - start_wait < 180:
        try:
            r = requests.get(f"{BASE_URL}/health", timeout=2)
            if r.status_code == 200:
                ready = True
                break
        except Exception:
            pass
        if proc.poll() is not None:
            print(f"Server exited early with code {proc.returncode}!")
            sys.exit(1)
        time.sleep(2)

    if not ready:
        print("Server failed to become ready within timeout.")
        sys.exit(1)

    print("Server is ready! Loading filler prompt...")
    with open("results/filler/filler-32k.txt", "r") as f:
        prefix = f.read().strip()

    payload_cold = {
        "prompt": prefix + "\n\nQuestion: What is 2 + 2?\nAnswer:",
        "n_predict": 32,
        "temperature": 0,
        "cache_prompt": True
    }

    print("Sending COLD request (32k tokens)...")
    t0 = time.time()
    res_cold = requests.post(f"{BASE_URL}/completion", json=payload_cold, timeout=600)
    cold_duration = time.time() - t0
    cold_data = res_cold.json()
    print(f"Cold request finished in {cold_duration:.2f}s")
    print(f"Cold timings: {json.dumps(cold_data.get('timings', {}), indent=2)}")
    print(f"Cold response text: {cold_data.get('content', '').strip()[:100]}")

    payload_warm = {
        "prompt": prefix + "\n\nQuestion: What is 3 + 3?\nAnswer:",
        "n_predict": 32,
        "temperature": 0,
        "cache_prompt": True
    }

    print("\nSending WARM request (same 32k prefix + new question)...")
    t0 = time.time()
    res_warm = requests.post(f"{BASE_URL}/completion", json=payload_warm, timeout=600)
    warm_duration = time.time() - t0
    warm_data = res_warm.json()
    print(f"Warm request finished in {warm_duration:.2f}s")
    print(f"Warm timings: {json.dumps(warm_data.get('timings', {}), indent=2)}")
    print(f"Warm response text: {warm_data.get('content', '').strip()[:100]}")

    cold_p_ms = cold_data.get("timings", {}).get("prompt_ms", 1)
    warm_p_ms = warm_data.get("timings", {}).get("prompt_ms", 1)
    speedup = cold_p_ms / max(warm_p_ms, 0.001)

    print("\n================ SUMMARY ================")
    print(f"Cold prompt time : {cold_p_ms:.1f} ms ({cold_p_ms/1000:.2f} s)")
    print(f"Warm prompt time : {warm_p_ms:.1f} ms ({warm_p_ms/1000:.2f} s)")
    print(f"Prefill Speedup  : {speedup:.1f}x")
    print(f"Cold Gen speed   : {cold_data.get('timings', {}).get('predicted_per_second', 0):.2f} t/s")
    print(f"Warm Gen speed   : {warm_data.get('timings', {}).get('predicted_per_second', 0):.2f} t/s")
    print("=========================================")

finally:
    print("Shutting down server...")
    proc.terminate()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
    print("Server stopped cleanly.")
